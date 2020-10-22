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
use XML::LibXML;
use XML::LibXML::XPathContext;
use Search::Elasticsearch;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use Data::Dumper;
$Data::Dumper::Indent = 0;

# For parsing the Elasticsearch configuration file
my $ES_NAMESPACE = 'http://evergreen-ils.org/spec/elasticsearch/v1';

sub new {
    my ($class, %args) = @_;

    my $self = {%args};

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
    return $self->{indices} if $self->{indices};

    my $def;
    eval { 
        # All open indices
        $def = $self->es->indices->get(
            index => $self->index_class . '-*',
            expand_wildcards => 'open'
        );
    };

    if ($@) {
        $logger->error("ES index lookup failed: $@");
        return {};
    }

    return $self->{indices} = $def;
}

sub es {
    my ($self) = @_;
    return $self->{es};
}

sub index_name {
    my ($self) = @_;
    return $self->{index_name};
}

my $xpc;
sub xpath_context {
    if (!$xpc) {
        $xpc = XML::LibXML::XPathContext->new;                                    
        $xpc->registerNs('es', $ES_NAMESPACE);
    }
    return $xpc;
}

# In maintenance mode we are working with specific indexes.
# Otherwise all actions target the index alias which is index_class.
sub index_target {
    my ($self) = @_;
    return $self->maintenance_mode ? $self->index_name : $self->index_class;
}

sub index_class {
    die "index_class() should be implemented by sub-classes\n";
}

# Are we modifying indexes or just read/writing indexed data?
sub maintenance_mode {
    my $self = shift;
    return $self->{maintenance_mode};
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

    my $dsn = 
        "dbi:Pg:db=$db_name;host=$db_host;port=$db_port;application_name='$db_appn';";

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

    my @nodes = $self->{nodes} ? @{$self->{nodes}} : ();

    if (@nodes) {

        $logger->info("ES overriding nodes with @nodes");
        $self->{nodes} = \@nodes;

    } else {

        my %active = $self->maintenance_mode ? () : (active => 't');
        my $nodes = $e->search_elastic_node({cluster => $cluster, %active});

        $self->{nodes} = [
            map {
                sprintf("%s://%s:%d%s", $_->proto, $_->host, $_->port, $_->path)
            } @$nodes
        ];
    }

    unless (@{$self->nodes}) {
        $logger->error("ES no nodes defined for cluster $cluster");
        return;
    }

    if (!$self->index_class) {
        $logger->error("ES index_class required to initialize");
        return;
    }
}

sub load_es_config {
    my ($self) = @_;

    my $cluster = $self->cluster;

    if (!$self->indices || !keys(%{$self->indices})) {
        $logger->info("ES no usable indices defined for cluster $cluster");
        return unless $self->maintenance_mode;
    }

    if (!$self->index_name) {
        # Default to the index that has an alias matching our index_class
        
        for my $name (keys %{$self->indices}) {
            if ($self->index_is_active($name)) {
                $logger->info("ES defaulting to active index $name");
                $self->{index_name} = $name;
            }
        }
    }

    # Load the main ES config file
    
    # TODO: 'dirs' option for 'conf'
    #my $client = OpenSRF::Utils::SettingsClient->new;
    #my $dir = $client->config_value("dirs", "conf");

    my $doc;
    my $filename = $self->{es_config_file} 
        || '/openils/conf/elastic-config.xml';

    eval { $doc = XML::LibXML->load_xml(location => $filename) };

    if ($@ || !$doc) {
        my $msg = "ES could not parse elastic config file: $filename $@";
        $logger->error($msg);
        die "$msg\n";
    }

    $self->{es_config} = $doc->documentElement;
}

sub es_config {
    my $self = shift;
    return $self->{es_config};
}

sub active_index {
    my $self = shift;
    my $indices = $self->indices;
    for my $name (keys %{$indices}) {
        return $name if $self->index_is_active($name);
    }
    return undef;
}

# True if the named index has an alias matching our index class
sub index_is_active {
    my ($self, $name) = @_;

    my $conf = $self->indices->{$name};
    return 0 unless $conf;

    my @aliases = keys %{$conf->{aliases}};
    return 1 if grep {$_ eq $self->index_class} @aliases;

    return 0;
}


