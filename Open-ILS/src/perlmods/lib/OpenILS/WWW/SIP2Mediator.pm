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
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Cache;
use OpenSRF::System;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::DateTime qw/:datetime/;

my $U = 'OpenILS::Application::AppUtils';

# TODO: config file which maps SIP logins to ILS logins and
# applies various flags.

my $bs_config;
sub import {
    $bs_config = shift;
}

my $init_complete = 0;
sub child_init {
    $init_complete = 1;

    OpenSRF::System->bootstrap_client(config_file => $bs_config);
    OpenILS::Utils::CStoreEditor->init;
    return Apache2::Const::OK;
}

sub sipdate {
    my $now = DateTime->now;
    return $now->strftime("%Y%m%d    %H%M%S");
}

sub handler {
    my $r = shift;
    my $cgi = CGI->new;

    child_init() unless $init_complete;

    my $session = $cgi->param('session');
    my $message = OpenSRF::Utils::JSON->JSON2perl($cgi->param('message'));

    my $msg_code = $message->{code};
    my $response;

    if ($msg_code eq '93') {
        $response = handle_login($session, $message);
    } elsif ($msg_code eq '99') {
        $response = handle_sc_status($session, $message);
    }

    unless ($response) {
        $logger->error("SIP2: no handler for message code: $msg_code");
        return Apache2::Const::NOT_FOUND;
    }

    $r->content_type('application/json');
    $r->print(OpenSRF::Utils::JSON->perl2JSON($response));

    return Apache2::Const::OK;
}

sub handle_login {
    my ($session, $message) = @_;

    # TODO: login and cache the authtoken vis the $session

    my $response = {
        code => '94',
        fixed_fields => ['1']
    };

    return $response;
}

sub handle_sc_status {
    my ($session, $message) = @_;

    # TODO: If we don't want to allow sc_status requests without
    # authentication, check for the authtoken.

    my $response = {
        code => '98',
        fixed_fields => [
            'Y',        # online_status
            'N',        # checkin_ok
            'N',        # checkout_ok
            'N',        # acs_renewal_policy
            'N',        # status_update_ok
            'N',        # offline_ok
            '999',      # timeout_period
            '999',      # retries_allowed
            sipdate(),  # transaction date
            '2.00'      # protocol_version
        ]
    }
}

1;
