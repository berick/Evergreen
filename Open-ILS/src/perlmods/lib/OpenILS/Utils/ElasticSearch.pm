package OpenILS::Utils::ElasticSearch;
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
use DateTime;
use DBI;
use XML::LibXML;
use XML::LibXSLT;
use Data::Dumper;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Utils::DateTime qw/:datetime/;
#use OpenILS::Utils::CStoreEditor qw/:funcs/;
use Search::Elasticsearch;

my $date_parser = DateTime::Format::ISO8601->new;
my $db_handle;

sub new {
    my ($class, %args) = @_;
    my $self = bless(
        {   clusters => {},
            config_file => $args{config_file},
            xsl_transforms => {},
            xml_namespaces => {}
        }, $class
    );
    $self->read_config;
    return $self;
}

sub get_db_conn {
	my ($self) = @_;
    return $db_handle if $db_handle;

    my $settings = $self->{config}->{'evergreen-database'};
    my $db_name = $settings->{name};
    my $db_host = $settings->{host};
    my $db_port = $settings->{port};
    my $db_user = $settings->{user};
    my $db_pass = $settings->{pass};

    my $dsn = "dbi:Pg:db=$db_name;host=$db_host;port=$db_port";
    $logger->debug("ES connecting to DB $dsn");

    $db_handle = DBI->connect(
        "$dsn;options='--statement-timeout=0'",
        $db_user, $db_pass, {
            RaiseError => 1,
            PrintError => 0,
            AutoCommit => 1,
            pg_expand_array => 0,
            pg_enable_utf8 => 1
        }
    ) or $logger->error(
        "ES Connection to database failed: $DBI::err : $DBI::errstr", 1);

    return $db_handle;
}

sub read_config {
    my $self = shift;

    open(CONFIG_FILE, $self->{config_file})
        or die "Cannot open elastic config " .$self->{config_file}. ": $!\n";

    my $json = join('', <CONFIG_FILE>);

    $self->{config} = OpenSRF::Utils::JSON->JSON2perl($json);

    close(CONFIG_FILE);
}

sub connect {
    my ($self, $cluster) = @_;

    my $nodes = $self->{config}{clusters}{$cluster}{nodes};

    $logger->info("ES connecting to nodes @$nodes");

    $self->{clusters}{$cluster} = {
        es => Search::Elasticsearch->new(nodes => $nodes)
    };
}

sub es {
    my ($self, $cluster) = @_;
    return $self->{clusters}{$cluster}{es};
}

sub delete_index {
    my ($self, $cluster, $index) = @_;

    if ($self->es($cluster)->indices->exists(index => $index)) {
        $logger->info("ES deleting index '$index' on cluster '$cluster'");
        $self->es($cluster)->indices->delete(index => $index);
    } else {
        $logger->warn("ES index '$index' does not exist");
    }
}

sub create_index {
    my ($self, $cluster, $index) = @_;

    if ($self->es($cluster)->indices->exists(index => $index)) {
        $logger->warn("ES index '$index' already exists");
        return;
    }

    $logger->info("ES creating index '$index' on cluster '$cluster'");

    my $config = $self->{config};

    my $es = $self->es($cluster);
    my $mappings = $config->{indexes}{$index}{'base-properties'};

    # TODO: a dynamic property may live in multiple indexes
    my @dynamics = grep {$_->{index} eq $index}
        @{$config->{'dynamic-properties'}};

    # Add an index definition for each dynamic field.
    # Add copy_to for field_class-level combined searches.
    for my $prop (@dynamics) {
        my $field_class = $prop->{field_class};
        my $field_name = "$field_class|" . $prop->{name};

        # Clone the class-level index definition (e.g. title) to
        # use as the source of the field-specific index.
        my $def = clone($config->{indexes}{$index}{'base-properties'}{$field_class});

        # Copy data for all fields to their parent class to
        # support group-level searches (e.g. title search)
        $def->{copy_to} = $field_class;
        $mappings->{$field_name} = $def;
    }

    my $settings = $config->{indexes}{$index}{settings};
    $settings->{number_of_replicas} =
        scalar(@{$config->{clusters}{$cluster}{nodes}});

    my $doc_type = $config->{indexes}{$index}{'document-type'};

    my $conf = {
        index => $index,
        body => {
            settings => $settings,
            mappings => {$doc_type => {properties => $mappings}}
        }
    };

    # Send the index definition to Elastic
    eval { $self->es($cluster)->indices->create($conf) };

    if ($@) {
        my $msg =
            "ES failed to create index cluster=$cluster index=$index error=$@";
        $logger->error($msg);
        die "$msg\n";
    }
}

sub populate_index {
    my ($self, $cluster, $index) = @_;

    if ($index eq 'bib-search') {
        return $self->populate_bib_search_index($cluster, $index);
    }
}

sub populate_bib_search_index {
    my ($self, $cluster, $index) = @_;

    $self->load_transforms($index);

    my $index_count = 0;
    my $total_indexed = 0;
    my $state = {last_bib_id => 0};

    do {
        $index_count =
            $self->populate_bib_search_index_page($cluster, $index, $state);
        $total_indexed += $index_count;
        $logger->info("ES indexed $total_indexed bib records");

    } while ($index_count > 0);

    $logger->info("ES bib indexing complete with $total_indexed records");
}

