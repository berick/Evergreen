
BEGIN;

CREATE TABLE config.elastic_cluster (
    id      SERIAL  PRIMARY KEY,
    name    TEXT NOT NULL
);

CREATE TABLE config.elastic_server (
    id      SERIAL  PRIMARY KEY,
    label   TEXT    NOT NULL UNIQUE,
    host    TEXT    NOT NULL,
    proto   TEXT    NOT NULL,
    port    INTEGER NOT NULL,
    active  BOOLEAN NOT NULL DEFAULT FALSE,
    cluster INTEGER NOT NULL 
            REFERENCES config.elastic_cluster (id) ON DELETE CASCADE
);

CREATE TABLE config.elastic_index (
    id            SERIAL  PRIMARY KEY,
    name          TEXT    NOT NULL UNIQUE,
    purpose       TEXT    NOT NULL DEFAULT 'bib-search',
    num_shards    INTEGER NOT NULL DEFAULT 5,
    active        BOOLEAN NOT NULL DEFAULT FALSE,
    cluster       INTEGER NOT NULL 
                  REFERENCES config.elastic_cluster (id) ON DELETE CASCADE,
    CONSTRAINT    valid_index_purpose CHECK (purpose IN ('bib-search'))
);

CREATE TABLE config.elastic_marc_field (
    id              SERIAL  PRIMARY KEY,
    index           INTEGER NOT NULL 
                    REFERENCES config.elastic_index (id) ON DELETE CASCADE,
    active          BOOLEAN NOT NULL DEFAULT FALSE,
    field_class     TEXT    NOT NULL REFERENCES config.metabib_class (name),
    label           TEXT    NOT NULL,
    name            TEXT    NOT NULL,
    datatype        TEXT    NOT NULL DEFAULT 'text',
    weight          INTEGER NOT NULL DEFAULT 1,
    format          TEXT    NOT NULL REFERENCES config.xml_transform (name),
    xpath           TEXT    NOT NULL,
    search_field    BOOLEAN NOT NULL DEFAULT FALSE,
    facet_field     BOOLEAN NOT NULL DEFAULT FALSE,
    sort_field      BOOLEAN NOT NULL DEFAULT FALSE,
    multi_value     BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT      valid_datatype CHECK (datatype IN 
        ('text', 'keyword', 'date', 'long', 'double', 'boolean', 'ip'))
);

/* SEED DATA ------------------------------------------------------------ */


INSERT INTO config.elastic_cluster (name) VALUES ('main');

INSERT INTO config.elastic_server 
    (label, host, proto, port, active, cluster)
VALUES ('localhost', 'localhost', 'http', 9200, TRUE,
    (SELECT id FROM config.elastic_cluster WHERE name = 'main'));

INSERT INTO config.elastic_index (name, purpose, active, cluster)
VALUES ('Bib Search', 'bib-search', TRUE, 
    (SELECT id FROM config.elastic_cluster WHERE name = 'main'));

-- Start with indexes that match search/facet fields in config.metabib_field

INSERT INTO config.elastic_marc_field 
    (index, active, field_class, label, name, weight, format,
        xpath, search_field, facet_field, datatype)
SELECT 
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE,
    cmf.field_class,
    cmf.label,
    cmf.name, 
    cmf.weight,
    cmf.format,
    cmf.xpath || COALESCE(cmf.facet_xpath, COALESCE(cmf.display_xpath, '')),
    cmf.search_field,
    cmf.facet_field,
    'text'
FROM config.metabib_field cmf
WHERE cmf.xpath IS NOT NULL AND (cmf.search_field OR cmf.facet_field);

-- Add additional indexes for other search-y / filter-y stuff

INSERT INTO config.elastic_marc_field 
    (index, active, search_field, facet_field, 
        field_class, label, name, format, datatype, xpath)
VALUES ( 
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE, TRUE, TRUE, 
    'identifier', 'Language', 'item_lang', 'marcxml', 'keyword',
    $$substring(//marc:controlfield[@tag='008']/text(), '36', '3')$$
), (
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE, TRUE, TRUE, 
    'identifier', 'Item Form', 'item_form', 'marcxml', 'keyword',
    $$substring(//marc:controlfield[@tag='008']/text(), '24', '1')$$
), (
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE, TRUE, TRUE, 
    'identifier', 'Audience', 'audience', 'marcxml', 'keyword',
    $$substring(//marc:controlfield[@tag='008']/text(), '23', '1')$$
), (
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE, TRUE, TRUE, 
    'identifier', 'Literary Form', 'lit_form', 'marcxml', 'keyword',
    $$substring(//marc:controlfield[@tag='008']/text(), '34', '1')$$
), (
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE, TRUE, TRUE, 
    'identifier', 'Publication Date', 'pub_date', 'mods32', 'long',
    $$//mods32:mods/mods32:originInfo/mods32:dateIssued[@encoding='marc']$$
), (
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE, FALSE, TRUE, 
    'title', 'Title Sort', 'sort', 'mods32', 'keyword',
    $$(//mods32:mods/mods32:titleInfo[mods32:nonSort]/mods32:title|//mods32:mods/mods32:titleNonfiling[mods32:title and not (@type)])[1]$$
), (
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE, FALSE, TRUE, 
    'author', 'Author Sort', 'sort', 'mods32', 'keyword',
    $$//mods32:mods/mods32:name[mods32:role/mods32:roleTerm[text()='creator']][1]$$
);

-- TODO ADD MORE FIELDS

-- avoid full-text indexing on identifier fields
UPDATE config.elastic_marc_field SET datatype = 'keyword' 
WHERE field_class = 'identifier';

COMMIT;

/* UNDO

DROP TABLE config.elastic_marc_field;
DROP TABLE config.elastic_index;
DROP TABLE config.elastic_server;
DROP TABLE config.elastic_cluster;

*/

