import {Component, OnInit, AfterViewInit, Input, Output, EventEmitter} from '@angular/core';
import {tap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';
import {ItemLocationService} from '@eg/share/item-location-select/item-location-select.service';

@Component({
  templateUrl: 'copy-attrs.component.html',
  selector: 'eg-lineitem-copy-attrs'
})
export class LineitemCopyAttrsComponent implements OnInit {

    fundEntries: ComboboxEntry[];
    circModEntries: ComboboxEntry[];

    private _copy: IdlObject;
    @Input() set copy(c: IdlObject) { // acqlid
        if (c === undefined) {
            return;
        } else if (c === null) {
            this._copy = null;
        } else {
            // Enture cbox entries are populated before the copy is
            // applied so the cbox has the minimal set of values it
            // needs at copy render time.
            this.setInitialOptions(c);
            this._copy = c;
        }
    }

    get copy(): IdlObject {
        return this._copy;
    }

    @Input() batchMode = false;

    // Emits an 'acqlid' object;
    @Output() saveRequested: EventEmitter<IdlObject> = new EventEmitter<IdlObject>();


    constructor(
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private loc: ItemLocationService,
        private liService: LineitemService
    ) {}

    ngOnInit() {
        if (!this.copy) {
            // Will be no copy in the batch edit row
            this.copy = this.idl.create('acqlid');
            this.copy.isnew(true);
        }
    }

    // Tell our inputs about the values we know we need,
    // then de-flesh the items for consistency
    setInitialOptions(copy: IdlObject) {
        if (copy.fund()) {
            this.fundEntries = [{
                id: copy.fund().id(),
                label: copy.fund().name(),
                fm: copy.fund()
            }];
            copy.fund(copy.fund().id());
        }

        if (copy.circ_modifier()) {
            this.circModEntries = [{
                id: copy.circ_modifier().code(),
                label: copy.circ_modifier().name(),
                fm: copy.circ_modifier()
            }];
            copy.circ_modifier(copy.circ_modifier().code());
        }

        if (copy.location()) {
            // This comp is a cbox wrapper and has its own cache
            this.loc.locationCache[copy.location().id()] = copy.location();
            copy.location(copy.location().id());
        }
    }
}


