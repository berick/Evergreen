package OpenILS::Elastic::BibMarc;
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
use Data::Dumper;
$Data::Dumper::Indent = 0;

my $INDEX_NAME = 'bib-marc';

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

my $BASE_PROPERTIES = {
    source => {type => 'integer', index => 'false'},
    create_date => {type => 'date'},
    edit_date => {type => 'date'},
    bib_source => {type => 'integer'},
    marc => {
        type => 'nested',
        properties => {
            tag => {type => 'keyword'},
            subfield => {type => 'keyword'},
            value => {type => 'text'}
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

    if (!$self->{index}) {
        $logger->error("No index configuration exists for '$INDEX_NAME'");
        return undef;
    }

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
    my $settings = $BASE_INDEX_SETTINGS;
    $settings->{number_of_replicas} = scalar(@{$self->nodes});
    $settings->{number_of_shards} = $self->index->num_shards;

    my $conf = {
        index => $INDEX_NAME,
        body => {settings => $settings}
    };

    $logger->info("ES creating index '$INDEX_NAME'");

    # Create the base index with settings
    eval { $self->es->indices->create($conf) };

    if ($@) {
        $logger->error("ES failed to create index cluster=".  
            $self->cluster. "index=$INDEX_NAME error=$@");
        warn "$@\n\n";
        return 0;
    }

    # Create each mapping one at a time instead of en masse so we 
    # can more easily report when mapping creation fails.

    for my $field (keys %$mappings) {
        $logger->info("ES Creating index mapping for field $field");

        eval { 
            $self->es->indices->put_mapping({
                index => $INDEX_NAME,
                type  => 'record',
                body  => {properties => {$field => $mappings->{$field}}}
            });
        };

        if ($@) {
            my $mapjson = OpenSRF::Utils::JSON->perl2JSON($mappings->{$field});

            $logger->error("ES failed to create index mapping: " .
                "index=$INDEX_NAME field=$field error=$@ mapping=$mapjson");

            warn "$@\n\n";
            return 0;
        }
    }

    return 1;
}

sub populate_index {
    my ($self, $settings) = @_;
    $settings ||= {};

    my $index_count = 0;
    my $total_indexed = 0;

    # extract the database settings.
    for my $db_key (grep {$_ =~ /^db_/} keys %$settings) {
        $self->{$db_key} = $settings->{$db_key};
    }

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
    my $stop_id = $state->{stop_record};
    my $modified_since = $state->{modified_since};

    my ($select, $from, $where);
    if ($modified_since) {
        $select = "SELECT id";
        $from   = "FROM elastic.bib_last_mod_date";
        $where  = "WHERE last_mod_date > '$modified_since'";
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
    bre.deleted
FROM biblio.record_entry bre
WHERE bre.id IN ($ids_str)
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

    # Remove records that are marked deleted.
    # This should only happen when running in refresh mode.

    my @active_ids;
    for my $bib_id (@$bib_ids) {

        # Every row in the result data contains the 'deleted' value.
        my ($field) = grep {$_->{id} == $bib_id} @$bib_data;

        if ($field->{deleted} == 1) { # not 't' / 'f'
           $self->delete_documents($bib_id); 
        } else {
            push(@active_ids, $bib_id);
        }
    }

    $bib_ids = [@active_ids];

    my $marc = $self->load_marc($bib_ids);

    for my $bib_id (@$bib_ids) {

        my ($record) = grep {$_->{id} == $bib_id} @$bib_data;

        my $body = {
            marc => $marc->{$bib_id} || [],
            bib_source => $record->{bib_source},
        };

        ($body->{create_date} = $record->{create_date}) =~ s/ /T/g;
        ($body->{edit_date} = $record->{edit_date}) =~ s/ /T/g;

        return 0 unless $self->index_document($bib_id, $body);

        $state->{start_record} = $bib_id + 1;
        $index_count++;
    }

    $logger->info("ES indexing completed for records " . 
        $bib_ids->[0] . '...' . $bib_ids->[-1]);

    return $index_count;
}

sub load_marc {
    my ($self, $bib_ids) = @_;

    my $bib_ids_str = join(',', @$bib_ids);

    my $marc_data = $self->get_db_rows(<<SQL);
SELECT record, tag, subfield, value
FROM metabib.full_rec
WHERE record IN ($bib_ids_str)
SQL

    $logger->info("ES found ".scalar(@$marc_data).
        " full record rows for current record batch");

    my $marc = {};
    for my $row (@$marc_data) {

        my $value = $row->{value};
        next unless defined $value && $value ne '';

        my $subfield = $row->{subfield};
        my $rec_id = $row->{record};
        delete $row->{record}; # avoid adding this to the index

        $row->{value} = $value = $self->truncate_value($value);

        $marc->{$rec_id} = [] unless $marc->{$rec_id};
        delete $row->{subfield} unless defined $subfield;

        # Add values to existing record/tag/subfield rows.
  
        my $existing;
        for my $entry (@{$marc->{$rec_id}}) {
            next unless $entry->{tag} eq $row->{tag};

            if (defined $subfield) {
                if (defined $entry->{subfield}) {
                    if ($subfield eq $entry->{subfield}) {
                        $existing = $entry;
                        last;
                    }
                }
            } elsif (!defined $entry->{subfield}) {
                # Neither has a subfield value / not all tags have subfields
                $existing = $entry;
                last;
            }
        }

        if ($existing) {
            
            $existing->{value} = [$existing->{value}] unless ref $existing->{value};
            push(@{$existing->{value}}, $value);

        } else {

            push(@{$marc->{$rec_id}}, $row);
        }
    }

    return $marc;
}


1;


