import {Component, OnInit, Input} from '@angular/core';
import {CatalogService} from '@eg/share/catalog/catalog.service';
import {CatalogUrlService} from '@eg/share/catalog/catalog-url.service';
import {CatalogSearchContext, FacetFilter} from '@eg/share/catalog/search-context';
import {StaffCatalogService} from '../catalog.service';

export const FACET_CONFIG = {
    display: [
        {facetClass : 'author',  facetOrder : ['combined']},
        {facetClass : 'subject', facetOrder : ['combined']},
        {facetClass : 'series',  facetOrder : ['seriestitle']}
    ],
    displayCount: 10
};

@Component({
  selector: 'eg-catalog-result-facets',
  templateUrl: 'facets.component.html'
})
export class ResultFacetsComponent implements OnInit {

    searchContext: CatalogSearchContext;
    facetConfig: any;

    constructor(
        private cat: CatalogService,
        private catUrl: CatalogUrlService,
        private staffCat: StaffCatalogService
    ) {
        this.facetConfig = FACET_CONFIG;
    }

    ngOnInit() {
        this.searchContext = this.staffCat.searchContext;
    }

    facetIsApplied(cls: string, name: string, value: string): boolean {
        return this.searchContext.termSearch.hasFacet(new FacetFilter(cls, name, value));
    }

    getFacetUrlParams(cls: string, name: string, value: string): any {
        const context = this.staffCat.cloneContext(this.searchContext);
        context.termSearch.toggleFacet(new FacetFilter(cls, name, value));
        context.pager.offset = 0;
        return this.catUrl.toUrlParams(context);
    }

    facetHasData(facetClass: string, name: string): boolean {
        return (
           this.searchContext.result.facetData[facetClass] &&
           this.searchContext.result.facetData[facetClass][name] &&
           this.searchContext.result.facetData[facetClass][name].valueList &&
           this.searchContext.result.facetData[facetClass][name].valueList.length > 0
        );
    }
}


