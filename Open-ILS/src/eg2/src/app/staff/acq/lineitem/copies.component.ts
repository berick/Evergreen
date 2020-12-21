import {Component, OnInit, AfterViewInit, Input, Output, EventEmitter} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';
import {tap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
  templateUrl: 'copies.component.html'
})
export class LineitemCopiesComponent implements OnInit, AfterViewInit {

    lineitemId: number;
    lineitem: IdlObject;
    copyCount = 1;
    batchOwningLib: IdlObject;
    batchFund: ComboboxEntry;
    batchCopyLocId: number;

    constructor(
        private route: ActivatedRoute,
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private liService: LineitemService
    ) {}

    ngOnInit() {

        this.route.paramMap.subscribe((params: ParamMap) => {
            const id = +params.get('lineitemId');
            if (id !== this.lineitemId) {
                this.lineitemId = id;
                if (id) { this.load(); }
            }
        });

        this.liService.getLiAttrDefs();
    }

    load() {
        this.lineitem = null;
        return this.liService.getFleshedLineitems([this.lineitemId])
        .pipe(tap(liStruct => this.lineitem = liStruct.lineitem))
        .toPromise().then(_ => this.applyCount());
    }

    ngAfterViewInit() {
        setTimeout(() => {
            const node = document.getElementById('copy-count-input');
            if (node) { (node as HTMLInputElement).select(); }
        });
    }

    applyCount() {
        const copies = this.lineitem.lineitem_details();
        while (copies.length < this.copyCount) {
            const copy = this.idl.create('acqlid');
            copy.isnew(true);
            copy.lineitem(this.lineitem.id());
            copies.push(copy);
        }

        if (copies.length > this.copyCount) {
            this.copyCount = copies.length;
        }
    }

    applyBatch(copy: IdlObject) {
        console.log('applying', copy);
    }

    applyFormula(id: number) {
        console.log('applying formula ', id);
    }
}


