package OpenILS::Application::Search::Elastic;
use base qw/OpenILS::Application/;
# ---------------------------------------------------------------
# Copyright (C) 2019 King County Library System
# Author: Bill Erickson <berickxx@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
use strict; 
use warnings;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Elastic::BibSearch;
use Digest::MD5 qw(md5_hex);
use List::Util qw/min/;

use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

# avoid repetitive calls to DB for org info.
my %org_data_cache = (ancestors_at => {});

# bib fields defined in the elastic bib-search index
my $bib_fields;
my $hidden_copy_statuses;
my $hidden_copy_locations;
my $avail_copy_statuses;
my $transcendant_sources;

# NOTE calling cstore functions in child_init is dicey because child_init
# may be run before cstore is ready for requests.  Use a local init() instead.
my $init_done = 0;
sub init {
    my $class = shift;

    return if $init_done;
    $init_done = 1;

    my $e = new_editor();

    # no pkey
    $bib_fields = $e->search_elastic_bib_field({name => {'!=' => undef}});

    my $stats = $e->json_query({
        select => {ccs => ['id', 'opac_visible', 'is_available']},
        from => 'ccs',
        where => {'-or' => [
            {opac_visible => 'f'},
            {is_available => 't'}
        ]}
    });

    $hidden_copy_statuses =
        [map {$_->{id}} grep {$_->{opac_visible} eq 'f'} @$stats];

    $avail_copy_statuses =
        [map {$_->{id}} grep {$_->{is_available} eq 't'} @$stats];

    # Include deleted copy locations since this is an exclusion set.
    my $locs = $e->json_query({
        select => {acpl => ['id']},
        from => 'acpl',
        where => {opac_visible => 'f'}
    });

    $hidden_copy_locations = [map {$_->{id}} @$locs];

    $transcendant_sources = [
        map {$_->id} @{$e->search_config_bib_source({transcendant => 't'})}
    ];

    return 1;
}

__PACKAGE__->register_method(
    method   => 'bib_search',
    api_name => 'open-ils.search.elastic.bib_search',
    signature => {
        desc   => q/
            Performs a search on the Elastic 'bib-search' index.

            The caller provides the core search struct, the API then
            augments the struct, depending on various options.

            Facets (Aggregations) are automatically appended to the search
            based on the Evergreen Facets configuration.

            Org unit based item presence and availability filtering may
            optionally be added to the query.  See search options
            below.

            See [ select * from elastic.bib_field where search_field; ] 
            for full-text search fields and classes.
        /,
        params => [
            {   type => 'object',
                query => q/Elastic-compatible search query struct.  A typical
                struct might look like:
                {
                  from: 0,
                  size: 20,
                  query: {
                    bool: {
                      must: [
                        {
                          multi_match: {
                            type: "best_fields",
                            query: "the piano",
                            fields: ["title|*text*"]
                          }
                        },
                         ...
                      ]
                    }
                  },
                  filter: [
                    {"terms":{"item_type":["t","d","p","j"]}},
                    ...
                  ]
                }
                /,
            }, {
               type => 'object',
               options => q/
                    Hash of additional search options:

                        search_org - Holdings filter org unit ID.
    
                        search_depth - Holdings filter search depth.

                        available - Ensure that at least one item is 
                            considered available within the search scope.
                /
            }
        ],
        return => { 
            desc => q/A search result object formatted to be consistent
                with the open-ils.search.biblio.multiclass and related APIs/
        }
    }
);

__PACKAGE__->register_method(
    method   => 'bib_search',
    api_name => 'open-ils.search.elastic.bib_search.staff',
    signature => {desc => q/Staff version of open-ils.search.elastic.bib_search /}
);

__PACKAGE__->register_method(
    method   => 'bib_search',
    api_name => 'open-ils.search.elastic.bib_search.metabib',
    signature => {desc => q/Staff version of open-ils.search.elastic.bib_search /}
);

