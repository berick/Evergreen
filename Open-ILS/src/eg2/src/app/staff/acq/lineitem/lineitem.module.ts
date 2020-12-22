import {NgModule} from '@angular/core';
import {StaffCommonModule} from '@eg/staff/common.module';
import {HttpClientModule} from '@angular/common/http';
import {ItemLocationSelectModule
    } from '@eg/share/item-location-select/item-location-select.module';
import {LineitemRoutingModule} from './routing.module';
import {WorksheetComponent} from './worksheet.component';
import {LineitemService} from './lineitem.service';
import {LineitemComponent} from './lineitem.component';
import {LineitemNotesComponent} from './notes.component';
import {LineitemDetailComponent} from './detail.component';
import {LineitemOrderSummaryComponent} from './order-summary.component';
import {LineitemListComponent} from './lineitem-list.component';
import {LineitemCopiesComponent} from './copies.component';
import {LineitemBatchCopiesComponent} from './batch-copies.component';
import {LineitemCopyAttrsComponent} from './copy-attrs.component';

@NgModule({
  declarations: [
    LineitemComponent,
    LineitemListComponent,
    LineitemNotesComponent,
    LineitemDetailComponent,
    LineitemCopiesComponent,
    LineitemOrderSummaryComponent,
    LineitemBatchCopiesComponent,
    LineitemCopyAttrsComponent,
    WorksheetComponent
  ],
  exports: [
    LineitemListComponent
  ],
  imports: [
    StaffCommonModule,
    LineitemRoutingModule,
    ItemLocationSelectModule
  ],
  providers: [
    LineitemService
  ]
})

export class LineitemModule {
}
