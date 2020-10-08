import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {PicklistComponent} from './picklist.component';

const routes: Routes = [{
  path: ':listId',
  component: PicklistComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class PicklistRoutingModule {}
