import {NgModule} from '@angular/core';
import {EgCommonModule} from '@eg/common.module';
import {CommonWidgetsModule} from '@eg/share/common-widgets.module';
import {AudioService} from '@eg/share/util/audio.service';
import {TitleComponent} from '@eg/share/title/title.component';

import {SckoResolver} from './resolver.service';
import {SckoComponent} from './scko.component';
import {SckoRoutingModule} from './routing.module';
import {SckoService} from './scko.service';
import {SckoBannerComponent} from './banner.component';

@NgModule({
  declarations: [
    SckoComponent,
    SckoBannerComponent,
  ],
  imports: [
    EgCommonModule,
    CommonWidgetsModule,
    SckoRoutingModule
  ],
  providers: [
    SckoService,
    SckoResolver
  ]
})

export class SckoModule {}

