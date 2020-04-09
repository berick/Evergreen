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
package OpenILS::WWW::SIPSession;
use strict; use warnings;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

# Cache instances cannot be created until opensrf is connected.
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

    if ($account) {
        return $class->new(seskey => $seskey, account => $account);

    } else {

        $logger->warn("SIP2: No session found in cache for key $seskey");
        return undef;
    }
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
        'open-ils.auth_internal',
        'open-ils.auth_internal.session.create', {
        user_id => $account->{ils_usr},
        workstation => $account->{ils_workstation},
        login_type => 'staff'
    });

    if ($auth->{textcode} ne 'SUCCESS') {
        $logger->warn(
            "SIP2 login failed for ils_usr".$account->{ils_usr});
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

package OpenILS::WWW::SIP2Gateway;
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
use OpenILS::WWW::SIP2Gateway::Patron;
use OpenILS::WWW::SIP2Gateway::Item;

my $json = JSON::XS->new;
$json->ascii(1);
$json->allow_nonref(1);

use constant SIP_DATE_FORMAT => "%Y%m%d    %H%M%S";

 # TODO: move to config / database
my $_config = {
    options => {
        # Allow 99 (sc status) message before successful 93 (login) message
        allow_sc_status_before_login => 1
    },
    accounts => [{
        sip_username => 'sip',
        sip_password => 'sip',
        ils_usr => 1,
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
            patron_status_permit_all => 0,
            msg64_hold_items_available => 0
        }
    }]
};

my $osrf_config;
sub import {
    $osrf_config = shift;
}

my $config;
my $init_complete = 0;
sub init {
    return if $init_complete;
    $init_complete = 1;

    OpenSRF::System->bootstrap_client(config_file => $osrf_config);
    OpenILS::Utils::CStoreEditor->init;

    my $e = new_editor();

    my $settings = $e->retrieve_all_config_sip_setting;

    $config = {institutions => []};

    # Institution specific settings.
    # In addition to the options, this tells us what institutions we support.
    for my $set (grep {$_->institution ne '*'} @$settings) {
        my $inst = $set->institution;
        my $value = $json->decode($set->value);
        my $name = $set->name;

        my ($inst_conf) = 
            grep {$_->id eq $inst} @{$config->{institutions}} ||
            {   id => $inst,
                currency => 'USD', # TODO
                supports => [],
                options => {}
            };

        $inst_conf->{options}->{$name} = $value;
    }

    # Apply values for global options without replacing 
    # institution-specific values.
    for my $set (grep {$_->institution eq '*'} @$settings) {
        my $name = $set->name;
        my $value = $json->decode($set->value);

        for my $inst_conf (@{$config->{institutions}}) {
            $inst_conf->{options}->{$name} = $value
                unless exists $inst_conf->{options}->{$name};
        }
    }
}

sub sipdate {
    my $date = shift || DateTime->now;
    return $date->strftime(SIP_DATE_FORMAT);
}

# False == 'N'
sub sipbool {
    my $bool = shift;
    return $bool ? 'Y' : 'N';
}

# False == ' '
sub spacebool {
    my $bool = shift;
    return $bool ? 'Y' : ' ';
}

sub count4 {
    my $value = shift;
    return '    ' unless defined $value;
    return sprintf("%04d", $value);
}

