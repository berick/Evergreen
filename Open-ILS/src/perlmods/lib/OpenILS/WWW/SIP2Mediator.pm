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
# Code borrows heavily and sometimes copies directly from from
# ../SIP* and SIPServer*
# ---------------------------------------------------------------
package OpenILS::WWW::SIPSession;
use strict; use warnings;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

# Note a cache instance cannot be instantiated until after
# opensrf has connected (see init below).
my $_cache;
sub cache {
    $_cache = OpenSRF::Utils::Cache->new unless $_cache;
    return $_cache;
}

sub new {
    my ($class, %args) = @_;
    my $self = bless(\%args, $class);
}

# Create a new sessesion from cached data.
sub from_cache {
    my ($class, $seskey) = @_;

    my $account = cache()->get_cache("sip2_$seskey");
    return undef unless $account;

    return $class->new(seskey => $seskey, account => $account);
}

sub seskey {
    my $self = shift;
    return $self->{seskey};
}

# Login account
sub account {
    my $self = shift;
    return $self->{account};
}

# Logs in to Evergreen and caches the auth token/login with the SIP
# account data.
# Returns true on success, false on failure to authenticate.
sub authenticate {
    my ($self, $account) = @_;

    my $seskey = $self->seskey;

    my $auth = $U->simplereq(
        'open-ils.auth',
        'open-ils.auth.login', {
        username => $account->{ils_username},
        password => $account->{ils_password},
        workstation => $account->{ils_workstation},
        type => 'staff'
    });

    if ($auth->{textcode} ne 'SUCCESS') {
        $logger->warn(
            "SIP2 login failed for ils_username".$account->{ils_username});
        return 0;
    }

    $account->{authtoken} = $auth->{payload}->{authtoken};

    # cache the login user account as well
    $account->{login} = $U->simplereq(
        'open-ils.auth',
        'open-ils.auth.session.retrieve',
        $account->{authtoken}
    );

    cache()->put_cache("sip2_$seskey", $account);
    return 1;
}

package OpenILS::WWW::SIP2Mediator;
use strict; use warnings;
use Apache2::Const -compile =>
    qw(OK FORBIDDEN NOT_FOUND HTTP_INTERNAL_SERVER_ERROR HTTP_BAD_REQUEST);
use Apache2::RequestRec;
use CGI;
use DateTime;
use DateTime::Format::ISO8601;
use JSON::XS;
use OpenSRF::System;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenILS::Const qw/:const/;

my $json = JSON::XS->new;
$json->ascii(1);
$json->allow_nonref(1);

my $SIP_DATE_FORMAT = "%Y%m%d    %H%M%S";

my $config = { # TODO: move to external config / database settings
    options => {
        # Allow 99 (sc status) message before successful 93 (login) message
        allow_sc_status_before_login => 1
    },
    accounts => [{
        sip_username => 'sip',
        sip_password => 'sip',
        ils_username => 'admin',
        ils_password => 'demo123',
        ils_workstation => 'BR1-gamma'
    }],
    institutions => [{
        id => 'example',
        currency => 'USD',
        supports => [ # Supported Messages (BX)
			'Y', # patron status request,
			'Y', # checkout,
			'Y', # checkin,
			'N', # block patron,
			'Y', # acs status,
			'N', # request sc/acs resend,
			'Y', # login,
			'Y', # patron information,
			'N', # end patron session,
			'Y', # fee paid,
			'Y', # item information,
			'N', # item status update,
			'N', # patron enable,
			'N', # hold,
			'Y', # renew,
			'N', # renew all,
        ],
        options => {
            due_date_use_sip_date_format => 0,
            patron_status_permit_loans => 0,
            patron_status_permit_all => 0
        }
    }]
};

my $osrf_config;
sub import {
    $osrf_config = shift;
    warn "OSRF CONFIG IS $osrf_config\n";
}

my $init_complete = 0;
sub init {
    return if $init_complete;
    $init_complete = 1;

    OpenSRF::System->bootstrap_client(config_file => $osrf_config);
    OpenILS::Utils::CStoreEditor->init;

    return Apache2::Const::OK;
}

sub sipdate {
    my $date = shift || DateTime->now;
    return $date->strftime($SIP_DATE_FORMAT);
}

