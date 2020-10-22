import {Injectable, EventEmitter} from '@angular/core';
import {tap} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CatalogSearchContext} from './search-context';
import {RequestBodySearch, MatchQuery, MultiMatchQuery, TermsQuery, Query, Sort,
    PrefixQuery, NestedQuery, BoolQuery, TermQuery, WildcardQuery, RangeQuery,
    QueryStringQuery} from 'elastic-builder';

@Injectable()
export class ElasticService {

    enabled: boolean;
    ebfMap: {[id: number]: IdlObject} = {};

    constructor(
        private idl: IdlService,
        private net: NetService,
        private org: OrgService,
        private pcrud: PcrudService
    ) {}

    init(): Promise<any> {
        return Promise.resolve();
    }

    // Returns true if Elastic can provide search results.
    canSearch(ctx: CatalogSearchContext): boolean {
        if (!this.enabled) { return false; }

        if (ctx.marcSearch.isSearchable()) { return true; }

        if ( ctx.termSearch.isSearchable() &&
            !ctx.termSearch.hasBrowseEntry) {
            return true;
        }

        if (ctx.identSearch.isSearchable() &&
            ctx.identSearch.queryType !== 'item_barcode' &&
            ctx.identSearch.queryType !== 'identifier|tcn') {
            return true;
        }

        return false;
    }

    // For API consistency, returns an array of arrays whose first
    // entry within each sub-array is a record ID.
    performSearch(ctx: CatalogSearchContext): Promise<any> {

        const requestBody = this.compileRequestBody(ctx);

        let method = ctx.termSearch.isMetarecordSearch() ?
            'open-ils.search.elastic.bib_search.metabib' :
            'open-ils.search.elastic.bib_search';

        if (ctx.isStaff) { method += '.staff'; }

        // Extract just the bits that get sent to ES.
        const elasticStruct: Object = requestBody.toJSON();

        console.debug(JSON.stringify(elasticStruct));

        const options: any = {search_org: ctx.searchOrg.id()};
        if (ctx.global) {
            options.search_depth = this.org.root().ou_type().depth();
        }
        if (ctx.termSearch.available) {
            options.available = true;
        }

        return this.net.request(
            'open-ils.search', method, elasticStruct, options
        ).toPromise();
    }

    compileRequestBody(ctx: CatalogSearchContext): RequestBodySearch {

        const search = new RequestBodySearch();

        search.size(ctx.pager.limit);
        search.from(ctx.pager.offset);

        const rootNode = new BoolQuery();

        if (ctx.termSearch.isSearchable()) {
            this.addFieldSearches(ctx, rootNode);
        } else if (ctx.marcSearch.isSearchable()) {
            this.addMarcSearches(ctx, rootNode);
        } else if (ctx.identSearch.isSearchable()) {
            this.addIdentSearches(ctx, rootNode);
        }

        this.addFilters(ctx, rootNode);
        this.addSort(ctx, search);

        search.query(rootNode);

        return search;
    }

    addSort(ctx: CatalogSearchContext, search: RequestBodySearch) {

        if (ctx.sort) { // e.g. title, title.descending

            const parts = ctx.sort.split(/\./);
            search.sort(new Sort(parts[0], parts[1] ? 'desc' : 'asc'));

        } else {

            // Sort by match score by default.
            search.sort(new Sort('_score', 'desc'));
        }
    }

    addFilters(ctx: CatalogSearchContext, rootNode: BoolQuery) {
        const ts = ctx.termSearch;

        if (ts.format) {
            rootNode.filter(new TermQuery(ts.formatCtype, ts.format));
        }

        Object.keys(ts.ccvmFilters).forEach(field => {
            // TermsQuery required since there may be multiple filter
            // values for a given CCVM.  These are treated like OR filters.
            const values: string[] = ts.ccvmFilters[field].filter(v => v !== '');
            if (values.length > 0) {
                rootNode.filter(new TermsQuery(field, values));
            }
        });

        ts.facetFilters.forEach(f => {
            if (f.facetValue !== '') {
                rootNode.filter(new TermQuery(
                    `${f.facetClass}|${f.facetName}|facet`, f.facetValue));
            }
        });

        if (ts.copyLocations[0] !== '') {
            const locQuery =
                new TermsQuery('holdings.location', ts.copyLocations);

            rootNode.filter(new NestedQuery(locQuery, 'holdings'));
        }

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

        if (ts.fromMetarecord) {
            rootNode.filter(new TermQuery('metarecord', ts.fromMetarecord));
        }
    }


    addIdentSearches(ctx: CatalogSearchContext, rootNode: BoolQuery) {
        rootNode.must(
            new TermQuery(ctx.identSearch.queryType, ctx.identSearch.value));
    }

