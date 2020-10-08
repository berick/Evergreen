import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HttpClientModule} from '@angular/common/http';
import {PoRoutingModule} from './routing.module';
import {PoComponent} from './po.component';
import {PrintComponent} from './print.component';

@NgModule({
  declarations: [
    PoComponent,
    PrintComponent
  ],
  imports: [
    StaffCommonModule,
    PoRoutingModule
  ],
  providers: [
  ]
})

export class PoModule {
}
