
BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

-- Collections of settings that can be linked to one or more SIP accounts.
CREATE TABLE config.sip_setting_group (
    id SERIAL   PRIMARY KEY,
    label       TEXT UNIQUE NOT NULL,
    institution TEXT NOT NULL -- Duplicates OK
);

-- Key/value setting pairs
CREATE TABLE config.sip_setting (
    id SERIAL       PRIMARY KEY,
    setting_group   INTEGER NOT NULL REFERENCES config.sip_setting_group (id)
                    ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name            TEXT NOT NULL,
    description     TEXT NOT NULL,
    value           JSON NOT NULL,
    CONSTRAINT      name_once_per_inst UNIQUE (setting_group, name)
);

CREATE TABLE config.sip_account (
    id              SERIAL PRIMARY KEY,
    enabled         BOOLEAN NOT NULL DEFAULT TRUE,
    setting_group   INTEGER NOT NULL REFERENCES config.sip_setting_group (id)
                    DEFERRABLE INITIALLY DEFERRED,
    sip_username    TEXT NOT NULL,
    sip_password    BIGINT NOT NULL REFERENCES actor.passwd 
                    DEFERRABLE INITIALLY DEFERRED,
    usr             BIGINT NOT NULL REFERENCES actor.usr(id)
                    DEFERRABLE INITIALLY DEFERRED,
    workstation     INTEGER REFERENCES actor.workstation(id),
    av_format       TEXT -- e.g. '3m'
);

-- SEED DATA

INSERT INTO actor.passwd_type (code, name, login, crypt_algo, iter_count)
    VALUES ('sip2', 'SIP2 Client Password', FALSE, 'bf', 5);

INSERT INTO config.sip_setting_group (label, institution) 
    VALUES ('Example Setting Group', 'example');

INSERT INTO config.sip_setting (setting_group, description, name, value)
VALUES (
    (SELECT id FROM config.sip_setting_group WHERE institution = 'example'), 
    'Monetary amounts are reported in this currency',
    'currency', '"USD"'
), (
    (SELECT id FROM config.sip_setting_group WHERE institution = 'example'), 
    'Allow clients to request the SIP server status before login (message 99)',
    'allow_sc_status_before_login', 'true'
), (
    (SELECT id FROM config.sip_setting_group WHERE institution = 'example'), 
    'Due date uses 18-char date format (YYYYMMDDZZZZHHMMSS).  Otherwise "YYYY-MM-DD HH:MM:SS',
    'due_date_use_sip_date_format', 'false'
), (
    (SELECT id FROM config.sip_setting_group WHERE institution = 'example'), 
    'Checkout and renewal are allowed even when penalties blocking these actions exist',
    'patron_status_permit_loans', 'false'
), (
    (SELECT id FROM config.sip_setting_group WHERE institution = 'example'), 
    'Holds, checkouts, and renewals allowed regardless of blocking penalties',
    'patron_status_permit_all', 'false'
), (
    (SELECT id FROM config.sip_setting_group WHERE institution = 'example'), 
    'Patron circulation data may be returned as either "title" or "barcode"',
    'msg64_summary_datatype', '"title"'
), (
    (SELECT id FROM config.sip_setting_group WHERE institution = 'example'), 
    'Patron holds data may be returned as either "title" or "barcode"',
    'msg64_hold_items_available', '"title"'
);


/* EXAMPLE SETTINGS


-- Example linking a SIP password to the 'admin' account.
SELECT actor.set_passwd(1, 'sip2', 'sip_password');

INSERT INTO actor.workstation (name, owning_lib) VALUES ('BR1-SIP2-Gateway', 4);

INSERT INTO config.sip_account(
    setting_group, sip_username, sip_password, usr, workstation, av_format
) VALUES (
    (SELECT id FROM config.sip_setting_group WHERE institution = 'example'), 
    'admin', 
    (SELECT id FROM actor.passwd WHERE usr = 1 AND passwd_type = 'sip2'),
    1, 
    (SELECT id FROM actor.workstation WHERE name = 'BR1-SIP2-Gateway'), 
    '3m'
);


*/

COMMIT;


