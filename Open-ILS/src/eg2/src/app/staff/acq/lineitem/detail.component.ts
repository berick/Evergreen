import {Component, OnInit, AfterViewInit, Input, Output, EventEmitter} from '@angular/core';
import {tap} from 'rxjs/operators';
import {Pager} from '@eg/share/util/pager';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {LineitemService} from './lineitem.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

@Component({
  templateUrl: 'detail.component.html',
  selector: 'eg-lineitem-detail'
})
export class LineitemDetailComponent implements OnInit {

    @Input() lineitem: IdlObject;
    marcHtml: string;

    @Output() closeRequested: EventEmitter<void> = new EventEmitter<void>();

    constructor(
        private net: NetService,
        private auth: AuthService,
        private liService: LineitemService
    ) {}

    ngOnInit() {
        this.liService.getLiAttrDefs();
    }

    attrLabel(attr: IdlObject): string {
        if (!this.liService.liAttrDefs) { return; }

        const def = this.liService.liAttrDefs.filter(
            d => d.id() === attr.definition())[0];

        return def ? def.description() : '';
    }
}


