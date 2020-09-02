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

    my $summary = $e->retrieve_money_open_user_summary($patron->id);
    $details->{balance_owed} = ($summary) ? $summary->balance_owed : 0;

    set_patron_summary_items($session, $instconf, $details, %params);
    set_patron_summary_list_items($session, $instconf, $details, %params);

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
    my $e = new_editor();

    $details->{recall_count} = 0; # not supported

    my $hold_ids = get_hold_ids($e, $instconf, $patron);
    $details->{holds_count} = scalar(@$hold_ids);

    my $unavail_hold_ids = get_hold_ids($e, $instconf, $patron, 1);
    $details->{unavail_holds_count} = scalar(@$unavail_hold_ids);

    $details->{overdue_count} = 0;
    $details->{out_count} = 0;

    my $circ_summary = $e->retrieve_action_open_circ_list($patron->id);
    if ($circ_summary) { # undef if no circs for user
        my $overdue_ids = [ grep {$_ > 0} split(',', $circ_summary->overdue) ];
        my $out_ids = [ grep {$_ > 0} split(',', $circ_summary->out) ];
        $details->{overdue_count} = scalar(@$overdue_ids);
        $details->{out_count} = scalar(@$out_ids) + scalar(@$overdue_ids);
    }

    my $xacts = $U->simplereq(
        'open-ils.actor',                                
        'open-ils.actor.user.transactions.history.have_balance',               
        $session->ils_authtoken,
        $patron->id
    );

    $details->{fine_count} = scalar(@$xacts);
}

sub get_hold_ids {
    my ($e, $instconf, $patron, $unavail, $offset, $limit) = @_;

    my $holds_where = {
        usr => $patron->id,
        fulfillment_time => undef,
        cancel_time => undef
    };

    if ($unavail) {
        $holds_where->{'-or'} = [
            {current_shelf_lib => undef},
            {current_shelf_lib => {'!=' => {'+ahr' => 'pickup_lib'}}}
        ];

    } else {

        $holds_where->{current_shelf_lib} = {'=' => {'+ahr' => 'pickup_lib'}} 
            if $instconf->{msg64_hold_items_available};
    }

    my $query = {
        select => {ahr => ['id']},
        from => 'ahr',
        where => {'+ahr' => $holds_where}
    };

    $query->{offset} = $offset if $offset;
    $query->{limit} = $limit if $limit;

    my $id_hashes = $e->json_query($query);

    return [map {$_->{id}} @$id_hashes];
}

sub set_patron_summary_list_items {
    my ($session, $instconf, $details, %params) = @_;
    my $e = new_editor();

    my $list_items = $params{summary_list_items};
    my $offset = $params{summary_start_item} || 0;
    my $end_item = $params{summary_end_item} || 10;
    my $limit = $end_item - $offset;

    add_hold_items($e, $session, $instconf, $details, $offset, $limit)
        if $list_items eq 'hold_items';
}

sub add_hold_items {
    my ($e, $session, $instconf, $details, $offset, $limit) = @_;

    my $patron = $details->{patron};
    my $format = $instconf->{msg64_hold_datatype} || '';
    my $hold_ids = get_hold_ids($e, $instconf, $patron, 0, $offset, $limit);

    my @hold_items;
    for my $hold_id (@$hold_ids) {
        my $hold = $e->retrieve_action_hold_request($hold_id);

        if ($format eq 'barcode') {
            my $copy = find_copy_for_hold($e, $hold);
            push(@hold_items, $copy->barcode) if $copy;
        } else {
            my $title = find_title_for_hold($e, $hold);
            push(@hold_items, $title) if $title;
        }
    }

    $details->{hold_items} = \@hold_items;
}

# Hold -> reporter.hold_request_record -> display field for title.
sub find_title_for_hold {
    my ($e, $hold) = @_;

    my $bib_link = $e->retrieve_reporter_hold_request_record($hold->id);

    my $title_field = $e->search_metabib_flat_display_entry({
        source => $bib_link->bib_record, name => 'title'})->[0];

    return $title_field ? $title_field->value : '';
}

# Finds a representative copy for the given hold.  If no copy exists at
# all, undef is returned.  The only limit placed on what constitutes a
# "representative" copy is that it cannot be deleted.  Otherwise, any
# copy that allows us to find the hold later is good enough.
sub find_copy_for_hold {
    my ($e, $hold) = @_;

    return $e->retrieve_asset_copy($hold->current_copy)
        if $hold->current_copy; 

    return $e->retrieve_asset_copy($hold->target)
        if $hold->hold_type =~ /C|R|F/;

    return $e->search_asset_copy([
        {call_number => $hold->target, deleted => 'f'}, 
        {limit => 1}])->[0] if $hold->hold_type eq 'V';

    my $bre_ids = [$hold->target];

    if ($hold->hold_type eq 'M') {
        # find all of the bibs that link to the target metarecord
        my $maps = $e->search_metabib_metarecord_source_map(
            {metarecord => $hold->target});
        $bre_ids = [map {$_->record} @$maps];
    }

    my $vol_ids = $e->search_asset_call_number( 
        {record => $bre_ids, deleted => 'f'}, 
        {idlist => 1}
    );

    return $e->search_asset_copy([
        {call_number => $vol_ids, deleted => 'f'}, 
        {limit => 1}
    ])->[0];
}


sub set_patron_privileges {
    my ($session, $instconf, $details, $penalties) = @_;
    my $patron = $details->{patron};

    my $expire = DateTime::Format::ISO8601->new
        ->parse_datetime(clean_ISO8601($patron->expire_date));

    if ($expire < DateTime->now) {
        $logger->info("SIP2 Patron account is expired; all privileges blocked");
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
                    $U->get_org_full_path($session->editor->requestor->ws_ou)
            }
        }
    });
}




1;
