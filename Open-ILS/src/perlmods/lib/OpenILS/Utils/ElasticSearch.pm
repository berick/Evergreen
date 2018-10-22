package OpenILS::Utils::ElasticSearch;
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
use Clone qw/clone/;
use DateTime;
use DBI;
use XML::LibXML;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::DateTime qw/:datetime/;
#use OpenILS::Utils::CStoreEditor qw/:funcs/;
use Search::Elasticsearch;

my $date_parser = DateTime::Format::ISO8601->new;
my $db_handle;

sub new {
    my ($class, %args) = @_;
    my $self = bless(
        {   clusters => {},
            config_file => $args{config_file}
        }, $class
    );
    $self->read_config;
    return $self;
}

sub get_db_conn {
	my ($self) = @_;
    return $db_handle if $db_handle;

    my $settings = $self->{config}->{'evergreen-database'};
    my $db_name = $settings->{name};
    my $db_host = $settings->{host};
    my $db_port = $settings->{port};
    my $db_user = $settings->{user};
    my $db_pass = $settings->{pass};

    my $dsn = "dbi:Pg:db=$db_name;host=$db_host;port=$db_port";
    $logger->debug("ES connecting to DB $dsn");

    $db_handle = DBI->connect(
        "$dsn;options='--statement-timeout=0'",
        $db_user, $db_pass, {
            RaiseError => 1,
            PrintError => 0,
            AutoCommit => 1,
            pg_expand_array => 0,
            pg_enable_utf8 => 1
        }
    ) or $logger->error(
        "ES Connection to database failed: $DBI::err : $DBI::errstr", 1);

    return $db_handle;
}

sub read_config {
    my $self = shift;

    open(CONFIG_FILE, $self->{config_file})
        or die "Cannot open elastic config " .$self->{config_file}. ": $!\n";

    my $json = join('', <CONFIG_FILE>);

    $self->{config} = OpenSRF::Utils::JSON->JSON2perl($json);

    close(CONFIG_FILE);
}

sub connect {
    my ($self, $cluster) = @_;

    my $nodes = $self->{config}{clusters}{$cluster}{nodes};

    $logger->info("ES connecting to nodes @$nodes");

    $self->{clusters}{$cluster} = {
        es => Search::Elasticsearch->new(nodes => $nodes)
    };
}

sub es {
    my ($self, $cluster) = @_;
    return $self->{clusters}{$cluster}{es};
}

sub delete_index {
    my ($self, $cluster, $index) = @_;

    if ($self->es($cluster)->indices->exists(index => $index)) {
        $logger->info("ES deleting index '$index' on cluster '$cluster'");
        $self->es($cluster)->indices->delete(index => $index);
    } else {
        $logger->warn("ES index '$index' does not exist");
    }
}

sub create_index {
    my ($self, $cluster, $index) = @_;

    if ($self->es($cluster)->indices->exists(index => $index)) {
        $logger->warn("ES index '$index' already exists");
        return;
    }

    $logger->info("ES creating index '$index' on cluster '$cluster'");

    my $config = $self->{config};

    my $es = $self->es($cluster);
    my $mappings = $config->{indexes}{$index}{'base-properties'};

    # TODO: a dynamic property may live in multiple indexes
    my @dynamics = grep {$_->{index} eq $index}
        @{$config->{'dynamic-properties'}};

    # Add an index definition for each dynamic field.
    # Add copy_to for field_class-level combined searches.
    for my $prop (@dynamics) {
        my $field_class = $prop->{field_class};
        my $field_name = "$field_class|" . $prop->{name};

        # Clone the class-level index definition (e.g. title) to
        # use as the source of the field-specific index.
        my $def = clone($config->{indexes}{$index}{'base-properties'}{$field_class});

        # Copy data for all fields to their parent class to
        # support group-level searches (e.g. title search)
        $def->{copy_to} = $field_class;
        $mappings->{$field_name} = $def;
    }

    my $settings = $config->{indexes}{$index}{settings};
    $settings->{number_of_replicas} =
        scalar(@{$config->{clusters}{$cluster}{nodes}});

    my $doc_type = $config->{indexes}{$index}{'document-type'};

    my $conf = {
        index => $index,
        body => {
            settings => $settings,
            mappings => {$doc_type => {properties => $mappings}}
        }
    };

    # Send the index definition to Elastic
    eval { $self->es($cluster)->indices->create($conf) };

    if ($@) {
        my $msg =
            "ES failed to create index cluster=$cluster index=$index error=$@";
        $logger->error($msg);
        die "$msg\n";
    }
}

sub populate_index {
    my ($self, $cluster, $index) = @_;

    if ($index eq 'bib-search') {
        return $self->populate_bib_search_index;
    }
}

sub populate_bib_search_index {
    my ($self, $cluster) = @_;

    my $db = $self->get_db_conn;

    my $index_count = 0;
    my $state = {
        last_bib_id => 0
    };

    do {
        $index_count =
            $self->populate_bib_search_index_page($cluster, $state);
    } while ($index_count > 0);
}

# TODO holdings
# TODO partial re-index
sub populate_bib_search_index_page {
    my ($self, $cluster, $state) = @_;

    my $index_count = 0;
    my $last_id = $state->{last_bib_id};

    my $sth = $self->get_db_conn()->prepare(<<SQL);

SELECT bre.id, bre.marc, bre.create_date, bre.edit_date, bre.source
FROM biblio.record_entry bre
WHERE (
    NOT bre.deleted
    AND bre.active
    AND bre.id > $last_id
)
ORDER BY bre.edit_date ASC, bre.id ASC
LIMIT 1000
SQL

    $sth->execute;

    while (my $bib = $sth->fetchrow_hashref) {
        print "found id " . $bib->{id} . "\n";

        $state->{last_bib_id} = $bib->{id};
        $index_count++;
    }

    return $index_count;
}


1;


