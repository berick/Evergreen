
DROP SCHEMA IF EXISTS elastic CASCADE;

BEGIN;

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


INSERT INTO config.global_flag (name, enabled, label, value)
VALUES (
    'elastic.bib_search.enabled', FALSE,
    'Elasticsearch Enable Bib Searching', NULL
);

INSERT INTO elastic.cluster (code, label) VALUES ('main', 'Main Cluster');

INSERT INTO elastic.node (label, host, proto, port, active, cluster)
    VALUES ('Localhost', 'localhost', 'http', 9200, TRUE, 'main');

COMMIT;

