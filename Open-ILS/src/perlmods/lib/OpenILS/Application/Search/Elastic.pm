package OpenILS::Application::Search::Elastic;
# ---------------------------------------------------------------
# Copyright (C) 2018 King County Library System
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
use List::Util qw/min/;
use Digest::MD5 qw(md5_hex);

use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

# bib fields defined in the elastic bib-search index
my $bib_search_fields;

# avoid repetitive calls to DB for org info.
my %org_data_cache = (by_shortname => {}, ancestors_at => {});

# Translate a bib search API call into something consumable by Elasticsearch
# Translate search results into a structure consistent with a bib search
# API response.
sub bib_search {
    my ($class, $query, $staff, $offset, $limit) = @_;

    $logger->info("ES parsing API query $query");

    $bib_search_fields = 
        new_editor()->retrieve_all_elastic_bib_field()
        unless $bib_search_fields;

    my ($elastic_query, $cache_key) = 
        translate_elastic_query($query, $staff, $offset, $limit);

    $logger->info("ES sending query to elasticsearch: ".
        OpenSRF::Utils::JSON->perl2JSON($elastic_query));

    my $es = OpenILS::Elastic::BibSearch->new('main');

    $es->connect;
    my $results = $es->search($elastic_query);

    $logger->debug("ES elasticsearch returned: ".
        OpenSRF::Utils::JSON->perl2JSON($results));

    return {count => 0} unless $results;

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


sub format_facets {
    my $aggregations = shift;
    my $facets = {}; # cmf.id => {"Facet Value" => count}

    for my $fname (keys %$aggregations) {

        my ($field_class, $name) = split(/\|/, $fname);

        my ($bib_field) = grep {
            $_->name eq $name && $_->search_group eq $field_class
        } @$bib_search_fields;

        my $hash = $facets->{$bib_field->metabib_field} = {};

        my $values = $aggregations->{$fname}->{buckets};
        for my $bucket (@$values) {
            $hash->{$bucket->{key}} = $bucket->{doc_count};
        }
    }

    return $facets;
}

sub translate_elastic_query {
    my ($query, $staff, $offset, $limit) = @_;

    # Scrub functions and tags from the bare query so they may
    # be translated to elastic equivalents.  We only want the 
    # query portion to be passed as-is for the elastic query string

    my ($available) = ($query =~ s/(\#available)//g);
    my ($descending) = ($query =~ s/(\#descending)//g);

    # Remove unsupported tags (e.g. #deleted)
    $query =~ s/\#[a-z]+//ig;

    my @funcs = qw/site depth sort item_lang format/; 
    my %calls;

    for my $func (@funcs) {
        my ($val) = ($query =~ /$func\(([^\)]+)\)/);

        if (defined $val) {
            $query =~ s/$func\(([^\)]+)\)//g; # scrub
            $calls{$func} = $val;
        }
    }

    my @facets = ($query =~ /([a-z]+\|[a-z]+\[[^\]]+\])/g);
    $query =~ s/([a-z]+\|[a-z]+\[[^\]]+\])//g if @facets; # scrub

    my $cache_seed = "$query $staff $available ";
    for my $key (qw/site depth item_lang format/) { 
        $cache_seed .= " $key=" . $calls{$key} if defined $calls{$key};
    }

    my $cache_key = md5_hex($cache_seed);

    my $elastic_query = {
        _source => ['id'], # Fetch bib ID only
        size => $limit,
        from => $offset,
        query => {
            bool => {
                # TODO fix must array below
                must => {
                    query_string => {
                        default_operator => 'AND',
                        default_field => 'keyword',
                        query => $query
                    }
                },
                filter => []
            }
        }
    };

    if ($calls{format}) {
        push(
            @{$elastic_query->{query}->{bool}->{filter}},
            {term => {search_format => $calls{format}}}
        );
    }

    add_elastic_facet_filters($elastic_query, @facets);

    add_elastic_holdings_filter(
        $elastic_query, $calls{site}, $calls{depth}, $available)
        if $calls{site};

    add_elastic_facet_aggregations($elastic_query);

    if (my $sf = $calls{sort}) {
        my $dir = $descending ? 'desc' : 'asc';
        $elastic_query->{sort} = [{$sf => $dir}];
    }
        
    return ($elastic_query, $cache_key);
}

sub add_elastic_facet_filters {
    my ($elastic_query, @facets) = @_;
    return unless @facets;

    for my $facet (@facets) {
        # e.g. subject|topic[Piano music]
        my ($name, $value) = ($facet =~ /([a-z]+\|[a-z]+)\[([^\]]+)\]/g);

        my ($field) = grep {
            (($_->search_group || '') . '|' . $_->name) eq $name}
            @$bib_search_fields;
        
        # Search fields have a .raw multi-field for indexing the raw
        # (keyword) value for aggregation.  Non-search fields use
        # the base field, since it's already a keyword field.
        $name .= ".raw" if $field->search_field eq 't';

        push(
            @{$elastic_query->{query}->{bool}->{filter}}, 
            {term => {$name => $value}}
        );
    }
}

