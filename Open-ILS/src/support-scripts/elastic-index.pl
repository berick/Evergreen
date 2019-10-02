#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use OpenSRF::Utils::JSON;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor;
use OpenILS::Elastic::BibSearch;

my $help;
my $osrf_config = '/openils/conf/opensrf_core.xml';
my $cluster = 'main';
my $create_index;
my $delete_index;
my $index_name = 'bib-search'; # only supported index at time of writing
my $populate;
my $index_record;
my $start_record;
my $stop_record;
my $modified_since;
my $max_duration;
my $batch_size = 500;
my $custom_mappings;

# Database settings read from ENV by default.
my $db_host = $ENV{PGHOST} || 'localhost';
my $db_port = $ENV{PGPORT} || 5432;
my $db_user = $ENV{PGUSER} || 'evergreen';
my $db_pass = $ENV{PGPASSWORD} || 'evergreen';
my $db_name = $ENV{PGDATABASE} || 'evergreen';
my $db_appn = 'Elastic Indexer';

GetOptions(
    'help'              => \$help,
    'osrf-config=s'     => \$osrf_config,
    'cluster=s'         => \$cluster,
    'create-index'      => \$create_index,
    'delete-index'      => \$delete_index,
    'index=s'           => \$index_name,
    'index-record=s'    => \$index_record,
    'start-record=s'    => \$start_record,
    'stop-record=s'     => \$stop_record,
    'modified-since=s'  => \$modified_since,
    'max-duration=s'    => \$max_duration,
    'batch-size=s'      => \$batch_size,
    'custom-mappings=s' => \$custom_mappings,
    'db-name=s'         => \$db_name,
    'db-host=s'         => \$db_host,
    'db-port=s'         => \$db_port,
    'db-user=s'         => \$db_user,
    'db-pass=s'         => \$db_pass,
    'db-appn=s'         => \$db_appn,
    'populate'          => \$populate
) || die "\nSee --help for more\n";

sub help {
    print <<HELP;
        Synopsis:
            
            $0 --delete-index --create-index --index bib-search --populate

        Options:

            --osrf-config <file-path>

            --db-name <$db_name>
            --db-host <$db_host>
            --db-port <$db_port>
            --db-user <$db_user>
            --db-pass <PASSWORD>
            --db-appn <$db_appn>
                Database connection values.  This is the Evergreen database
                where values should be extracted for elastic search indexing.

                Values default to their PG* environment variable equivalent.

            --cluster <name>
                Specify a cluster name.  Defaults to 'main'.

            --index <name>
                Specify an index name.  Defaults to 'bib-search'.

            --delete-index
                Delete the specified index and all of its data. 

            --create-index
                Create an index whose name equals --index-name.

            --batch-size <number>
                Index at most this many records per batch.
                Default is 500.

            --index-record <id>
                Index a specific record by identifier.

            --start-record <id>
                Start indexing at the record with this ID.

            --stop-record <id>
                Stop indexing after the record with this ID has been indexed.

            --modified-since <YYYY-MM-DD[Thh::mm:ss]>
                Index new records and reindex existing records whose last
                modification date falls after the date provided.  Use this
                at regular intervals to keep the ES-indexed data in sync 
                with the EG data.

            --max-duration <duration>
                Stop indexing once the process has been running for this
                amount of time.

            --populate
                Populate the selected index with data.  If no filters
                are provided (e.g. --index-start-record) then all 
                applicable values will be indexed.

            --custom-mappings
                Path to a JSON file continaining custom index mapping
                definitions.  The mapppings must match the stock mapping
                structure, fields may only be removed.  Added fields will
                be ignored at data population time (barring code changes).

                For example:

                curl http://ELASTIC_HOST/bib-search?pretty > mappings.json
                # edit mappings.json and remove stuff you don't want.
                $0 --create-index --custom-mappings mappings.json
HELP
    exit(0);
}

help() if $help;

# connect to osrf...
OpenSRF::System->bootstrap_client(config_file => $osrf_config);
Fieldmapper->import(
    IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
OpenILS::Utils::CStoreEditor::init();

my $es;

if ($index_name eq 'bib-search') {
    $es = OpenILS::Elastic::BibSearch->new($cluster);
}

if (!$es) {
    die "Unknown index type: $index_name\n";
}

$es->connect;

if ($delete_index) {
    $es->delete_index or die "Index delete failed.\n";
}

if ($create_index) {
    $es->create_index($custom_mappings) or die "Index create failed.\n";
}

if ($populate) {

    my $settings = {
        db_name => $db_name,
        db_host => $db_host,
        db_port => $db_port,
        db_user => $db_user,
        db_pass => 'REDACTED',
        db_appn => $db_appn,
        index_record   => $index_record,
        start_record   => $start_record,
        stop_record    => $stop_record,
        modified_since => $modified_since,
        max_duration   => $max_duration,
        batch_size     => $batch_size
    };

    print "Commencing index populate with settings: " . 
        OpenSRF::Utils::JSON->perl2JSON($settings) . "\n";

    # Apply after logging $settings
    $settings->{db_pass} = $db_pass;

    $es->populate_index($settings) or die "Index populate failed.\n";
}


