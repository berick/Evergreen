import {Component, OnInit, Input, Output} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {Observable} from 'rxjs';
import {tap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
  templateUrl: 'lineitem-list.component.html',
  selector: 'eg-lineitem-list',
  styleUrls: ['lineitem-list.component.css']
})
export class LineitemListComponent implements OnInit {

    picklistId: number;

    loading = false;
    pager: Pager = new Pager();
    pageOfLineitems: IdlObject[] = [];
    lineitemIds: number[] = [];

    selected: {[id: number]: boolean} = {};

    orderIdentTypes: {[id: number]: 'isbn' | 'issn' | 'upc'} = {};

    existingCopyCounts: {[id: number]: number} = {};

    // Squash these down to an easily traversable data set to avoid
    // a lot of repetitive looping.
    liMarcAttrs: {[id: number]: {[name: string]: IdlObject[]}} = {};

    liCache: {[id: number]: IdlObject} = {};

    batchNote: string;
    noteIsPublic = false;
    batchSelectPage = false;
    batchSelectAll = false;
    showNotesFor: number;
    showExpandFor: number; // 'Expand'
    expandAll = false;
    action = '';

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private net: NetService,
        private auth: AuthService,
        private liService: LineitemService
    ) {}

    ngOnInit() {

        this.route.queryParamMap.subscribe((params: ParamMap) => {
            this.pager.offset = +params.get('offset');
            this.pager.limit = +params.get('limit');
            if (this.picklistId) { this.load(); }
        });

        this.route.parent.paramMap.subscribe((params: ParamMap) => {
            this.picklistId = +params.get('picklistId');
            this.load();
        });
    }

    load(): Promise<any> {
        this.pageOfLineitems = [];

        if (!this.pager.limit) {
            this.pager.limit = 10; // TODO: setting
        }

        this.loading = true;
        return this.loadIds()
            .then(_ => this.loadPage())
            .then(_ => this.loading = false);
    }

    // TODO: support loading from PO, etc.
    loadIds(): Promise<any> {
        this.lineitemIds = [];
        this.liCache = {};

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.lineitem.picklist.retrieve.atomic',
            this.auth.token(), this.picklistId, {idlist: true, limit: 1000}
        ).toPromise().then(ids => {

            this.lineitemIds = ids.sort(
                (id1, id2) => Number(id1) < Number(id2) ? -1 : 1);

            this.pager.resultCount = ids.length;
        });
    }

    goToPage() {
        this.router.navigate([], {
            relativeTo: this.route,
            queryParamsHandling: 'merge',
            queryParams: {
                offset: this.pager.offset,
                limit: this.pager.limit
            }
        });
    }

    loadPage(): Promise<any> {
        return this.loadPageOfLis().then(_ => this.setBatchSelect());
    }

    loadPageOfLis(): Promise<any> {
        this.pageOfLineitems = [];

        const ids = this.lineitemIds.slice(
            this.pager.offset, this.pager.offset + this.pager.limit)
            .filter(id => id !== undefined);

        if (ids.length === 0) {
            return Promise.resolve();
        }

        // See if we already have them in the cache
        ids.forEach(id => {
            if (this.liCache[id]) {
                this.pageOfLineitems.push(this.liCache[id]);
            }
        });

        if (this.pageOfLineitems.length === ids.length) {
            // All entries found in the cache
            return Promise.resolve();
        }

        this.pageOfLineitems = []; // reset

        // TODO: cache in liService for faster navigation

        return this.liService.getFleshedLineitems(ids).pipe(tap(struct => {
            this.ingestOneLi(struct.lineitem);
            this.existingCopyCounts[struct.id] = struct.existing_copies;
        })).toPromise();
    }

    ingestOneLi(li: IdlObject, replace?: boolean) {

        this.liMarcAttrs[li.id()] = {};
        this.liCache[li.id()] = li;

        li.attributes().forEach(attr => {
            const name = attr.attr_name();
            this.liMarcAttrs[li.id()][name] =
                this.liService.getAttributes(
                    li, name, 'lineitem_marc_attr_definition');
        });

        const ident = this.liService.getOrderIdent(li);
        this.orderIdentTypes[li.id()] = ident ? ident.attr_name() : 'isbn';

        // newest to oldest
        li.lineitem_notes(li.lineitem_notes().sort(
            (n1, n2) => n1.create_time() < n2.create_time() ? 1 : -1));

        if (replace) {
            for (let idx = 0; idx < this.pageOfLineitems.length; idx++) {
                if (this.pageOfLineitems[idx].id() === li.id()) {
                    this.pageOfLineitems[idx] = li;
                    break;
                }
            }
        } else {
            this.pageOfLineitems.push(li);
        }
    }

    // First matching attr
    displayAttr(li: IdlObject, name: string): string {
        return (
            this.liMarcAttrs[li.id()][name] &&
            this.liMarcAttrs[li.id()][name][0]
        ) ? this.liMarcAttrs[li.id()][name][0].attr_value() : '';
    }

    // All matching attrs
    attrs(li: IdlObject, name: string, attrType?: string): IdlObject[] {
        return this.liService.getAttributes(li, name, attrType);
    }

    jacketIdent(li: IdlObject): string {
        return this.displayAttr(li, 'isbn') || this.displayAttr(li, 'upc');
    }

    // Order ident options are pulled from the MARC, but the ident
    // value proper is stored as a local attr def.
    identOptions(li: IdlObject): ComboboxEntry[] {
        const otype = this.orderIdentTypes[li.id()];

        if (this.liMarcAttrs[li.id()][otype]) {
            return this.liMarcAttrs[li.id()][otype].map(
                attr => ({id: attr.id(), label: attr.attr_value()}));
        }

        return [];
    }

    // Returns the MARC attr with the same type and value as the applied
    // order identifier (which is a local attr)
    selectedIdent(li: IdlObject): number {
        const ident = this.liService.getOrderIdent(li);
        if (!ident) { return null; }

        const attr = this.identOptions(li).filter(
            (entry: ComboboxEntry) => entry.label === ident.attr_value())[0];
        return attr ? attr.id : null;
    }

    currentIdent(li: IdlObject): IdlObject {
        return this.liService.getOrderIdent(li);
    }

    orderIdentChanged(li: IdlObject, entry: ComboboxEntry) {
        if (entry === null) { return; }

        this.liService.changeOrderIdent(
            li, entry.id, this.orderIdentTypes[li.id()], entry.label
        ).subscribe(freshLi => this.ingestOneLi(freshLi, true));
    }

    addBriefRecord() {
    }

    selectedIds(): number[] {
        return Object.keys(this.selected)
            .filter(id => this.selected[id] === true)
            .map(id => Number(id));
    }


    // After a page of LI's are loaded, see if the batch-select checkbox
    // needs to be on or off.
    setBatchSelect() {
        let on = true;
        const ids = this.selectedIds();
        this.pageOfLineitems.forEach(li => {
            if (!ids.includes(li.id())) { on = false; }
        });

        this.batchSelectPage = on;

        on = true;

        this.lineitemIds.forEach(id => {
            if (!this.selected[id]) { on = false; }
        });

        this.batchSelectAll = on;
    }

    toggleSelectAll(allItems: boolean) {

        if (allItems) {
            this.lineitemIds.forEach(
                id => this.selected[id] = this.batchSelectAll);

            this.batchSelectPage = this.batchSelectAll;

        } else {

            this.pageOfLineitems.forEach(
                li => this.selected[li.id()] = this.batchSelectPage);

            if (!this.batchSelectPage) {
                // When deselecting items in the page, we're no longer
                // selecting all items.
                this.batchSelectAll = false;
            }
        }
    }

    applyBatchNote() {
        const ids = this.selectedIds();
        if (ids.length === 0 || !this.batchNote) { return; }

        this.liService.applyBatchNote(ids, this.batchNote, this.noteIsPublic)
        .then(resp => this.load());
    }

    liPriceIsValid(li: IdlObject): boolean {
        const price = li.estimated_unit_price();
        if (price === null || price === undefined || price === '') {
            return true;
        }
        return !Number.isNaN(Number(price)) && Number(price) >= 0;
    }

    liPriceChange(li: IdlObject) {
        const price = li.estimated_unit_price();
        if (this.liPriceIsValid(li)) {
            li.estimated_unit_price(Number(price).toFixed(2));

            this.net.request(
                'open-ils.acq',
                'open-ils.acq.lineitem.update',
                this.auth.token(), li
            ).subscribe(resp => {
                console.debug('LI update returned ', resp);
            });
        }
    }

    toggleShowNotes(liId: number) {
        this.showExpandFor = null;
        this.showNotesFor = this.showNotesFor === liId ? null : liId;
    }

    toggleShowExpand(liId: number) {
        this.showNotesFor = null;
        this.showExpandFor = this.showExpandFor === liId ? null : liId;
    }

    toggleExpandAll() {
        this.showNotesFor = null;
        this.showExpandFor = null;
        this.expandAll = !this.expandAll;
    }

    liHasAlerts(li: IdlObject): boolean {
        return li.lineitem_notes().filter(n => n.alert_text()).length > 0;
    }
}

