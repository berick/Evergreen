import {Component, Input, OnInit, AfterViewInit, ViewChild} from '@angular/core';
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
  templateUrl: 'summary.component.html',
  selector: 'eg-acq-po-summary'
})
export class PoSummaryComponent implements OnInit, AfterViewInit {

    private _poId: number;
    @Input() set poId(id: number) {
        if (id !== this._poId) {
            this._poId = id;
            if (this.initDone) {
                this.load();
            }
        }
    }

    get poId(): number {
        return this._poId;
    }

    po: IdlObject;
    newPoName: string;
    editPoName = false;
    initDone = false;

    constructor(
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
        this.load().then(_ => this.initDone = true);
    }

    ngAfterViewInit() {
    }

    load(): Promise<any> {
        this.po = null;
        if (!this.poId) { return Promise.resolve(); }

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.purchase_order.retrieve',
            this.auth.token(), this.poId, {
                flesh_provider: true,
                flesh_creator: true,
                flesh_editor: true,
                flesh_owner: true,
                flesh_notes: true,
                flesh_po_items: true,
                flesh_price_summary: true,
                flesh_lineitem_ids: true,
                li_limit: 10000
        }).toPromise().then(po => {

            const evt = this.evt.parse(po);
            if (evt) {
                alert(evt);
                return Promise.reject();
            }

            this.po = po;
        });
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
}
