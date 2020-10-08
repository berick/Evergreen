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

    listId: number;
    picklist: IdlObject;
    newPlName: string;
    editPlName = false;
    batchNote: string;
    noteIsPublic = false;

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
            const listId = +params.get('listId');

            if (listId !== this.listId) {
                this.listId = listId;
                this.load();
            }
        });
    }

    load(): Promise<any> {
        this.picklist = null;

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.picklist.retrieve.authoritative',
            this.auth.token(), this.listId,
            {flesh_lineitem_count: true, flesh_owner: true}
        ).toPromise().then(list => {

            const evt = this.evt.parse(list);
            if (evt) {
                console.error('API returned ', evt);
                return Promise.reject();
            }

            this.picklist = list;
        });
    }

    ngAfterViewInit() {
    }

    applyAction(action: string) {
        switch (action) {
            case 'brief-record':
                break;
        }
    }

    toggleNameEdit() {
        this.editPlName = !this.editPlName;

        if (this.editPlName) {
            this.newPlName = this.picklist.name();
            setTimeout(() => {
                const node =
                    document.getElementById('pl-name-input') as HTMLInputElement;
                if (node) { node.select(); }
            });

        } else if (this.newPlName && this.newPlName !== this.picklist.name()) {

            const prevName = this.picklist.name();
            this.picklist.name(this.newPlName);
            this.newPlName = null;

            this.net.request(
                'open-ils.acq',
                'open-ils.acq.picklist.update',
                this.auth.token(), this.picklist
            ).subscribe(resp => {
                const evt = this.evt.parse(resp);
                if (evt) {
                    alert(evt);
                    this.picklist.name(prevName);
                }
            });
        }
    }


    /*
    savePref(name: string) {
        switch (name) {
            case 'checkdigit':
                this.serverStore.setItem(
                    'eg.acq.update_items.use_checkdigit', this.useCheckdigit);
                break;

            case 'notes':
                this.serverStore.setItem(
                    'eg.acq.update_items.add_notes', this.addNotes);
                break;

            case 'labels':
                this.serverStore.setItem(
                    'eg.acq.update_items.print_labels', this.printLabels);
                break;

        }
    }
    */
}
