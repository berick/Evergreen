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
package OpenILS::WWW::SIP2Mediator;
use strict; use warnings;
use Apache2::Const -compile =>
    qw(OK FORBIDDEN NOT_FOUND HTTP_INTERNAL_SERVER_ERROR HTTP_BAD_REQUEST);
use Apache2::RequestRec;
use CGI;
use DateTime;
use DateTime::Format::ISO8601;
use JSON::XS;
use OpenSRF::Utils::Cache;
use OpenSRF::System;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenILS::Const qw/:const/;

my $U = 'OpenILS::Application::AppUtils';
my $cache;

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
            due_date_use_sip_date_format => 0
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
    $cache = OpenSRF::Utils::Cache->new;

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
    } elsif ($msg_code eq '17') {
        $response = handle_item_info($seskey, $message);
    }

    unless ($response) {
        $logger->error("SIP2: no handler for message code: $msg_code");
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
    return $instconf;
}

# Returns account object if found, undef otherwise.
sub get_auth_account {
    my ($seskey) = @_;
    my $account = $cache->get_cache("sip2_$seskey");
    return $account if $account;

    $logger->info("SIP2 has no cached session for seskey=$seskey");
    return undef;
}

# Logs in to Evergreen and caches the authtoken with the SIP account.
# Returns true on success, false on failure to authenticate.
sub set_auth_token {
    my ($seskey, $account) = @_;

    my $auth = $U->simplereq(
        'open-ils.auth',
        'open-ils.auth.login', {
        username => $account->{ils_username},
        password => $account->{ils_password},
        workstation => $account->{ils_workstation},
        type => 'staff'
    });

    if ($auth->{textcode} eq 'SUCCESS') {
        $account->{authtoken} = $auth->{payload}->{authtoken};
        $cache->put_cache("sip2_$seskey", $account);
        return 1;

    } else {
        $logger->warn("SIP2 login failed for ils_username".$account->{ils_username});
        return 0;
    }
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
        $response->{fixed_fields}->[0] = '1'
            if set_auth_token($seskey, $account);

    } else {
        $logger->info("SIP2 login failed for user=$sip_username")
    }

    return $response;
}

sub handle_sc_status {
    my ($seskey, $message) = @_;

    return undef unless (
        $config->{options}->{allow_sc_status_before_login} ||
        get_auth_account($seskey)
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
    my ($seskey, $message) = @_;

    my $institution = get_field_value($message, 'AO');
    my $barcode = get_field_value($message, 'AB');
    my $instconf = get_inst_config($institution);
    my $item_details = get_item_details($barcode, $instconf);

    my $response = {code => '18'};

    if (!$item_details) {
        # No matching item found, return a vague, minimal response.
        $response->{fixed_fields} = ['01', '01', '01', sipdate()];
        $response->{fields} = [{AB => $barcode, AJ => ''}];
        return $response;
    };

    $response->{fixed_fields} = [
        $item_details->{circ_status},
        '02', # Security Marker, consistent with ../SIP*
        $item_details->{fee_type},
        sipdate()
    ];

    $response->{fields} = [
        {AB => $barcode},
        {AJ => $item_details->{title}},
        {CF => $item_details->{hold_queue_length}},
        {AH => $item_details->{due_date}}
    ];

    return $response;
}

sub get_item_details {
    my ($barcode, $instconf) = @_;
    my $e = new_editor();

    my $item = $e->search_asset_copy([{
        barcode => $barcode,
        deleted => 'f'
    }, {
        flesh => 3,
        flesh_fields => {
            acp => [qw/circ_lib call_number status stat_cat_entry_copy_maps/],
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
        ($item->deposit_amount > 0.0 && $item->deposit eq 'f') ?  '06' : '01';

    if ($details->{circ}) {

        my $due_date = DateTime::Format::ISO8601->new->
            parse_datetime(clean_ISO8601($details->{circ}->due_date));

        $details->{due_date} = 
            $instconf->{due_date_use_sip_date_format} ?
            sipdate($due_date) :
            $due_date->strftime('%F %T');
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


1;
