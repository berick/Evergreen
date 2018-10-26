package OpenILS::Elastic;
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
use DBI;
use Time::HiRes qw/time/;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use Search::Elasticsearch;
use OpenSRF::Utils::JSON;

sub new {
    my ($class, $cluster) = @_;

    my $self = {
        cluster     => $cluster,
        indices     => [],
        marc_fields => []
    };

    return bless($self, $class);
}

sub cluster {
    my $self = shift;
    return $self->{cluster};
}

sub nodes {
    my $self = shift;
    return $self->{nodes};
}

sub indices {
    my $self = shift;
    return $self->{indices};
}

sub es {
    my ($self) = @_;
    return $self->{es};
}

sub index_name {
    die "Index name must be provided by sub-class\n";
}

# Provide a direct DB connection so some high-volume activities,
# like indexing bib records, can take advantage of a direct connection.
# Returns database connection object -- connects if necessary.
sub db {
	my ($self) = @_;

    return $self->{db} if $self->{db};

    my $client = OpenSRF::Utils::SettingsClient->new;
    my $settings = $client->config_value('elastic_search');
    my $db_name = $settings->{database}->{db};
    my $db_host = $settings->{database}->{host};
    my $db_port = $settings->{database}->{port};
    my $db_user = $settings->{database}->{user};
    my $db_pass = $settings->{database}->{pw};
    my $db_appn = $settings->{database}->{application_name};

    # TODO Add application_name to dsn

    my $dsn = "dbi:Pg:db=$db_name;host=$db_host;port=$db_port";
    $logger->debug("ES connecting to DB $dsn");

    $self->{db} = DBI->connect(
        $dsn, $db_user, $db_pass, {
            RaiseError => 1,
            PrintError => 0,
            pg_expand_array => 0,
            pg_enable_utf8 => 1
        }
    ) or $logger->error(
        "ES Connection to database failed: $DBI::err : $DBI::errstr", 1);

    return $self->{db};
}

# Return selected rows as an array of hashes
sub get_db_rows {
    my ($self, $sql) = @_;
    return $self->db->selectall_arrayref($sql, {Slice => {}});
}

# load the config via cstore.
sub load_config {
    my $self = shift;
    my $e = new_editor();
    my $cluster = $self->cluster;

    $self->{nodes} = $e->search_elastic_node({cluster => $cluster});

    unless (@{$self->nodes}) {
        $logger->error("ES no nodes defined for cluster $cluster");
        return;
    }

    $self->{indices} = $e->search_elastic_index({cluster => $cluster});

    unless (@{$self->indices}) {
        $logger->error("ES no indices defined for cluster $cluster");
        return;
    }
}

sub connect {
    my ($self) = @_;
    $self->load_config;

    my @nodes;
    for my $server (@{$self->nodes}) {
        push(@nodes, sprintf("%s://%s:%d", 
            $server->proto, $server->host, $server->port));
    }

    $logger->info("ES connecting to nodes @nodes");

    eval { $self->{es} = Search::Elasticsearch->new(nodes => \@nodes) };

    if ($@) {
        $logger->error("ES failed to connect to @nodes: $@");
        return;
    }
}

sub delete_index {
    my ($self) = @_;

    my $index = $self->index_name;

    if ($self->es->indices->exists(index => $index)) {
        $logger->info(
            "ES deleting index '$index' on cluster '".$self->cluster."'");
        $self->es->indices->delete(index => $index);

    } else {
        $logger->warn("ES index '$index' ".
            "does not exist in cluster '".$self->cluster."'");
    }
}

sub index_document {
    my ($self, $id, $body) = @_;

    my $result;

    eval {
        $result = $self->es->index(
            index => $self->index_name,
            type => 'record', # deprecated in v6
            id => $id,
            body => $body
        );
    };

    if ($@) {
        $logger->error("ES index_document failed with $@");
        return undef;
    } 

    $logger->debug("ES index command returned $result");
    return $result;
}

sub search {
    my ($self, $query) = @_;

    my $result;
    my $duration;

    $logger->info("ES searching " . OpenSRF::Utils::JSON->perl2JSON($query));

    eval {
        my $start_time = time;
        $result = $self->es->search(
            index => $self->index_name,
            body => $query
        );
        $duration = time - $start_time;
    };

    if ($@) {
        $logger->error("ES search failed with $@");
        return undef;
    }

    $logger->info(
        sprintf("ES search found %d results in %0.3f seconds.",
            $result->{hits}->{total}, $duration
        )
    );

    return $result;
}



1;


