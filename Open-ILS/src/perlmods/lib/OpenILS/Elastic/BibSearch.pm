package OpenILS::Elastic::BibSearch;
# ---------------------------------------------------------------
# Copyright (C) 2019 King County Library System
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
use Encode;
use DateTime;
use Time::HiRes qw/time/;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenSRF::Utils::JSON;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::DateTime qw/interval_to_seconds/;
use OpenILS::Elastic;
use base qw/OpenILS::Elastic/;

# default number of bibs to index per batch.
my $DEFAULT_BIB_BATCH_SIZE = 500;

my $INDEX_NAME = 'bib-search';

my $BASE_INDEX_SETTINGS = {
    analysis => {
        analyzer => {
            folding => {
                filter => ['lowercase', 'asciifolding'],
                tokenizer => 'standard'
            }
        },
        normalizer =>  {
            custom_lowercase => {
                type => 'custom',
                filter => ['lowercase']
            }
        }
    }
};

# Well-known bib-search index properties
my $BASE_PROPERTIES = {
    bib_source  => {type => 'integer'},
    create_date => {type => 'date'},
    edit_date   => {type => 'date'},
    metarecord  => {type => 'integer'},

    # Holdings summaries.  For bib-search, we don't need
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
    marc => {
        type => 'nested',
        properties => {
            tag => {
                type => 'keyword',
                normalizer => 'custom_lowercase'
            },
            subfield => {
                type => 'keyword',
                normalizer => 'custom_lowercase'
            },
            value => {
                type => 'text',
                fields => {
                    text_folded => {
                        type => 'text',
                        analyzer => 'folding'
                    }
                }
            }
        }
    },

    # Make it possible to search across all fields in a search group.
    # Values from grouped fields are copied into the group field.
    # Here we make some assumptions about the general purpose of
    # each group.
    # Note the ignore_above only affects the 'keyword' version of the
    # field, the assumption being text that large would solely be
    # searched via 'text' indexes.
    title => {
        type => 'keyword',
        ignore_above => 256,
        normalizer => 'custom_lowercase',
        fields => {
            text => {type => 'text'},
            text_folded => {type => 'text', analyzer => 'folding'}
        }
    },
    author => {
        type => 'keyword',
        ignore_above => 256,
        normalizer => 'custom_lowercase',
        fields => {
            text => {type => 'text'},
            text_folded => {type => 'text', analyzer => 'folding'}
        }
    },
    subject => {
        type => 'keyword',
        ignore_above => 256,
        normalizer => 'custom_lowercase',
        fields => {
            text => {type => 'text'},
            text_folded => {type => 'text', analyzer => 'folding'}
        }
    },
    series => {
        type => 'keyword',
        ignore_above => 256,
        normalizer => 'custom_lowercase',
        fields => {
            text => {type => 'text'},
            text_folded => {type => 'text', analyzer => 'folding'}
        }
    },
    keyword => {
        # term (aka "keyword") searches are not used on the 
        # keyword field, but we index it just the same (sans lowercase) 
        # for structural consistency with other group fields.
        type => 'keyword',
        ignore_above => 256,
        fields => {
            text => {type => 'text'},
            text_folded => {type => 'text', analyzer => 'folding'}
        }
    },
    identifier => {
        # Avoid full-text indexing on identifier fields.
        type => 'keyword',
        ignore_above => 256,
        normalizer => 'custom_lowercase',
    },

    # Create some shortcut indexes for streamlining query_string searches.
    ti => {type => 'text'},
    au => {type => 'text'},
    se => {type => 'text'},
    su => {type => 'text'},
    kw => {type => 'text'},
    id => {
        type => 'keyword',
        ignore_above => 256
    }
};

my %SHORT_GROUP_MAP = (
    title => 'ti',
    author => 'au',
    subject => 'su',
    series => 'se',
    keyword => 'kw',
    identifier => 'id'
);

sub index_name {
    return $INDEX_NAME;
}

# TODO: add index-specific language analyzers to DB config
sub language_analyzers {
    return ("english");
}

