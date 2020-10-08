import {Component, OnInit, Renderer2} from '@angular/core';
import {Observable} from 'rxjs';
import {map, take} from 'rxjs/operators';
import {ActivatedRoute, ParamMap} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {IdlService} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {PrintService} from '@eg/share/print/print.service';
import {BroadcastService} from '@eg/share/util/broadcast.service';

@Component({
  templateUrl: 'print.component.html'
})
export class PrintComponent implements OnInit {

    id: number;
    outlet: Element;
    po: IdlObject;
    printing: boolean;
    closing: boolean;

    constructor(
        private route: ActivatedRoute,
        private renderer: Renderer2,
        private idl: IdlService,
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private broadcaster: BroadcastService,
        private printer: PrintService) {

        this.id = +this.route.snapshot.paramMap.get('id');

        this.route.url.pipe(map(segments => segments.join('_')), take(1))
        .subscribe(path => {
            this.printing = Boolean(path.match(/printer_print/));
            this.closing = Boolean(path.match(/printer_print_close/));
        });
    }

    ngOnInit() {
        this.outlet =
            this.renderer.selectRootElement('#print-outlet');

        this.po = null;

        this.net.request(
            'open-ils.acq', 'open-ils.acq.purchase_order.retrieve',
            this.auth.token(), this.id, {
                flesh_provider: true,
                flesh_provider_addresses: true,
                flesh_price_summary: true,
                flesh_po_items: true,
                flesh_lineitems: true,
                flesh_lineitem_attrs: true,
                flesh_lineitem_notes: true,
                flesh_lineitem_details: true,
                clear_marc: true,
                flesh_notes: true
            }
        ).toPromise()
        .then(po => this.po = po)
        .then(_ => this.populatePreview())
        .then(_ => {
            if (this.printing) {
               this.printPo();
            }
        });
    }

    populatePreview(): Promise<any> {

        return this.printer.compileRemoteTemplate({
            templateName: 'purchase_order',
            printContext: 'default',
            contextData: {po: this.po}

        }).then(response => {
            this.outlet.innerHTML = response.content;
        });
    }

    addLiPrintNotes(): Promise<any> {

        const notes = [];
        this.po.lineitems().forEach(li => {
            const note = this.idl.create('acqlin');
            note.isnew(true);
            note.lineitem(li.id());
            note.value('printed: ' + this.auth.user().usrname());
            notes.push(note);
        });

        return this.net.request('open-ils.acq',
            'open-ils.acq.lineitem_note.cud.batch', this.auth.token(), notes)
        .toPromise().then(_ => {
            this.broadcaster.broadcast(
                'eg.acq.lineitem.notes.update', {
                lineitems: notes.map(n => Number(n.lineitem()))
            });
        });
    }

    printPo(closeTab?: boolean) {
        this.addLiPrintNotes().then(_ => this.printPo2(closeTab));
    }

    printPo2(closeTab?: boolean) {
        if (closeTab || this.closing) {
            const sub: any = this.printer.printJobQueued$.subscribe(req => {
                if (req.templateName === 'purchase_order') {
                    setTimeout(() => {
                        window.close();
                        sub.unsubscribe();
                    }, 2000); // allow for a time cushion past queueing.
                }
            });
        }

        this.printer.print({
            templateName: 'purchase_order',
            printContext: 'default',
            contextData: {po: this.po}
        });
    }
}

