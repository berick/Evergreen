#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use Time::HiRes qw/time/;
use OpenSRF::Utils::JSON;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Elastic::BibSearch;

use utf8;
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');

my $help;
my $osrf_config = '/openils/conf/opensrf_core.xml';
my $cluster = 'main';
my $index_class = 'bib-search';
my $index_name;
my $quiet = 0;
my $query_string;

GetOptions(
    'help'              => \$help,
    'osrf-config=s'     => \$osrf_config,
    'cluster=s'         => \$cluster,
    'index-name=s'      => \$index_name,
    'quiet'             => \$quiet,
) || die "\nSee --help for more\n";

sub help {
    print <<HELP;
        Synopsis:

            $0 --index-name <name>

        Performs a series of canned bib record searches

        Note if --index-name is omitted, the currently active index on 
        the 'bib-search' index class will be used.

HELP
    exit(0);
}

help() if $help;

my $queries = [{

    # Title search AND subject search AND MARC tag=100 search
    bool => {
      must => [{ 
        multi_match => {
          query => 'ready',
          fields => ['title.text*'],
          operator => 'and',
          type => 'most_fields'
        }
      }, {
        multi_match => {
          query => 'puzzle',
          fields => ['subject.text*'],
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
                  fields => ['marc.value*'],
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
}, {
    # Author search
    bool => {
      must => [{ 
        multi_match => {
          query => 'Cuthbert Morton Girdlestone',
          fields => ['author.text*'],
          operator => 'and',
          type => 'most_fields'
        }
      }]
    }
}, {
    # Personal author exact match search
    bool => {
      must => [{ 
        term => {'author|personal' => 'Rowling, J. K.'}
      }]
    }
}, {
    # Main title search
    bool => {
      must => [{ 
        multi_match => {
          query => 'ready player',
          fields => ['title|maintitle.text*'],
          operator => 'and',
          type => 'most_fields'
        }
      }]
    }
}];

# connect to osrf...
print "Connecting...\n";
OpenSRF::System->bootstrap_client(config_file => $osrf_config);
Fieldmapper->import(
    IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
OpenILS::Utils::CStoreEditor::init();

my $es = OpenILS::Elastic::BibSearch->new(index_name => $index_name);
$es->connect;

if ($es->index_name) {
    print "Using bib-search index '" . $es->index_name . "'\n";
} else {
    die "No active 'bib-search' index found.  ".
        "Use --index-name or activate an index in the database.\n";
}

print "Searching...\n";
for my $query_part (@$queries) {

    my $query = {
      _source => ['id', 'title|maintitle'] , # return only the ID field
      from => 0,
      size => 5,
      sort => [{'_score' => 'desc'}],
      query => $query_part
    };

    print OpenSRF::Utils::JSON->perl2JSON($query) . "\n\n" unless $quiet;

    my $start = time();
    my $results = $es->search($query);
    my $duration = substr(time() - $start, 0, 6);

    print OpenSRF::Utils::JSON->perl2JSON($results) . "\n\n" unless $quiet;

    print "Search returned ".$results->{hits}->{total}.
        " hits with a reported duration of ".$results->{took}."ms.\n";
    print "Full round-trip time was $duration seconds.\n\n";
}

