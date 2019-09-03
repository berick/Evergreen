package OpenILS::Application::Search::ElasticMapper;
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
use OpenILS::Elastic::Bib::Search;
#use OpenILS::Elastic::Bib::Marc;
use List::Util qw/min/;
use Digest::MD5 qw(md5_hex);

use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

# Use the QueryParser module to make sense of the inbound search query.
use OpenILS::Application::Storage::Driver::Pg::QueryParser;


# avoid repetitive calls to DB for org info.
my %org_data_cache = (by_shortname => {}, ancestors_at => {});

# bib fields defined in the elastic bib-search index
my $bib_fields;
my $hidden_copy_statuses;
my $hidden_copy_locations;
my $avail_copy_statuses;
our $enabled = {};

# Returns true if the Elasticsearch 'bib-search' index is active.
sub is_enabled {
    my ($class, $index) = @_;

    $class->init;

    return $enabled->{$index} if exists $enabled->{$index};

    # Elastic bib search is enabled if a "bib-search" index is enabled.
    my $config = new_editor()->search_elastic_index(
        {active => 't', code => $index})->[0];

    if ($config) {
        $logger->info("ES '$index' index is enabled");
        $enabled->{$index} = 1;
    } else {
        $enabled->{$index} = 0;
    }

    return $enabled->{$index};
}

my $init_complete = 0;
sub init {
    my $class = shift;
    return if $init_complete;

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

    $init_complete = 1;
    return 1;
}

# Translate a bib search API call into something consumable by Elasticsearch
# Translate search results into a structure consistent with a bib search
# API response.
sub bib_search {
    my ($class, $query, $staff, $offset, $limit) = @_;

    $logger->info("ES parsing API query $query staff=$staff");

    my ($elastic_query, $cache_key) = 
        compile_elastic_query($query, $staff, $offset, $limit);

    my $es = OpenILS::Elastic::Bib::Search->new('main');

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
    my ($query, $staff, $offset, $limit) = @_;

    my $parser = init_query_parser($query);

    $parser->parse;
    my $query_struct = $parser->parse_tree->to_abstract_query;

    my $elastic = {
        _source => ['id'], # Fetch bib ID only
        size => $limit,
        from => $offset,
        sort => [],
        query => {
            bool => {
                must => [],
                filter => []
            }
        }
    };

    $elastic->{query}->{bool}->{must} = 
        [translate_query_node($elastic, $query_struct)];

    add_elastic_holdings_filter($elastic, $staff, 
        $elastic->{__site}, $elastic->{__depth}, $elastic->{__available});

    add_elastic_facet_aggregations($elastic);

    # delete __-prefixed state maintenance keys.
    delete $elastic->{$_} for (grep {$_ =~ /^__/} keys %$elastic);

    $elastic->{sort} = ['_score'] unless @{$elastic->{sort}};

    return $elastic;
}

sub translate_query_node {
    my ($elastic, $node) = @_;

    if ($node->{type} eq 'query_plan') {

        my ($joiner) = keys %{$node->{children}};
        my $children = $node->{children}->{$joiner};
        my $filters  = $node->{filters};
        my $modifiers = $node->{modifiers};

        if (grep {$_ eq 'descending'} @$modifiers) {
            $elastic->{__sort_dir} = 'desc';
        }

        if (grep {$_ eq 'available'} @$modifiers) {
            $elastic->{__available} = 1;
        }

        return unless @$children || @$filters;

        my $bool_op = $joiner eq '&' ? 'must' : 'should';
        my $bool_nodes = [];
        my $filter_nodes = [];
        my $query = {
            bool => {
                $bool_op => $bool_nodes,
                filter => $filter_nodes
            }
        };

        for my $child (@$children) {
            my $type = $child->{type};

            if ($type eq 'node' || $type eq 'query_plan') {
                my $subq = translate_query_node($elastic, $child);
                push(@$bool_nodes, $subq) if defined $subq;

            } elsif ($type eq 'facet') {

                for my $value (@{$child->{values}}) {
                    push(@$filter_nodes, {term => {$child->{name} => $value}});
                }
            }
        }

        for my $filter (@$filters) {
            my $name = $filter->{name};
            my @values = @{$filter->{args}};

            # Sorting is managed at the root of the ES search structure.
            # QP assumes all sorts are ascending or descending -- possible
            # only one sort filter per struct is supported?
            if ($name eq 'sort') {
                my $dir = $elastic->{__sort_dir} || 'asc';
                push(@{$elastic->{sort}}, {$_ => $dir}) for @values;

            } elsif ($name =~ /site|depth/) {
                # site and depth are copy-level filters.
                # Apply those after the main structure is built.
                $elastic->{"__$name"} = $values[0];

            } else {
                if (@values > 1) {
                    push(@$filter_nodes, {terms => {$name => \@values}});
                } else {
                    push(@$filter_nodes, {term => {$name => $values[0]}});
                }
            }
        }

        # trim and compress branches
        if (!@$filter_nodes) {
            delete $query->{bool}{filter};
            return $bool_nodes->[0] if scalar(@$bool_nodes) == 1;

        } elsif (!@$bool_nodes) {
           # If this is a filter-only node, add a match-all 
           # query for the filter to have something to match on.
           $query->{bool}{must} = {match_all => {}};
        }

        return $query;

    } elsif ($node->{type} eq 'node') {

        my $field_class = $node->{class}; # e.g. subject
        my @fields = @{$node->{fields}};  # e.g. temporal (optional)

        $logger->info("ES query node field_class=$field_class fields=@fields");

        # class-level searches are OR ("should") searches across all
        # fields in the selected class.
        @fields = map {$_->name} 
            grep {$_->search_group eq $field_class} @$bib_fields
            unless @fields;

        # note: $joiner is always '&' for type=node
        my ($joiner) = keys %{$node->{children}};
        my $children = $node->{children}->{$joiner};

        # Content is only split across children when multiple words
        # are part of the same query structure, e.g. kw:piano music
        # This equates to a match search with multiple words in ES.
        my $content = join(' ', map {$_->{content}} @$children);

        # not sure how/why this happens sometimes.
        return undef unless $content;

        my $first_char = substr($content, 0, 1);
        my $last_char = substr($content, -1, 1);
        my $prefix = $children->[0]->{prefix};

        my $match_type = 'most_fields';

        # "Contains Phrase"
        $match_type = 'phrase' if $prefix eq '"';

        my @field_nodes;

        # Matchiness specificiers embedded in the content override
        # the query node prefix.
        if ($first_char eq '^') {
            $content = substr($content, 1);

            if ($last_char eq '$') { # "Matches Exactly" 

                $match_type = undef;
                $content = substr($content, 0, -1);

                for my $field (@fields) {
                    my $key = "$field_class|$field";
                    # Use the lowercase normalized keyword index for 
                    # exact match searches.
                    push(@field_nodes, {term => {"$key.lower" => $content}});
                }

            } else { # "Starts With"

                $match_type = 'phrase_prefix';
            }
        }

        if ($match_type) {

            push(@field_nodes, {
                multi_match => {
                    query => $content,
                    operator => 'and',
                    fields => ["$field_class|*.text*"],
                    type => $match_type
                }
            });
        }

        $logger->info(
            "ES content = ". OpenSRF::Utils::JSON->perl2JSON($content) . 
            "; bools = ". OpenSRF::Utils::JSON->perl2JSON(\@field_nodes)
        );

        my $query;
        if (scalar(@field_nodes) == 1) {
            $query = {bool => {must => \@field_nodes}};
        } else {
            # Query multiple fields within a search class via OR query.
            $query = {bool => {should => \@field_nodes}};
        }

        if ($prefix eq '-"') {
            # Negation query.  Wrap the whole shebang in a must_not
            $query = {bool => {must_not => $query}};
        }

        $logger->info("ES sub-query = ". OpenSRF::Utils::JSON->perl2JSON($query));

        return $query;
    }
}

