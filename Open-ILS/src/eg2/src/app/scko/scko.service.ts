import {Injectable, EventEmitter} from '@angular/core';
import {NetService} from '@eg/core/net.service';
import {AuthService} from '@eg/core/auth.service';
import {EventService, EgEvent} from '@eg/core/event.service';
import {IdlService, IdlObject} from '@eg/core/idl.service';
import {StoreService} from '@eg/core/store.service';
import {ServerStoreService} from '@eg/core/server-store.service';

@Injectable({providedIn: 'root'})
export class SckoService {

    // Currently active patron account object.
    patron: IdlObject;

    constructor(
        private net: NetService,
        public auth: AuthService
    ) {}
}



