import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {LineitemComponent} from './lineitem.component';
import {WorksheetComponent} from './worksheet.component';

const routes: Routes = [{
  path: ':id/worksheet',
  component: WorksheetComponent
}, {
    path: ':id/worksheet/print',
    component: WorksheetComponent
}, {
    path: ':id/worksheet/print/close',
    component: WorksheetComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class LineitemRoutingModule {}
