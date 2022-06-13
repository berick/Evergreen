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
    }

    verifyPatronAuth() {
    }
}

