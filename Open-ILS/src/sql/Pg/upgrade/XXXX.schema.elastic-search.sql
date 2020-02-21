
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
    label           TEXT NOT NULL,
    field_class     TEXT REFERENCES config.metabib_class(name) ON DELETE CASCADE,
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
VALUES 
    ('author', 'conference', 'Conference Author', 
        TRUE, TRUE, FALSE, FALSE, 1),
    ('author', 'corporate', 'Corporate Author', 
        TRUE, TRUE, FALSE, FALSE, 1),
    ('author', 'personal', 'Personal Author', 
        TRUE, TRUE, FALSE, FALSE, 1),
    ('series', 'seriestitle', 'Series Title', 
        TRUE, TRUE, FALSE, FALSE, 1),
    ('subject', 'geographic', 'Geographic Subject', 
        TRUE, TRUE, FALSE, FALSE, 1),
    ('subject', 'name', 'Name Subject', 
        TRUE, TRUE, FALSE, FALSE, 1),
    ('subject', 'topic', 'Topic Subject', 
        TRUE, TRUE, FALSE, FALSE, 1),
    ('title', 'seriestitle', 'Series Title', 
        TRUE, TRUE, FALSE, FALSE, 1),
    ('author', 'added_personal', 'Additional Personal Author', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('author', 'conference_series', 'Personal Conference Author', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('author', 'corporate_series', 'Personal Corporate Author', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('author', 'meeting', 'Meeting Author', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('author', 'personal_series', 'Personal Series Author', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('author', 'responsibility', 'Author (Statement of Responsibility)', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('identifier', 'bibcn', 'Bib Call Number', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('identifier', 'isbn', 'ISBN', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('identifier', 'issn', 'ISSN', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('identifier', 'lccn', 'LCCN', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('identifier', 'sudoc', 'SuDoc Number', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('identifier', 'tech_number', 'Technical Report Number', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('identifier', 'upc', 'UPC', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('keyword', 'keyword', 'General Keyword', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('keyword', 'publisher', 'Publisher', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('subject', 'corpname', 'Corporate Name Subject', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('subject', 'genre', 'Genre', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('subject', 'meeting', 'Conference Subject', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('subject', 'uniftitle', 'Title Subject', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('title', 'abbreviated', 'Abbreviated Title', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('title', 'added', 'Additional Title', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('title', 'alternative', 'Alternate Title', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('title', 'former', 'Former Title', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('title', 'magazine', 'Magazine Title', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('title', 'maintitle', 'Main Title', 
        TRUE, FALSE, FALSE, FALSE, 10),
    ('title', 'previous', 'Previous Title', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('title', 'proper', 'Title Proper', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('title', 'succeeding', 'Succeeding Title', 
        TRUE, FALSE, FALSE, FALSE, 1),
    ('title', 'uniform', 'Uniform Title', 
        TRUE, FALSE, FALSE, FALSE, 1),
    (NULL, 'audience', 'Audience', 
        FALSE, FALSE, TRUE, FALSE, 1),
    (NULL, 'bib_level', 'Bib Level', 
        FALSE, FALSE, TRUE, FALSE, 1),
    (NULL, 'date1', 'Date1', 
        FALSE, FALSE, TRUE, FALSE, 1),
    (NULL, 'date2', 'Date2', 
        FALSE, FALSE, TRUE, FALSE, 1),
    (NULL, 'item_form', 'Item Form', 
        FALSE, FALSE, TRUE, FALSE, 1),
    (NULL, 'item_lang', 'Language', 
        FALSE, FALSE, TRUE, FALSE, 1),
    (NULL, 'item_type', 'Item Type', 
        FALSE, FALSE, TRUE, FALSE, 1),
    (NULL, 'lit_form', 'Lit Form', 
        FALSE, FALSE, TRUE, FALSE, 1),
    (NULL, 'search_format', 'Search Format', 
        FALSE, FALSE, TRUE, FALSE, 1),
    (NULL, 'sr_format', 'Sound Recording Format', 
        FALSE, FALSE, TRUE, FALSE, 1),
    (NULL, 'vr_format', 'Video Recording Format', 
        FALSE, FALSE, TRUE, FALSE, 1),
    (NULL, 'author', 'Author Sort', 
        FALSE, FALSE, FALSE, TRUE, 1),
    (NULL, 'pubdate', 'Pubdate Sort', 
        FALSE, FALSE, FALSE, TRUE, 1),
    (NULL, 'title', 'Title Sort', 
        FALSE, FALSE, FALSE, TRUE, 1)
;

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
