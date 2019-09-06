import {Injectable, EventEmitter} from '@angular/core';
import {tap} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CatalogSearchContext} from './search-context';
import {RequestBodySearch, MatchQuery, MultiMatchQuery, 
    Sort, NestedQuery, BoolQuery, TermQuery, RangeQuery} from 'elastic-builder';

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

        const rootNode = new BoolQuery();

        if (ctx.termSearch.isSearchable()) {
            this.addTermSearches(ctx, rootNode);
        } else if (ctx.marcSearch.isSearchable()) {
            this.addMarcSearches(ctx, rootNode);
        }
        this.addFilters(ctx, rootNode);
        this.addSort(ctx, search);

        search.query(rootNode);

        return search;
    }

    addSort(ctx: CatalogSearchContext, search: RequestBodySearch) {

        if (!ctx.sort) { return; }

        // e.g. title, title.descending
        const parts = ctx.sort.split(/\./);
        search.sort(new Sort(parts[0], parts[1] ? 'desc' : 'asc'));
    }

    addFilters(ctx: CatalogSearchContext, rootNode: BoolQuery) {
        const ts = ctx.termSearch;

        if (ts.format) {
            rootNode.filter(new TermQuery(ts.formatCtype, ts.format));
        }

        Object.keys(ts.ccvmFilters).forEach(field => {
            ts.ccvmFilters[field].forEach(value => {
                if (value !== '') {
                    rootNode.filter(new TermQuery(field, value));
                }
            });
        });

        ts.facetFilters.forEach(f => {
            if (f.facetValue !== '') {
                rootNode.filter(new TermQuery(
                    `${f.facetClass}|${f.facetName}`, f.facetValue));
            }
        });

        if (ts.date1 && ts.dateOp) {

            if (ts.dateOp === 'is') {

                rootNode.filter(new TermQuery('date1', ts.date1));

            } else {
                
                const range = new RangeQuery('date1');

                switch (ts.dateOp) {
                    case 'before':
                        range.lt(ts.date1);
                        break;
                    case 'after':
                        range.gt(ts.date1);
                        break;
                    case 'between':
                        range.gt(ts.date1);
                        range.lt(ts.date2);
                        break;
                }

                rootNode.filter(range);
            }
        }
    }

    addMarcSearches(ctx: CatalogSearchContext, rootNode: BoolQuery) {
        const ms = ctx.marcSearch;

        ms.values.forEach((value, idx) => {
            if (value === '' || value === null) { return; }
                
            const marcQuery = new BoolQuery();
            const tag = ms.tags[idx];
            const subfield = ms.subfields[idx];

            // Full-text search on the values
            const valMatch = new MultiMatchQuery(['marc.value*'], value);
            valMatch.operator('and');
            valMatch.type('most_fields');
            marcQuery.must(valMatch);

            if (tag) {
                marcQuery.must(new TermQuery('marc.tag', tag));
            }

            if (subfield) {
                marcQuery.must(new TermQuery('marc.subfield', subfield));
            }

            rootNode.must(new NestedQuery(marcQuery, 'marc'));
        });
    }

    addTermSearches(ctx: CatalogSearchContext, rootNode: BoolQuery) {

        // TODO: boolean OR support.  
        const ts = ctx.termSearch;
        ts.joinOp.forEach((op, idx) => {

            const value = ts.query[idx];

            const fieldClass = ts.fieldClass[idx];
            const textIndex = `${fieldClass}|*text*`;
            let query;

            switch (ts.matchOp[idx]) {

                case 'contains':
                    query = new MultiMatchQuery([textIndex], value);
                    query.operator('and');
                    query.type('most_fields');
                    rootNode.must(query);
                    break;

                case 'phrase':
                    query = new MultiMatchQuery([textIndex], value);
                    query.type('phrase');
                    rootNode.must(query);
                    break;

                case 'nocontains':
                    query = new MultiMatchQuery([textIndex], value);
                    query.operator('and');
                    query.type('most_fields');
                    rootNode.mustNot(query);
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
                    rootNode.must(query);
                    break;
            }
        });
    }
}

