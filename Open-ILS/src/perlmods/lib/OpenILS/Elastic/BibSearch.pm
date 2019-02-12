package OpenILS::Elastic::BibSearch;
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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR code.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
use strict;
use warnings;
use Encode;
use DateTime;
use Time::HiRes qw/time/;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenSRF::Utils::JSON;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::DateTime qw/interval_to_seconds/;
use OpenILS::Elastic;
use base qw/OpenILS::Elastic/;

my $INDEX_NAME = 'bib-search';

# number of bibs to index per batch.
my $BIB_BATCH_SIZE = 500;

# TODO: it's possible to apply multiple language analyzers.
my $LANG_ANALYZER = 'english';

my $BASE_INDEX_SETTINGS = {
    analysis => {
        analyzer => {
            folding => {
                filter => ['lowercase', 'asciifolding'],
                tokenizer => 'standard'
            }
        },
        normalizer =>  {
            custom_lowercase => {
                type => 'custom',
                filter => ['lowercase']
            }
        }
    }
};

# Well-known bib-search index properties
my $BASE_PROPERTIES = {
    source      => {type => 'integer', index => 'false'},
    create_date => {type => 'date', index => 'false'},
    edit_date   => {type => 'date', index => 'false'},

    # Holdings summaries.  For bib-search codes, we don't need
    # copy-specific details, only aggregate visibility information.
    holdings => {
        type => 'nested',
        properties => {
            status => {type => 'integer'},
            circ_lib => {type => 'integer'},
            location => {type => 'integer'},
            circulate => {type => 'boolean'},
            opac_visible => {type => 'boolean'}
        }
    }
};

sub index_name {
    return $INDEX_NAME;
}

sub index {
    my $self = shift;
    return $self->{index} if $self->{index};
    ($self->{index}) = grep {$_->code eq $INDEX_NAME} @{$self->indices};
    return $self->{index};
}

sub create_index {
    my ($self) = @_;

    if ($self->es->indices->exists(index => $INDEX_NAME)) {
        $logger->warn("ES index '$INDEX_NAME' already exists");
        return;
    }

    $logger->info(
        "ES creating index '$INDEX_NAME' on cluster '".$self->cluster."'");

    my $mappings = $BASE_PROPERTIES;

    my $fields = new_editor()->retrieve_all_elastic_bib_field();

    for my $field (@$fields) {

        my $field_name = $field->name;
        my $search_group = $field->search_group;
        $field_name = "$search_group|$field_name" if $search_group;

        # Every field gets a keyword index (default) for aggregation and 
        # a lower-case keyword index (.lower) for sorting and certain
        # types of searches (exact match, starts with)
        my $def = {
            type => 'keyword',
            fields => {
                lower => {
                    type => 'keyword', 
                    normalizer => 'custom_lowercase'
                }
            }
        };

        if ($field->search_field eq 't') {
            # Search fields also get full text indexing and analysis
            # plus a "folded" variation for ascii folded searches.

            $def->{fields}->{text} = {
                type => 'text',
                analyzer => $LANG_ANALYZER
            };

            $def->{fields}->{text_folded} = {
                type => 'text', 
                analyzer => 'folding'
            };
        }

        # Apply field boost.
        $def->{boost} = $field->weight if ($field->weight || 1) > 1;

        $logger->info("ES adding field $field_name: ". 
            OpenSRF::Utils::JSON->perl2JSON($def));

        $mappings->{$field_name} = $def;
    }

    my $settings = $BASE_INDEX_SETTINGS;
    $settings->{number_of_replicas} = scalar(@{$self->nodes});
    $settings->{number_of_shards} = $self->index->num_shards;

    my $conf = {
        index => $INDEX_NAME,
        body => {
            settings => $settings,
            mappings => {record => {properties => $mappings}}
        }
    };

    # Send the index definition to Elastic
    eval { $self->es->indices->create($conf) };

    if ($@) {
        $logger->error("ES failed to create index cluster=".  
            $self->cluster. "index=$INDEX_NAME error=$@");
        print "$@\n\n";
        return 0;
    }

    return 1;
}

# Add data to the bib-search index
sub populate_index {
    my ($self, $settings) = @_;
    $settings ||= {};

    my $index_count = 0;
    my $total_indexed = 0;

    # extract the database settings.
    for my $db_key (grep {$_ =~ /^db_/} keys %$settings) {
        $self->{$db_key} = $settings->{$db_key};
    }

    # TODO $settings->{stop_record}
    # TODO $settings->{start_date}

    my $end_time;
    my $duration = $settings->{max_duration};
    if ($duration) {
        my $seconds = interval_to_seconds($duration);
        $end_time = DateTime->now;
        $end_time->add(seconds => $seconds);
    }

    while (1) {

        $index_count = $self->populate_bib_index_batch($settings);
        $total_indexed += $index_count;

        $logger->info("ES indexed $total_indexed bib records");

        # exit if we're only indexing a single record or if the 
        # batch indexer says there are no more records to index.
        last if !$index_count || $settings->{index_record};

        if ($end_time && DateTime->now > $end_time) {
            $logger->info(
                "ES index populate exiting early on max_duration $duration");
            last;
        }
    } 

    $logger->info("ES bib indexing complete with $total_indexed records");
}

