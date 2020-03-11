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

my $U = 'OpenILS::Application::AppUtils';
my $cache;

my $json = JSON::XS->new;
$json->ascii(1);
$json->allow_nonref(1);

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
        options => {}
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
    my $now = DateTime->now;
    return $now->strftime("%Y%m%d    %H%M%S");
}

sub handler {
    my $r = shift;
    my $cgi = CGI->new;

    init();

    my $seskey = $cgi->param('session');
    my $message = $json->decode($cgi->param('message'));

    my $msg_code = $message->{code};
    my $response;

    if ($msg_code eq '93') {
        $response = handle_login($seskey, $message);
    } elsif ($msg_code eq '99') {
        $response = handle_sc_status($seskey, $message);
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
        my ($c, $v) = each(%$field); # one key/value pair per field
        return $v if $c eq $code;
    }

    return undef;
}

sub get_auth_account {
    my ($seskey) = @_;
    my $account = $cache->get_cache("sip2_$seskey");

    if ($account) {
        return $account->{authtoken};
    } else {
        $logger->info("SIP2 no cached session for seskey=$seskey");
        return undef;
    }
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

# NOTE: response should be modified as message handlers are implemented.
sub handle_sc_status {
    my ($seskey, $message) = @_;

    return undef unless (
        $config->{options}->{allow_sc_status_before_login} ||
        get_auth_account($seskey)
    );

    # The SC Status message does not include an institution, but expects
    # one in return.  Use the configuration for the first institution.
    # Maybe the SIP server itself should track which institutoin its
    # instance is configured to use.  That may multiple servers could,
    # one per institution.
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

1;
