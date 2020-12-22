import {Component, OnInit, Input, Output, EventEmitter, ViewChild} from '@angular/core';
import {tap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {LineitemCopyAttrsComponent} from './copy-attrs.component';

const BATCH_FIELDS = [
    'owning_lib',
    'location',
    'collection_code',
    'fund',
    'circ_modifier',
    'cn_label'
];

@Component({
  templateUrl: 'batch-copies.component.html',
  selector: 'eg-lineitem-batch-copies',
  styleUrls: ['batch-copies.component.css']
})
export class LineitemBatchCopiesComponent implements OnInit {

    @Input() lineitem: IdlObject;

    constructor(
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private liService: LineitemService
    ) {}

    ngOnInit() {}

    // Propagate values from the batch edit bar into the indivudual LID's
    attrsSaveRequested(copyTemplate: IdlObject) {
        BATCH_FIELDS.forEach(field => {
            const val = copyTemplate[field]();
            if (val === undefined) { return; }
            this.lineitem.lineitem_details().forEach(copy => {
                copy[field](val);
                copy.ischanged(true); // isnew() takes precedence
            });
        });
    }

    copyDeleteRequested(copy: IdlObject) {
        if (copy.isnew()) {
            // Brand new copies can be discarded
            this.lineitem.lineitem_details(
                this.lineitem.lineitem_details().filter(c => c.id() !== copy.id())
            );
        } else {
            copy.isdeleted(true);
        }
    }
}