sub get_bib_ids {
    my ($self, $state) = @_;

    # A specific record is selected for indexing.
    return [$state->{index_record}] if $state->{index_record};

    my $start_id = $state->{start_record} || 0;
    my $stop_id = $state->{stop_record}; # TODO
    my $start_date = $state->{start_date};

    my ($select, $from, $where);
    if ($start_date) {
        $select = "SELECT id";
        $from   = "FROM elastic.bib_last_mod_date";
        $where  = "WHERE last_mod_date > '$start_date'";
    } else {
        $select = "SELECT id";
        $from   = "FROM biblio.record_entry";
        $where  = "WHERE NOT deleted AND active";
    }

    $where .= " AND id >= $start_id" if $start_id;
    $where .= " AND id <= $stop_id" if $stop_id;

    # Ordering by ID is the simplest way to guarantee all requested
    # records are processed, given that edit dates may not be unique
    # and that we're using start_id/stop_id instead of OFFSET to
    # define the batches.
    my $order = "ORDER BY id";

    my $sql = "$select $from $where $order LIMIT $BIB_BATCH_SIZE";

    my $ids = $self->get_db_rows($sql);
    return [ map {$_->{id}} @$ids ];
}

sub get_bib_data {
    my ($self, $record_ids) = @_;

    my $ids_str = join(',', @$record_ids);

    my $sql = <<SQL;
SELECT 
    bre.id, 
    bre.create_date, 
    bre.edit_date, 
    bre.source AS bib_source,
    (elastic.bib_record_properties(bre.id)).*
FROM biblio.record_entry bre
WHERE id IN ($ids_str)
SQL

    return $self->get_db_rows($sql);
}

sub populate_bib_index_batch {
    my ($self, $state) = @_;

    my $index_count = 0;

    my $bib_ids = $self->get_bib_ids($state);
    return 0 unless @$bib_ids;

    $logger->info("ES indexing ".scalar(@$bib_ids)." records");

    my $bib_data = $self->get_bib_data($bib_ids);

    my $holdings = $self->load_holdings($bib_ids);

    for my $bib_id (@$bib_ids) {

        my $body = {
            holdings => $holdings->{$bib_id} || []
        };

        # there are multiple rows per bib in the data list.
        my @fields = grep {$_->{id} == $bib_id} @$bib_data;

        my $first = 1;
        for my $field (@fields) {
        
            if ($first) {
                $first = 0;
                # some values are repeated per field. 
                # extract them from the first entry.
                $body->{bib_source} = $field->{bib_source};

                # ES ikes the "T" separator for ISO dates
                ($body->{create_date} = $field->{create_date}) =~ s/ /T/g;
                ($body->{edit_date} = $field->{edit_date}) =~ s/ /T/g;
            }

            my $fclass = $field->{search_group};
            my $fname = $field->{name};
            my $value = $field->{value};
            $fname = "$fclass|$fname" if $fclass;

            # Lucene has a hard limit on the size of an indexable chunk.
            # Avoid trying to index such data by lazily chopping it off
            # at 1/4 the limit to accomodate all UTF-8 chars.
            if (length(Encode::encode('UTF-8', $value)) > 32760) {
                $value = substr($value, 0, 8190);
            }

            if ($body->{$fname}) {
                if (ref $body->{$fname}) {
                    # Three or more values encountered for field.
                    # Add to the list.
                    push(@{$body->{$fname}}, $value);
                } else {
                    # Second value encountered for field.
                    # Upgrade to array storage.
                    $body->{$fname} = [$body->{$fname}, $value];
                }
            } else {
                # First value encountered for field.
                # Assume for now there will only be one value.
                $body->{$fname} = $value
            }
        }

        return 0 unless $self->index_document($bib_id, $body);

        $state->{start_record} = $bib_id + 1;
        $index_count++;
    }

    $logger->info("ES indexing completed for records " . 
        $bib_ids->[0] . '...' . $bib_ids->[-1]);

    return $index_count;
}

# Load holdings summary blobs for requested bibs
sub load_holdings {
    my ($self, $bib_ids) = @_;

    my $bib_ids_str = join(',', @$bib_ids);

    my $copy_data = $self->get_db_rows(<<SQL);
SELECT 
    COUNT(*) AS count,
    acn.record, 
    acp.status AS status, 
    acp.circ_lib AS circ_lib, 
    acp.location AS location,
    acp.circulate AS circulate,
    acp.opac_visible AS opac_visible
FROM asset.copy acp
JOIN asset.call_number acn ON acp.call_number = acn.id
WHERE 
    NOT acp.deleted AND
    NOT acn.deleted AND
    acn.record IN ($bib_ids_str)
GROUP BY 2, 3, 4, 5, 6, 7
SQL

    $logger->info("ES found ".scalar(@$copy_data).
        " holdings summaries for current record batch");

    my $holdings = {};
    for my $copy (@$copy_data) {

        $holdings->{$copy->{record}} = [] 
            unless $holdings->{$copy->{record}};

        push(@{$holdings->{$copy->{record}}}, {
            count => $copy->{count},
            status => $copy->{status},
            circ_lib => $copy->{circ_lib},
            location => $copy->{location},
            circulate => $copy->{circulate} ? 'true' : 'false',
            opac_visbile => $copy->{opac_visible} ? 'true' : 'false'
        });
    }

    return $holdings;
}

1;


