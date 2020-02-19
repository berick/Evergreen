# ---------------------------------------------------------------
# Copyright (C) 2020 King County Library System
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
package OpenILS::Elastic::BibSearch::BibField;
# Helper class for modeling an elastic bib field.
# This is what OpenILS::Elastic::BibSearch expects.

sub new {
    my ($class, %args) = @_;
    return bless(\%args, $class);
}
sub name {
    my $self = shift;
    return $self->{name};
}
sub search_group {
    my $self = shift;
    return $self->{search_group};
}
sub search_field {
    my $self = shift;
    return $self->{purpose} eq 'search' ? 't' : 'f';
}
sub facet_field {
    my $self = shift;
    return $self->{purpose} eq 'facet' ? 't' : 'f';
}
sub sorter {
    my $self = shift;
    return $self->{purpose} eq 'sorter' ? 't' : 'f';
}
sub filter {
    my $self = shift;
    return $self->{purpose} eq 'filter' ? 't' : 'f';
}
sub weight {
    my $self = shift;
    return $self->{weight} || 1;
}

package OpenILS::Elastic::BibSearch::XSLT;
use strict;
use warnings;
use XML::LibXML;
use XML::LibXSLT;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Elastic::BibSearch;
use OpenILS::Utils::Normalize;
use base qw/OpenILS::Elastic::BibSearch/;


sub xsl_file {
    my ($self, $filename) = @_;
    $self->{xsl_file} = $filename if $filename;
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


my @seen_fields;
sub add_dynamic_field {
    my ($self, $fields, $purpose, $search_group, $name, $weight) = @_;
    return unless $name;
    $search_group ||= '';
    $weight ||= 1;

    my $tag = $purpose . ($search_group || '') . $name;
    return if grep {$_ eq $tag} @seen_fields;
    push(@seen_fields, $tag);

    $logger->info("ES adding dynamic field purpose=$purpose ".
        "search_group=$search_group name=$name weight=$weight");

    my $field = OpenILS::Elastic::BibSearch::BibField->new(
        purpose => $purpose, 
        search_group => $search_group, 
        name => $name,
        weight => $weight
    );

    push(@$fields, $field);
}

sub get_dynamic_fields {
    my $self = shift;
    my $fields = [];

    @seen_fields = (); # reset with each run

    my $null_doc = XML::LibXML->load_xml(string => '<root/>');
    my $result = $self->xsl_sheet->transform($null_doc, index_defs_only => '1');
    my $output = $self->xsl_sheet->output_as_chars($result);

    my @rows = split(/\n/, $output);
    for my $row (@rows) {
        my @parts = split(/ /, $row);
        if ($parts[0] eq 'search' || $parts[0] eq 'facet') {
            $self->add_dynamic_field($fields, @parts);
        } else {
            $self->add_dynamic_field($fields, $parts[0], undef, $parts[1]);
        }
    }

    return $fields;
}

sub get_bib_data {
    my ($self, $record_ids) = @_;

    my $bib_data = [];
    my $db_data = $self->get_bib_db_data($record_ids);

    for my $db_rec (@$db_data) {

        if ($db_rec->{deleted} == 1) {
            # No need to extract index values.
            push(@$bib_data, {deleted => 1});
            next;
        }

        my $marc_doc = XML::LibXML->load_xml(string => $db_rec->{marc});
        my $result = $self->xsl_sheet->transform($marc_doc, index_defs_only => 'false');
        my $output = $self->xsl_sheet->output_as_chars($result);

        my @rows = split(/\n/, $output);
        for my $row (@rows) {
            my @parts = split(/ /, $row);

            my $purpose = $parts[0];
            my $field = {purpose => $purpose};

            if ($purpose eq 'search' || $purpose eq 'facet') {
                next unless @parts > 3;
                $field->{search_group} = $parts[1];
                $field->{name} = $parts[2];
                $field->{value} = join(' ', @parts[3 .. $#parts]);

            } else { # filter or sorter
                next unless @parts > 2;
                $field->{name} = $parts[1];
                $field->{value} = join(' ', @parts[2 .. $#parts]);
            }

            # Stamp each field with the additional bib metadata.
            $field->{$_} = $db_rec->{$_} for 
                qw/id bib_source metarecord create_date edit_date deleted/;

            push(@$bib_data, $field);
        }
    }

    return $bib_data;
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


1;