sub add_elastic_facet_aggregations {
    my ($elastic_query) = @_;

    my @facet_fields = grep {$_->facet_field eq 't'} @$bib_search_fields;
    return unless @facet_fields;

    $elastic_query->{aggs} = {};

    for my $facet (@facet_fields) {
        my $fname = $facet->name;
        my $fgrp = $facet->search_group;
        $fname = "$fgrp|$fname" if $fgrp;

        # Search fields have a .raw multi-field for indexing the
        # raw (keyword) value for aggregation.
        # Non-search fields use the base field, since it's already a 
        # keyword field.
        my $index = $fname;
        $index = "$fname.raw" if $facet->search_field eq 't';

        $elastic_query->{aggs}{$fname} = {terms => {field => $index}};
    }
}


sub add_elastic_holdings_filter {
    my ($elastic_query, $shortname, $depth, $available) = @_;

    if (!$org_data_cache{by_shortname}{$shortname}) {
        $org_data_cache{by_shortname}{$shortname} = 
            $U->find_org_by_shortname($U->get_org_tree, $shortname);
    }

    my $org = $org_data_cache{by_shortname}{$shortname};

    my $types = $U->get_org_types; # pulls from cache
    my ($type) = grep {$_->id == $org->ou_type} @$types;

    $depth = defined $depth ? min($depth, $type->depth) : $type->depth;

    # TODO: if $staff is false, add a holdings filter for 
    # opac_visble / location.opac_visible / status.opac_visible
    
    # array of filters in progress
    my $filters = $elastic_query->{query}->{bool}->{filter};

    if ($depth > 0) {

        if (!$org_data_cache{ancestors_at}{$shortname}) {
            $org_data_cache{ancestors_at}{$shortname} = {};
        }

        if (!$org_data_cache{ancestors_at}{$shortname}{$depth}) {
            $org_data_cache{ancestors_at}{$shortname}{$depth} = 
                $U->get_org_descendants($org->id, $depth);
        }

        my $org_ids = $org_data_cache{ancestors_at}{$shortname}{$depth};

        # Add a boolean OR-filter on holdings circ lib and optionally
        # add a boolean AND-filter on copy status for availability
        # checking.

        my $filter = {
            nested => {
                path => 'holdings',
                query => {bool => {should => []}}
            }
        };

        push(@$filters, $filter);

        my $should = $filter->{nested}{query}{bool}{should};

        for my $org_id (@$org_ids) {

            # Ensure at least one copy exists at the selected org unit
            my $and = {
                bool => {
                    must => [
                        {term => {'holdings.circ_lib' => $org_id}}
                    ]
                }
            };

            # When limiting to available, ensure at least one of the
            # above copies is in status 0 or 7.
            # TODO: consult config.copy_status.is_available
            push(
                @{$and->{bool}{must}}, 
                {terms => {'holdings.status' => [0, 7]}}
            ) if $available;

            push(@$should, $and);
        }

    } elsif ($available) {
        # Limit to results that have an available copy, but don't worry
        # about where the copy lives, since we're searching globally.

        my $filter = {
            nested => {
                path => 'holdings',
                query => {bool => {must => [
                    # TODO: consult config.copy_status.is_available
                    {terms => {'holdings.status' => [0, 7]}}
                ]}}
            }
        };

        push(@$filters, $filter);
    }
}

1;

