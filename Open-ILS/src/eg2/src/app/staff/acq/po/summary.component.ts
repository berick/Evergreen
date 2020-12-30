import {Component, Input, OnInit, ViewChild} from '@angular/core';
import {Router} from '@angular/router';
import {of, Observable} from 'rxjs';
import {tap, take, map} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {OrgService} from '@eg/core/org.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {ComboboxEntry, ComboboxComponent} from '@eg/share/combobox/combobox.component';
import {ProgressDialogComponent} from '@eg/share/dialog/progress.component';
import {EventService, EgEvent} from '@eg/core/event.service';
import {ConfirmDialogComponent} from '@eg/share/dialog/confirm.component';
import {PoService} from './po.service';
import {CancelDialogComponent} from '../lineitem/cancel-dialog.component';


@Component({
  templateUrl: 'summary.component.html',
  selector: 'eg-acq-po-summary'
})
export class PoSummaryComponent implements OnInit {

    private _poId: number;
    @Input() set poId(id: number) {
        if (id === this._poId) { return; }
        this._poId = id;
        if (this.initDone) { this.load(); }
    }
    get poId(): number { return this._poId; }

    po: IdlObject;
    newPoName: string;
    editPoName = false;
    initDone = false;
    ediMessageCount = 0;
    invoiceCount = 0;
    showNotes = false;
    canActivate: boolean = null;

    activationBlocks: EgEvent[] = [];

    @ViewChild('cancelDialog') cancelDialog: CancelDialogComponent;

    constructor(
        private router: Router,
        private evt: EventService,
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService,
        private auth: AuthService,
        private store: ServerStoreService,
        private poService: PoService
    ) {}

    ngOnInit() {
        this.load().then(_ => this.initDone = true);
    }

    load(): Promise<any> {
        this.po = null;
        if (!this.poId) { return Promise.resolve(); }

        return this.poService.getFleshedPo(this.poId)
        .then(po => {

            // EDI message count
            this.po = po;
            return this.pcrud.search('acqedim',
                {purchase_order: this.poId}, {}, {idlist: true, atomic: true}
            ).toPromise().then(ids => this.ediMessageCount = ids.length);

        }).then(_ => {

            // Invoice count
            return this.net.request('open-ils.acq',
                'open-ils.acq.invoice.unified_search.atomic',
                this.auth.token(), {acqpo: [{id: this.poId}]},
                null, null, {id_list: true}
            ).toPromise().then(ids => this.invoiceCount = ids.length);

        }).then(_ => this.setCanActivate());
    }

    toggleNameEdit() {
        this.editPoName = !this.editPoName;

        if (this.editPoName) {
            this.newPoName = this.po.name();
            setTimeout(() => {
                const node =
                    document.getElementById('pl-name-input') as HTMLInputElement;
                if (node) { node.select(); }
            });

        } else if (this.newPoName && this.newPoName !== this.po.name()) {

            const prevName = this.po.name();
            this.po.name(this.newPoName);
            this.newPoName = null;

            this.pcrud.update(this.po).subscribe(resp => {
                const evt = this.evt.parse(resp);
                if (evt) {
                    alert(evt);
                    this.po.name(prevName);
                }
            });
        }
    }

    cancelPo() {
        this.cancelDialog.open().subscribe(reason => {
            if (!reason) { return; }

            this.net.request('open-ils.acq',
                'open-ils.acq.purchase_order.cancel',
                this.auth.token(), this.poId, reason
            ).subscribe(ok => location.href = location.href);
        });
    }

    setCanActivate() {
        this.activationBlocks = [];

        if (!(this.po.state().match(/new|pending/))) {
            this.canActivate = false;
            return;
        }

        this.net.request('open-ils.acq',
            'open-ils.acq.purchase_order.activate.dry_run',
            this.auth.token(), this.poId

        ).pipe(tap(resp => {

            const evt = this.evt.parse(resp);
            if (evt) { this.activationBlocks.push(evt); }

        })).toPromise().then(_ => {

            if (this.activationBlocks.length == 0) {
                this.canActivate = true;
                return;
            }

            this.canActivate = false;

            // More logic likely needed here to handle zero-copy
            // activation / ACQ_LINEITEM_NO_COPIES
        });
    }
}