sub handler {
    my $r = shift;
    my $cgi = CGI->new;

    init();

    my $seskey = $cgi->param('session');
    my $msg_json = $cgi->param('message');
    my $message = $json->decode($msg_json);
    my $msg_code = $message->{code};
    my $response;

    if ($msg_code eq '93') {
        $response = handle_login($seskey, $message);

    } elsif ($msg_code eq '99') {
        $response = handle_sc_status($seskey, $message);

    } else {

        # A cached session means we have successfully logged in with
        # the SIP credentials provided during a login request.  All
        # message types following require authentication.
        my $session = OpenILS::WWW::SIPSession->from_cache($seskey);

        return Apache2::Const::FORBIDDEN unless $session;

        if ($msg_code eq '63') {
            $response = handle_patron_info($session, $message);
        } elsif ($msg_code eq '17') {
            $response = handle_item_info($session, $message);
        }
    }

    unless ($response) {
        $logger->error("SIP2: no response generated for: $msg_code");
        return Apache2::Const::NOT_FOUND;
    }

    $r->content_type('application/json');
    $r->print($json->encode($response));

    return Apache2::Const::OK;
}

# Returns the value of the first occurrence of the requested field by SIP code.
sub get_field_value {
    my ($message, $code) = @_;
    for my $field (@{$message->{fields}}) {
        while (my ($c, $v) = each(%$field)) { # one pair per field
            return $v if $c eq $code;
        }
    }

    return undef;
}

sub get_inst_config {
    my $institution = shift;
    my ($instconf) = grep {$_->{id} eq $institution} @{$config->{institutions}};

    $logger->error(
        "SIP2 has no configuration for institution: $institution")
        unless $instconf;

    return $instconf;
}

sub handle_login {
    my ($seskey, $message) = @_;

    my $response = {
        code => '94',
        fixed_fields => ['0'] # default to login failed.
    };

    my $sip_username = get_field_value($message, 'CN');
    my $sip_password = get_field_value($message, 'CO');

    my ($account) = grep {
        $_->{sip_username} eq $sip_username &&
        $_->{sip_password} eq $sip_password
    } @{$config->{accounts}};

    if ($account) {
        my $session = OpenILS::WWW::SIPSession->new(seskey => $seskey);
        $response->{fixed_fields}->[0] = '1' 
            if $session->authenticate($account);

    } else {
        $logger->info("SIP2 login failed for user=$sip_username")
    }

    return $response;
}

sub handle_sc_status {
    my ($seskey, $message) = @_;

    return undef unless (
        $config->{options}->{allow_sc_status_before_login} ||
        OpenILS::WWW::SIPSession->from_cache($seskey)
    );

    # The SC Status message does not include an institution, but expects
    # one in return.  Use the configuration for the first institution.
    # Maybe the SIP server itself should track which institutoin its
    # instance is configured to use?  That may multiple servers could
    # run, one per institution.
    my $instconf = $config->{institutions}->[0];
    my $instname = $instconf->{id};

    my $response = {
        code => '98',
        fixed_fields => [
            'Y',        # online_status
            'Y',        # checkin_ok
            'Y',        # checkout_ok
            'Y',        # acs_renewal_policy
            'N',        # status_update_ok
            'N',        # offline_ok
            '999',      # timeout_period
            '999',      # retries_allowed
            sipdate(),  # transaction date
            '2.00'      # protocol_version
        ],
        fields => [
            {AO => $instname},
            {BX => join('', @{$instconf->{supports}})}
        ]
    }
}

sub handle_item_info {
    my ($session, $message) = @_;

    my $account = $session->account;
    my $institution = get_field_value($message, 'AO');
    my $instconf = get_inst_config($institution) || return undef;
    my $barcode = get_field_value($message, 'AB');
    my $item_details = get_item_details($session, $instconf, $barcode);

    if (!$item_details) {
        # No matching item found, return a minimal response.
        return {
            code => '18',
            fixed_fields => ['01', '01', '01', sipdate()],
            fields => [{AB => $barcode, AJ => ''}]
        };
    };

    return {
        code => '18',
        fixed_fields => [
            $item_details->{circ_status},
            '02', # Security Marker, consistent with ../SIP*
            $item_details->{fee_type},
            sipdate()
        ],
        fields => [
            {AB => $barcode},
            {AJ => $item_details->{title}},
            {CF => $item_details->{hold_queue_length}},
            {AH => $item_details->{due_date}},
            {CM => $item_details->{hold_pickup_date}},
            {BG => $item_details->{item}->circ_lib->shortname},
            {BH => $instconf->{currency}},
            {BV => $item_details->{item}->deposit_amount},
            {CK => $item_details->{media_type}},
            {AQ => $item_details->{item}->circ_lib->shortname},
            {AP => $item_details->{item}->circ_lib->shortname},
        ]
    };
}

