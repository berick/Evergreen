import {Injectable, EventEmitter} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService, EgEvent} from '@eg/core/event.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';

@Injectable({providedIn: 'root'})
export class SckoService {

    // Currently active patron account object.
    patron: IdlObject;
    barcodeRegex: RegExp;
    patronPasswordRequired = false;

    constructor(
        private net: NetService,
        private evt: EventService,
        private serverStore: ServerStoreService,
        public auth: AuthService
    ) {}

    load(): Promise<any> {
        this.auth.authDomain = 'eg.scko';

        return this.auth.testAuthToken()

        .then(_ => {

            return this.serverStore.getItemBatch([
                'opac.barcode_regex',
                'circ.selfcheck.patron_login_timeout',
                'circ.selfcheck.auto_override_checkout_events',
                'circ.selfcheck.patron_password_required',
                'circ.checkout_auto_renew_age',
                'circ.selfcheck.workstation_required',
                'circ.selfcheck.alert.popup',
                'circ.selfcheck.alert.sound',
                'credit.payments.allow',
                'circ.selfcheck.block_checkout_on_copy_status'
            ]);

        }).then(sets => {
            const regPattern = sets['opac.barcode_regex'] || /^\d/;
            this.barcodeRegex = new RegExp(regPattern);
            this.patronPasswordRequired =
                sets['circ.selfcheck.patron_password_required'];
        });
    }

    loadPatron(username: string, password: string): Promise<any> {
        this.patron = null;

        if (!username) { return; }

        let barcode;

        if (username.match(this.barcodeRegex)) {
            barcode = username;
            username = null;
        }

        if (this.patronPasswordRequired) {
            // TODO verify password

        } else {

            return this.fetchPatron(username, barcode);
        }
    }

    fetchPatron(username: string, barcode: string): Promise<any> {

        return this.net.request(
            'open-ils.actor',
            'open-ils.actor.user.retrieve_id_by_barcode_or_username',
            this.auth.token(), barcode, username).toPromise()

        .then(patronId => {

            const evt = this.evt.parse(patronId);

            if (evt || !patronId) {
                console.error("Cannot find user: ", evt);
                return Promise.reject('User not found');
            }

            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.user.fleshed.retrieve.authoritative',
                this.auth.token(), patronId).toPromise()

        }).then(patron => {

            const evt = this.evt.parse(patron);

            if (evt) {
                console.error('fetchPatron()', evt);
                return Promise.reject('User not found');
            }

            this.patron = patron;
        });
    }
}



