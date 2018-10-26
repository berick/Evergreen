#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor;
use OpenILS::Elastic::BibSearch;

my $help;
my $osrf_config = '/openils/conf/opensrf_core.xml';
my $cluster = 'main';
my $create_index;
my $delete_index;
my $index_name;
my $populate;

GetOptions(
    'help'              => \$help,
    'osrf-config=s'     => \$osrf_config,
    'cluster=s'         => \$cluster,
    'create-index'      => \$create_index,
    'delete-index'      => \$delete_index,
    'index=s'           => \$index_name,
    'populate'          => \$populate
) || die "\nSee --help for more\n";

# connect to osrf...
OpenSRF::System->bootstrap_client(config_file => $osrf_config);
Fieldmapper->import(
    IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
OpenILS::Utils::CStoreEditor::init();

my $es = OpenILS::Elastic::BibSearch->new($cluster);

$es->connect;

if ($delete_index) {
    $es->delete_index or die "Index delete failed.\n";
}

if ($create_index) {
    $es->create_index or die "Index create failed.\n";
}

if ($populate) {
    $es->populate_index or die "Index populate failed.\n";
}