sub create_index_properties {
    my ($self, $custom_properties) = @_;

    if ($custom_properties) {
        $logger->info("ES generating index mappings from custom file $custom_properties");

        my $json;
        {
            local $/=undef;

            if (!open(MAPPING_FILE, $custom_properties)) {
                $logger->error("ES cannot open mappings file: $!");
                return undef;
            }

            $json = <MAPPING_FILE>;
            close MAPPING_FILE;
        }

        my $struct = OpenSRF::Utils::JSON->JSON2perl($json);
        return $struct->{'bib-search'}->{mappings}->{record}->{properties};
    }

    my $properties = $BASE_PROPERTIES;

    # Add the language analyzers to the MARC mappings
    for my $lang_analyzer ($self->language_analyzers) {
        $properties->{marc}->{properties}->{value}->{fields}->{"text_$lang_analyzer"} = {
            type => 'text',
            analyzer => $lang_analyzer
        };

        # Apply language analysis to grouped fields, however skip
        # the 'author' and 'identifier' groups since it makes less sense to 
        # language-analyze proper names and identifiers.
        $properties->{$_}->{fields}->{"text_$lang_analyzer"} = {
            type => 'text',
            analyzer => $lang_analyzer
        } foreach qw/title subject series keyword/;
    }

    # elastic.bib_field has no primary key field, so retrieve_all won't work.
    # Note the name value may be repeated across search group depending
    # on local configuration.
    my $fields = new_editor()->search_elastic_bib_field({name => {'!=' => undef}});

    for my $field (@$fields) {

        my $field_name = $field->name;
        my $search_group = $field->search_group;
        $field_name = "$search_group|$field_name" if $search_group;

        my $def;

        if ($search_group) {

            # Use the same fields and analysis as the 'grouped' field.
            $def = clone($properties->{$search_group});
            $def->{copy_to} = [$search_group, $SHORT_GROUP_MAP{$search_group}];

            # Apply ranking boost to each analysis variation.
            my $flds = $def->{fields};
            if ($flds && (my $boost = ($field->weight || 1)) > 1) {
                $flds->{$_}->{boost} = $boost foreach keys %$flds;
            }

        } else {

            # Non-grouped fields are used for filtering and sorting, so
            # they don't need as much processing.

            $def = {
                type => 'keyword',
                ignore_above => 256,
                normalizer => 'custom_lowercase'
            };
        }

        if ($field->facet_field eq 't' && $def->{fields}) {
            # Facet fields are used for aggregation which requires
            # an additional unaltered keyword field.
            $def->{fields}->{facet} = {
                type => 'keyword',
                ignore_above => 256
            };
        }

        $logger->debug("ES adding field $field_name: ". 
            OpenSRF::Utils::JSON->perl2JSON($def));

        $properties->{$field_name} = $def;
    }

    return $properties;
}

sub create_index {
    my ($self, $custom_properties) = @_;

    if ($self->es->indices->exists(index => $INDEX_NAME)) {
        $logger->warn("ES index '$INDEX_NAME' already exists");
        return;
    }

    $logger->info(
        "ES creating index '$INDEX_NAME' on cluster '".$self->cluster."'");

    my $properties = $self->create_index_properties($custom_properties);

    my $settings = $BASE_INDEX_SETTINGS;
    $settings->{number_of_replicas} = scalar(@{$self->nodes});
    $settings->{number_of_shards} = $self->index->num_shards;

    my $conf = {
        index => $INDEX_NAME,
        body => {settings => $settings}
    };

    $logger->info("ES creating index '$INDEX_NAME'");

    # Create the base index with settings
    eval { $self->es->indices->create($conf) };

    if ($@) {
        $logger->error("ES failed to create index cluster=".  
            $self->cluster. "index=$INDEX_NAME error=$@");
        warn "$@\n\n";
        return 0;
    }

    # Create each mapping one at a time instead of en masse so we 
    # can more easily report when mapping creation fails.

    for my $field (keys %$properties) {
        $logger->info("ES Creating index mapping for field $field");

        eval { 
            $self->es->indices->put_mapping({
                index => $INDEX_NAME,
                type  => 'record',
                body  => {dynamic => 'false', properties => {$field => $properties->{$field}}}
            });
        };

        if ($@) {
            my $mapjson = OpenSRF::Utils::JSON->perl2JSON($properties->{$field});

            $logger->error("ES failed to create index mapping: " .
                "index=$INDEX_NAME field=$field error=$@ mapping=$mapjson");

            warn "$@\n\n";
            return 0;
        }
    }

    return 1;
}

sub get_bib_data {
    my ($self, $record_ids) = @_;

    my $ids_str = join(',', @$record_ids);

    my $sql = <<SQL;
SELECT DISTINCT ON (bre.id, search_group, name, value)
    bre.id, 
    bre.create_date, 
    bre.edit_date, 
    bre.source AS bib_source,
    bre.deleted,
    mmrsm.metarecord,
    (elastic.bib_record_properties(bre.id)).*
FROM biblio.record_entry bre
LEFT JOIN metabib.metarecord_source_map mmrsm ON (mmrsm.source = bre.id)
WHERE bre.id IN ($ids_str)
SQL

    return $self->get_db_rows($sql);
}

