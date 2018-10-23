#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Time::HiRes qw/time/;
use OpenSRF::Utils::JSON;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Elastic;

my $help;
my $elastic_config;
my $osrf_config = '/openils/conf/opensrf_core.xml';
my $cluster = 'main';
my $index = 'bib-search';
my $query_string;

GetOptions(
    'help'              => \$help,
    'elastic-config=s'  => \$elastic_config,
    'osrf-config=s'     => \$osrf_config,
    'cluster=s'         => \$cluster,
    'index=s'           => \$index,
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

my $es = OpenILS::Utils::ElasticSearch->new(
    config_file => $elastic_config
);

$es->connect($cluster);

my $start = time();
my $results = $es->search($index, $query);
my $duration = substr(time() - $start, 0, 6);

print OpenSRF::Utils::JSON->perl2JSON($results) . "\n\n";

print "Search returned ".$results->{hits}->{total}.
    " hits with a reported duration of ".$results->{took}."ms.\n";
print "Full round-trip time was $duration seconds.\n";


