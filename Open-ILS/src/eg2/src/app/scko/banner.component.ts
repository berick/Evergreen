import {Component, OnInit, NgZone, HostListener} from '@angular/core';
import {Location} from '@angular/common';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {AuthService, AuthWsState} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {StoreService} from '@eg/core/store.service';
import {SckoService} from './scko.service';
import {OrgService} from '@eg/core/org.service';
import {EventService, EgEvent} from '@eg/core/event.service';

@Component({
  selector: 'eg-scko-banner',
  templateUrl: 'banner.component.html'
})

export class SckoBannerComponent implements OnInit {

    workstations: any[];
    workstationNotFound = false;

    patronUsername: string;
    patronPassword: string;
    patronLoginFailed = false;

    staffUsername: string;
    staffPassword: string;
    staffWorkstation: string;
    staffLoginFailed = false;

    constructor(
        private route: ActivatedRoute,
        private store: StoreService,
        private net: NetService,
        private auth: AuthService,
        private evt: EventService,
        private ngLocation: Location,
        private org: OrgService,
        public scko: SckoService
    ) {}

    ngOnInit() {

        const node = document.getElementById('staff-username');

        // NOTE: Displaying a list of workstations will not work for users
        // of Hatch until the extension is updated to support /eg2/*/scko
        this.store.getWorkstations()
        .then(wsList => {
            this.workstations = wsList;
            return this.store.getDefaultWorkstation();
        }).then(def => {
            this.staffWorkstation = def;
            this.applyWorkstation();
        });
    }

    applyWorkstation() {
        const wanted = this.route.snapshot.queryParamMap.get('workstation');
        if (!wanted) { return; } // use the default

        const exists = this.workstations.filter(w => w.name === wanted)[0];
        if (exists) {
            this.staffWorkstation = wanted;
        } else {
            console.error(`Unknown workstation requested: ${wanted}`);
        }
    }

    submitStaffLogin() {

        this.staffLoginFailed = false;

        const args = {
            type: 'persistent',
            username: this.staffUsername,
            password: this.staffPassword,
            workstation: this.staffWorkstation
        };

        this.staffLoginFailed = false;
        this.workstationNotFound = false;

        this.auth.login(args).then(
            ok => {

                if (this.auth.workstationState === AuthWsState.NOT_FOUND_SERVER) {
                    this.staffLoginFailed = true;
                    this.workstationNotFound = true;

                } else {

                    // Initial login clears cached org unit setting values
                    // and user/workstation setting values
                    this.org.clearCachedSettings().then(_ => {

                        // Force reload of the app after a successful login.
                        window.location.href =
                            this.ngLocation.prepareExternalUrl('/scko');

                    });
                }
            },
            notOk => {
                this.staffLoginFailed = true;
            }
        );
    }

    submitPatronLogin() {
        this.patronLoginFailed = false;
        this.loadPatron().finally(() => {
            this.patronLoginFailed = this.scko.patron === null;
        });
    }

    loadPatron(): Promise<any> {
        this.scko.patron = null;

        if (!this.patronUsername) { return; }

        let username;
        let barcode;

        if (this.patronUsername.match(this.scko.barcodeRegex)) {
            barcode = this.patronUsername;
        } else {
            username = this.patronUsername;
        }

        if (this.scko.patronPasswordRequired) {
            // TODO verify password

            return this.net.request(
                'open-ils.actor',
                'open-ils.actor.verify_user_password',
                this.auth.token(), barcode, username, null, this.patronPassword)

            .toPromise().then(verified => {
                if (Number(verified) === 1) {
                    return this.fetchPatron(username, barcode);
                } else {
                    return Promise.reject('Bad password');
                }
            });

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

            this.scko.patron = patron;
        });
    }

}

