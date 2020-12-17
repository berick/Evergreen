import {Component, OnInit, AfterViewInit, ViewChild} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {of, Observable} from 'rxjs';
import {tap, take, map} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {FormatService} from '@eg/core/format.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {EventService} from '@eg/core/event.service';
import {HoldingsService} from '@eg/staff/share/holdings/holdings.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {BroadcastService} from '@eg/share/util/broadcast.service';


@Component({
  templateUrl: 'picklist.component.html'
})
export class PicklistComponent implements OnInit, AfterViewInit {

    picklistId: number;

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private idl: IdlService,
        private net: NetService,
        private format: FormatService,
        private evt: EventService,
        private org: OrgService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private store: StoreService,
        private serverStore: ServerStoreService,
        private broadcaster: BroadcastService,
        private holdingSvc: HoldingsService
    ) {}

    ngOnInit() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.picklistId = +params.get('picklistId');
        });
    }

    ngAfterViewInit() {
    }
}
