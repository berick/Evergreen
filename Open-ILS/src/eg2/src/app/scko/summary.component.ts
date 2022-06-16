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
  selector: 'eg-scko-summary',
  templateUrl: 'summary.component.html'
})

export class SckoSummaryComponent implements OnInit {

    receiptType = 'email';

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

    }
}

