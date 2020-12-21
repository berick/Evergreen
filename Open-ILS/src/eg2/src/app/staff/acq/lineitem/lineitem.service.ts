import {Injectable, EventEmitter} from '@angular/core';
import {Observable, empty} from 'rxjs';
import {switchMap, map, tap} from 'rxjs/operators';
import {IdlObject, IdlService} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {ItemLocationService} from '@eg/share/item-location-select/item-location-select.service';

export interface BatchLineitemStruct {
    id: number;
    lineitem: IdlObject;
    existing_copies: number;
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

    constructor(
        private idl: IdlService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private loc: ItemLocationService
    ) {}

    getFleshedLineitems(ids: number[], flesh?: any): Observable<BatchLineitemStruct> {

        if (!flesh) {
            flesh = {
                flesh_attrs: true,
                flesh_cancel_reason: true,
                flesh_li_details: true,
                flesh_notes: true,
                flesh_fund_debit: true,
                clear_marc: true,
                flesh_po: true,
                flesh_pl: true
            };
        }

        return new Observable<BatchLineitemStruct>(observer => {
            const locIds = {};
            const lis = [];

            this.net.request(
                'open-ils.acq', 'open-ils.acq.lineitem.retrieve.batch',
                this.auth.token(), ids, flesh

            ).pipe(tap(struct => {

                struct.lineitem.lineitem_details().forEach(copy => {
                    if (copy.location()) { locIds[copy.location()] = true; }
                });

                lis.push(struct);

            })).toPromise().then(_ => {
                this.getLocations(Object.keys(locIds).map(id => Number(id)))
                .toPromise().then(_ => {
                    lis.forEach(struct => observer.next(struct));
                    observer.complete();
                });
            })
        });
    }

    // Pre-fetch related copy locations so our update inputs aren't
    // required to fetch them all one a a time (sometimes in parallel)
    getLocations(ids: number[]): Observable<any> {
        if (ids.length === 0) { return empty(); }
        return this.pcrud.search('acpl', {id: ids})
        .pipe(tap(loc => this.loc.locationCache[loc.id()] = loc));
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

        if (lids.length === 0) { return empty(); }

        return this.net.request(
            'open-ils.acq',
            'open-ils.acq.lineitem_detail.cud.batch', this.auth.token(), lids);
    }
}