sub populate_bib_index_batch {
    my ($self, $state) = @_;

    my $index_count = 0;

    my $bib_ids = $self->get_bib_ids($state);
    return 0 unless @$bib_ids;

    $logger->info("ES indexing ".scalar(@$bib_ids)." records");

    my $bib_data = $self->get_bib_data($bib_ids);

    # Remove records that are marked deleted.
    # This should only happen when running in refresh mode.

    my @active_ids;
    for my $bib_id (@$bib_ids) {

        # Every row in the result data contains the 'deleted' value.
        my ($field) = grep {$_->{id} == $bib_id} @$bib_data;

        if ($field->{deleted} == 1) { # not 't' / 'f'
           $self->delete_documents($bib_id); 
        } else {
            push(@active_ids, $bib_id);
        }
    }

    $bib_ids = [@active_ids];

    my $holdings = $self->load_holdings($bib_ids);
    my $marc = $self->load_marc($bib_ids);
    my $def = $self->get_index_def;

    # Ask ES what the index properties are so we can avoid passing data
    # that will not be indexed, since ES will store the data on the source
    # object even if it's not indexed.  This reduces bulk.
    my $properties =
        $def->{$self->index_name}->{mappings}->{record}->{properties};

    for my $bib_id (@$bib_ids) {

        my $body = {
            marc => $marc->{$bib_id} || [],
            holdings => $holdings->{$bib_id} || []
        };

        # there are multiple rows per bib in the data list.
        my @fields = grep {$_->{id} == $bib_id} @$bib_data;

        my $first = 1;
        for my $field (@fields) {
        
            if ($first) {
                $first = 0;
                # some values are repeated per field. 
                # extract them from the first entry.
                $body->{bib_source} = $field->{bib_source};
                $body->{metarecord} = $field->{metarecord};

                # ES ikes the "T" separator for ISO dates
                ($body->{create_date} = $field->{create_date}) =~ s/ /T/g;
                ($body->{edit_date} = $field->{edit_date}) =~ s/ /T/g;
            }

            my $fclass = $field->{search_group};
            my $fname = $field->{name};
            my $value = $field->{value};
            $fname = "$fclass|$fname" if $fclass;
            $value = $self->truncate_value($value);

            if ($fname eq 'identifier|isbn') {
                index_isbns($body, $value);
            } elsif ($fname eq 'identifier|issn') {
                index_issns($body, $value);
            } else {
                append_field_value($body, $fname, $value, $properties);
            }
        }

        return 0 unless $self->index_document($bib_id, $body);

        $state->{start_record} = $bib_id + 1;
        $index_count++;
    }

    $logger->info("ES indexing completed for records " . 
        $bib_ids->[0] . '...' . $bib_ids->[-1]);

    return $index_count;
}


# Indexes ISBN10, ISBN13, and formatted values of both (with hyphens)
sub index_isbns {
    my ($body, $value) = @_;
    return unless $value;
    
    my %seen; # deduplicate values

    # Chop up the collected raw values into parts and let
    # Business::* tell us which parts looks like ISBNs.
    for my $token (split(/ /, $value)) {
        my $isbn = Business::ISBN->new($token);
        if ($isbn && $isbn->is_valid) {
            if ($isbn->as_isbn10) {
                $seen{$isbn->as_isbn10->isbn} = 1;
                $seen{$isbn->as_isbn10->as_string} = 1;
            }
            if ($isbn->as_isbn13) {
                $seen{$isbn->as_isbn13->isbn} = 1;
                $seen{$isbn->as_isbn13->as_string} = 1;
            }
        }
    }

    append_field_value($body, 'identifier|isbn', $_) foreach keys %seen;
}

# Indexes ISSN values with and wihtout hyphen formatting.
sub index_issns {
    my ($body, $value) = @_;
    return unless $value;

    my %seen; # deduplicate values
    
    # Chop up the collected raw values into parts and let
    # Business::* tell us which parts looks valid.
    for my $token (split(/ /, $value)) {
        my $issn = Business::ISSN->new($token);
        if ($issn && $issn->is_valid) {
            # no option in business::issn to get the unformatted value.
            (my $unformatted = $issn->as_string) =~ s/-//g;
            $seen{$unformatted} = 1;
            $seen{$issn->as_string} = 1;
        }
    }

    append_field_value($body, 'identifier|issn', $_) foreach keys %seen;
}

sub append_field_value {
    my ($body, $fname, $value, $properties) = @_;

    # Confirm the data is wanted in the index before passing to ES to
    # reduce the overall data footprint.
    return unless $properties->{$fname};

    if ($body->{$fname}) {
        if (ref $body->{$fname}) {
            # Three or more values encountered for field.
            # Add to the list.
            push(@{$body->{$fname}}, $value);
        } else {
            # Second value encountered for field.
            # Upgrade to array storage.
            $body->{$fname} = [$body->{$fname}, $value];
        }
    } else {
        # First value encountered for field.
        # Assume for now there will only be one value.
        $body->{$fname} = $value
    }
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
            circulate => $copy->{circulate} ? 'true' : 'false',
            opac_visbile => $copy->{opac_visible} ? 'true' : 'false'
        });
    }

    return $holdings;
}

