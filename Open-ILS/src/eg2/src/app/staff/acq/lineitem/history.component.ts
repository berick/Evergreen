import {Component, OnInit, Input, Output} from '@angular/core';
import {IdlObject} from '@eg/core/idl.service';

@Component({
  templateUrl: 'history.component.html',
  selector: 'eg-lineitem-history'
})
export class LineitemHistoryComponent {
    @Input() li: IdlObject;
}

