import {Injectable} from '@angular/core';
import {Location} from '@angular/common';
import {Observable, Observer, of, from} from 'rxjs';
import {Router, Resolve, RouterStateSnapshot,
        ActivatedRoute, ActivatedRouteSnapshot} from '@angular/router';
import {AuthService} from '@eg/core/auth.service';

@Injectable()
export class SckoResolver implements Resolve<Observable<any>> {

    constructor(
        private router: Router,
        private route: ActivatedRoute,
        private ngLocation: Location,
        private auth: AuthService
    ) {}

    resolve(
        route: ActivatedRouteSnapshot,
        state: RouterStateSnapshot): Observable<any> {

        this.auth.storePrefix = 'eg.scko';

        if (this.auth.token() === null) {
            return from(this.router.navigate(
              ['/staff/login'],
              {queryParams: {route_to: '/eg/scko', auth_domain: 'eg.scko'}}
            ));
        } else {
            return of(true);
        }
    }
}


