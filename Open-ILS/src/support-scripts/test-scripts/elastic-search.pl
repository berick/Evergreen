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
    'index=s'           => \$index,
    'quiet'             => \$quiet,
    'query-string=s'    => \$query_string
) || die "\nSee --help for more\n";

sub help {
    print <<HELP;
        Synopsis:

        $0 --query-string "author:mozart || title:piano"

HELP
    exit(0);
}

help() if $help;

# connect to osrf...
OpenSRF::System->bootstrap_client(config_file => $osrf_config);
Fieldmapper->import(
    IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
OpenILS::Utils::CStoreEditor::init();

my $query = {
  _source => ['id'] , # return only the ID field
  from => 0,
  size => 5,
  sort => [
    {'titlesort' => 'asc'},
    '_score'
  ],
  query => {
    bool => {
      must => {
        query_string => {
          default_operator => 'AND',
          default_field => 'keyword',
          query => $query_string
        }
      },
      filter => [
        #{term => {"subject|topic.raw" => "Piano music"}},
        {
          nested => {
            path => 'holdings',
            query => {
              bool => {
                must => [
                  {
                    bool => {
                      should => [
                        {term => {'holdings.status' => '0'}},
                        {term => {'holdings.status' => '7'}}
                      ]
                    }
                  },
                  {
                    bool => {
                      should => [
                        {term => {'holdings.circ_lib' => '4'}},
                        {term => {'holdings.circ_lib' => '5'}}
                      ]
                    }
                  }
                ]
              }
            }
          }
        }
      ]
    }
  },
  aggs => {
    genres => {
      terms => {
        field => 'identifier|genre'
      }
    },
    'author|corporate' => {
      terms => {
        field => 'author|corporate.raw'
      }
    },
    'subject|topic' => {
      terms => {
        field => 'subject|topic.raw'
      }
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


