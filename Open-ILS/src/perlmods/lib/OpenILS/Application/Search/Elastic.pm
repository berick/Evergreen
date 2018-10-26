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
    my ($class, $query, $offset, $limit) = @_;

    if (!$bib_search_fields) {
        # gather fields and flesh with crad / cmf
    }

    my $elastic_query = translate_elastic_query($query, $offset, $limit);

    my $es = OpenILS::Elastic::BibSearch->new('main');

    $es->connect;
    my $results = $es->search($elastic_query);

    return {count => 0} unless $results;

    return {
        count => $results->{hits}->{total},
        ids => [
            map { [$_->{_id}, undef, $_->{_score}] } 
                grep {defined $_} @{$results->{hits}->{hits}}
        ]
    };
}

sub translate_elastic_query {
    my ($query, $offset, $limit) = @_;

    my ($available) = ($query =~ s/(\#available)//g);
    my ($descending) = ($query =~ s/(\#descending)//g);

    my @funcs = qw/site depth sort item_lang/; # todo add others
    my %calls;

    for my $func (@funcs) {
        my ($val) = ($query =~ /$func\(([^\)]+)\)/);
        if (defined $val) {
            # scrub from query string
            $query =~ s/$func\(([^\)]+)\)//g;
            $calls{$func} = $val;
        }
    }

    my $elastic_query = {
        # Fetch only the bib ID field from each source document
        _source => ['id'],
        size => $limit,
        from => $offset,
        query => {
            bool => {
                must => {
                    query_string => {
                        default_field => 'keyword',
                        query => $query
                    }
                }
            }
        }
    };

    if (my $sn = $calls{site}) {
        add_elastic_holdings_filter(
            $elastic_query, $sn, $calls{depth}, $available);
    }

    if (my $key = $calls{sort}) {

        # These sort fields match the default display field entries.
        # TODO: index fields specific to sorting

        my $dir = $descending ? 'desc' : 'asc';
        if ($key =~ /title/) {
            $elastic_query->{sort} = [
                {'titlesort' => $dir},
            ];
            
        } elsif ($key =~ /author/) {
            $elastic_query->{sort} = [
                {'authorsort' => $dir},
            ];

        } elsif ($key =~ /pubdate/) {
            $elastic_query->{sort} = [
                {'pubdate' => $dir}
            ];
        }
    }

    return $elastic_query;
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
        $elastic_query->{query}->{bool}->{filter} = {
            nested => {
                path => 'holdings',
                query => {bool => {should => []}}
            }
        };

        my $should = 
            $elastic_query->{query}{bool}{filter}{nested}{query}{bool}{should};

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

        $elastic_query->{query}->{bool}->{filter} = {
            nested => {
                path => 'holdings',
                query => {bool => {must => [
                    # TODO: consult config.copy_status.is_available
                    {terms => {'holdings.status' => [0, 7]}}
                ]}}
            }
        };
    }
}

1;

