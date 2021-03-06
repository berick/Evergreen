import {Component, OnInit, Input} from '@angular/core';
import {OrgService} from '@eg/core/org.service';
import {BibRecordService, BibRecordSummary
    } from '@eg/share/catalog/bib-record.service';
import {ServerStoreService} from '@eg/core/server-store.service';
import {CatalogService} from '@eg/share/catalog/catalog.service';

@Component({
  selector: 'eg-bib-summary',
  templateUrl: 'bib-summary.component.html',
  styleUrls: ['bib-summary.component.css']
})
export class BibSummaryComponent implements OnInit {

    initDone = false;

    // True / false if the display is vertically expanded
    private _exp: boolean;
    set expand(e: boolean) {
        this._exp = e;
        if (this.initDone) {
            this.saveExpandState();
        }
    }
    get expand(): boolean { return this._exp; }

    // If provided, the record will be fetched by the component.
    @Input() recordId: number;

    // Otherwise, we'll use the provided bib summary object.
    summary: BibRecordSummary;
    @Input() set bibSummary(s: any) {
        this.summary = s;
        if (this.initDone && this.summary) {
            this.summary.getBibCallNumber();
        }
    }

    constructor(
        private bib: BibRecordService,
        private org: OrgService,
        private store: ServerStoreService,
        private cat: CatalogService
    ) {}

    ngOnInit() {

        if (this.summary) {
            this.summary.getBibCallNumber();
        } else {
            if (this.recordId) {
                this.loadSummary();
            }
        }

        this.store.getItem('eg.cat.record.summary.collapse')
        .then(value => this.expand = !value)
        .then(() => this.initDone = true);
    }

    saveExpandState() {
        this.store.setItem('eg.cat.record.summary.collapse', !this.expand);
    }

    loadSummary(): void {
        this.bib.getBibSummary(this.recordId).toPromise()
        .then(summary => {
            summary.getBibCallNumber();
            this.bib.fleshBibUsers([summary.record]);
            this.summary = summary;
        });
    }

    orgName(orgId: number): string {
        if (orgId) {
            return this.org.get(orgId).shortname();
        }
    }

    iconFormatLabel(code: string): string {
        return this.cat.iconFormatLabel(code);
    }
}


