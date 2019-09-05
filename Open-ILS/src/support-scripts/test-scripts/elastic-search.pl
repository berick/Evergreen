#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Time::HiRes qw/time/;
use OpenSRF::Utils::JSON;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Elastic::BibSearch;

my $help;
my $osrf_config = '/openils/conf/opensrf_core.xml';
my $cluster = 'main';
my $index = 'bib-search';
my $quiet = 0;
my $query_string;

GetOptions(
    'help'              => \$help,
    'osrf-config=s'     => \$osrf_config,
    'cluster=s'         => \$cluster,
    'quiet'             => \$quiet,
) || die "\nSee --help for more\n";

sub help {
    print <<HELP;
        Synopsis:

            $0

        Performs a canned bib record search

HELP
    exit(0);
}

help() if $help;

# connect to osrf...
OpenSRF::System->bootstrap_client(config_file => $osrf_config);
Fieldmapper->import(
    IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
OpenILS::Utils::CStoreEditor::init();

# Title search AND author search AND MARC tag=100 search
my $query = {
  _source => ['id', 'title|proper'] , # return only the ID field
  from => 0,
  size => 5,
  sort => [
    {'titlesort' => 'asc'},
    '_score'
  ],
  query => {
    bool => {
      must => [{ 
        multi_match => {
          query => 'ready',
          fields => ['title|*.text*'],
          operator => 'and',
          type => 'most_fields'
        }
      }, {
        multi_match => {
          query => 'puzzle',
          fields => ['subject|*.text*'],
          operator => 'and',
          type => 'most_fields'
        }
      }, {
        nested => {
          path => 'marc',
          query => {
            bool => { 
              must => [{
                multi_match => {
                  query => 'cline',
                  fields => ['marc.value.text*'],
                  operator => 'and',
                  type => 'most_fields'
                }
              }, {
                term => {'marc.tag' => 100}
              }]
            }
          }
        }
      }]
    }
  }
};

my $es = OpenILS::Elastic::BibSearch->new($cluster);

$es->connect;

print OpenSRF::Utils::JSON->perl2JSON($query) . "\n\n";

my $start = time();
my $results = $es->search($query);
my $duration = substr(time() - $start, 0, 6);

print OpenSRF::Utils::JSON->perl2JSON($results) . "\n";

unless ($quiet) {
    print "\nSearch returned ".$results->{hits}->{total}.
        " hits with a reported duration of ".$results->{took}."ms.\n";
    print "Full round-trip time was $duration seconds.\n";
}


