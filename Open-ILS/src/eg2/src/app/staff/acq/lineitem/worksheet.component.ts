import {Component, OnInit, Renderer2} from '@angular/core';
import {map, take} from 'rxjs/operators';
import {ActivatedRoute, ParamMap} from '@angular/router';
import {IdlObject} from '@eg/core/idl.service';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {OrgService} from '@eg/core/org.service';
import {PrintService} from '@eg/share/print/print.service';

@Component({
  templateUrl: 'worksheet.component.html'
})
export class WorksheetComponent implements OnInit {

    outlet: Element;
    id: number;
    lineitem: IdlObject;
    holdCount: number;
    printing: boolean;
    closing: boolean;

    constructor(
        private route: ActivatedRoute,
        private renderer: Renderer2,
        private org: OrgService,
        private net: NetService,
        private auth: AuthService,
        private pcrud: PcrudService,
        private printer: PrintService) {

        this.id = +this.route.snapshot.paramMap.get('id');

        this.route.url.pipe(map(segments => segments.join('_')), take(1))
        .subscribe(path => {
            this.printing = Boolean(path.match(/worksheet_print/));
            this.closing = Boolean(path.match(/worksheet_print_close/));
        });
    }

    ngOnInit() {
        this.outlet =
            this.renderer.selectRootElement('#worksheet-outlet');

        this.lineitem = null;

        this.net.request(
            'open-ils.acq', 'open-ils.acq.lineitem.retrieve',
            this.auth.token(), this.id, {
                flesh_attrs: true,
                flesh_notes: true,
                flesh_cancel_reason: true,
                flesh_li_details: true,
                flesh_fund: true,
                flesh_li_details_copy: true,
                flesh_li_details_location: true,
                flesh_li_details_receiver: true,
                distribution_formulas: true
            }
        ).toPromise()
        .then(li => this.lineitem = li)
        .then(_ => this.getRemainingData())
        .then(_ => this.populatePreview())
        .then(_ => {
            if (this.printing) {
               this.printWorksheet();
            }
        });
    }

    getRemainingData(): Promise<any> {

        // Flesh owning lib
        this.lineitem.lineitem_details().forEach(lid => {
            lid.owning_lib(this.org.get(lid.owning_lib()));
        });

        return this.net.request(
            'open-ils.circ',
            'open-ils.circ.bre.holds.count', this.lineitem.eg_bib_id()
        ).toPromise().then(count => this.holdCount = count);

    }

    populatePreview(): Promise<any> {

        return this.printer.compileRemoteTemplate({
            templateName: 'lineitem_worksheet',
            printContext: 'default',
            contextData: {
                lineitem: this.lineitem,
                hold_count: this.holdCount
            }

        }).then(response => {
            this.outlet.innerHTML = response.content;
        });
    }

    printWorksheet(closeTab?: boolean) {

        if (closeTab || this.closing) {
            const sub: any = this.printer.printJobQueued$.subscribe(
                req => {
                    if (req.templateName === 'lineitem_worksheet') {
                        setTimeout(() => {
                            window.close();
                            sub.unsubscribe();
                        }, 2000); // allow for a time cushion past queueing.
                    }
                }
            );
        }

        this.printer.print({
            templateName: 'lineitem_worksheet',
            contextData: {
                lineitem: this.lineitem,
                hold_count: this.holdCount
            },
            printContext: 'default'
        });
    }
}
