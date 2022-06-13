import {Component, OnInit, NgZone, HostListener} from '@angular/core';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {AuthService, AuthWsState} from '@eg/core/auth.service';
import {NetService} from '@eg/core/net.service';
import {IdlObject, IdlService} from '@eg/core/idl.service';

@Component({
  templateUrl: 'scko.component.html',
  styleUrls: ['scko.component.css']
})

export class SckoComponent implements OnInit {

    // Currently active patron account object.
    patron: IdlObject;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
    ) {}

    ngOnInit() {
    }
}

