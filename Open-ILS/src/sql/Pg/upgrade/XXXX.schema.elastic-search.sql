
DROP SCHEMA IF EXISTS elastic CASCADE;

BEGIN;

INSERT INTO config.global_flag (name, enabled, label, value) 
VALUES (
    'elastic.bib_search.enabled', FALSE,
    'Elasticsearch Enable Bib Searching', NULL
), (
    'elastic.bib_search.transform_file', FALSE,
    'Elasticsearch Bib Transform File [Relative to xsl directory]',
    'elastic-bib-transform.xsl'
);

CREATE SCHEMA elastic;

CREATE TABLE elastic.cluster (
    code    TEXT NOT NULL DEFAULT 'main' PRIMARY KEY,
    label   TEXT NOT NULL
);

CREATE TABLE elastic.node (
    id      SERIAL  PRIMARY KEY,
    label   TEXT    NOT NULL UNIQUE,
    host    TEXT    NOT NULL,
    proto   TEXT    NOT NULL,
    port    INTEGER NOT NULL,
    path    TEXT    NOT NULL DEFAULT '/',
    active  BOOLEAN NOT NULL DEFAULT FALSE,
    cluster TEXT    NOT NULL 
            REFERENCES elastic.cluster (code) ON DELETE CASCADE,
    CONSTRAINT node_once UNIQUE (host, port, path, cluster)
);

CREATE TABLE elastic.index (
    id            SERIAL  PRIMARY KEY,
    name          TEXT    NOT NULL,
    index_class   TEXT    NOT NULL,
    cluster       TEXT    NOT NULL 
                  REFERENCES elastic.cluster (code) ON DELETE CASCADE,
    active        BOOLEAN NOT NULL DEFAULT FALSE,
    num_shards    INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT    active_index_once_per_cluster UNIQUE (active, index_class, cluster),
    CONSTRAINT    valid_index_class CHECK (index_class IN ('bib-search'))
);

-- XXX consider storing the xsl chunk directly on the field,
-- then stitching the chunks together for indexing.  This would 
-- require a search chunk and a facet chunk.
CREATE TABLE elastic.bib_field (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    field_class     TEXT REFERENCES config.metabib_class(name) ON DELETE CASCADE,
    label           TEXT NOT NULL UNIQUE,
    search_field    BOOLEAN NOT NULL DEFAULT FALSE,
    facet_field     BOOLEAN NOT NULL DEFAULT FALSE,
    filter          BOOLEAN NOT NULL DEFAULT FALSE,
    sorter          BOOLEAN NOT NULL DEFAULT FALSE,
    weight          INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT      name_class_once_per_field UNIQUE (name, field_class)
);

CREATE OR REPLACE VIEW elastic.bib_last_mod_date AS
    /**
     * Last update date for each bib, which is taken from most recent
     * edit for either the bib, a linked call number, or a linked copy.
     * If no call numbers are linked, uses the bib edit date only.
     * Includes deleted data since it can impact indexing.
     */
    WITH mod_dates AS (
        SELECT bre.id, 
            bre.edit_date, 
            MAX(COALESCE(acn.edit_date, '1901-01-01')) AS max_call_number_edit_date, 
            MAX(COALESCE(acp.edit_date, '1901-01-01')) AS max_copy_edit_date
        FROM biblio.record_entry bre
            LEFT JOIN asset.call_number acn ON (acn.record = bre.id)
            LEFT JOIN asset.copy acp ON (acp.call_number = acn.id)
        GROUP BY 1, 2
    ) SELECT dates.id, 
        GREATEST(dates.edit_date, 
            GREATEST(dates.max_call_number_edit_date, dates.max_copy_edit_date)
        ) AS last_mod_date
    FROM mod_dates dates;


/* SEED DATA ------------------------------------------------------------ */

INSERT INTO elastic.cluster (code, label) 
    VALUES ('main', 'Main Cluster');

INSERT INTO elastic.node (label, host, proto, port, active, cluster)
    VALUES ('Localhost', 'localhost', 'http', 9200, TRUE, 'main');

INSERT INTO elastic.bib_field 
    (field_class, name, label, search_field, facet_field, filter, sorter, weight)
VALUES (
    'author',   'conference', '', FALSE, TRUE, FALSE, FALSE, 1),
    'author',   'corporate', '', FALSE, TRUE, FALSE, FALSE, 1),
    'author',   'personal', '', FALSE, TRUE, FALSE, FALSE, 1),
    'series',   'seriestitle', '', FALSE, TRUE, FALSE, FALSE, 1),
    'subject',  'geographic', '', FALSE, TRUE, FALSE, FALSE, 1),
    'subject',  'name', '', FALSE, TRUE, FALSE, FALSE, 1),
    'subject',  'topic', '', FALSE, TRUE, FALSE, FALSE, 1),
    'title',    'seriestitle', '', FALSE, TRUE, FALSE, FALSE, 1),

filter _ audience _
filter _ bib_level _
filter _ date1 _
filter _ date2 _
filter _ item_form _
filter _ item_lang _
filter _ item_type _
filter _ lit_form _
filter _ search_format _
filter _ sr_format _
filter _ vr_format _
search author added_personal 
search author conference 
search author conference_series 
search author corporate 
search author corporate_series 
search author meeting 
search author personal 
search author personal_series 
search author responsibility 
search identifier bibcn 
search identifier isbn 
search identifier issn 
search identifier lccn 
search identifier match_isbn 
search identifier sudoc 
search identifier tech_number 
search identifier upc 
search keyword keyword _
search keyword publisher 
search series seriestitle 
search subject corpname 
search subject genre 
search subject geographic 
search subject meeting 
search subject name 
search subject topic 
search subject uniftitle 
search title abbreviated 
search title added 
search title alternative 
search title former 
search title magazine 
search title maintitle 10
search title previous 
search title proper 
search title seriestitle 
search title succeeding 
search title uniform 
sorter _ author _ 
sorter _ pubdate _ 
sorter _ title _ 
COMMIT;

/* UNDO

DROP SCHEMA IF EXISTS elastic CASCADE;

DELETE FROM config.global_flag WHERE name ~ 'elastic.*';

*/

/*

-- Bill's elastic VM for testing.
UPDATE elastic.node 
    SET host = 'elastic.gamma', port = 80, path = '/elastic/node1' 
    WHERE id = 1;

*/
