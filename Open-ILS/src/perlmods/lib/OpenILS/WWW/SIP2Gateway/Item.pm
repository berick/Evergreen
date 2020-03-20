# ---------------------------------------------------------------
# Copyright (C) 2020 King County Library System
# Bill Erickson <berickxx@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
package OpenILS::WWW::SIP2Gateway::Item;
use strict; use warnings;
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::System;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenILS::Const qw/:const/;
my $U = 'OpenILS::Application::AppUtils';

sub get_item_details {
    my ($class, %params) = @_;

    my $session = $params{session};
    my $instconf = $params{instconf};
    my $barcode = $params{barcode};

    my $e = new_editor();

    my $item = $e->search_asset_copy([{
        barcode => $barcode,
        deleted => 'f'
    }, {
        flesh => 3,
        flesh_fields => {
            acp => [qw/circ_lib call_number
                status stat_cat_entry_copy_maps circ_modifier/],
            acn => [qw/owning_lib record/],
            bre => [qw/flat_display_entries/],
            ascecm => [qw/stat_cat stat_cat_entry/],
        }
    }])->[0];

    return undef unless $item;

    my $details = {item => $item};

    $details->{circ} = $e->search_action_circulation([{
        target_copy => $item->id,
        checkin_time => undef,
        '-or' => [
            {stop_fines => undef},
            {stop_fines => [qw/MAXFINES LONGOVERDUE/]},
        ]
    }, {
        flesh => 2,
        flesh_fields => {circ => ['usr'], au => ['card']}
    }])->[0];

    if ($details->{circ}) {

        my $due_date = DateTime::Format::ISO8601->new->
            parse_datetime(clean_ISO8601($details->{circ}->due_date));

        $details->{due_date} =
            $instconf->{due_date_use_sip_date_format} ?
            sipdate($due_date) :
            $due_date->strftime('%F %T');
    }


    if ($item->status->id == OILS_COPY_STATUS_IN_TRANSIT) {
        $details->{transit} = $e->search_action_transit_copy([{
            target_copy => $item->id,
            dest_recv_time => undef,
            cancel_time => undef
        },{
            flesh => 1,
            flesh_fields => {atc => ['dest']}
        }])->[0];
    }

    if ($item->status->id == OILS_COPY_STATUS_ON_HOLDS_SHELF || (
        $details->{transit} &&
        $details->{transit}->copy_status == OILS_COPY_STATUS_ON_HOLDS_SHELF)) {

        $details->{hold} = $e->search_action_hold_request([{
            current_copy        => $item->id,
            capture_time        => {'!=' => undef},
            cancel_time         => undef,
            fulfillment_time    => undef
        }, {
            limit => 1,
            flesh => 1,
            flesh_fields => {ahr => ['pickup_lib']}
        }])->[0];
    }


    if ($details->{hold}) {
        my $pickup_date = $details->{hold}->shelf_expire_time;
        $details->{hold_pickup_date} =
            $pickup_date ? sipdate($pickup_date) : undef;
    }

    my ($title_entry) = grep {$_->name eq 'title'}
        @{$item->call_number->record->flat_display_entries};

    $details->{title} = $title_entry ? $title_entry->value : '';

    # Same as ../SIP*
    $details->{hold_queue_length} = $details->{hold} ? 1 : 0;

    $details->{circ_status} = circulation_status($item->status->id);

    $details->{fee_type} =
        ($item->deposit_amount > 0.0 && $item->deposit eq 'f') ?
        '06' : '01';

    my $cmod = $item->circ_modifier;
    $details->{magnetic_media} = $cmod && $cmod->magnetic_media eq 't';
    $details->{media_type} = $cmod ? $cmod->sip2_media_type : '001';

    return $details;
}

# Maps item status to SIP circulation status constants.
sub circulation_status {
    my $stat = shift;

    return '02' if $stat == OILS_COPY_STATUS_ON_ORDER;
    return '03' if $stat == OILS_COPY_STATUS_AVAILABLE;
    return '04' if $stat == OILS_COPY_STATUS_CHECKED_OUT;
    return '06' if $stat == OILS_COPY_STATUS_IN_PROCESS;
    return '08' if $stat == OILS_COPY_STATUS_ON_HOLDS_SHELF;
    return '09' if $stat == OILS_COPY_STATUS_RESHELVING;
    return '10' if $stat == OILS_COPY_STATUS_IN_TRANSIT;
    return '12' if (
        $stat == OILS_COPY_STATUS_LOST ||
        $stat == OILS_COPY_STATUS_LOST_AND_PAID
    );
    return '13' if $stat == OILS_COPY_STATUS_MISSING;

    return '01';
}

1;
