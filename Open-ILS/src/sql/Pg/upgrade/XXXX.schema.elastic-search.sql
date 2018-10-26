
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
    active  BOOLEAN NOT NULL DEFAULT FALSE,
    cluster TEXT    NOT NULL 
            REFERENCES elastic.cluster (code) ON DELETE CASCADE,
    CONSTRAINT node_once UNIQUE (host, port)
);

CREATE TABLE elastic.index (
    id            SERIAL  PRIMARY KEY,
    code          TEXT    NOT NULL DEFAULT 'bib-search',
    cluster       TEXT    NOT NULL 
                  REFERENCES elastic.cluster (code) ON DELETE CASCADE,
    active        BOOLEAN NOT NULL DEFAULT FALSE,
    num_shards    INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT    valid_index_code CHECK (code IN ('bib-search')),
    CONSTRAINT    index_type_once_per_cluster UNIQUE (code, cluster)
);

CREATE OR REPLACE VIEW elastic.bib_index_properties AS
    SELECT fields.* FROM (
        SELECT 
            NULL::INT AS metabib_field,
            crad.name,
            NULL AS search_group,
            crad.sorter,
            crad.multi,
            FALSE AS search_field,
            FALSE AS facet_field,
            1 AS weight
        FROM config.record_attr_definition crad
        WHERE crad.name NOT LIKE '%_ind_%'
        UNION
        SELECT 
            cmf.id AS metabib_field,
            cmf.name,
            cmf.field_class AS search_group,
            FALSE AS sorter,
            TRUE AS multi,
            -- always treat identifier fields as non-search fields.
            (cmf.field_class <> 'identifier' AND cmf.search_field) AS search_field,
            cmf.facet_field,
            cmf.weight
        FROM config.metabib_field cmf
        WHERE cmf.search_field OR cmf.facet_field
    ) fields;

-- Note this could be done with a view, but pushing the bib ID
-- filter down to the base filter makes it a lot faster.
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
            UNION

            -- metabib field entries
            SELECT 
                cmf.field_class AS search_group, 
                cmf.name, 
                mfe.source, 
                -- Index individual values instead of string-joined values
                -- so they may be treated individually.  This is useful,
                -- for example, when aggregating on individual subjects.
                CASE WHEN cmf.joiner IS NOT NULL THEN
                    REGEXP_SPLIT_TO_TABLE(mfe.value, cmf.joiner)
                ELSE
                    mfe.value
                END AS value
            FROM (
                SELECT * FROM metabib.title_field_entry UNION 
                SELECT * FROM metabib.author_field_entry UNION
                SELECT * FROM metabib.subject_field_entry UNION
                SELECT * FROM metabib.series_field_entry UNION
                SELECT * FROM metabib.keyword_field_entry UNION
                SELECT * FROM metabib.identifier_field_entry
            ) mfe
            JOIN config.metabib_field cmf ON (cmf.id = mfe.field)
            WHERE mfe.source = $$ || QUOTE_LITERAL(bre_id) || $$
                AND (cmf.search_field OR cmf.facet_field)
        ) record
    $$;
END $FUNK$ LANGUAGE PLPGSQL;



/* SEED DATA ------------------------------------------------------------ */

INSERT INTO elastic.cluster (code, label) VALUES ('main', 'Main Cluster');

INSERT INTO elastic.node 
    (label, host, proto, port, active, cluster)
VALUES ('Localhost', 'localhost', 'http', 9200, TRUE, 'main');

INSERT INTO elastic.index (code, active, cluster)
VALUES ('bib-search', TRUE, 'main');

COMMIT;

/* UNDO

DROP SCHEMA IF EXISTS elastic CASCADE;

*/

