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
use OpenILS::Elastic::BibMarc;
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
our $enabled = {};

sub child_init {
    my $class = shift;

    my $e = new_editor();

    $bib_fields = $e->retrieve_all_elastic_bib_field;

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

    return 1;
}

__PACKAGE__->register_method(
    method   => 'bib_search',
    api_name => 'open-ils.search.elastic.bib_search'
);

__PACKAGE__->register_method(
    method   => 'bib_search',
    api_name => 'open-ils.search.elastic.bib_search.staff'
);

# Translate a bib search API call into something consumable by Elasticsearch
# Translate search results into a structure consistent with a bib search
# API response.
sub bib_search {
    my ($self, $client, $options, $query) = @_;
    $options ||= {};

    my $staff = ($self->api_name =~ /staff/);

    $logger->info("ES parsing API query $query staff=$staff");

    my ($elastic_query, $cache_key) = 
        compile_elastic_query($query, $options, $options);

    my $es = OpenILS::Elastic::BibSearch->new('main');

    $es->connect;
    my $results = $es->search($elastic_query);

    $logger->debug("ES elasticsearch returned: ".
        OpenSRF::Utils::JSON->perl2JSON($results));

    return {count => 0, ids => []} unless $results;

    return {
        count => $results->{hits}->{total},
        ids => [
            map { [$_->{_id}, undef, $_->{_score}] } 
                grep {defined $_} @{$results->{hits}->{hits}}
        ],
        facets => format_facets($results->{aggregations}),
        # Elastic has its own search cacheing, so external caching is
        # performed, but providing cache keys allows the caller to 
        # know if this search matches another search.
        cache_key => $cache_key,
        facet_key => $cache_key.'_facets'
    };
}

sub compile_elastic_query {
    my ($query, $options, $staff) = @_;

    my $elastic = {
        _source => ['id'], # Fetch bib ID only
        size => $options->{limit},
        from => $options->{offset},
        sort => $query->{sort},
        query => {
            bool => {
                must => [],
                filter => $query->{filters} || []
            }
        }
    };

    append_search_nodes($elastic, $_) for @{$query->{searches}};

    add_elastic_holdings_filter($elastic, $staff, 
        $query->{search_org}, $query->{search_depth}, $query->{available});

    add_elastic_facet_aggregations($elastic);

    $elastic->{sort} = ['_score'] unless @{$elastic->{sort}};

    return $elastic;
}


# Translate the simplified boolean search nodes into an Elastic
# boolean structure with the appropriate index names.
sub append_search_nodes {
    my ($elastic, $search) = @_;

    my ($field_class, $field_name) = split(/\|/, $search->{field});
    my $match_op = $search->{match_op};
    my $value = $search->{value};

    my @fields;
    if ($field_name) {
        @fields = ($field_name);

    } else {
        # class-level searches are OR ("should") searches across all
        # fields in the selected class.

        @fields = map {$_->name} 
            grep {$_->search_group eq $field_class} @$bib_fields;
    }

    $logger->info("ES adding searches for class=$field_class and fields=@fields");

    my $must_not = $match_op eq 'must_not';

    # Build a must_not query as a collection of must queries, which will 
    # be combined under a single must_not parent query.
    $match_op = 'must' if $must_not; 

    # for match queries, treat multi-word search as AND searches
    # instead of the default ES OR searches.
    $value = {query => $value, operator => 'and'} if $match_op eq 'match';

    my $field_nodes = [];
    for my $field (@fields) {
        my $key = "$field_class|$field";

        if ($match_op eq 'term' || $match_op eq 'match_phrase_prefix') {

            # Use the lowercase normalized keyword index for exact-match searches.
            push(@$field_nodes, {$match_op => {"$key.lower" => $value}});

        } else {

            # use the full-text indices
            
            push(@$field_nodes, 
                {$match_op => {"$key.text" => $value}});

            push(@$field_nodes, 
                {$match_op => {"$key.text_folded" => $value}});
        }
    }

    my $query_part;
    if (scalar(@$field_nodes) == 1) {
        $query_part = {bool => {must => $field_nodes}};
    } else {
        # Query multiple fields within a search class via OR query.
        $query_part = {bool => {should => $field_nodes}};
    }

    if ($must_not) {
        # Negation query.  Wrap the whole shebang in a must_not
        $query_part = {bool => {must_not => $query_part}};
    }

    $logger->info("ES field search part: ". 
        OpenSRF::Utils::JSON->perl2JSON($query_part));

    push(@{$elastic->{query}->{bool}->{must}}, $query_part);
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

        $elastic_query->{aggs}{$fname} = {terms => {field => $fname}};
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

    # array of filters in progress
    push(@{$elastic_query->{query}->{bool}->{filter}}, $filter);
}


sub compile_elastic_marc_query {
    my ($args, $staff, $offset, $limit) = @_;

    # args->{searches} = 
    #   [{term => "harry", restrict => [{tag => 245, subfield => "a"}]}]

    my $root_and = [];
    for my $search (@{$args->{searches}}) {

        # NOTE Assume only one tag/subfield will be queried per search term.
        my $tag = $search->{restrict}->[0]->{tag};
        my $sf = $search->{restrict}->[0]->{subfield};
        my $value = $search->{term};

        # Use text searching on the value field
        my $value_query = {
            bool => {
                should => [
                    {match => {'marc.value.text' => 
                        {query => $value, operator => 'and'}}},
                    {match => {'marc.value.text_folded' => 
                        {query => $value, operator => 'and'}}}
                ]
            }
        };

        my @must = ($value_query);

        # tag (ES-only) and subfield are both optional
        push (@must, {term => {'marc.tag' => $tag}}) if $tag;
        push (@must, {term => {'marc.subfield' => $sf}}) if $sf && $sf ne '_';

        my $sub_query = {bool => {must => \@must}};

        push (@$root_and, {
            nested => {
                path => 'marc',
                query => {bool => {must => $sub_query}}
            }
        });
    }

    return { 
        _source => ['id'], # Fetch bib ID only
        size => $limit,
        from => $offset,
        sort => [],
        query => {
            bool => {
                must => $root_and,
                filter => []
            }
        }
    };
}



# Translate a MARC search API call into something consumable by Elasticsearch
# Translate search results into a structure consistent with a bib search
# API response.
# TODO: This version is not currently holdings-aware, meaning it will return
# results for all non-deleted bib records that match the query.
sub marc_search {
    my ($class, $args, $staff, $limit, $offset) = @_;

    return {count => 0, ids => []} 
        unless $args->{searches} && @{$args->{searches}};

    my $elastic_query =
        compile_elastic_marc_query($args, $staff, $offset, $limit);

    my $es = OpenILS::Elastic::BibMarc->new('main');

    $es->connect;
    my $results = $es->search($elastic_query);

    $logger->debug("ES elasticsearch returned: ".
        OpenSRF::Utils::JSON->perl2JSON($results));

    return {count => 0, ids => []} unless $results;

    my @bib_ids = map {$_->{_id}} 
        grep {defined $_} @{$results->{hits}->{hits}};

    return {
        ids => \@bib_ids,
        count => $results->{hits}->{total}
    };
}



1;

