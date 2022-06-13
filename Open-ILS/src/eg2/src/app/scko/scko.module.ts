import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {AudioService} from '@eg/share/util/audio.service';
import {TitleComponent} from '@eg/share/title/title.component';

import {SckoComponent} from './scko.component';
import {SckoRoutingModule} from './routing.module';

@NgModule({
  declarations: [
    SckoComponent,
  ],
  imports: [
    EgCommonModule,
    CommonWidgetsModule,
    SckoRoutingModule
  ]
})

export class SckoModule {}

