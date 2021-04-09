import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';

const routes: Routes = [{
  path: 'patron',
  loadChildren: () =>
    import('./patron/patron.module').then(m => m.PatronManagerModule)
}, {
  path: 'checkin',
  loadChildren: () =>
    import('./checkin/checkin.module').then(m => m.CheckinModule)
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class CircRoutingModule {}
