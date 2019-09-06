import {IdlObject} from '@eg/core/idl.service';
import {CatalogSearchContext} from './search-context';

class ElasticSearchParams {
    search_org: number;
    search_depth: number;
    available: boolean;
    sort: any[] = [];
    searches: any[] = [];
    marc_searches: any[] = [];
    filters: any[] = [];
}

export class ElasticSearchContext extends CatalogSearchContext {

    // The UI is ambiguous re: mixing ANDs and ORs.
    // Here booleans are grouped ANDs first, then each OR is given its own node.
    compileTerms(params: ElasticSearchParams) {

        const ts = this.termSearch;

        ts.joinOp.forEach((op, idx) => {
            let matchOp = 'match';

            switch (ts.matchOp[idx]) {
                case 'phrase':
                    matchOp = 'match_phrase';
                    break;
                case 'nocontains':
                    matchOp = 'must_not';
                    break;
                case 'exact':
                    matchOp = 'term';
                    break;
                case 'starts':
                    matchOp = 'match_phrase_prefix';
                    break;
            }

            params.searches.push({
                field: ts.fieldClass[idx],
                match_op: matchOp,
                value: ts.query[idx]
            });
        });
    }

    addTermFilter(params: ElasticSearchParams, name: string, value: any) {
        if (value === ''   || 
            value === null || 
            value === undefined) { return; }

        // Multiple filter values for a single filter are OR'ed.
        for (let idx = 0; idx < params.filters.length; idx++) {
            const filter = params.filters[idx];

            if (filter.term && name in filter.term) {
                // Pluralize an existing filter
                filter.terms = {};
                filter.terms[name] = [filter.term[name], value];
                delete filter.term;
                return;

            } else if (filter.terms && name in filter.terms) {
                // Append a filter value to an already pluralized filter.
                filter.terms[name].push(value);
                return;
            }
        }

        // New filter type
        const node: any = {term: {}};
        node.term[name] = value;
        params.filters.push(node);
    }

    compileTermSearchQuery(): any {
        const ts = this.termSearch;
        const params = this.newParams();

        params.available = ts.available;

        if (ts.date1 && ts.dateOp) {
            const dateFilter: Object = {};
            switch (ts.dateOp) {
                case 'is':
                    this.addTermFilter(params, 'date1', ts.date1);
                    break;
                case 'before':
                    params.filters.push({range: {date1: {lt: ts.date1}}});
                    break;
                case 'after':
                    params.filters.push({range: {date1: {gt: ts.date1}}});
                    break;
                case 'between':
                    if (ts.date2) {
                        params.filters.push(
                            {range: {date1: {gt: ts.date1, lt: ts.date2}}});
                    }
            }
        }

        this.compileTerms(params);

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
            this.addTermFilter(params, ts.formatCtype, ts.format);
        }

        Object.keys(ts.ccvmFilters).forEach(field => {
            ts.ccvmFilters[field].forEach(value => {
                if (value !== '') {
                    this.addTermFilter(params, field, value);
                }
            });
        });

        ts.facetFilters.forEach(f => {
            this.addTermFilter(params, 
                `${f.facetClass}|${f.facetName}`, f.facetValue);
        });

        return params;
    }

    newParams(): ElasticSearchParams {
        const params = new ElasticSearchParams();
        /*
        params.limit = this.pager.limit;
        params.offset = this.pager.offset;
        */
        params.search_org = this.searchOrg.id()

        if (this.sort) {
            // e.g. title, title.descending => [{title => 'desc'}]
            const parts = this.sort.split(/\./);
            const sort: any = {};
            sort[parts[0]] = parts[1] ? 'desc' : 'asc';
            params.sort = [sort];
        }

        return params;
    }

    compileMarcSearchArgs(): any {
        const ms = this.marcSearch;
        const params = this.newParams();

        ms.values.forEach((val, idx) => {
            if (val !== '') {
                params.marc_searches.push({
                    tag: ms.tags[idx],
                    subfield: ms.subfields[idx] ? ms.subfields[idx] : null,
                    value: ms.values[idx]
                });
            }
        });

        return params;
    }

    /*
    getApiName(): string {

        // Elastic covers only a subset of available search types.
        if (this.marcSearch.isSearchable() || 
            (
                 this.termSearch.isSearchable() &&
                !this.termSearch.groupByMetarecord &&
                !this.termSearch.fromMetarecord
            )
        ) {

            return this.isStaff ?
                'open-ils.search.elastic.bib_search.staff' :
                'open-ils.search.elastic.bib_search';
        }
            
        // Fall back to existing APIs.
        return super.getApiName();
    }
    */
}

