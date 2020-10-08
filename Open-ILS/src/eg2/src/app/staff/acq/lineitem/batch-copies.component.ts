import {Component, OnInit, Input, Output, EventEmitter, ViewChild} from '@angular/core';
import {tap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {LineitemCopyAttrsComponent} from './copy-attrs.component';

@Component({
  templateUrl: 'batch-copies.component.html',
  selector: 'eg-lineitem-batch-copies'
})
export class LineitemBatchCopiesComponent implements OnInit {

    copies: IdlObject[] = [];

    @Input() lineitem: IdlObject;
    @Output() saveRequested: EventEmitter<IdlObject> = new EventEmitter<IdlObject>();

    constructor(
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private liService: LineitemService
    ) {}

    ngOnInit() {
        // testing
        const c = this.idl.create('acqlid');
        c.cn_label('FOO');
        this.copies = [c, c, c];
    }

    attrsSaveRequested(copy: IdlObject) { // acqlid
        this.saveRequested.emit(copy);
    }
}


