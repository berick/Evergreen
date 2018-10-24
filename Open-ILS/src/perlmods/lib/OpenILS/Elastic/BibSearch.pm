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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
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
use base qw/OpenILS::Elastic/;
use Data::Dumper;
$Data::Dumper::Indent = 2;

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

    # Holdings summaries.  For bib-search purposes, we don't need
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
            folded => {type => 'text', analyzer => 'folding'},
            raw => {type => 'keyword'}
        }
    },
    author => {
        type => 'text',
        analyzer => $LANG_ANALYZER,
        fields => {
            folded => {type => 'text', analyzer => 'folding'},
            raw => {type => 'keyword'}
        }
    },
    subject => {
        type => 'text',
        analyzer => $LANG_ANALYZER,
        fields => {
            folded => {type => 'text', analyzer => 'folding'},
            raw => {type => 'keyword'}
        }
    },
    series => {
        type => 'text',
        analyzer => $LANG_ANALYZER,
        fields => {
            folded => {type => 'text', analyzer => 'folding'},
            raw => {type => 'keyword'}
        }
    },

    # No .raw field for keyword based on the assumption
    # keyword values are not used for sorting or aggregation.
    keyword => {
        type => 'text',
        analyzer => $LANG_ANALYZER,
        fields => {
            folded => {type => 'text', analyzer => 'folding'}
        }
    },

    # Index identifier fields as keywords to avoid unnecessary
    # ES analysis.
    identifier => {type => 'keyword'}
};

sub index_name {
    return $INDEX_NAME;
}

sub index {
    my $self = shift;
    return $self->{index} if $self->{index};
    ($self->{index}) = grep {$_->{purpose} eq $INDEX_NAME} @{$self->{indices}};
    return $self->{index};
}

sub get_marc_fields {
    my $self = shift;
    return grep {
        $_->{index} == $self->index->{id}
    } @{$self->{marc_fields}};
}

# Load the XSLT transforms from the DB.
sub load_transforms {
    my $self = shift;

    $self->{xsl_transforms} = {} unless $self->{xsl_transforms};

    for my $field ($self->get_marc_fields) {
        my $format = $field->{format};
        next if $self->{xsl_transforms}{$format};

        $logger->info("ES loading info for document type $format");

        my $xform = $self->get_db_rows(
            "SELECT * FROM config.xml_transform WHERE name = '$format'")->[0];

        $self->{xml_namespaces}{$format} = {
            prefix => $xform->{prefix},
            uri => $xform->{namespace_uri}
        };

        if ($format eq 'marcxml') {
            # No transform needed for MARCXML.  
            # Indicate we've seen it and move on.
            $self->{xsl_transforms}{$format} = {};
            next;
        }

        $logger->info("ES parsing stylesheet for $format");

        my $xsl_doc = XML::LibXML->new->parse_string($xform->{xslt});

        $self->{xsl_transforms}{$format} = 
            XML::LibXSLT->new->parse_stylesheet($xsl_doc);
    }
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

    # Add an index definition for each dynamic field.
    # Add copy_to for field_class-level combined searches.
    for my $field ($self->get_marc_fields) {

        my $field_class = $field->{field_class};
        my $field_name = "$field_class|" . $field->{name};

        # Clone the class-level index definition (e.g. title) to
        # use as the source of the field-specific index.
        my $def = clone($BASE_PROPERTIES->{$field_class});

        # Copy data for all fields to their parent class to
        # support group-level searches (e.g. title search)
        $def->{copy_to} = $field_class;
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

    $self->load_transforms;

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
SELECT bre.id, bre.marc, bre.create_date, bre.edit_date, bre.source
FROM biblio.record_entry bre
SQL

    if ($record_id) {
        $sql .= " WHERE bre.id = $record_id"
    } else {
        my $last_id = $state->{last_bib_id};
        $sql .= <<SQL;
WHERE NOT bre.deleted AND bre.active AND bre.id > $last_id
ORDER BY bre.edit_date , bre.id LIMIT $BIB_BATCH_SIZE
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

    for my $bib (@$bib_data) {
        my $bib_id = $bib->{id};

        my $marc_doc = XML::LibXML->new->parse_string($bib->{marc});
        my $body = $self->extract_bib_values($marc_doc);

        $body->{holdings} = $holdings->{$bib_id} || [];
        $body->{source} = $bib->{source};

        for my $field (q/create_date edit_date/) {
            next unless $bib->{$field};
            # ES wants ISO dates with the 'T' separator
            (my $val = $bib->{$field}) =~ s/ /T/g;
            $body->{$field} = $val;
        }

        return 0 unless 
            $self->index_document($bib_id, $body);

        $state->{last_bib_id} = $bib_id;
        $index_count++;
    }

    return $index_count;
}

sub get_bib_as {
    my ($self, $marc_doc, $format) = @_;
    return $marc_doc if $format eq 'marcxml';
    return $self->{xsl_transforms}{$format}->transform($marc_doc);
}

# Returns either a string value or an array of string values.
sub extract_xpath {
    my ($self, $xml_doc, $format, $xpath) = @_;

    my $ns = $self->{xml_namespaces}{$format};
    my $root = $xml_doc->documentElement;

    $root->setNamespace($ns->{uri}, $ns->{prefix}, 1);

    my @nodes = $root->findnodes($xpath);

    if (@nodes) {
        if (@nodes == 1) {
            return $nodes[0]->textContent;
        } else {
            return [ map { $_->textContent } @nodes ]; 
        }
    } else {
        # Some XPATH returns nodes, some (e.g. substring()) returns 
        # string values instead of nodes.
        return $root->findvalue($xpath) || undef;
    }
}

sub extract_bib_values {
    my ($self, $marc_doc) = @_;

    # various formats of the current MARC record (mods, etc.)
    my %xform_docs;
    my $values = {};
    for my $field ($self->get_marc_fields) {

        my $format = $field->{format};
        my $field_name = $field->{field_class} .'|' . $field->{name};

        $xform_docs{$format} = $self->get_bib_as($marc_doc, $format)
            unless $xform_docs{$format};

        my $xform_doc = $xform_docs{$format};

        $values->{$field_name} = 
            $self->extract_xpath($xform_doc, $format, $field->{xpath});
    }

    return $values;
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
            circulate => $copy->{circulate} eq 't' ? 'true' : 'false',
            opac_visbile => $copy->{opac_visible} eq 't' ? 'true' : 'false'
        });
    }

    return $holdings;
}

1;


