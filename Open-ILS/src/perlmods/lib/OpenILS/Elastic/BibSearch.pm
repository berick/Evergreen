package OpenILS::Elastic::BibSearch;
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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR code.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
use strict;
use warnings;
use Clone qw/clone/;
use DBI;
use XML::LibXML;
use XML::LibXSLT;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Elastic;
use OpenSRF::Utils::JSON;
use base qw/OpenILS::Elastic/;

my $INDEX_NAME = 'bib-search';

# number of bibs to index per batch.
my $BIB_BATCH_SIZE = 1000;

# TODO: it's possible to apply multiple language analyzers.
my $LANG_ANALYZER = 'english';

my $BASE_INDEX_SETTINGS = {
    analysis => {
        analyzer => {
            folding => {
                filter => ['lowercase', 'asciifolding'],
                tokenizer => 'standard'
            }
        }
    }
};

# Well-known bib-search index properties
my $BASE_PROPERTIES = {
    source      => {type => 'integer', index => 'false'},
    create_date => {type => 'date', index => 'false'},
    edit_date   => {type => 'date', index => 'false'},

    # Holdings summaries.  For bib-search codes, we don't need
    # copy-specific details, only aggregate visibility information.
    holdings => {
        type => 'nested',
        properties => {
            status => {type => 'integer'},
            circ_lib => {type => 'integer'},
            location => {type => 'integer'},
            circulate => {type => 'boolean'},
            opac_visible => {type => 'boolean'}
        }
    },

    # Combo fields for field-class level searches.
    # The value for every (for eaxmple) title|* field will be copied
    # to the "title" field for searching accross all title entries.
    title => {
        type => 'text',
        analyzer => $LANG_ANALYZER,
        fields => {
            folded => {type => 'text', analyzer => 'folding'}
        }
    },
    author => {
        type => 'text',
        analyzer => $LANG_ANALYZER,
        fields => {
            folded => {type => 'text', analyzer => 'folding'}
        }
    },
    subject => {
        type => 'text',
        analyzer => $LANG_ANALYZER,
        fields => {
            folded => {type => 'text', analyzer => 'folding'}
        }
    },
    series => {
        type => 'text',
        analyzer => $LANG_ANALYZER,
        fields => {
            folded => {type => 'text', analyzer => 'folding'}
        }
    },

    keyword => {
        type => 'text',
        analyzer => $LANG_ANALYZER,
        fields => {
            folded => {type => 'text', analyzer => 'folding'}
        }
    },

    # Avoid full-text analysis on identifer fields.
    identifier => {type => 'keyword'}
};

sub index_name {
    return $INDEX_NAME;
}

sub index {
    my $self = shift;
    return $self->{index} if $self->{index};
    ($self->{index}) = grep {$_->{code} eq $INDEX_NAME} @{$self->{indices}};
    return $self->{index};
}

sub create_index {
    my ($self) = @_;

    if ($self->es->indices->exists(index => $INDEX_NAME)) {
        $logger->warn("ES index '$INDEX_NAME' already exists");
        return;
    }

    $logger->info(
        "ES creating index '$INDEX_NAME' on cluster '".$self->cluster."'");

    my $mappings = $BASE_PROPERTIES;

    my $fields = $self->get_db_rows(
        'SELECT * FROM elastic.bib_index_properties');

    for my $field (@$fields) {

        my $field_name = $field->{name};
        my $search_group = $field->{search_group};
        $field_name = "$search_group|$field_name" if $search_group;

        my $def;
        if ($field->{search_field}) {
            # Search fields get full text indexing and analysis

            $def = {
                type => 'text',
                analyzer => $LANG_ANALYZER,
                fields => {
                    folded => {type => 'text', analyzer => 'folding'}
                }
            };

            if ($field->{facet_field} || $field->{sorter}) {
                # If it's also a facet field, add a keyword version
                # of the field to use for aggregation
                $def->{fields}{raw} = {type => 'keyword'};

                if ($search_group) {
                    # Fields in a search group are "copy_to"'ed the 
                    # group definition
                    $def->{copy_to} = $search_group;
                }
            }

        } else {
            # Fields that are only used for aggregation and sorting
            # and filtering get no full-text treatment.
            $def = {type => 'keyword'};
        }

        $logger->info("ES adding field $field_name: ". 
            OpenSRF::Utils::JSON->perl2JSON($def));

        $mappings->{$field_name} = $def;
    }

    my $settings = $BASE_INDEX_SETTINGS;
    $settings->{number_of_replicas} = scalar(@{$self->{servers}});
    $settings->{number_of_shards} = $self->index->{num_shards};

    my $conf = {
        index => $INDEX_NAME,
        body => {
            settings => $settings,
            mappings => {record => {properties => $mappings}}
            # document type (i.e. 'record') deprecated in v6
            #mappings => {properties => $mappings}
        }
    };

    # Send the index definition to Elastic
    eval { $self->es->indices->create($conf) };

    if ($@) {
        $logger->error("ES failed to create index cluster=".  
            $self->cluster. "index=$INDEX_NAME error=$@");
        print "$@\n\n";
        return 0;
    }

    return 1;
}

