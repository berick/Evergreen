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

        Performs query string searches.

HELP
    exit(0);
}

help() if $help;

# connect to osrf...
print "Connecting to OpenSRF...\n";
OpenSRF::System->bootstrap_client(config_file => $osrf_config);
Fieldmapper->import(
    IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
OpenILS::Utils::CStoreEditor::init();

my $es = OpenILS::Elastic::BibSearch->new($cluster);
$es->connect;

print <<MESSAGE;

Enter a query string to perform a search. Ctrl-c to exit.
See https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html
Some examples:

harry potter
title|proper.text\\*:piano
author.text\\*:GrandPré
au:((johann brahms) OR (wolfgang mozart))
su:history
MESSAGE

while (1) {

    print "\nEnter query string: ";

    $query_string = <STDIN>;
    last unless defined $query_string; # ctrl-d

    chomp $query_string;
    next unless $query_string;

    my $query = {
        _source => ['id', 'title|proper', 'author|first_author'] , # return only a few fields
        from => 0,
        size => 10,
        sort => [{'_score' => 'desc'}],
        query => {      
            query_string => {
                query => $query_string,
                default_operator => 'AND',
                # Combine scores for matched indexes
                type => 'most_fields',
                # Search the base keyword text index by default.
                default_field => 'keyword.text'
            } 
        },
        # Request highligh data for title/author text fields.
        # See below for logging highlight response data.
        highlight => {
            # Pre/Post tags modified to match stock Evergreen.
            pre_tags => '<b class="oils_SH">',
            post_tags => '</b>',
            fields => {
                'title*.text' => {},
                'author*.text' => {}
            }
        }
    };

    my $start = time();
    my $results = $es->search($query);
    my $duration = substr(time() - $start, 0, 6);

    if (!$results) {
        print "Search failed.  See error logs\n";
        next;
    }

    print "Search returned ".$results->{hits}->{total}.
        " hits with a reported duration of ".$results->{took}."ms.\n";
    print "Full round-trip time was $duration seconds.\n\n";

    for my $hit (@{$results->{hits}->{hits}}) {
        printf("Record: %-8d | Score: %-11f | Title: %s\n", 
            $hit->{_id}, $hit->{_score}, 
            ($hit->{_source}->{'title|proper'} || '')
        );

# Uncomment to log highlighted field data.
#        for my $hl (keys %{$hit->{highlight}}) {
#            my @values = @{$hit->{highlight}->{$hl}};
#            print "\tHighlight: $hl => @values\n";
#        }
    }
}

print "\n";

