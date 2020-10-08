import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {PoComponent} from './po.component';
import {PrintComponent} from './print.component';

const routes: Routes = [{
    path: ':id/printer',
    component: PrintComponent
}, {
    path: ':id/printer/print',
    component: PrintComponent
}, {
    path: ':id/printer/print/close',
    component: PrintComponent
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule],
  providers: []
})

export class PoRoutingModule {}