# Add data to the bib-search index
sub populate_index {
    my ($self) = @_;

    my $index_count = 0;
    my $total_indexed = 0;
    my $state = {last_bib_id => 0};

    do {
        $index_count =
            $self->populate_bib_search_index_page($state);
        $total_indexed += $index_count;

        $logger->info("ES indexed $total_indexed bib records");

    } while ($index_count > 0);

    $logger->info("ES bib indexing complete with $total_indexed records");
}

# TODO add support for last_edit_date for partial re-indexing
sub get_bib_records {
    my ($self, $state, $record_id) = @_;

    my $sql = <<SQL;
SELECT bre.id, bre.create_date, bre.edit_date, bre.source AS bib_source
FROM biblio.record_entry bre
SQL

    if ($record_id) {
        $sql .= " WHERE bre.id = $record_id"
    } else {
        my $last_id = $state->{last_bib_id};
        $sql .= <<SQL;
WHERE NOT bre.deleted AND bre.active AND bre.id > $last_id
ORDER BY bre.edit_date, bre.id LIMIT $BIB_BATCH_SIZE
SQL
    }

    return $self->get_db_rows($sql);
}

# TODO partial re-index
sub populate_bib_search_index_page {
    my ($self, $state) = @_;

    my $index_count = 0;
    my $last_id = $state->{last_bib_id};

    my $bib_data = $self->get_bib_records($state);
    return 0 unless @$bib_data;

    my $bib_ids = [ map {$_->{id}} @$bib_data ];

    my $holdings = $self->load_holdings($bib_ids);

    my $fields = $self->get_db_rows(                                           
        'SELECT * FROM elastic.bib_index_properties');                         

    for my $bib (@$bib_data) {
        my $bib_id = $bib->{id};

        my $body = {
            bib_source => $bib->{bib_source},
            holdings => $holdings->{$bib_id} || []
        };

        for my $df (q/create_date edit_date/) {
            next unless $bib->{$df};
            # ES wants ISO dates with the 'T' separator
            (my $val = $bib->{$df}) =~ s/ /T/g;
            $body->{$df} = $val;
        }

        my $fields = $self->get_db_rows(
            "SELECT * FROM elastic.bib_record_properties($bib_id)");

        for my $field (@$fields) {
            my $fclass = $field->{search_group};
            my $fname = $field->{name};
            $fname = "$fclass|$fname" if $fclass;
            $body->{$fname} = $field->{value}
        }

        return 0 unless 
            $self->index_document($bib_id, $body);

        $state->{last_bib_id} = $bib_id;
        $index_count++;
    }

    return $index_count;
}

# Load holdings summary blobs for requested bibs
sub load_holdings {
    my ($self, $bib_ids) = @_;

    my $bib_ids_str = join(',', @$bib_ids);

    my $copy_data = $self->get_db_rows(<<SQL);
SELECT 
    COUNT(*) AS count,
    acn.record, 
    acp.status AS status, 
    acp.circ_lib AS circ_lib, 
    acp.location AS location,
    acp.circulate AS circulate,
    acp.opac_visible AS opac_visible
FROM asset.copy acp
JOIN asset.call_number acn ON acp.call_number = acn.id
WHERE 
    NOT acp.deleted AND
    NOT acn.deleted AND
    acn.record IN ($bib_ids_str)
GROUP BY 2, 3, 4, 5, 6, 7
SQL

    $logger->info("ES found ".scalar(@$copy_data).
        " holdings summaries for current record batch");

    my $holdings = {};
    for my $copy (@$copy_data) {

        $holdings->{$copy->{record}} = [] 
            unless $holdings->{$copy->{record}};

        push(@{$holdings->{$copy->{record}}}, {
            count => $copy->{count},
            status => $copy->{status},
            circ_lib => $copy->{circ_lib},
            location => $copy->{location},
            #circulate => $copy->{circulate} eq 't' ? 'true' : 'false',
            #opac_visbile => $copy->{opac_visible} eq 't' ? 'true' : 'false'
            circulate => $copy->{circulate} ? 'true' : 'false',
            opac_visbile => $copy->{opac_visible} ? 'true' : 'false'
        });
    }

    return $holdings;
}

1;


