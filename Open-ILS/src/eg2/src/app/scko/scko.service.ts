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

    sessionTotalCheckouts = 0;
    accountTotalCheckouts = 0;

    totalHolds = 0;
    holdsReady = 0;
    totalFines = 0;

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
            console.log('REQ', this.patronPasswordRequired);
        });
    }
}