__PACKAGE__->register_method(
    method   => 'bib_search',
    api_name => 'open-ils.search.elastic.bib_search.metabib.staff',
    signature => {desc => q/Staff version of open-ils.search.elastic.bib_search /}
);


# Augment and relay an Elastic query to the Elasticsearch backend.
# Translate search results into a structure consistent with a bib search
# API response.
sub bib_search {
    my ($self, $client, $query, $options) = @_;
    $options ||= {};

    init();

    my $staff = ($self->api_name =~ /staff/);
    my $meta = ($self->api_name =~ /metabib/);

    return {count => 0, ids => []} unless $query && $query->{query};

    # Only ask ES to return the 'id' field from the source bibs in
    # the response object, since that's all we need.
    $query->{_source} = [$meta ? 'metarecord' : 'id'];

    my $elastic_query = compile_elastic_query($query, $options, $staff);

    my $from = $elastic_query->{from} || 0;
    my $size = $elastic_query->{size} || 20;

    if ($meta) {
        $elastic_query->{collapse} = {field => 'metarecord'};
        # ES field collapse queries return counts for matched documents
        # instead of matched groups.  To determine the metarecord hit
        # count (up to 1k), fetch up to 1k responses and count them.
        $elastic_query->{from} = 0;
        $elastic_query->{size} = 1000;
    }

    my $es = OpenILS::Elastic::BibSearch->new('main');

    $es->connect;
    my $results = $es->search($elastic_query);

    $logger->debug("ES elasticsearch returned: ".
        OpenSRF::Utils::JSON->perl2JSON($results));

    return {count => 0, ids => []} unless $results;

    # Elastic has its own search cacheing, so no memcache'ing is 
    # required , but providing cache keys allows the caller to 
    # know if this search matches another search.
    # Lazily generate a cache key from the JSON string of the search.
    # This is not guaranteed to be 1-to-1 given key shuffling, but meh.
    my $cache_key = md5_hex(OpenSRF::Utils::JSON->perl2JSON($elastic_query));

    my $hits = $results->{hits}->{hits};
    if ($meta) {
        # count the number of groups represented in the result set.
        $results->{hits}->{total} = scalar(@$hits);

        # Only return the requested window of hits to the caller.
        $hits = [ grep {defined $_} @$hits[$from .. ($from + $size)] ];
    }

    my $ids = [
        map {[
            $meta ? $_->{_source}->{'metarecord'} : $_->{_id}, 
            undef, 
            $_->{_score}
        ]} @$hits
    ];

    return {
        ids => $ids,
        count => $results->{hits}->{total},
        facets => format_facets($results->{aggregations}),
        cache_key => $cache_key,
        facet_key => $cache_key.'_facets'
    };
}

sub compile_elastic_query {
    my ($elastic, $options, $staff) = @_;

    # We require a boolean root node to collect all the other stuff.
    $elastic->{query}->{bool} = {must => $elastic->{query}}
        unless $elastic->{query}->{bool};

    # coerce the filter into an array so we can append to it.
    my $filters = $elastic->{query}->{bool}->{filter};
    if ($filters) {
        $elastic->{query}->{bool}->{filter} = [$filters] 
            unless ref $filters eq 'ARRAY';
    } else {
        $elastic->{query}->{bool}->{filter} = [];
    }

    add_elastic_holdings_filter($elastic, $staff, 
        $options->{search_org}, $options->{search_depth}, $options->{available});

    add_elastic_facet_aggregations($elastic);

    $elastic->{sort} = ['_score'] unless @{$elastic->{sort} || []};

    return $elastic;
}

# Format ES search aggregations to match the API response facet structure
# {$cmf_id => {"Value" => $count}, $cmf_id2 => {"Value Two" => $count2}, ...}
sub format_facets {
    my $aggregations = shift;
    my $facets = {}; 

    for my $fname (keys %$aggregations) {

        my ($field_class, $name) = split(/\|/, $fname);

        my ($bib_field) = grep {
            $_->name eq $name && $_->search_group eq $field_class
        } @$bib_fields;

        my $hash = $facets->{$bib_field->metabib_field} = {};

        my $values = $aggregations->{$fname}->{buckets};
        for my $bucket (@$values) {
            $hash->{$bucket->{key}} = $bucket->{doc_count};
        }
    }

    return $facets;
}