sub init_query_parser {
    my $query = shift;

    my $query_parser = 
        OpenILS::Application::Storage::Driver::Pg::QueryParser->new(
            query => $query
        );

    my %attrs = get_qp_attrs();
    $query_parser->initialize(%attrs);

    return $query_parser;
}

my %qp_attrs;
sub get_qp_attrs {
    return %qp_attrs if %qp_attrs;

    # Fetch and cache the QP configuration attributes
    # TODO: call this in service child_init()?

    $logger->debug("ES initializing query parser attributes");
    my $e = new_editor();

    %qp_attrs = (
        config_record_attr_index_norm_map  =>
            $e->search_config_record_attr_index_norm_map([
                { id => { "!=" => undef } },
                { flesh => 1, flesh_fields  => { crainm => [qw/norm/] }, 
                    order_by => [{ class => "crainm", field => "pos" }] }
            ]),
        search_relevance_adjustment =>
            $e->retrieve_all_search_relevance_adjustment,
        config_metabib_field => 
            $e->retrieve_all_config_metabib_field,
        config_metabib_field_virtual_map => 
            $e->retrieve_all_config_metabib_field_virtual_map,
        config_metabib_search_alias =>
            $e->retrieve_all_config_metabib_search_alias,
        config_metabib_field_index_norm_map =>
            $e->search_config_metabib_field_index_norm_map([
                { id => { "!=" => undef } },
                { flesh => 1, flesh_fields => { cmfinm => [qw/norm/] }, 
                    order_by => [{ class => "cmfinm", field => "pos" }] }
            ]),
        config_record_attr_definition =>
            $e->retrieve_all_config_record_attr_definition
    );

    return %qp_attrs;
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

        $elastic_query->{aggs}{$fname} = {terms => {field => "$fname.raw"}};
    }
}

sub add_elastic_holdings_filter {
    my ($elastic_query, $staff, $shortname, $depth, $available) = @_;

    # in non-staff mode, ensure at least on copy in scope is visible
    my $visible = !$staff;

    my $org;
    if ($shortname) {

        if (!$org_data_cache{by_shortname}{$shortname}) {
            $org_data_cache{by_shortname}{$shortname} = 
                $U->find_org_by_shortname($U->get_org_tree, $shortname);
        }

        $org = $org_data_cache{by_shortname}{$shortname};

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

        my $should = [];
        $filter->{nested}->{query}->{bool}->{should} = $should;

        for my $org_id (@$org_ids) {

            # Ensure at least one copy exists at the selected org unit
            my $and = {
                bool => {
                    must => [
                        {term => {'holdings.circ_lib' => $org_id}}
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
            multi_match => {
                query => $value,
                fields => ['marc.value*'],
                type => 'most_fields',
                operator => 'and'
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
# results for all non-deleted bib records that match the query.  However,
# the data does exist in the EL index.  Just need to integrate.
sub marc_search {
    my ($class, $args, $staff, $limit, $offset) = @_;

    return {count => 0, ids => []} 
        unless $args->{searches} && @{$args->{searches}};

    my $elastic_query =
        compile_elastic_marc_query($args, $staff, $offset, $limit);

    my $es = OpenILS::Elastic::Bib::Search->new('main');

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

