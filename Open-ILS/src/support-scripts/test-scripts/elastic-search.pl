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

my $query = {
  _source => ['id'] , # return only the ID field
  sort => [
    {'title.raw' => 'asc'},
    {'author.raw' => 'asc'},
    '_score'
  ],
  query => {
    bool => {
      must => {
        query_string => {
          default_field => 'keyword',
          query => $query_string
        }
      },
      filter => {
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
    }
  },
  aggs => {
    genres => {
      terms => {
        field => 'identifier|genre.raw'
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

my $start = time();
my $results = $es->search($query);
my $duration = substr(time() - $start, 0, 6);

print OpenSRF::Utils::JSON->perl2JSON($results) . "\n";

unless ($quiet) {
    print "\nSearch returned ".$results->{hits}->{total}.
        " hits with a reported duration of ".$results->{took}."ms.\n";
    print "Full round-trip time was $duration seconds.\n";
}


