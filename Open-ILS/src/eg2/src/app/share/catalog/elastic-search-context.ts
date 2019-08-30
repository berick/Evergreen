import {IdlObject} from '@eg/core/idl.service';
import {CatalogSearchContext} from './search-context';

class ElasticSearchParams {
    search_org: number;
    search_depth: number;
    available: boolean;
    sort: any[] = [];
    query: any = {bool: {must: [], filter: []}};
}

export class ElasticSearchContext extends CatalogSearchContext {


    // The UI is ambiguous re: mixing ANDs and ORs.
    // Here booleans are grouped ANDs first, then each OR is given its own node.
    compileTerms(params: ElasticSearchParams) {

        const ts = this.termSearch;
        const terms: any = {
            bool: {
                should: [
                    {bool: {must: []}} // ANDs
                    // ORs
                ]
            }
        };

        ts.joinOp.forEach((op, idx) => {
            let matchOp = 'match';

            // The 'and' operator here tells EL to treat multi-word search
            // terms as an ANDed pair (e.g. "harry potter" = "harry and potter")
            let operator = 'and';

            switch (ts.matchOp[idx]) {
                case 'phrase':
                    matchOp = 'match_phrase';
                    operator = null;
                    break;
                case 'nocontains':
                    matchOp = 'must_not';
                    break;
                case 'exact':
                    matchOp = 'term';
                    operator = null;
                    break;
                case 'starts':
                    matchOp = 'match_phrase_prefix';
                    operator = null;
                    break;
            }

            let node: any = {};
            node[matchOp] = {};

            if (operator) {
                node[matchOp][ts.fieldClass[idx]] = 
                    {query: ts.query[idx], operator: operator};
            } else {
                node[matchOp][ts.fieldClass[idx]] = ts.query[idx];
            }

            if (matchOp === 'must_not') {
                // adds a boolean sub-node
                node = {bool: node};
            }

            if (ts.joinOp[idx] === 'or') {
                terms.bool.should.push(node);
            } else {
                terms.bool.should[0].bool.must.push(node);
            }
        });

        params.query.bool.must.push(terms);
    }

    addFilter(params: ElasticSearchParams, name: string, value: any) {
        if (value === ''   || 
            value === null || 
            value === undefined) { return; }

        const node: any = {term: {}};
        node.term[name] = value;
        params.query.bool.filter.push(node);
    }

    compileTermSearchQuery(): any {
        const ts = this.termSearch;
        const params = new ElasticSearchParams();

        params.available = ts.available;

        if (this.sort) {
            // e.g. title, title.descending => [{title => 'desc'}]
            const parts = this.sort.split(/\./);
            const sort: any = {};
            sort[parts[0]] = parts[1] ? 'desc' : 'asc';
            params.sort = [sort];
        }

        if (ts.date1 && ts.dateOp) {
            switch (ts.dateOp) {
                case 'is':
                    this.addFilter(params, 'date1', ts.date1);
                    break;
                case 'before':
                    this.addFilter(params, 'range', {date1: {'lt': ts.date1}});
                    break;
                case 'after':
                    this.addFilter(params, 'range', {date1: {'gt': ts.date1}});
                    break;
                case 'between':
                    if (ts.date2) {
                        this.addFilter(params, 'range', 
                            {date1: {'gt': ts.date1, 'lt': ts.date2}});
                    }
            }
        }

        this.compileTerms(params);
        params.search_org = this.searchOrg.id();

        if (this.global) {
            params.search_depth = this.org.root().ou_type().depth();
        }

        // PENDING DEV
        /*
        if (ts.copyLocations[0] !== '') {
            str += ' locations(' + ts.copyLocations + ')';
        }
        */

        if (ts.format) {
            this.addFilter(params, ts.formatCtype, ts.format);
        }

        Object.keys(ts.ccvmFilters).forEach(field => {
            ts.ccvmFilters[field].forEach(value => {
                if (value !== '') {
                    this.addFilter(params, field, value);
                }
            });
        });

        ts.facetFilters.forEach(f => {
            this.addFilter(params, 
                `${f.facetClass}:${f.facetName}`, f.facetValue);
        });

        return params;
    }

    getApiName(): string {

        // Elastic covers only a subset of available search types.
        if (!this.termSearch.isSearchable() || 
            this.termSearch.groupByMetarecord || 
            this.termSearch.fromMetarecord
        ) {
            return super.getApiName();
        }

        return this.isStaff ?
            'open-ils.search.elastic.bib_search.staff' :
            'open-ils.search.elastic.bib_search';
    }
}

