import {Injectable, EventEmitter} from '@angular/core';
import {tap} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CatalogSearchContext} from './search-context';
import {RequestBodySearch, MatchQuery, MultiMatchQuery, 
    Sort, BoolQuery, TermQuery} from 'elastic-builder';

@Injectable()
export class ElasticService {

    bibFields: IdlObject[] = [];

    constructor(
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService
    ) {}

    init(): Promise<any> {
        if (this.bibFields.length > 0) {
            return Promise.resolve();
        }

        return this.pcrud.search('ebf', {search_field: 't'})
            .pipe(tap(field => this.bibFields.push(field)))
            .toPromise();
    }

    canSearch(ctx: CatalogSearchContext): boolean {
        
        if (ctx.marcSearch.isSearchable()) { return true; }

        if ( ctx.termSearch.isSearchable() &&
            !ctx.termSearch.groupByMetarecord &&
            !ctx.termSearch.fromMetarecord
        ) { return true; }

        return false;
    }


    // For API consistency, returns an array of arrays whose first
    // entry within each sub-array is a record ID.
    performSearch(ctx: CatalogSearchContext): Promise<any> {

        const requestBody = this.compileRequestBody(ctx);

        const method = ctx.isStaff ?
            'open-ils.search.elastic.bib_search.staff' :
            'open-ils.search.elastic.bib_search';

        // Extract just the bits that get sent to ES.
        const elasticStruct: Object = requestBody.toJSON();

        console.log(JSON.stringify(elasticStruct));

        const options: any = {search_org: ctx.searchOrg.id()};
        if (ctx.global) {
            options.search_depth = this.org.root().ou_type().depth();
        }

        return this.net.request(
            'open-ils.search', method, elasticStruct, options
        ).toPromise();
    }

    compileRequestBody(ctx: CatalogSearchContext): RequestBodySearch {

        const search = new RequestBodySearch()
        search.source(['id']); // only retrieve IDs
        search.size(ctx.pager.limit)
        search.from(ctx.pager.offset);

        const rootAnd = new BoolQuery();

        this.compileTermSearch(ctx, rootAnd);
        this.addFilters(ctx, rootAnd);
        this.addSort(ctx, search);

        search.query(rootAnd);

        return search;
    }

    addSort(ctx: CatalogSearchContext, search: RequestBodySearch) {

        if (!ctx.sort) { return; }

        // e.g. title, title.descending => [{title => 'desc'}]
        const parts = ctx.sort.split(/\./);
        search.sort(new Sort(parts[0], parts[1] ? 'desc' : 'asc'));
    }

    addFilters(ctx: CatalogSearchContext, rootAnd: BoolQuery) {
        const ts = ctx.termSearch;

        if (ts.format) {
            rootAnd.filter(new TermQuery(ts.formatCtype, ts.format));
        }

        Object.keys(ts.ccvmFilters).forEach(field => {
            ts.ccvmFilters[field].forEach(value => {
                if (value !== '') {
                    rootAnd.filter(new TermQuery(field, value));
                }
            });
        });

        ts.facetFilters.forEach(f => {
            if (f.facetValue !== '') {
                rootAnd.filter(new TermQuery(
                    `${f.facetClass}|${f.facetName}`, f.facetValue));
            }
        });
    }

    compileTermSearch(ctx: CatalogSearchContext, rootAnd: BoolQuery) {

        // TODO: boolean OR support.  
        const ts = ctx.termSearch;
        ts.joinOp.forEach((op, idx) => {

            const fieldClass = ts.fieldClass[idx];
            const textIndex = `${fieldClass}|*text*`;
            const value = ts.query[idx];
            let query;

            switch (ts.matchOp[idx]) {

                case 'contains':
                    query = new MultiMatchQuery([textIndex], value);
                    query.operator('and');
                    query.type('most_fields');
                    rootAnd.must(query);
                    break;

                case 'phrase':
                    query = new MultiMatchQuery([textIndex], value);
                    query.type('phrase');
                    rootAnd.must(query);
                    break;

                case 'nocontains':
                    query = new MultiMatchQuery([textIndex], value);
                    query.operator('and');
                    query.type('most_fields');
                    rootAnd.mustNot(query);
                    break;

                case 'exact':

                    // TODO: these need to be grouped first by field
                    // so we can search multiple values on a singel term
                    // via 'terms' search.

                    /*
                    const shoulds = [];
                    this.bibFields.filter(f => (
                        f.search_field() === 't' && 
                        f.search_group() === fieldClass
                    )).forEach(field => {
                        shoulds.push(
                    });

                    const should = new BoolQuery();
                    */
                    break;

                case 'starts':
                    query = new MultiMatchQuery([textIndex], value);
                    query.type('phrase_prefix');
                    rootAnd.must(query);
                    break;
            }
        });
    }


}