sub load_marc {
    my ($self, $bib_ids) = @_;

    my $bib_ids_str = join(',', @$bib_ids);

    my $marc_data = $self->get_db_rows(<<SQL);
SELECT record, tag, subfield, value
FROM metabib.real_full_rec
WHERE record IN ($bib_ids_str)
SQL

    $logger->info("ES found ".scalar(@$marc_data).
        " MARC rows for current record batch");

    my $marc = {};
    for my $row (@$marc_data) {

        my $value = $row->{value};
        next unless defined $value && $value ne '';

        my $subfield = $row->{subfield};
        my $rec_id = $row->{record};
        delete $row->{record}; # avoid adding this to the index

        $row->{value} = $value = $self->truncate_value($value);

        $marc->{$rec_id} = [] unless $marc->{$rec_id};
        delete $row->{subfield} unless defined $subfield;

        # Add values to existing record/tag/subfield rows.
  
        my $existing;
        for my $entry (@{$marc->{$rec_id}}) {
            next unless $entry->{tag} eq $row->{tag};

            if (defined $subfield) {
                if (defined $entry->{subfield}) {
                    if ($subfield eq $entry->{subfield}) {
                        $existing = $entry;
                        last;
                    }
                }
            } elsif (!defined $entry->{subfield}) {
                # Neither has a subfield value / not all tags have subfields
                $existing = $entry;
                last;
            }
        }

        if ($existing) {
            
            $existing->{value} = [$existing->{value}] unless ref $existing->{value};
            push(@{$existing->{value}}, $value);

        } else {

            push(@{$marc->{$rec_id}}, $row);
        }
    }

    return $marc;
}



sub index {
    my $self = shift;
    return $self->{index} if $self->{index};
    ($self->{index}) = grep {$_->code eq $self->index_name} @{$self->indices};

    $logger->error("No ndex configured named ".$self->index_name) unless $self->{index};

    return $self->{index};
}


# Add data to the bib-search index
sub populate_index {
    my ($self, $settings) = @_;
    $settings ||= {};

    my $index_count = 0;
    my $total_indexed = 0;

    # extract the database settings.
    for my $db_key (grep {$_ =~ /^db_/} keys %$settings) {
        $self->{$db_key} = $settings->{$db_key};
    }

    my $end_time;
    my $duration = $settings->{max_duration};
    if ($duration) {
        my $seconds = interval_to_seconds($duration);
        $end_time = DateTime->now;
        $end_time->add(seconds => $seconds);
    }

    while (1) {

        $index_count = $self->populate_bib_index_batch($settings);
        $total_indexed += $index_count;

        $logger->info("ES indexed $total_indexed bib records");

        # exit if we're only indexing a single record or if the 
        # batch indexer says there are no more records to index.
        last if !$index_count || $settings->{index_record};

        if ($end_time && DateTime->now > $end_time) {
            $logger->info(
                "ES index populate exiting early on max_duration $duration");
            last;
        }
    } 

    $logger->info("ES bib indexing complete with $total_indexed records");
}

sub get_bib_ids {
    my ($self, $state) = @_;

    # A specific record is selected for indexing.
    return [$state->{index_record}] if $state->{index_record};

    my $start_id = $state->{start_record} || 0;
    my $stop_id = $state->{stop_record};
    my $modified_since = $state->{modified_since};
    my $batch_size = $state->{batch_size} || $DEFAULT_BIB_BATCH_SIZE;

    my ($select, $from, $where);
    if ($modified_since) {
        $select = "SELECT id";
        $from   = "FROM elastic.bib_last_mod_date";
        $where  = "WHERE last_mod_date > '$modified_since'";
    } else {
        $select = "SELECT id";
        $from   = "FROM biblio.record_entry";
        $where  = "WHERE NOT deleted AND active";
    }

    $where .= " AND id >= $start_id" if $start_id;
    $where .= " AND id <= $stop_id" if $stop_id;

    # Ordering by ID is the simplest way to guarantee all requested
    # records are processed, given that edit dates may not be unique
    # and that we're using start_id/stop_id instead of OFFSET to
    # define the batches.
    my $order = "ORDER BY id";

    my $sql = "$select $from $where $order LIMIT $batch_size";

    my $ids = $self->get_db_rows($sql);
    return [ map {$_->{id}} @$ids ];
}

1;


