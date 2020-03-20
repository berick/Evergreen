
BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

CREATE TABLE config.sip_account (
    id              SERIAL PRIMARY KEY,
    institution     TEXT NOT NULL,
    sip_username    TEXT NOT NULL,
    sip_password    BIGINT NOT NULL REFERENCES actor.passwd 
                    DEFERRABLE INITIALLY DEFERRED,
    usr             BIGINT NOT NULL REFERENCES actor.usr(id)
                    DEFERRABLE INITIALLY DEFERRED,
    workstation     INTEGER REFERENCES actor.workstation(id),
    activity_type   INTEGER REFERENCES config.usr_activity_type(id),
    av_format       TEXT -- e.g. '3m'
);

-- institution and global-level key/value setting pairs.
CREATE TABLE config.sip_setting (
    id SERIAL   PRIMARY KEY,
    institution TEXT NOT NULL, -- '*' applies to all institutions
    name        TEXT NOT NULL,
    value       JSON NOT NULL,
    CONSTRAINT  name_once_per_inst UNIQUE (institution, name)
);

-- SEED DATA

INSERT INTO actor.passwd_type (code, name, login, crypt_algo, iter_count)
    VALUES ('sip2', 'SIP2 Client Password', FALSE, 'bf', 5);

/* EXAMPLE SETTINGS
INSERT INTO config.sip_setting (institution, name, value)
VALUES 
    ('*',       'allow_sc_status_before_login', 'true'),
    ('example', 'due_date_use_sip_date_format', 'false'),
    ('example', 'patron_status_permit_loans', 'false'),
    ('example', 'patron_status_permit_all', 'false'), 
    ('example', 'msg64_hold_items_available', 'false')
);
*/

COMMIT;


