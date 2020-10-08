import {Component, OnInit, AfterViewInit, Input, Output, EventEmitter} from '@angular/core';
import {tap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
  templateUrl: 'copies.component.html',
  selector: 'eg-lineitem-copies'
})
export class LineitemCopiesComponent implements OnInit, AfterViewInit {

    copyCount = 0;
    batchOwningLib: IdlObject;
    batchFund: ComboboxEntry;
    batchCopyLocId: number;

    @Input() lineitem: IdlObject;
    @Output() closeRequested: EventEmitter<void> = new EventEmitter<void>();

    constructor(
        private net: NetService,
        private auth: AuthService,
        private liService: LineitemService
    ) {}

    ngOnInit() {
    }

    ngAfterViewInit() {
        const node = document.getElementById('copy-count-input');
        if (node) { node.focus(); }
    }

    applyBatch(copy: IdlObject) {
        console.log('applying', copy);
    }

    applyFormula(id: number) {
        console.log('applying formula ', id);
    }
}