sub handler {
    my $r = shift;
    my $cgi = CGI->new;
    my ($message, $msg_code, $response);

    init();

    my $seskey = $cgi->param('session');
    my $msg_json = $cgi->param('message');

    if ($seskey && $msg_json) {
        eval { $message = $json->decode($msg_json) };
        if ($message) {
            $msg_code = $message->{code};
        } else {
            $logger->error("SIP2: Error parsing message JSON: $@ : $msg_json");
        }
    }

    return Apache2::Const::HTTP_BAD_REQUEST unless $msg_code;

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

# Returns the value of the first occurrence of the requested SIP code.
sub get_field_value {
    my ($message, $code) = @_;
    for my $field (@{$message->{fields}}) {
        while (my ($c, $v) = each(%$field)) { # one pair per field
            return $v if $c eq $code;
        }
    }

    return undef;
}

# Returns the configuation chunk mapped to the requested institution.
sub get_inst_config {
    my $institution = shift;
    my ($instconf) = grep {$_->{id} eq $institution} @{$config->{institutions}};

    $logger->error(
        "SIP2: has no configuration for institution: $institution")
        unless $instconf;

    return $instconf;
}

# Login to Evergreen and cache the login data.
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
        $logger->info("SIP2: login failed for user=$sip_username")
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
            sipbool(1),    # online_status
            sipbool(1),    # checkin_ok
            sipbool(1),    # checkout_ok
            sipbool(1),    # acs_renewal_policy
            sipbool(0),    # status_update_ok
            sipbool(0),    # offline_ok
            '999',         # timeout_period
            '999',         # retries_allowed
            sipdate(),     # transaction date
            '2.00'         # protocol_version
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

    my $idetails = OpenILS::WWW::SIP2Gateway::Item->get_item_details(
        session => $session,
        instconf => $instconf,
        barcode => $barcode
    );

    if (!$idetails) {
        # No matching item found, return a minimal response.
        return {
            code => '18',
            fixed_fields => [
                '01', # circ status: other/Unknown
                '01', # security marker: other/unknown
                '01', # fee type: other/unknown
                sipdate()
            ],
            fields => [{AB => $barcode, AJ => ''}]
        };
    };

    return {
        code => '18',
        fixed_fields => [
            $idetails->{circ_status},
            '02', # Security Marker, consistent with ../SIP*
            $idetails->{fee_type},
            sipdate()
        ],
        fields => [
            {AB => $barcode},
            {AJ => $idetails->{title}},
            {CF => $idetails->{hold_queue_length}},
            {AH => $idetails->{due_date}},
            {CM => $idetails->{hold_pickup_date}},
            {BG => $idetails->{item}->circ_lib->shortname},
            {BH => $instconf->{currency}},
            {BV => $idetails->{item}->deposit_amount},
            {CK => $idetails->{media_type}},
            {AQ => $idetails->{item}->circ_lib->shortname},
            {AP => $idetails->{item}->circ_lib->shortname},
        ]
    };
}

sub handle_patron_info {
    my ($session, $message) = @_;
    my $account = $session->account;

    my $institution = get_field_value($message, 'AO');
    my $barcode = get_field_value($message, 'AA');
    my $password = get_field_value($message, 'AD');
    my $instconf = get_inst_config($institution) || return undef;
    my $summary = $message->{fixed_fields}->[2];

    my $pdetails = OpenILS::WWW::SIP2Gateway::Patron->get_patron_details(
        session => $session,
        instconf => $instconf,
        barcode => $barcode,
        password => $password,
        summary_start_item => get_field_value($message, 'BP'),
        summary_end_item => get_field_value($message, 'BQ'),
        summary_list_items => patron_summary_list_items($summary)
    );

    if (!$pdetails) {
        return {
            code => '64',
            fixed_fields => [
                spacebool(1), # charge denied
                spacebool(1), # renew denied
                spacebool(1), # recall denied
                spacebool(1), # holds denied
                split('', (' ' x 10)),
                '000', # language
                sipdate()
            ],
            fields => [
                {AO => $institution},
                {AA => $barcode},
                {BL => sipbool(0)}, # valid patron
                {CQ => sipbool(0)}  # valid patron password
            ]
        };
    }

    return {
        code => '64',
        fixed_fields => [
            spacebool($pdetails->{charge_denied}),
            spacebool($pdetails->{renew_denied}),
            spacebool($pdetails->{recall_denied}),
            spacebool($pdetails->{holds_denied}),
            spacebool($pdetails->{patron}->card->active eq 'f'),
            spacebool(0), # too many charged
            spacebool($pdetails->{too_may_overdue}),
            spacebool(0), # too many renewals
            spacebool(0), # too many claims retruned
            spacebool(0), # too many lost
            spacebool($pdetails->{too_many_fines}),
            spacebool($pdetails->{too_many_fines}),
            spacebool(0), # recall overdue
            spacebool($pdetails->{too_many_fines}),
            '000', # language
            sipdate(),
            count4($pdetails->{holds_count}),
            count4($pdetails->{overdue_count}),
            count4($pdetails->{out_count}),
            count4($pdetails->{fine_count}),
            count4($pdetails->{recall_count}),
            count4($pdetails->{unavail_holds_count}),
        ],
        fields => [
            {AO => $institution},
            {AA => $barcode},
            {BL => sipbool(1)},         # valid patron
            {CQ => sipbool($password)}  # password verified if exists
        ]
    };
}


# Determines which class of data the SIP client wants detailed
# information on in the patron info request.
sub patron_summary_list_items {
    my $summary = shift;

    my $idx = index($summary, 'Y');

    return 'hold_items'        if $idx == 0;
    return 'overdue_items'     if $idx == 1;
    return 'charged_items'     if $idx == 2;
    return 'fine_items'        if $idx == 3;
    return 'recall_items'      if $idx == 4;
    return 'unavailable_holds' if $idx == 5;
}

1;
