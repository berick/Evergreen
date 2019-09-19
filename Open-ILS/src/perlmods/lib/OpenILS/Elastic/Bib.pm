package OpenILS::Elastic::Bib;
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

# default number of bibs to index per batch.
my $DEFAULT_BIB_BATCH_SIZE = 500;

sub index {
    my $self = shift;
    return $self->{index} if $self->{index};
    ($self->{index}) = grep {$_->code eq $self->index_name} @{$self->indices};

    $logger->error("No ndex configured named ".$self->index_name) unless $self->{index};

    return $self->{index};
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
    my $batch_size = $state->{batch_size} || $DEFAULT_BIB_BATCH_SIZE;

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

    my $sql = "$select $from $where $order LIMIT $batch_size";

    my $ids = $self->get_db_rows($sql);
    return [ map {$_->{id}} @$ids ];
}

1;