    addMarcSearches(ctx: CatalogSearchContext, rootNode: BoolQuery) {
        const ms = ctx.marcSearch;

        ms.values.forEach((value, idx) => {
            if (value === '' || value === null) { return; }

            const marcQuery = new BoolQuery();
            const tag = ms.tags[idx];
            const subfield = ms.subfields[idx];
            const matchOp = ms.matchOp[idx];

            console.log('MATCH OP IS', matchOp, 'value is', value);
            this.appendMatchOp(
                marcQuery, matchOp, 'marc.value.text*', 'marc.value', value);

            if (tag) {
                marcQuery.must(new TermQuery('marc.tag', tag));
            }

            if (subfield) {
                marcQuery.must(new TermQuery('marc.subfield', subfield));
            }

            rootNode.must(new NestedQuery(marcQuery, 'marc'));
        });
    }

    addFieldSearches(ctx: CatalogSearchContext, rootNode: BoolQuery) {
        const ts = ctx.termSearch;
        let boolNode: BoolQuery;
        const shouldNodes: Query[] = [];

        if (ts.joinOp.filter(op => op === '||').length > 0) {
            // Searches containing ORs require a series of boolean buckets.
            boolNode = new BoolQuery();
            shouldNodes.push(boolNode);

        } else {
            // Searches composed entirely of ANDed terms can live on the
            // root boolean AND node.
            boolNode = rootNode;
        }

        ts.joinOp.forEach((op, idx) => {

            if (op === '||') {
                // Start a new OR sub-branch
                // op on the first query term will never be 'or'.
                boolNode = new BoolQuery();
                shouldNodes.push(boolNode);
            }

            this.addSearchField(ctx, idx, boolNode);
        });

        if (shouldNodes.length > 0) {
            rootNode.should(shouldNodes);
        }
    }


    addSearchField(ctx: CatalogSearchContext, idx: number, boolNode: BoolQuery) {
        const ts = ctx.termSearch;
        const value = ts.query[idx];

        if (value === '' || value === null) { return; }

        const matchOp = ts.matchOp[idx];
        let fieldClass = ts.fieldClass[idx];

        if (fieldClass === 'jtitle') {
            // Presented as a search class, but it's really a special
            // title search.
            fieldClass = 'title';
            ts.ccvmFilters.bib_level.push('s');

        } else if (fieldClass === 'keyword' &&
            matchOp === 'contains' && value.match(/:/)) {

            // A search where 'keyword' 'contains' a value with a ':'
            // character is assumed to be a complex / query string search.
            // NOTE: could handle this differently, e.g. provide an escape
            // character (e.g. !title:potter), a dedicated matchOp, etc.
            boolNode.must(
                new QueryStringQuery(value)
                    .defaultOperator('AND')
                    .defaultField('keyword.text')
            );

            return;
        }

        // Identifier indices don't have text variations
        const textIndex = fieldClass.match('identifier') ?
            fieldClass : `${fieldClass}.text*`;

        this.appendMatchOp(boolNode, matchOp, textIndex, fieldClass, value);
    }

    appendMatchOp(boolNode: BoolQuery, matchOp: string,
        textIndex: string, termIndex: string, value: string) {

        let query;

        switch (matchOp) {
            case 'contains':
                query = new MultiMatchQuery([textIndex], value);
                query.operator('and');
                query.type('most_fields');
                boolNode.must(query);
                return;

            // Use full text searching for "contains phrase".  We could
            // also support exact phrase searches with wildcard (term)
            // queries, such that no text analysis occured.
            case 'phrase':
                query = new MultiMatchQuery([textIndex], value);
                query.type('phrase');
                boolNode.must(query);
                return;

            case 'nocontains':
                query = new MultiMatchQuery([textIndex], value);
                query.operator('and');
                query.type('most_fields');
                boolNode.mustNot(query);
                return;

            // "containsexact", "exact", "starts" searches use term
            // searches instead of full-text searches.
            case 'containsexact':
                query = new WildcardQuery(termIndex, `*${value}*`);
                boolNode.must(query);
                return;

            case 'exact':
                query = new TermQuery(termIndex, value);
                boolNode.must(query);
                return;

            case 'starts':
                query = new PrefixQuery(termIndex, value);
                boolNode.must(query);
                return;
        }
    }


    // Elastic facets are grouped by elastic.bib_field entries.
    formatFacets(facets: any) {
        const facetData = {};
        Object.keys(facets).forEach(ebfId => {
            const facetHash = facets[ebfId];

            const ebfData = [];
            Object.keys(facetHash).forEach(value => {
                const count = facetHash[value];
                ebfData.push({value : value, count : count});
            });

            const parts = ebfId.split('|');
            const fclass = parts[0];
            const fname = parts[1];

            if (!facetData[fclass]) { facetData[fclass] = {}; }

            facetData[fclass][fname] = {
                // 'cmfLabel' is what the higher-level code seeks
                cmfLabel : ebfId, // TODO
                valueList : ebfData.sort((a, b) => {
                    if (a.count > b.count) { return -1; }
                    if (a.count < b.count) { return 1; }
                    return a.value < b.value ? -1 : 1;
                })
            };
        });

        return facetData;
    }
}

