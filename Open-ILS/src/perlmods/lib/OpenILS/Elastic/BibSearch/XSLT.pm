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

sub search_field {
    return $self->{search_field} ? 't' : 'f';
}
sub facet_field {
    return $self->{facet_field} ? 't' : 'f';
}
sub sorter {
    return $self->{sorter} ? 't' : 'f';
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

    $self->{xsl_doc} = XML::LibXML->load_xml(location => $self->xsl_file);
        unless ($self->{xsl_doc});

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
    my ($self, $fields, $purpose, $class, $name) = @_;
    my $tag = $purpose . ($class || '') . $name;
    return if grep {$_ eq $tag} @seen_fields;

    my $field = OpenILS::Elastic::BibSearch::BibField->new(
        purpose => $purpose, 
        class => $class, 
        name => $name
    );

    push(@$fields, $field);
}

# TODO: what to do about fields that have the same class/name
# and are both search and facet fields, but the facet values
# are different than the searched value?

sub get_dynamic_fields {
    my $self = shift;
    my $fields = [];

    @seen_fields = (); # reset with each run

    my $doc = $self->xsl_doc;

    for my $node ($doc->findnodes('//xsl:call-template[@name="add_search_entry"]')) {
        my $class = $node->findnodes('./xsl:with-param[@name="field_class"]/text()');
        my $name = $node->findnodes('./xsl:with-param[@name="index_name"]/text()');
        $self->add_dynamic_field($fields, 'search', $class, $name);
    }

    for my $node ($doc->findnodes('//xsl:call-template[@name="add_facet_entry"]')) {
        my $class = $node->findnodes('./xsl:with-param[@name="field_class"]/text()');
        my $name = $node->findnodes('./xsl:with-param[@name="index_name"]/text()');
        $self->add_dynamic_field($fields, 'facet', $class, $name);
    }

    for my $node ($doc->findnodes('//xsl:call-template[@name="add_filter_entry"]')) {
        my $name = $node->findnodes('./xsl:with-param[@name="name"]/text()');
        $self->add_dynamic_field($fields, 'filter', undef, $name);
    }

    for my $node ($doc->findnodes('//xsl:call-template[@name="add_composite_filter_entry"]')) {
        my $name = $node->findnodes('./xsl:with-param[@name="name"]/text()');
        $self->add_dynamic_field($fields, 'filter', undef, $name);
    }

    for my $node ($doc->findnodes('//xsl:call-template[@name="add_sorter_entry"]')) {
        my $name = $node->findnodes('./xsl:with-param[@name="name"]/text()');
        $self->add_dynamic_field($fields, 'sorter', undef, $name);
    }

    return $fields;
}

sub get_bib_data {
    my ($self, $record_ids) = @_;

    my $bib_data = [];
    my $db_data = $self->get_bib_db_data($record_ids);

    for my $db_rec (@$db_data) {
        my $marc_doc = XML::LibXML->load_xml(string => $db_rec->{marc});
        my $result = $self->xsl_sheet->transform($marc_doc);
        my $output = $stylesheet->output_as_chars($result);

        my @fields = split(/\n/, $output);
        for my $field (@fields) {
            my @parts = split(/ /, $field);
            my $field_type = $parts[0];

            if ($field_type eq 'search') {
            } elsif ($field_type eq 'facet') {
            } elsif ($field_type eq 'filter') {
            } elsif ($field_type eq 'sorter') {
            }
        }
    }
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

