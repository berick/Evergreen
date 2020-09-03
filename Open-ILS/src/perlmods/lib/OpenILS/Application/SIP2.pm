package OpenILS::Application::SIP2;
use strict; use warnings;
use base 'OpenILS::Application';
use OpenSRF::Utils::Cache;
use OpenILS::Application;
use OpenILS::Event;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::AppUtils;
use OpenILS::Application::SIP2::Common;
use OpenILS::Application::SIP2::Session;
use OpenILS::Application::SIP2::Item;
my $U = 'OpenILS::Application::AppUtils';
my $SC = 'OpenILS::Application::SIP2::Common';


__PACKAGE__->register_method(
    method    => 'dispatch_sip2_request',
    api_name  => 'open-ils.sip2.request', 
    api_level => 1,
    argc      => 2,
    signature => {
        desc     => q/
            Takes a SIP2 JSON message and handles the request/,
        params   => [{   
            name => 'seskey',
            desc => 'The SIP2 session key',
            type => 'string'
        }, {
            name => 'message',
            desc => 'SIP2 JSON message',
            type => q/SIP JSON object/
        }],
        return => {
            desc => q/SIP2 JSON message on success, Event on error/,
            type => 'object'
        }
    }
);

sub dispatch_sip2_request {
    my ($self, $client, $seskey, $message) = @_;

    return OpenILS::Event->new('SIP2_SESSION_REQUIRED') unless $seskey;
    my $msg_code = $message->{code};

    return handle_login($seskey, $message) if $msg_code eq '93';
    return handle_sc_status($seskey, $message) if $msg_code eq '99';

    # A cached session means we have successfully logged in with
    # the SIP credentials provided during a login request.  All
    # message types following require authentication.
    my $session = OpenILS::Application::SIPSession->from_cache($seskey);
    return OpenILS::Event->new('SIP2_SESSION_REQUIRED') unless $session;

    my $MESSAGE_MAP = {
        '17' => &handle_item_info,
        '23' => &handle_patron_status,
        '63' => &handle_patron_info
    };

    return OpenILS::Event->new('SIP2_NOT_IMPLEMENTED', {payload => $message})
        unless exists $MESSAGE_MAP->{$msg_code};

    return $MESSAGE_MAP->{$msg_code}->($session, $message);
}

# Login to Evergreen and cache the login data.
sub handle_login {
    my ($seskey, $message) = @_;
    my $e = new_editor();

    # Default to login-failed
    my $response = {code => '94', fixed_fields => ['0']};

    my $sip_username = get_field_value($message, 'CN');
    my $sip_password = get_field_value($message, 'CO');
    my $sip_account = $e->search_config_sip_account([
        {sip_username => $sip_username, enabled => 't'}, 
        {flesh => 1, flesh_fields => {csa => ['workstation']}}
    ])->[0];

    if (!$sip_account) {
        $logger->warn("SIP2: No such SIP account: $sip_username");
        return $response;
    }

    if ($U->verify_user_password($e, $sip_account->usr, $sip_password, 'sip2')) {
    
        my $session = OpenILS::Application::SIPSession->new(
            seskey => $seskey,
            sip_account => $sip_account
        );
        $response->{fixed_fields}->[0] = '1' if $session->set_ils_account;

    } else {
        $logger->info("SIP2: login failed for user=$sip_username")
    }

    return $response;
}

sub handle_sc_status {
    my ($seskey, $message) = @_;

    my $session = OpenILS::Application::SIPSession->from_cache($seskey);

    my $config;

    if ($session) {
        $config = $session->config;

    } else {
        # TODO: where should the 'allow_sc_status_before_login' setting 
        # live, since we don't yet have an institution configuration loaded?
        # TODO: Do we need a 'default institution' setting?
        $config = {id => 'NONE', supports => [], settings => {}};
    }

    my $response = {
        code => '98',
        fixed_fields => [
            $SC->sipbool(1),    # online_status
            $SC->sipbool(1),    # checkin_ok
            $SC->sipbool(1),    # checkout_ok
            $SC->sipbool(1),    # acs_renewal_policy
            $SC->sipbool(0),    # status_update_ok
            $SC->sipbool(0),    # offline_ok
            '999',              # timeout_period
            '999',              # retries_allowed
            $SC->sipdate,       # transaction date
            '2.00'              # protocol_version
        ],
        fields => [
            {AO => $config->{id}},
            {BX => join('', @{$config->{supports}})}
        ]
    }
}

sub handle_item_info {
    my ($session, $message) = @_;

    my $barcode = get_field_value($message, 'AB');
    my $config = $session->config;

    my $idetails = OpenILS::Application::SIP2::Item->get_item_details(
        $session, barcode => $barcode
    );

    if (!$idetails) {
        # No matching item found, return a minimal response.
        return {
            code => '18',
            fixed_fields => [
                '01', # circ status: other/Unknown
                '01', # security marker: other/unknown
                '01', # fee type: other/unknown
                $SC->sipdate
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
            $SC->sipdate
        ],
        fields => [
            {AB => $barcode},
            {AH => $idetails->{due_date}},
            {AJ => $idetails->{title}},
            {AP => $idetails->{item}->circ_lib->shortname},
            {AQ => $idetails->{item}->circ_lib->shortname},
            {BG => $idetails->{item}->circ_lib->shortname},
            {BH => $config->{settings}->{currency}},
            {BV => $idetails->{item}->deposit_amount},
            {CF => $idetails->{hold_queue_length}},
            {CK => $idetails->{media_type}},
            {CM => $idetails->{hold_pickup_date}}
        ]
    };
}

1;




