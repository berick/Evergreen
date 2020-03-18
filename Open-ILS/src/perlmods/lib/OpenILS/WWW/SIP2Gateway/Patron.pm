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
#
# ---------------------------------------------------------------
# Code borrows heavily and sometimes copies directly from from
# ../SIP* and SIPServer*
# ---------------------------------------------------------------
package OpenILS::WWW::SIP2Gateway::Patron;
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

sub get_patron_details {
    my ($class, %params) = @_;

    my $session = $params{session};
    my $instconf = $params{instconf};
    my $barcode = $params{barcode};
    my $password = $params{password};

    my $e = new_editor();
    my $details = {};

    my $card = $e->search_actor_card([{
        barcode => $barcode
    }, {
        flesh => 3,
        flesh_fields => {
            ac => [qw/usr/],
            au => [qw/
                billing_address
                mailing_address
                profile
                stat_cat_entries
            /],
            actscecm => [qw/stat_cat/]
        }
    }])->[0];

    my $patron = $details->{patron} = $card->usr;
    $patron->card($card);

    # We only attempt to verify the password if one is provided.
    return undef if defined $password &&
        !$U->verify_migrated_user_password($e, $patron->id, $password);

    my $penalties = get_patron_penalties($session, $patron);

    set_patron_privileges($session, $instconf, $details, $penalties);

    $details->{too_many_overdue} = 1 if
        grep {$_->{id} == OILS_PENALTY_PATRON_EXCEEDS_OVERDUE_COUNT}
        @$penalties;

    $details->{too_many_fines} = 1 if
        grep {$_->{id} == OILS_PENALTY_PATRON_EXCEEDS_FINES}
        @$penalties;

    set_patron_summary_items($session, $instconf, $details, %params);

    return $details;
}


# Sets:
#    holds_count
#    overdue_count
#    out_count
#    fine_count
#    recall_count
#    unavail_holds_count
sub set_patron_summary_items {
    my ($session, $instconf, $details, %params) = @_;

    my $patron = $details->{patron};
    my $start_item = $params{summary_start_item} || 0;
    my $end_item = $params{summary_end_item} || 10;
    my $list_items = $params{summary_list_items};

    my $e = new_editor();

    my $holds_where = {
        usr => $patron->id,
        fulfillment_time => undef,
        cancel_time => undef
    };

    $holds_where->{current_shelf_lib} = {'=' => {'+ahr' => 'pickup_lib'}} 
        if $instconf->{msg64_hold_items_available};

    my $hold_ids = $e->json_query({
        select => {ahr => ['id']},
        from => 'ahr',
        where => {'+ahr' => $holds_where}
    });

    $details->{holds_count} = scalar(@$hold_ids);

    my $circ_ids = $e->retrieve_action_open_circ_list($patron->id);
    my $overdue_ids = [ grep {$_ > 0} split(',', $circ_ids->overdue) ];
    my $out_ids = [ grep {$_ > 0} split(',', $circ_ids->out) ];

    $details->{overdue_count} = scalar(@$overdue_ids);
    $details->{out_count} = scalar(@$out_ids) + scalar(@$overdue_ids);

    $details->{recall_count} = undef; # not supported

    my $xacts = $U->simplereq(
        'open-ils.actor',                                
        'open-ils.actor.user.transactions.history.have_balance',               
        $session->account->{authtoken},
        $patron->id
    );

    $details->{fine_count} = scalar(@$xacts);

    # TODO: unavail holds count; summary details request
}

sub set_patron_privileges {
    my ($session, $instconf, $details, $penalties) = @_;
    my $patron = $details->{patron};

    my $expire = DateTime::Format::ISO8601->new
        ->parse_datetime(clean_ISO8601($patron->expire_date));

    if ($expire < DateTime->now) {
        $logger->info(
            "SIP2 Patron account is expired; all privileges blocked");
        $details->{charge_denied} = 1;
        $details->{recall_denied} = 1;
        $details->{renew_denied} = 1;
        $details->{holds_denied} = 1;
        return;
    }

    # Non-expired patrons are allowed all privileges when 
    # patron_status_permit_all is true.
    return if $instconf->{patron_status_permit_all};

    my $blocked = (
           $patron->barred eq 't'
        || $patron->active eq 'f'
        || $patron->card->active eq 'f'
    );

    my @block_tags = map {$_->{block_list}} grep {$_->{block_list}} @$penalties;

    return unless $blocked || @block_tags; # no blocks remain

    $details->{holds_denied} = ($blocked || grep {$_ =~ /HOLD/} @block_tags);

    # Ignore loan-related blocks?
    return if $instconf->{patron_status_permit_loans};

    $details->{charge_denied} = ($blocked || grep {$_ =~ /CIRC/} @block_tags);
    $details->{renew_denied} = ($blocked || grep {$_ =~ /RENEW/} @block_tags);

    # In evergreen, patrons cannot create Recall holds directly, but that
    # doesn't mean they would not have said privilege if the functionality
    # existed.  Base the ability to perform recalls on whether they have
    # checkout and holds privilege, since both would be needed for recalls.
    $details->{recall_denied} = 
        ($details->{charge_denied} || $details->{holds_denied});
}

# Returns an array of penalty hashes with keys "id" and "block_list"
sub get_patron_penalties {
    my ($session, $patron) = @_;

    return new_editor()->json_query({
        select => {csp => ['id', 'block_list']},
        from => {ausp => 'csp'},
        where => {
            '+ausp' => {
                usr => $patron->id,
                '-or' => [
                    {stop_date => undef},
                    {stop_date => {'>' => 'now'}}
                ],
                org_unit => 
                    $U->get_org_full_path($session->account->{login}->ws_ou)
            }
        }
    });
}




1;