sub add_elastic_facet_aggregations {
    my ($elastic_query) = @_;

    my @facet_fields = grep {$_->facet_field eq 't'} @$bib_fields;
    return unless @facet_fields;

    $elastic_query->{aggs} = {};

    for my $facet (@facet_fields) {
        my $fname = $facet->name;
        my $fgrp = $facet->search_group;
        $fname = "$fgrp|$fname" if $fgrp;

        $elastic_query->{aggs}{$fname} = {terms => {field => "$fname.facet"}};
    }
}

sub add_elastic_holdings_filter {
    my ($elastic_query, $staff, $org_id, $depth, $available) = @_;

    # in non-staff mode, ensure at least one copy in scope is visible
    my $visible = !$staff;

    if ($org_id) {
        my ($org) = $U->fetch_org_unit($org_id);
        my $types = $U->get_org_types; # pulls from cache
        my ($type) = grep {$_->id == $org->ou_type} @$types;
        $depth = defined $depth ? min($depth, $type->depth) : $type->depth;
    }

    my $visible_filters = {
        query => {
            bool => {
                must_not => [
                    {terms => {'holdings.status' => $hidden_copy_statuses}},
                    {terms => {'holdings.location' => $hidden_copy_locations}}
                ]
            }
        }
    };
    
    my $filter = {nested => {path => 'holdings', query => {bool => {}}}};

    if ($depth > 0) {

        if (!$org_data_cache{ancestors_at}{$org_id}) {
            $org_data_cache{ancestors_at}{$org_id} = {};
        }

        if (!$org_data_cache{ancestors_at}{$org_id}{$depth}) {
            $org_data_cache{ancestors_at}{$org_id}{$depth} = 
                $U->get_org_descendants($org_id, $depth);
        }

        my $org_ids = $org_data_cache{ancestors_at}{$org_id}{$depth};

        # Add a boolean OR-filter on holdings circ lib and optionally
        # add a boolean AND-filter on copy status for availability
        # checking.

        my $should = [];
        $filter->{nested}->{query}->{bool}->{should} = $should;

        for my $aou_id (@$org_ids) {

            # Ensure at least one copy exists at the selected org unit
            my $and = {
                bool => {
                    must => [
                        {term => {'holdings.circ_lib' => $aou_id}}
                    ]
                }
            };

            # When limiting to visible/available, ensure at least one of the
            # copies from the above org-limited set is visible/available.
            if ($available) {
                push(
                    @{$and->{bool}{must}}, 
                    {terms => {'holdings.status' => $avail_copy_statuses}}
                );

            } elsif ($visible) {
                push(@{$and->{bool}{must}}, $visible_filters);
            }

            push(@$should, $and);
        }

    } elsif ($available) {
        # Limit to results that have an available copy, but don't worry
        # about where the copy lives, since we're searching globally.

        $filter->{nested}->{query}->{bool}->{must} = 
            [{terms => {'holdings.status' => $avail_copy_statuses}}];

    } elsif ($visible) {

        $filter->{nested}->{query} = $visible_filters->{query};

    } elsif ($staff) {

        $logger->info("ES skipping holdings filter on global staff search");
        return;
    }

    $logger->info("ES holdings filter is " . 
        OpenSRF::Utils::JSON->perl2JSON($filter));

    # If we reach this point, we are performing some level of holdings
    # filtering.  Transcendant bib records are considered visible and
    # available, so allow them to bubble up through the holdings filter.
    if (@$transcendant_sources) {
        $filter = {
            bool => {must => { # 'must' enforce at least one 'should'
                bool => {should => [
                    {terms => {bib_source => $transcendant_sources}},
                    $filter
                ]}
            }}
        };
    }

    # array of filters in progress
    push(@{$elastic_query->{query}->{bool}->{filter}}, $filter);
}

1;

