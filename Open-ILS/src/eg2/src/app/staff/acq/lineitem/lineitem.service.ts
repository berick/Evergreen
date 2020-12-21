import {Injectable, EventEmitter} from '@angular/core';
import {Observable} from 'rxjs';
import {switchMap, map} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ComboboxEntry} from '@eg/share/combobox/combobox.component';

export interface BatchLineitemStruct {
    id: number;
    lineitem: IdlObject;
    existing_copies: number;
    all_locations: IdlObject[];
    all_funds: IdlObject[];
    all_circ_modifiers: IdlObject[];
}

export interface BatchLineitemUpdateStruct {
    lineitem: IdlObject;
    lid: number;
    max: number;
    progress: number;
    complete: number; // Perl bool
    total: number;
    [key: string]: any; // Perl Acq::BatchManager
}

@Injectable()
export class LineitemService {

    liAttrDefs: IdlObject[];

    // Pre-fetch large batches of objects so our comboboxes aren't
    // forced to fetch them all in parallel at render time.
    preloadLocations: ComboboxEntry[];
    preloadFunds: ComboboxEntry[];
    preloadCircMods: ComboboxEntry[];

    // Emitted when our copy batch editor wants to apply a value
    // to a set of inputs.  This allows the the copy input comboxoes, etc.
    // to add the entry before it's forced to grab the value from the
    // server, often in large parallel batches.
    batchOptionWanted: EventEmitter<{[field: string]: ComboboxEntry}>
        = new EventEmitter<{[field: string]: ComboboxEntry}> ();

    constructor(
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService
    ) {}

    getFleshedLineitems(ids: number[]): Observable<BatchLineitemStruct> {

        const flesh: any = {
            flesh_attrs: true,
            flesh_cancel_reason: true,
            flesh_li_details: true,
            flesh_notes: true,
            flesh_fund: true,
            flesh_circ_modifier: true,
            flesh_location: true,
            flesh_fund_debit: true,
            clear_marc: true,
            flesh_po: true,
            flesh_pl: true
        };

        return this.net.request(
            'open-ils.acq', 'open-ils.acq.lineitem.retrieve.batch',
            this.auth.token(), ids, flesh);
    }


    // Returns all matching attributes
    // 'li' should be fleshed with attributes()
    getAttributes(li: IdlObject, name: string, attrType?: string): IdlObject[] {
        const values: IdlObject[] = [];
        li.attributes().forEach(attr => {
            if (attr.attr_name() === name) {
                if (!attrType || attrType === attr.attr_type()) {
                    values.push(attr);
                }
            }
        });

        return values;
    }

    getAttributeValues(li: IdlObject, name: string, attrType?: string): string[] {
        return this.getAttributes(li, name, attrType).map(attr => attr.attr_value());
    }

    // Returns the first matching attribute
    // 'li' should be fleshed with attributes()
    getFirstAttribute(li: IdlObject, name: string, attrType?: string): IdlObject {
        return this.getAttributes(li, name, attrType)[0];
    }

    getFirstAttributeValue(li: IdlObject, name: string, attrType?: string): string {
        const attr = this.getFirstAttribute(li, name, attrType);
        return attr ? attr.attr_value() : '';
    }

    getOrderIdent(li: IdlObject): IdlObject {
        for (let idx = 0; idx < li.attributes().length; idx++) {
            const attr = li.attributes()[idx];
            if (attr.order_ident() === 't' &&
                attr.attr_type() === 'lineitem_local_attr_definition') {
                return attr;
            }
        }
        return null;
    }

    // Returns an updated copy of the lineitem
    changeOrderIdent(li: IdlObject,
        id: number, attrType: string, attrValue: string): Observable<IdlObject> {

        const args: any = {lineitem_id: li.id()};

        if (id) {
            // Order ident set to an existing attribute.
            args.source_attr_id = id;
        } else {
            // Order ident set to a new free text value
            args.attr_name = attrType;
            args.attr_value = attrValue;
        }

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.lineitem.order_identifier.set',
            this.auth.token(), args
        ).pipe(switchMap(_ => this.getFleshedLineitems([li.id()]))
        ).pipe(map(struct => struct.lineitem));
    }

    applyBatchNote(liIds: number[],
        noteValue: string, vendorPublic: boolean): Promise<any> {

        if (!noteValue || liIds.length === 0) { return Promise.resolve(); }

        const notes = [];
        liIds.forEach(id => {
            const note = this.idl.create('acqlin');
            note.isnew(true);
            note.lineitem(id);
            note.value(noteValue);
            note.vendor_public(vendorPublic ? 't' : 'f');
            notes.push(note);
        });

        return this.net.request('open-ils.acq',
            'open-ils.acq.lineitem_note.cud.batch',
            this.auth.token(), notes).toPromise();
    }

    getLiAttrDefs(): Promise<IdlObject[]> {
        if (this.liAttrDefs) {
            return Promise.resolve(this.liAttrDefs);
        }

        return this.pcrud.retrieveAll('acqliad', {}, {atomic: true})
        .toPromise().then(defs => this.liAttrDefs = defs);
    }

    updateLiDetails(li: IdlObject): Observable<BatchLineitemUpdateStruct> {
        const lids = li.lineitem_details().filter(copy =>
            (copy.isnew() || copy.ischanged() || copy.isdeleted()));

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.lineitem_detail.cud.batch', this.auth.token(), lids);
    }
}

