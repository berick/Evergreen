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
use Search::Elasticsearch;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use Data::Dumper;
$Data::Dumper::Indent = 0;

sub new {
    my ($class, %args) = @_;

    my $self = {
        %args,
        indices => []
    };

    $self->{cluster} = 'main' unless $args{cluster};

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
    my ($self) = @_;
    return $self->{index_name};
}

sub index_class {
    die "index_class() should be implemented by sub-classes\n";
}

# When write_mode is enable, it means we're editing indexes instead
# of just searching them.
sub write_mode {
    my $self = shift;
    return $self->{write_mode};
}

sub language_analyzers {
    # Override in subclass as needed
    return ("english");
}

# Provide a direct DB connection so some high-volume activities,
# like indexing bib records, can take advantage of a direct connection.
# Returns database connection object -- connects if necessary.
sub db {
	my ($self) = @_;

    return $self->{db} if $self->{db};
    
    my $db_name = $self->{db_name};
    my $db_host = $self->{db_host};
    my $db_port = $self->{db_port};
    my $db_user = $self->{db_user};
    my $db_pass = $self->{db_pass};
    my $db_appn = $self->{db_appn} || 'Elastic Indexer';

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
    my ($self) = @_;

    my $e = new_editor();
    my $cluster = $self->cluster;

    my %active = $self->write_mode ? () : (active => 't');

    $self->{nodes} = $e->search_elastic_node({cluster => $cluster, %active});

    unless (@{$self->nodes}) {
        $logger->error("ES no nodes defined for cluster $cluster");
        return;
    }

    $self->{indices} = $e->search_elastic_index({cluster => $cluster, %active});

    unless ($self->write_mode || @{$self->indices}) {
        $logger->warn("ES no active indices defined for cluster $cluster");
        return;
    }
}

sub find_index_config {
    my $self = shift;

    my ($conf) = grep {
        $_->name eq $self->index_name &&
        $_->index_class eq $self->index_class
    } @{$self->indices};

    return $conf;
}

sub find_or_create_index_config {
    my $self = shift;

    my $conf = $self->find_index_config;
    return $conf if $conf;

    $logger->info("ES creating new index configuration for ".
        sprintf("cluster=%s index_class=%s name=%s",
            $self->cluster, $self->index_class, $self->index_name));

    my $e = new_editor(xact => 1);
    $conf = Fieldmapper::elastic::index->new;

    $conf->cluster($self->cluster);
    $conf->index_class($self->index_class);
    $conf->name($self->index_name);
    
    # Created by default with active=false and num_shards=1

    unless ($e->create_elastic_index($conf)) {
        $logger->error("ES failed creating index ".$self->index_name);
        return undef;
    }

    $e->commit;

    push(@{$self->indices}, $conf);

    return $conf;
}

sub connect {
    my ($self) = @_;

    $self->load_config;

    my @nodes;
    for my $server (@{$self->nodes}) {
        push(@nodes, {
            scheme => $server->proto,
            host   => $server->host,
            port   => $server->port,
            path   => $server->path
        });
    }

    $logger->debug("ES connecting to ".scalar(@nodes)." nodes");

    eval { $self->{es} = Search::Elasticsearch->new(nodes => \@nodes) };

    if ($@) {
        $logger->error("ES failed to connect to @nodes: $@");
        return;
    }
}

# Activates the currently loaded index while deactivating any active
# index with the same cluster and index_class.
sub activate_index {
    my ($self) = @_;

    my $index = $self->index_name;

    if (!$self->es->indices->exists(index => $index)) {
        $logger->warn("ES cannot activate index '$index' which does not exist");
        return;
    }

    my ($active) = grep {
        $_->index_class eq $self->index_class &&
        $_->cluster eq $self->cluster &&
        $_->active eq 't' &&
        $_->name ne $index
    } @{$self->indices};

    my $e = new_editor(xact => 1);

    if ($active) {
        $logger->info(
            "ES deactivating index ".$active->name." before activating $index");

        $active->active('f');
        unless ($e->update_elastic_index($active)) {
            $logger->error("ES failed deactivating index ".$active->name);
            $e->rollback;
            return 0;
        }
    }

    my $conf = $self->find_index_config;

    if (!$conf) {
        $logger->error("ES no such index to activate: $index");
        $e->rollback;
        return 0;
    }

    $conf->active('t');
    unless ($e->update_elastic_index($conf)) {
        $logger->error("ES failed deactivating index: $index");
        $e->rollback;
        return 0;
    }

    $e->commit;

    return 1;
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

# Remove multiple documents from the index by ID.
# $ids can be a single ID or an array ref of IDs.
sub delete_documents {
    my ($self, $ids) = @_;
    $ids = [$ids] unless ref $ids;

    my $result;

    eval {
    
        $result = $self->es->delete_by_query(
            index => $self->index_name,
            type => 'record',
            body => {query => {terms => {_id => $ids}}}
        );
    };

    if ($@) {
        $logger->error("ES delete document failed with $@");
        return undef;
    } 

    $logger->debug("ES delete removed " . $result->{deleted} . " document");
    return $result;
}

sub index_document {
    my ($self, $id, $body) = @_;

    my $result;

    eval {
        $result = $self->es->index(
            index => $self->index_name,
            type => 'record',
            id => $id,
            body => $body
        );
    };

    if ($@) {
        $logger->error("ES index_document failed with $@");
        return undef;
    } 

    if ($result->{failed}) {
        $logger->error("ES index document $id failed " . Dumper($result));
        return undef;
    }

    $logger->debug("ES index => $id succeeded");
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

# Lucene has a hard limit on the size of an indexable chunk.
# Avoid trying to index such data by lazily chopping it off
# at 1/4 the limit to accomodate all UTF-8 chars.
sub truncate_value {
    my ($self, $value, $length) = @_;
    $length = 8190 unless $length;
    return substr($value, 0, 8190);
}

sub get_index_def {
    my ($self) = @_;
    return $self->es->indices->get(index => $self->index_name);
}



1;


