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
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::DateTime qw/:datetime/;
#use OpenILS::Utils::CStoreEditor qw/:funcs/;
use Search::Elasticsearch;

our $date_parser = DateTime::Format::ISO8601->new;

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

    # send to es


    #print "\n\n\n";
    #print OpenSRF::Utils::JSON->perl2JSON($conf) . "\n";
    #print "\n\n\n";

    eval { $self->es($cluster)->indices->create($conf) };

    if ($@) {
        my $msg = 
            "ES failed to create index cluster=$cluster index=$index error=$@";
        $logger->error($msg);
        die "$msg\n";
    }
}


1;


