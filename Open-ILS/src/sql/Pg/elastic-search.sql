
BEGIN;

CREATE TABLE config.elastic_cluster (
    id      SERIAL  PRIMARY KEY,
    label   TEXT NOT NULL
);

CREATE TABLE config.elastic_server (
    id      SERIAL  PRIMARY KEY,
    label   TEXT    NOT NULL UNIQUE,
    host    TEXT    NOT NULL,
    proto   TEXT    NOT NULL,
    port    INTEGER NOT NULL,
    active  BOOLEAN NOT NULL DEFAULT FALSE,
    cluster INTEGER NOT NULL REFERENCES config.elastic_cluster (id)
);

CREATE TABLE config.elastic_index (
    id      SERIAL  PRIMARY KEY,
    name    TEXT    NOT NULL UNIQUE,
    purpose TEXT    NOT NULL DEFAULT 'bib-search', -- constraint?
    active  BOOLEAN NOT NULL DEFAULT FALSE,
    cluster INTEGER NOT NULL REFERENCES config.elastic_cluster (id)
);

CREATE TABLE config.elastic_field (
    id              SERIAL  PRIMARY KEY,
    elastic_index   INTEGER NOT NULL REFERENCES config.elastic_index (id),
    active          BOOLEAN NOT NULL DEFAULT FALSE,
    field_class     TEXT    NOT NULL REFERENCES config.metabib_class (name),
    label           TEXT    NOT NULL,
    name            TEXT    NOT NULL,
    weight          INTEGER NOT NULL DEFAULT 1,
    format          TEXT    NOT NULL REFERENCES config.xml_transform (name),
    xpath           TEXT    NOT NULL,
    search_field    BOOLEAN NOT NULL DEFAULT FALSE,
    facet_field     BOOLEAN NOT NULL DEFAULT FALSE,
    sort_field      BOOLEAN NOT NULL DEFAULT FALSE,
    multi_value     BOOLEAN NOT NULL DEFAULT FALSE
);

/* SEED DATA ------------------------------------------------------------ */


INSERT INTO config.elastic_cluster (label) VALUES ('Main');

INSERT INTO config.elastic_server 
    (label, host, proto, port, active, cluster)
VALUES ('localhost', 'localhost', 'http', 9200, TRUE,
    (SELECT id FROM config.elastic_cluster WHERE label = 'Main'));

INSERT INTO config.elastic_index (name, purpose, active, cluster)
VALUES ('Bib Search', 'bib-search', TRUE, 
    (SELECT id FROM config.elastic_cluster WHERE label = 'Main'));

-- Start with indexes that match search/facet fields in config.metabib_field

INSERT INTO config.elastic_field 
    (elastic_index, active, field_class, label, name, weight, format,
        xpath, search_field, facet_field)
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
    cmf.facet_field
FROM config.metabib_field cmf
WHERE cmf.xpath IS NOT NULL AND (cmf.search_field OR cmf.facet_field);

-- Add additional indexes for other search-y / filter-y stuff

INSERT INTO config.elastic_field 
    (elastic_index, active, field_class, label, name, format,
        search_field, facet_field, xpath)
VALUES ( 
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE,
    'identifier', 'Language', 'item_lang', 'marcxml', TRUE, TRUE,
    $$substring(//marc:controlfield[@tag='008']/text(), '36', '38')$$
), (
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE,
    'identifier', 'Item Form', 'item_form', 'marcxml', TRUE, TRUE,
    $$substring(//marc:controlfield[@tag='008']/text(), '24', '25')$$
), (
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE,
    'identifier', 'Audience', 'audience', 'marcxml', TRUE, TRUE,
    $$substring(//marc:controlfield[@tag='008']/text(), '23', '24')$$
), (
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE,
    'identifier', 'Literary Form', 'lit_form', 'marcxml', TRUE, TRUE,
    $$substring(//marc:controlfield[@tag='008']/text(), '34', '35')$$
), (
    (SELECT id FROM config.elastic_index WHERE purpose = 'bib-search'),
    TRUE,
    'identifier', 'Publication Date', 'pub_date', 'mods32', TRUE, TRUE,
    $$//mods32:mods/mods32:originInfo/mods32:dateIssued[@encoding='marc']$$
);

-- TODO ADD MORE FIELDS

COMMIT;

/* UNDO

DROP TABLE config.elastic_field;
DROP TABLE config.elastic_index;
DROP TABLE config.elastic_server;
DROP TABLE config.elastic_cluster;

*/
