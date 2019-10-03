
DROP SCHEMA IF EXISTS elastic CASCADE;

BEGIN;

ALTER TABLE config.record_attr_definition
    ADD COLUMN elastic_field BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE config.metabib_field
    ADD COLUMN elastic_field BOOLEAN NOT NULL DEFAULT FALSE;

-- Provide a sweeping set of default elastic fields.
-- Likely this set of fields can be trimmed significantly for most sites,
-- since many of these fields will never be searched from the catalog.
-- Reducing the number of elastic_field's will improve indexing time, 
-- search time, and reduce Elastic disk space requirements.
UPDATE config.record_attr_definition 
    SET elastic_field = TRUE WHERE name NOT LIKE 'marc21_%';

UPDATE config.metabib_field 
    SET elastic_field = TRUE WHERE search_field OR facet_field;

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
    code          TEXT    NOT NULL, -- e.g. 'bib-search'
    cluster       TEXT    NOT NULL 
                  REFERENCES elastic.cluster (code) ON DELETE CASCADE,
    active        BOOLEAN NOT NULL DEFAULT FALSE,
    num_shards    INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT    index_type_once_per_cluster UNIQUE (code, cluster)
);

CREATE OR REPLACE VIEW elastic.bib_field AS
    SELECT fields.* FROM (
        SELECT 
            NULL::INT AS metabib_field,
            crad.name,
            crad.label,
            NULL AS search_group,
            crad.sorter,
            FALSE AS search_field,
            FALSE AS facet_field,
            1 AS weight
        FROM config.record_attr_definition crad
        WHERE crad.elastic_field
        UNION
        SELECT 
            cmf.id AS metabib_field,
            cmf.name,
            cmf.label,
            cmf.field_class AS search_group,
            FALSE AS sorter,
            -- always treat identifier fields as non-search fields.
            (cmf.field_class <> 'identifier' AND cmf.search_field) AS search_field,
            cmf.facet_field,
            cmf.weight
        FROM config.metabib_field cmf 
        WHERE cmf.elastic_field
    ) fields;

-- Note this could be done with a view, but pushing the bib ID
-- filter down to the bottom of the query makes it a lot faster.
CREATE OR REPLACE FUNCTION elastic.bib_record_properties(bre_id BIGINT) 
    RETURNS TABLE (
        search_group TEXT,
        name TEXT,
        source BIGINT,
        value TEXT
    )
    AS $FUNK$
DECLARE
BEGIN
    RETURN QUERY EXECUTE $$
        SELECT DISTINCT record.* FROM (

            -- record sorter values
            SELECT 
                NULL::TEXT AS search_group, 
                crad.name, 
                mrs.source, 
                mrs.value
            FROM metabib.record_sorter mrs
            JOIN config.record_attr_definition crad ON (crad.name = mrs.attr)
            WHERE mrs.source = $$ || QUOTE_LITERAL(bre_id) || $$
                AND crad.elastic_field
            UNION

            -- record attributes
            SELECT 
                NULL::TEXT AS search_group, 
                crad.name, 
                mraf.id AS source, 
                mraf.value
            FROM metabib.record_attr_flat mraf
            JOIN config.record_attr_definition crad ON (crad.name = mraf.attr)
            WHERE mraf.id = $$ || QUOTE_LITERAL(bre_id) || $$
                AND crad.elastic_field
            UNION

            -- metabib field search/facet entries
            SELECT 
                cmf.field_class AS search_group, 
                cmf.name, 
                compiled.source, 
                -- Index individual values instead of string-joined values
                -- so they may be treated individually.  This is useful,
                -- for example, when aggregating on subjects.
                CASE WHEN cmf.joiner IS NOT NULL THEN
                    REGEXP_SPLIT_TO_TABLE(compiled.value, cmf.joiner)
                ELSE
                    compiled.value
                END AS value
            FROM (
                -- Extract the values from the source MARC record instead
                -- of pulling them from the metabib.*_field_entry tables.
                -- This allows use of Elastic without requiring search/facet
                -- fields be ingested in Evergreen (since that data will no
                -- longer be used by EG).
                SELECT * FROM biblio.extract_metabib_field_entry(
                    $$ || QUOTE_LITERAL(bre_id) || $$, ' ', '{facet,search}',
                    (SELECT ARRAY_AGG(id) 
                        FROM config.metabib_field WHERE elastic_field)
                )
            ) compiled
            JOIN config.metabib_field cmf ON (cmf.id = compiled.field)
        ) record
    $$;
END $FUNK$ LANGUAGE PLPGSQL;

/* give me bibs I should upate */

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

INSERT INTO elastic.index (code, active, cluster)
    VALUES ('bib-search', TRUE, 'main');

COMMIT;

/* UNDO

DROP SCHEMA IF EXISTS elastic CASCADE;

ALTER TABLE config.record_attr_definition DROP COLUMN elastic_field;

ALTER TABLE config.metabib_field DROP COLUMN elastic_field;

*/

/*
-- Sample narrower set of elastic fields to avoid duplication and 
-- indexing data that will likely never be searched.

UPDATE config.metabib_field SET elastic_field = FALSE
WHERE 
    (field_class = 'keyword' AND name <> 'keyword') OR
    (field_class = 'subject' AND name = 'complete') OR
    (field_class = 'author'  AND name = 'first_author')
;

UPDATE config.record_attr_definition SET elastic_field = FALSE
WHERE name NOT IN (
    'authorsort',
    'date1',
    'date2',
    'bib_level',
    'icon_format',
    'item_form',
    'item_lang',
    'item_type',
    'lit_form',
    'search_format',
    'titlesort',
    'sr_format',
    'vr_format'
);

