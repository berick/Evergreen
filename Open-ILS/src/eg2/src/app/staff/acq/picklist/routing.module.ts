import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {PicklistComponent} from './picklist.component';
import {PicklistSummaryComponent} from './summary.component';
import {LineitemListComponent} from '../lineitem/lineitem-list.component';
import {LineitemDetailComponent} from '../lineitem/detail.component';
import {LineitemCopiesComponent} from '../lineitem/copies.component';

const routes: Routes = [{
  path: ':picklistId',
  component: PicklistComponent,
  children : [{
    path: '',
    component: LineitemListComponent
  }, {
    path: 'lineitem/:lineitemId/detail',
    component: LineitemDetailComponent
  }, {
    path: 'lineitem/:lineitemId/items',
    component: LineitemCopiesComponent
  }]
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class PicklistRoutingModule {}
