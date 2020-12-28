import {Component, OnInit} from '@angular/core';
import {Router, ActivatedRoute, ParamMap} from '@angular/router';

@Component({
  templateUrl: 'po.component.html'
})
export class PoComponent implements OnInit {

    poId: number;

    constructor(
        private route: ActivatedRoute
    ) {}

    ngOnInit() {
        this.route.paramMap.subscribe((params: ParamMap) => {
            this.poId = +params.get('poId');
        });
    }
}

