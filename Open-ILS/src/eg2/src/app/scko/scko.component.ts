import {Component, OnInit, ViewEncapsulation} from '@angular/core';
import {Router, ActivatedRoute, NavigationEnd} from '@angular/router';
import {AuthService} from '@eg/core/auth.service';
import {SckoService} from './scko.service';
import {ServerStoreService} from '@eg/core/server-store.service';

@Component({
  templateUrl: 'scko.component.html',
  styleUrls: ['scko.component.css'],
  encapsulation: ViewEncapsulation.None
})

export class SckoComponent implements OnInit {

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        public  scko: SckoService
    ) {}

    ngOnInit() {
        this.scko.load();
    }
}

