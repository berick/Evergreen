import {NgModule} from '@angular/core';
import {RouterModule, Routes} from '@angular/router';
import {SckoResolver} from './resolver.service';
import {SckoComponent} from './scko.component';

const routes: Routes = [{
  path: '',
  component: SckoComponent,
  resolve: {sckoResolver : SckoResolver},
  /*
  children: [{

  }]
  */
}];

@NgModule({
  imports: [RouterModule.forChild(routes)],
  exports: [RouterModule]
})

export class SckoRoutingModule {}

