#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use OpenILS::Utils::ElasticSearch;

my $help;
my $elastic_config;
my $cluster = 'main';
my $create_index;
my $delete_index;
my $index_name; # use "all" to affect all configured indexes
my $populate;
my $partial;

GetOptions(
    'help'              => \$help,
    'elastic-config=s'  => \$elastic_config,
    'cluster=s'         => \$cluster,
    'create-index'      => \$create_index,
    'delete-index'      => \$delete_index,
    'index=s'           => \$index_name,
    'populate'          => \$populate,
    'partial'           => \$partial
) || die "\nSee --help for more\n";


my $es = OpenILS::Utils::ElasticSearch->new(
    cluster => $cluster,
    config_file => $elastic_config
);

$es->connect($cluster);

$es->delete_index($cluster, $index_name) if $delete_index;

$es->create_index($cluster, $index_name) if $create_index;

$es->populate_index($cluster, $index_name) if $populate;