# TODO holdings
# TODO partial re-index
sub populate_bib_search_index_page {
    my ($self, $cluster, $index, $state) = @_;

    my $index_count = 0;
    my $last_id = $state->{last_bib_id};
    my $doc_type = $self->{config}->{indexes}{$index}{'document-type'};
    my $bib_data = $self->get_db_conn()->selectall_arrayref(<<SQL, {Slice => {}});
SELECT bre.id, bre.marc, bre.create_date, bre.edit_date, bre.source
FROM biblio.record_entry bre
WHERE (
    NOT bre.deleted
    AND bre.active
    AND bre.id > $last_id
)
ORDER BY bre.edit_date ASC, bre.id ASC
LIMIT 1000
SQL

    my $bib_ids = [ map {$_->{id}} @$bib_data ];

    my $holdings = $self->load_holdings($index, $bib_ids);

    for my $bib (@$bib_data) {
        my $bib_id = $bib->{id};

        my $marc_doc = XML::LibXML->new->parse_string($bib->{marc});
        my $body = $self->extract_bib_values($index, $marc_doc);

        $body->{holdings} = $holdings->{$bib_id} || [];
        $body->{source} = $bib->{source};

        for my $field (q/create_date edit_date/) {
            next unless $bib->{$field};
            # ES wants ISO dates with the 'T' separator
            (my $val = $bib->{$field}) =~ s/ /T/g;
            $body->{$field} = $val;
        }

        $self->add_to_elastic($cluster, $index, $doc_type, $bib_id, $body);

        $state->{last_bib_id} = $bib_id;
        $index_count++;
    }

    return $index_count;
}

sub load_transforms {
    my ($self, $index) = @_;

    my @dynamics = grep {$_->{index} eq $index}
        @{$self->{config}{'dynamic-properties'}};

    for my $prop (@dynamics) {
        my $format = $prop->{format};
        next if $self->{xsl_transforms}{$format};

        $logger->info("ES loading info for document type $format");

        my $xform = $self->get_db_conn()->selectrow_hashref(
            "SELECT * FROM config.xml_transform WHERE name = '$format'");

        $self->{xml_namespaces}{$format} = {
            prefix => $xform->{prefix},
            uri => $xform->{namespace_uri}
        };

        if ($format eq 'marcxml') {
            # No transform needed for MARCXML.  Indicate we've seen
            # it and move on.
            $self->{xsl_transforms}{$format} = {};
            next;
        }

        $logger->info("ES parsing stylesheet for $format");
        my $xsl_doc = XML::LibXML->new->parse_string($xform->{xslt});
        my $stylesheet = XML::LibXSLT->new->parse_stylesheet($xsl_doc);
        $self->{xsl_transforms}{$format} = $stylesheet;
    }
}

sub extract_bib_values {
    my ($self, $index, $marc_doc) = @_;
    my $values = {};

    my @dynamics = grep {$_->{index} eq $index}
        @{$self->{config}{'dynamic-properties'}};

    # various formats of the current MARC record (mods, etc.)
    my %xform_docs;

    for my $prop (@dynamics) {

        my $format = $prop->{format};
        my $xform_doc = $marc_doc;
        my $field_name = $prop->{field_class} .'|' . $prop->{name};

        if ($format ne 'marcxml') { # no transform required for MARCXML

            if (!$xform_docs{$format}) {
                # No document exists for the current format.
                # Perform the transform here.
                $xform_docs{$format} = 
                    $self->{xsl_transforms}{$format}->transform($marc_doc);
            }

            $xform_doc = $xform_docs{$format};
        }

        # Apply the field-specific xpath to our transformed document

        my $ns = $self->{xml_namespaces}{$format};
        my $root = $xform_doc->documentElement;
        $root->setNamespace($ns->{uri}, $ns->{prefix}, 1);

        my @nodes = $root->findnodes($prop->{xpath});

        if (@nodes) {
            if (@nodes == 1) {
                $values->{$field_name} = $nodes[0]->textContent;
            } else {
                $values->{$field_name} = [ map { $_->textContent } @nodes ]; 
            }
        } else {
            # Some XPATH returns nodes, some (e.g. substring()) returns 
            # string values instead of nodes.
            $values->{$field_name} = $root->findvalue($prop->{xpath}) || undef;
        }

        $logger->internal(
            "ES $field_name = " . Dumper($values->{$field_name}));
    }

    $logger->debug("ES extracted record values: " . Dumper($values));

    return $values;
}

# Load holdings summary blobs for requested bibs
sub load_holdings {
    my ($self, $index, $bib_ids) = @_;

    my $bib_ids_str = join(',', @$bib_ids);

    my $copy_data = $self->get_db_conn()->selectall_arrayref(<<SQL, {Slice => {}});
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

sub add_to_elastic {
    my ($self, $cluster, $index, $doc_type, $id, $body) = @_;

    my $result = $self->es($cluster)->index(
        index => $index,
        type => $doc_type,
        id => $id,
        body => $body
    );

    $logger->debug("ES index command returned $result");
}


1;


