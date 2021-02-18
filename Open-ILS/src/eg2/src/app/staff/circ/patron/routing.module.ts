import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {PatronComponent} from './patron.component';
import {BcSearchComponent} from './bcsearch.component';

const routes: Routes = [{
    path: '',
    pathMatch: 'full',
    redirectTo: 'search'
  }, {
    path: 'search',
    component: PatronComponent
  }, {
    path: 'bcsearch',
    component: BcSearchComponent
  }, {
    path: 'bcsearch/:barcode',
    component: BcSearchComponent
  }, {
    path: ':id/:tab',
    component: PatronComponent,
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class PatronRoutingModule {}