sub get_item_details {
    my ($session, $instconf, $barcode) = @_;
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

    if ($details->{circ}) {

        my $due_date = DateTime::Format::ISO8601->new->
            parse_datetime(clean_ISO8601($details->{circ}->due_date));

        $details->{due_date} =
            $instconf->{due_date_use_sip_date_format} ?
            sipdate($due_date) :
            $due_date->strftime('%F %T');
    }

    if ($details->{hold}) {
        my $pickup_date = $details->{hold}->shelf_expire_time;
        $details->{hold_pickup_date} =
            $pickup_date ? sipdate($pickup_date) : undef;
    }

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

sub handle_patron_info {
    my ($session, $message) = @_;
    my $account = $session->account;

    my $institution = get_field_value($message, 'AO');
    my $instconf = get_inst_config($institution) || return undef;
    my $barcode = get_field_value($message, 'AA');
    my $password = get_field_value($message, 'AD');
    my $start_item = get_field_value($message, 'BP');
    my $end_item = get_field_value($message, 'BQ');

    my $patron_details =
        get_patron_details($session, $instconf, $barcode, $password);

    if (!$patron_details) {
        return {
            code => '64',
            fixed_fields => [
                'Y', # charge denied
                'Y', # renew denied
                'Y', # recall denied
                'Y', # holds denied
                split('', (' ' x 10)),
                '000', # language
                sipdate(),
            ],
            fields => [
                {AO => $institution},
                {AA => $barcode},
                {BL => 'N'}, # valid patron
                {CQ => 'N'}  # valid patron password
            ]
        };
    }

    return {
        code => '64',
        fixed_fields => [
            $patron_details->{charge_denied}   ? 'Y' : ' ',
            $patron_details->{renew_denied}    ? 'Y' : ' ',
            $patron_details->{recall_denied}   ? 'Y' : ' ',
            $patron_details->{holds_denied}    ? 'Y' : ' ',
            $patron_details->{patron}->card->active eq 'f' ? 'Y' : ' ',
            ' ', # too many charged
            $patron_details->{too_may_overdue} ? 'Y' : ' ',
            ' ', # too many renewals
            $patron_details->{too_many_claims_returned}  ? 'Y' : ' ',
            ' ', # too many lost
            $patron_details->{too_many_fines}  ? 'Y' : ' ',
            $patron_details->{too_many_fines}  ? 'Y' : ' ', # too many fees
            $patron_details->{recall_overdue}  ? 'Y' : ' ',
            $patron_details->{too_many_fines}  ? 'Y' : ' ', # too many billed
            '000', # language
            sipdate(),
        ],
        fields => [
            {AO => $institution},
            {AA => $barcode},
            {BL => 'Y'}, # valid patron
            {CQ => $password ? 'Y' : 'N'}  # password verified if exists
        ]
    };
}

sub get_patron_details {
    my ($session, $instconf, $barcode, $password) = @_;

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

    # We only verify the password if one is provided.
    return undef if defined $password &&
        !$U->verify_migrated_user_password($e, $patron->id, $password);

    set_patron_privileges($session, $instconf, $details);

    return $details;
}

sub set_patron_privileges {
    my ($session, $instconf, $details) = @_;
    my $patron = $details->{patron};

    # Assume all are allowed and modify as needed.
    $details->{charge_denied} = 0;
    $details->{recall_denied} = 0;
    $details->{renew_denied} = 0;
    $details->{holds_denied} = 0;

    my $expire = DateTime::Format::ISO8601->new
        ->parse_datetime(clean_ISO8601($patron->expire_date));

    if ($expire < DateTime->now) {
        $logger->info(
            "SIP2 Patron account is expired; all privileges blocked");
        $details->{charge_denied} = 1;
        $details->{renew_denied} = 1;
        $details->{recall_denied} = 1;
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

    # No need for the extra call to fetch penalties if the user
    # is already blocked.
    my $blocks = $blocked ? [] : new_editor()->json_query({
        select => {csp => ['block_list']},
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
            },
            '+csp' => {
                '-and' => [
                    {block_list => {'!=' => undef}},
                    {block_list => {'!=' => ''}},
                ]
            }
        }
    });

    return unless $blocked || @$blocks; # nothing left to check.

    my @block_tags = map {$_->{block_list}} @$blocks;

    $details->{holds_denied} = 1 if $blocked || grep {$_ =~ /HOLD/} @block_tags;

    # Ignore loan-related blocks?
    return if $instconf->{patron_status_permit_loans};

    # In evergreen, recalls are a type of hold.
    $details->{recall_denied} = $details->{holds_denied};

    $details->{charge_denied} = 1 if $blocked || grep {$_ =~ /CIRC/} @block_tags;
    $details->{renew_denied} = 1 if $blocked || grep {$_ =~ /RENEW/} @block_tags;
}



1;