sub index_config {
    my $self = shift;
    my $class = $self->index_class;

    if (!$self->es_config) {
        $logger->error("ES cannot load index config without a config file");
        return undef;
    }

    my @conf;
    eval {
        @conf = $xpc->findnodes(
            "//es:elasticsearch/es:index[\@class='$class']",
            $self->es_config
        );
    };

    if ($@ || !@conf) {
        my $msg = "ES failed to locate config for index class '$class' $@";
        $logger->error($msg);
        die "$msg\n";
    }

    return $conf[0];
}

sub connect {
    my ($self) = @_;

    $self->load_config;

    my @nodes = @{$self->nodes};
    $logger->info("ES connecting to nods: @nodes");

    eval { 
        $self->{es} = Search::Elasticsearch->new(
            client => '6_0::Direct',
            nodes  => \@nodes
        );
    };

    if ($@) {
        $logger->error("ES failed to connect to @nodes: $@");
        return;
    }

    $self->load_es_config;
}

# Activates the currently loaded index while deactivating any active
# index with the same cluster and index_class.
# Applies an alias to the activated index equal to the index class.
sub activate_index {
    my ($self) = @_;

    my $index = $self->index_name;

    if (!$self->es->indices->exists(index => $index)) {
        $logger->warn("ES cannot activate index '$index' which does not exist");
        return;
    }

    my $from_index = $self->active_index;

    # When activating an index, point the main alias toward the
    # newly active index.
    return $self->migrate_alias($self->index_class, $from_index, $index);
}


# Migrate an alias from one index to another.
# If either from_index or to_index are not defined, then only half
# of the migration (i.e. remove or add) is performed.
sub migrate_alias {
    my ($self, $alias, $from_index, $to_index) = @_;
    return undef unless $alias && ($from_index || $to_index);

    my @actions;

    $from_index ||= '';
    $to_index ||= '';
    $logger->info("ES migrating alias [$alias] from $from_index to $to_index");

    if ($from_index) {
        push(@actions, {remove => {alias => $alias, index => $from_index}});
    }

    if ($to_index) {
        push(@actions, {add => {alias => $alias, index => $to_index}});
    }

    eval {
        $self->es->indices->update_aliases({body => {actions => \@actions}});
    };

    if ($@) {
        $logger->error("ES alias migration [$alias] failed $@");
        return undef;
    } 

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

    delete $self->indices->{$index};

    return 1;
}

# Remove multiple documents from the index by ID.
# $ids can be a single ID or an array ref of IDs.
sub delete_documents {
    my ($self, $ids) = @_;
    $ids = [$ids] unless ref $ids;

    my $result;

    eval {
    
        $result = $self->es->delete_by_query(
            index => $self->index_target,
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

# Returns true if a document with the requested ID exists.
sub document_exists {
    my ($self, $id) = @_;

    my $result;

    eval {
        $result = $self->es->index(
            index => $self->index_target,
            type => 'record',
            id => $id,
        );
    };


    if ($@) {
        $logger->error("ES document_exists failed with $@");
        return undef;
    } 

    return $result ? 1 : 0;
}

# Create or replace a document.
sub index_document {
    my ($self, $id, $body) = @_;

    my $result;

    eval {
        $result = $self->es->index(
            index => $self->index_target,
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

# Index a new document
# This will fail if the document already exists.
sub create_document {
    my ($self, $id, $body) = @_;

    my $result;

    eval {
        $result = $self->es->create(
            index => $self->index_target,
            type => 'record',
            id => $id,
            body => $body
        );
    };

    if ($@) {
        $logger->error("ES create_document failed with $@");
        return undef;
    } 

    if ($result->{failed}) {
        $logger->error("ES create document $id failed " . Dumper($result));
        return undef;
    }

    $logger->debug("ES create => $id succeeded");
    return $result;
}


# Partial document update
# This will fail if the document does not exist.
sub update_document {
    my ($self, $id, $body) = @_;

    my $result;

    eval {
        $result = $self->es->update(
            index => $self->index_target,
            type => 'record',
            id => $id,
            body => {doc => $body}
        );
    };

    if ($@) {
        $logger->error("ES update_document failed with $@");
        return undef;
    } 

    if ($result->{failed}) {
        $logger->error("ES update document $id failed " . Dumper($result));
        return undef;
    }

    $logger->debug("ES update => $id succeeded");
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
            index => $self->index_target,
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
    my ($self, $name) = @_;
    $name ||= $self->index_name;

    my $def;
    eval { $def = $self->es->indices->get(index => $name) };

    if ($@) {
        $logger->error("ES cannot find index def for $name");
        return undef;
    }

    return $def;
}



1;


