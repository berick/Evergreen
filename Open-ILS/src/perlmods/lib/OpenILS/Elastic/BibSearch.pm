# ---------------------------------------------------------------
# Copyright (C) 2019-2020 King County Library System
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
package OpenILS::Elastic::BibSearch;
use strict;
use warnings;
use DateTime;
use Clone 'clone';
use Time::HiRes qw/time/;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::DateTime qw/interval_to_seconds/;
use OpenILS::Elastic;
use OpenILS::Utils::Normalize;
use base qw/OpenILS::Elastic/;

# default number of bibs to index per batch.
my $DEFAULT_BIB_BATCH_SIZE = 500;
my $INDEX_CLASS = 'bib-search';

# https://www.elastic.co/guide/en/elasticsearch/reference/current/ignore-above.html
# Useful for ignoring excessively long filters and facets.
# Only applied to the keyword variation of each index.  Does not affect
# the 'text' varieties. The selected limit is arbitrary.
my $IGNORE_ABOVE = 256;

# Individual characters of some values like sorters provide less and less
# value as the length of the text gets longer and longer.  Unlike
# $IGNORE_ABOVE, this only trims the string, it does not prevent it from
# getting indexed in the first place.  The selected limit is arbitrary.
my $TRIM_ABOVE = 512;

my $BASE_INDEX_SETTINGS = {
    analysis => {
        analyzer => {
            folding => {
                filter => ['lowercase', 'asciifolding'],
                tokenizer => 'standard'
            },
            stripdots => {
                # "R.E.M." => "REM"
                char_filter => ['stripdots'],
                filter => ['lowercase'],
                tokenizer => 'standard'
            },
            spacedots => {
                # "R.E.M." => "R E M"
                char_filter => ['spacedots'],
                filter => ['lowercase'],
                tokenizer => 'standard'
            }
        },
        normalizer =>  {
            custom_lowercase => {
                type => 'custom',
                filter => ['lowercase']
            }
        },
        char_filter => {
            stripdots => {
                type => 'mapping',
                mappings => ['. =>']
            },
            spacedots => {
                type => 'mapping',
                mappings => ['. => " "']
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
    # The 'keyword' variation of each is used for exact matches, 
    # starts with, and similar searches.
    # Note the ignore_above only affects the 'keyword' version of the
    # field, the assumption being text that large would solely be
    # searched via 'text' indexes.
    title => {
        type => 'keyword',
        ignore_above => $IGNORE_ABOVE,
        normalizer => 'custom_lowercase',
        fields => {
            text => {type => 'text'},
            text_folded => {type => 'text', analyzer => 'folding'},
            text_spacedots => {type => 'text', analyzer => 'spacedots'},
            text_stripdots => {type => 'text', analyzer => 'stripdots'}
        }
    },
    author => {
        type => 'keyword',
        ignore_above => $IGNORE_ABOVE,
        normalizer => 'custom_lowercase',
        fields => {
            text => {type => 'text'},
            text_folded => {type => 'text', analyzer => 'folding'},
            text_spacedots => {type => 'text', analyzer => 'spacedots'},
            text_stripdots => {type => 'text', analyzer => 'stripdots'}
        }
    },
    subject => {
        type => 'keyword',
        ignore_above => $IGNORE_ABOVE,
        normalizer => 'custom_lowercase',
        fields => {
            text => {type => 'text'},
            text_folded => {type => 'text', analyzer => 'folding'},
            text_spacedots => {type => 'text', analyzer => 'spacedots'},
            text_stripdots => {type => 'text', analyzer => 'stripdots'}
        }
    },
    series => {
        type => 'keyword',
        ignore_above => $IGNORE_ABOVE,
        normalizer => 'custom_lowercase',
        fields => {
            text => {type => 'text'},
            text_folded => {type => 'text', analyzer => 'folding'},
            text_spacedots => {type => 'text', analyzer => 'spacedots'},
            text_stripdots => {type => 'text', analyzer => 'stripdots'}
        }
    },
    keyword => {
        # term (aka "keyword") searches are not used on the 
        # keyword field, but we structure the index just the same
        # for consistency with other group fields.
        type => 'keyword',
        ignore_above => 1, # essentially a no-op.
        fields => {
            text => {type => 'text'},
            text_folded => {type => 'text', analyzer => 'folding'},
            text_spacedots => {type => 'text', analyzer => 'spacedots'},
            text_stripdots => {type => 'text', analyzer => 'stripdots'}
        }
    },
    # Identifier fields only support 'keyword' indexes, no full-text.
    identifier => {
        type => 'keyword',
        ignore_above => $IGNORE_ABOVE,
        normalizer => 'custom_lowercase',
    }
};

# Map 'au' to 'author', etc.
my %SEARCH_CLASS_ALIAS_MAP = (
    ti => 'title.text',
    au => 'author.text',
    su => 'subject.text',
    se => 'series.text',
    kw => 'keyword.text',
    pb => 'keyword|publisher.text',
    id => 'identifier'
);

sub index_class {
    return $INDEX_CLASS;
}

# TODO: determine when/how to apply language analyzers.
# e.g. create lang-specific index fields?
sub language_analyzers {
    return ("english");
}

sub skip_holdings {
    my $self = shift;
    return $self->{skip_holdings};
}

sub xsl_file {
    my ($self) = @_;

    if (!$self->{xsl_file}) {

        my $client = OpenSRF::Utils::SettingsClient->new;
        my $dir = $client->config_value("dirs", "xsl");

        my $filename = new_editor()->search_config_global_flag({
            name => 'elastic.bib_search.transform_file', 
            enabled => 't'
        })->[0];

        if ($filename) {
            $self->{xsl_file} = "$dir/" . $filename->value;

        } else {
            die <<'            TEXT';
            No XSL file provided for Elastic::BibSearch.  Confirm
            config.global_flag "elastic.bib_search.transform_file"
            is enabled, contains a valid value, and the file exists 
            in the XSL directory.
            TEXT
        }
    }

    return $self->{xsl_file};
}

sub xsl_doc {
    my ($self) = @_;

    $self->{xsl_doc} = XML::LibXML->load_xml(location => $self->xsl_file)
        unless $self->{xsl_doc};

    return $self->{xsl_doc};
}

sub xsl_sheet {
    my $self = shift;

    $self->{xsl_sheet} = XML::LibXSLT->new->parse_stylesheet($self->xsl_doc)
        unless $self->{xsl_sheet};

    return $self->{xsl_sheet};
}

sub get_bib_data {
    my ($self, $record_ids) = @_;

    my $records = [];
    my $db_data = $self->get_bib_db_data($record_ids);

    for my $db_rec (@$db_data) {

        my $rec = {fields => []};
        push(@$records, $rec);

        # Copy DB data into our record object.
        $rec->{$_} = $db_rec->{$_} for 
            qw/id bib_source metarecord create_date edit_date deleted/;

        # No need to extract index values for delete records;
        next if $rec->{deleted} == 1;

        my $marc_doc = XML::LibXML->load_xml(string => $db_rec->{marc});
        my $result = $self->xsl_sheet->transform($marc_doc);
        my $output = $self->xsl_sheet->output_as_chars($result);

        my @rows = split(/\n/, $output);
        for my $row (@rows) {
            my ($purpose, $field_class, $name, @tokens) = split(/ /, $row);

            $field_class = '' if ($field_class || '') eq '_';

            my $value = join(' ', @tokens);

            my $field = {
                purpose => $purpose,
                field_class => $field_class,
                name => $name,
                value => $value
            };

            push(@{$rec->{fields}}, $field);
        }
    }

    return $records;
}

sub get_bib_db_data {
    my ($self, $record_ids) = @_;

    my $ids_str = join(',', @$record_ids);

    my $sql = <<SQL;
SELECT DISTINCT ON (bre.id)
    bre.id, 
    bre.create_date, 
    bre.edit_date, 
    bre.source AS bib_source,
    bre.deleted,
    bre.marc
FROM biblio.record_entry bre
LEFT JOIN metabib.metarecord_source_map mmrsm ON (mmrsm.source = bre.id)
WHERE bre.id IN ($ids_str)
SQL

    return $self->get_db_rows($sql);
}

sub create_index_properties {
    my ($self) = @_;

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

    my $fields = new_editor()->retrieve_all_elastic_bib_field;

    for my $field (@$fields) {

        my $field_name = $field->name;
        my $field_class = $field->field_class;
        $field_name = "$field_class|$field_name" if $field_class;

        my $def;

        if ($field_class) {
            if ($field->search_field eq 't') {

                # Use the same fields and analysis as the 'grouped' field.
                $def = clone($properties->{$field_class});

                # Copy grouped fields into their group parent field.
                $def->{copy_to} = $field_class;

                # Apply ranking boost to each analysis variation.
                my $flds = $def->{fields};
                if ($flds && (my $boost = ($field->weight || 1)) > 1) {
                    $flds->{$_}->{boost} = $boost foreach keys %$flds;
                }
            }

        } else {
            # Filters and sorters

            $def = {
                type => 'keyword',
                normalizer => 'custom_lowercase'
            };

            # Long sorter values are not necessarily unexpected,
            # e.g. long titles.
            $def->{ignore_above} = $IGNORE_ABOVE unless $field->sorter eq 't';
        }

        if ($def) {
            $logger->debug("ES adding field $field_name: ". 
                OpenSRF::Utils::JSON->perl2JSON($def));
    
            $properties->{$field_name} = $def;
        }

        # Search and facet fields can have the same name/group pair,
        # but are stored as separate fields in ES since the content
        # may vary between the two.
        if ($field->facet_field eq 't') {

            # Facet fields are stored as separate fields, because their
            # content may differ from the matching search field.
            $field_name = "$field_name|facet";

            $def = {
                type => 'keyword',
                ignore_above => $IGNORE_ABOVE
            };

            $logger->debug("ES adding field $field_name: ". 
                OpenSRF::Utils::JSON->perl2JSON($def));

            $properties->{$field_name} = $def;
        }
    }

    return $properties;
}

sub create_index {
    my ($self) = @_;
    my $index_name = $self->index_name;

    if ($self->es->indices->exists(index => $index_name)) {
        $logger->warn("ES index '$index_name' already exists in ES");
        return;
    }

    # Add a record of our new index to EG's DB if necessary.
    my $eg_conf = $self->find_or_create_index_config;

    $logger->info(
        "ES creating index '$index_name' on cluster '".$self->cluster."'");

    my $properties = $self->create_index_properties;

    my $settings = $BASE_INDEX_SETTINGS;
    $settings->{number_of_replicas} = scalar(@{$self->nodes});
    $settings->{number_of_shards} = $eg_conf->num_shards;

    my $conf = {
        index => $index_name,
        body => {settings => $settings}
    };

    $logger->info("ES creating index '$index_name'");

    # Create the base index with settings
    eval { $self->es->indices->create($conf) };

    if ($@) {
        $logger->error("ES failed to create index cluster=".  
            $self->cluster. "index=$index_name error=$@");
        warn "$@\n\n";
        return 0;
    }

    # Create each mapping one at a time instead of en masse so we 
    # can more easily report when mapping creation fails.
    for my $field (keys %$properties) {
        return 0 unless 
            $self->create_one_field_index($field, $properties->{$field});
    }

    # Now that we've added the configured fields,
    # add the shortened field_class aliases.
    while (my ($alias, $field) = each %SEARCH_CLASS_ALIAS_MAP) {
        return 0 unless $self->create_one_field_index(
            $alias, {type => 'alias', path => $field});
    }

    return 1;
}

sub create_one_field_index {
    my ($self, $field, $properties) = @_;
    my $index_name = $self->index_name;
    $logger->info("ES Creating index mapping for field $field");
    if ($field eq 'author') {
        $logger->info("ES Def Is: " . OpenSRF::Utils::JSON->perl2JSON($properties));
    }

    eval { 
        $self->es->indices->put_mapping({
            index => $index_name,
            type  => 'record',
            body  => {
                dynamic => 'strict', 
                properties => {$field => $properties}
            }
        });
    };

    if ($@) {
        my $mapjson = OpenSRF::Utils::JSON->perl2JSON($properties);

        $logger->error("ES failed to create index mapping: " .
            "index=$index_name field=$field error=$@ mapping=$mapjson");

        warn "$@\n\n";
        return 0;
    }

    return 1;
}


sub get_bib_field_for_data {
    my ($self, $bib_fields, $field) = @_;

    my @matches = grep {$_->name eq $field->{name}} @$bib_fields;

    @matches = grep {
        (($_->field_class || '') eq ($field->{field_class} || ''))
    } @matches;

    my ($match) = grep {
        ($_->search_field eq 't' && $field->{purpose} eq 'search') ||
        ($_->facet_field eq 't' && $field->{purpose} eq 'facet') ||
        ($_->filter eq 't' && $field->{purpose} eq 'filter') ||
        ($_->sorter eq 't' && $field->{purpose} eq 'sorter')
    } @matches;

    if (!$match) {
        $logger->warn("ES No elastic.bib_field matches extracted data ".
            OpenSRF::Utils::JSON->perl2JSON($field));
    }

    return $match;
}

sub populate_bib_index_batch {
    my ($self, $state) = @_;

    my $index_count = 0;

    my $bib_ids = $self->get_bib_ids($state);
    return 0 unless @$bib_ids;

    $logger->info("ES indexing ".scalar(@$bib_ids)." records");

    my $records = $self->get_bib_data($bib_ids);

    # Remove records that are marked deleted.
    # This should only happen when running in refresh mode.

    my @active_ids;
    for my $bib_id (@$bib_ids) {

        # Every row in the result data contains the 'deleted' value.
        my ($rec) = grep {$_->{id} == $bib_id} @$records;

        if ($rec->{deleted} == 1) { # not 't' / 'f'
           $self->delete_documents($bib_id); 
        } else {
            push(@active_ids, $bib_id);
        }
    }

    $bib_ids = [@active_ids];

    my $holdings = $self->load_holdings($bib_ids) unless $self->skip_holdings;

    my $bib_fields = new_editor()->retrieve_all_elastic_bib_field;

    for my $bib_id (@$bib_ids) {
        my ($rec) = grep {$_->{id} == $bib_id} @$records;

        my $body = {
            bib_source => $rec->{bib_source},
            metarecord => $rec->{metarecord},
            marc => []
        };

        $body->{holdings} = $holdings->{$bib_id} || [] unless $self->skip_holdings;

        # ES likes the "T" separator for ISO dates
        ($body->{create_date} = $rec->{create_date}) =~ s/ /T/g;
        ($body->{edit_date} = $rec->{edit_date}) =~ s/ /T/g;

        for my $field (@{$rec->{fields}}) {
            my $purpose = $field->{purpose};
            my $fclass = $field->{field_class};
            my $fname = $field->{name};
            my $value = $field->{value};

            next unless defined $value && $value ne '';

            my $trim = $purpose eq 'sorter' ? $TRIM_ABOVE : undef;
            $value = $self->truncate_value($value, $trim);

            if ($purpose eq 'marc') {
                # NOTE: we could create/require elastic.bib_field entries for 
                # MARC values as well if we wanted to control the exact
                # MARC data that's indexed.
                $self->add_marc_value($body, $fclass, $fname, $value);
                next;
            }

            # Ignore any data provided by the transform we have
            # no configuration for.
            next unless $self->get_bib_field_for_data($bib_fields, $field);
        
            $fname = "$fclass|$fname" if $fclass;
            $fname = "$fname|facet" if $purpose eq 'facet';

            if ($fname eq 'identifier|isbn') {
                index_isbns($body, $value);

            } elsif ($fname eq 'identifier|issn') {
                index_issns($body, $value);

            } elsif ($fname eq 'pubdate') {
                index_pubdate($body, $value);

            } elsif ($fname =~ /sort/) {
                index_sorter($body, $fname, $value);

            } else {
                append_field_value($body, $fname, $value);
            }
        }

        if ($self->skip_holdings) {
            # Skip-Holdings mode performs an update for existing
            # documents, so the attached holdings will remain, but 
            # performs a create for documents that don't yet exist.
            if ($self->document_exists($bib_id)) {
                return 0 unless $self->update_document($bib_id, $body);
            } else {
                return 0 unless $self->create_document($bib_id, $body);
            }
        } else {
            return 0 unless $self->index_document($bib_id, $body);
        }

        $state->{start_record} = $bib_id + 1;
        $index_count++;
    }

    $logger->info("ES indexing completed for records " . 
        $bib_ids->[0] . '...' . $bib_ids->[-1]);

    return $index_count;
}

sub index_sorter {
    my ($body, $fname, $value) = @_;

    $value = OpenILS::Utils::Normalize::search_normalize($value);

    $value =~ s/^ +//g;

    append_field_value($body, $fname, $value) if $value;
}

# Normalize the pubdate (used for sorting) to a single 4-digit year.
# Pad with zeroes where the year fall short of 4 digits.
sub index_pubdate {
    my ($body, $value) = @_;

    $value =~ s/\D//g;

    return unless $value; # no numbers

    $value = substr($value . '0' x 4, 0, 4);

    return if $value eq '0000'; # treat as no date.

    append_field_value($body, 'pubdate', $value) if $value;
}


# Indexes ISBN10, ISBN13, and formatted values of both (with hyphens)
sub index_isbns {
    my ($body, $value) = @_;
    return unless $value;
    
    my %seen; # deduplicate values
    my @isbns = OpenILS::Utils::Normalize::clean_isbns($value);

    for my $isbn (@isbns) {
        if ($isbn->as_isbn10) {
            $seen{$isbn->as_isbn10->isbn} = 1; # compact
            $seen{$isbn->as_isbn10->as_string} = 1; # with hyphens
        }
        if ($isbn->as_isbn13) {
            $seen{$isbn->as_isbn13->isbn} = 1;
            $seen{$isbn->as_isbn13->as_string} = 1;
        }
    }

    append_field_value($body, 'identifier|isbn', $_) foreach keys %seen;
}

# Indexes ISSN values with and wihtout hyphen formatting.
sub index_issns {
    my ($body, $value) = @_;
    return unless $value;

    my %seen; # deduplicate values
    my @issns = OpenILS::Utils::Normalize::clean_issns($value);
    
    for my $issn (@issns) {
        # no option in business::issn to get the unformatted value.
        (my $unformatted = $issn->as_string) =~ s/-//g;
        $seen{$unformatted} = 1;
        $seen{$issn->as_string} = 1;
    }

    append_field_value($body, 'identifier|issn', $_) foreach keys %seen;
}

sub append_field_value {
    my ($body, $fname, $value) = @_;

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
            status => $copy->{status},
            circ_lib => $copy->{circ_lib},
            location => $copy->{location},
            circulate => $copy->{circulate} ? 'true' : 'false',
            opac_visible => $copy->{opac_visible} ? 'true' : 'false'
        });
    }

    return $holdings;
}

sub add_marc_value {
    my ($self, $rec, $tag, $subfield, $value) = @_;

    # XSL uses '_' when no subfield is present (e.g. controlfields)
    $subfield = undef if $subfield eq '_';

    my ($match) = grep {
        $_->{tag} eq $tag &&
        ($_->{subfield} || '') eq ($subfield || '')
    } @{$rec->{marc}};

    if ($match) {
        if (ref $match->{value}) {
            # 3rd or more instance of tag/subfield for this record.

            # avoid dupes
            return if grep {$_ eq $value} @{$match->{value}};

            push(@{$match->{value}}, $value);

        } else {
            # 2nd instance of tag/subfield for this record.
            
            # avoid dupes
            return if $match->{value} eq $value;

            $match->{value} = [$match->{value}, $value];
        }

    } else {
        # first instance of tag/subfield for this record.

        $match = {tag => $tag, value => $value};
        $match->{subfield} = $subfield if defined $subfield;

        push(@{$rec->{marc}}, $match);
    }
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


