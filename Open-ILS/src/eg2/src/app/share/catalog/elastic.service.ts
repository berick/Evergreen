import {Injectable, EventEmitter} from '@angular/core';
import {tap} from 'rxjs/operators';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {OrgService} from '@eg/core/org.service';
import {NetService} from '@eg/core/net.service';
import {PcrudService} from '@eg/core/pcrud.service';
import {CatalogSearchContext} from './search-context';
import {RequestBodySearch, MatchQuery, MultiMatchQuery, TermsQuery, Query, Sort,
    PrefixQuery, NestedQuery, BoolQuery, TermQuery, RangeQuery} from 'elastic-builder';

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

    // Returns true if Elastic can provide search results.
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

        const search = new RequestBodySearch();

        search.source(['id']); // only retrieve IDs
        search.size(ctx.pager.limit);
        search.from(ctx.pager.offset);

        const rootNode = new BoolQuery();

        if (ctx.termSearch.isSearchable()) {
            this.addFieldSearches(ctx, rootNode);
        } else if (ctx.marcSearch.isSearchable()) {
            this.addMarcSearches(ctx, rootNode);
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
            search.sort(new Sort('_score', 'asc'));
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
        const fieldClass = ts.fieldClass[idx];
        const textIndex = `${fieldClass}|*text*`;
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
        }

        // Under the covers, searches on a field class are OR searches
        // across all fields within the class.  Unlike MultiMatch
        // searches (above) where this can be accomplished with field
        // name wildcards, term/prefix searches require explicit field
        // names.
        const shoulds: Query[] = [];

        this.getSearchFieldsForClass(fieldClass).forEach(field => {
            const fieldName = `${fieldClass}|${field.name()}`;
            if (matchOp === 'exact') {
                query = new TermQuery(fieldName, value);
            } else if (matchOp === 'starts') {
                query = new PrefixQuery(fieldName, value);
            }

            shoulds.push(query);
        });

        // Wrap the 'shoulds' in a 'must' so that at least one of
        // the shoulds must match for the group to match.
        boolNode.must(new BoolQuery().should(shoulds));
    }

    getSearchFieldsForClass(fieldClass: string): any[] {
        return this.bibFields.filter(f => (
            f.search_field() === 't' &&
            f.search_group() === fieldClass
        ));
    }
}

