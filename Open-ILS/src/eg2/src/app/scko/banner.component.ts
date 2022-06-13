import {Component, OnInit, NgZone, HostListener} from '@angular/core';
import {Location} from '@angular/common';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {AuthService, AuthWsState} from '@eg/core/auth.service';
import {StoreService} from '@eg/core/store.service';
import {SckoService} from './scko.service';
import {OrgService} from '@eg/core/org.service';

@Component({
  selector: 'eg-scko-banner',
  templateUrl: 'banner.component.html'
})

export class SckoBannerComponent implements OnInit {

    workstations: any[];
    loginFailed = false;
    workstationNotFound = false;

    patronUsername: string;
    patronPassword: string;

    staffUsername: string;
    staffPassword: string;
    staffWorkstation: string;

    constructor(
        private route: ActivatedRoute,
        private store: StoreService,
        private auth: AuthService,
        private ngLocation: Location,
        private org: OrgService,
        public scko: SckoService
    ) {}

    ngOnInit() {

        const node = document.getElementById('staff-username');

        console.log('PFX', this.scko.auth.storePrefix);
        console.log(this.scko.auth.token());
        console.log(this.scko.auth.user());

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

        this.loginFailed = false;

        const args = {
            type: 'persistent',
            username: this.staffUsername,
            password: this.staffPassword,
            workstation: this.staffWorkstation
        };

        this.loginFailed = false;
        this.workstationNotFound = false;

        this.auth.login(args).then(
            ok => {

                if (this.auth.workstationState === AuthWsState.NOT_FOUND_SERVER) {
                    this.loginFailed = true;
                    this.workstationNotFound = true;

                } else {

                    // Initial login clears cached org unit setting values
                    // and user/workstation setting values
                    this.org.clearCachedSettings().then(_ => {

                        // Force reload of the app after a successful login.
                        // This allows the route resolver to re-run with a
                        // valid auth token and workstation.
                        window.location.href =
                            this.ngLocation.prepareExternalUrl('/scko');

                    });
                }
            },
            notOk => {
                this.loginFailed = true;
            }
        );
    }

    submitPatronLogin() {
    }
}

