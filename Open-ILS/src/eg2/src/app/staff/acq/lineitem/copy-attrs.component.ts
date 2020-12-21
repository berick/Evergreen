import {Component, OnInit, AfterViewInit, Input, Output, EventEmitter} from '@angular/core';
import {tap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
  templateUrl: 'copy-attrs.component.html',
  selector: 'eg-lineitem-copy-attrs'
})
export class LineitemCopyAttrsComponent implements OnInit {

    @Input() copy: IdlObject; // acqlid
    @Input() showBatchUpdate = false;

    // Emits an 'acqlid' object;
    @Output() saveRequested: EventEmitter<IdlObject> = new EventEmitter<IdlObject>();

    constructor(
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private liService: LineitemService
    ) {}

    ngOnInit() {
        if (!this.copy) {
            // Will be no copy in the batch edit row
            this.copy = this.idl.create('acqlid');
            this.copy.isnew(true);
        }
    }
}


