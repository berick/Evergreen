import {Component, OnInit, Input, Output} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';

@Component({
  templateUrl: 'order-summary.component.html',
  selector: 'eg-lineitem-order-summary'
})
export class LineitemOrderSummaryComponent {
    @Input() li: IdlObject;
}

