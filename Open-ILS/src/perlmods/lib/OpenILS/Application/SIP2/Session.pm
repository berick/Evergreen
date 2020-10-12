package OpenILS::Application::SIPSession;
use strict; use warnings;
use JSON::XS;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::Fieldmapper;
my $U = 'OpenILS::Application::AppUtils';
my $json = JSON::XS->new;
$json->ascii(1);
$json->allow_nonref(1);

# Supported Messages (BX)
# Currently hard-coded, since it's based on availabilty of functionality
# in the code, but it could be moved into the database to limit access for 
# specific setting groups.
use constant INSTITUTION_SUPPORTS => [ 
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
];

sub new {
    my ($class, %args) = @_;
    return bless(\%args, $class);
}

sub config {
    my $self = shift;
    return $self->{config} if $self->{config};

    my $group = $self->editor->retrieve_sip_setting_group([
        $self->sip_account->setting_group,
        {flesh => 1, flesh_fields => {sipsetg => ['settings']}}
    ]);

    my $config = {
        institution => $group->institution,
        supports => INSTITUTION_SUPPORTS
    };

    # Decode and hashify settings for easy access
    $config->{settings} = 
        {map {$_->name => $json->decode($_->value)} @{$group->settings}};

    $logger->info("SIP settings " . $json->encode($config->{settings}));
    return $self->{config} = $config;
}

# Retrieve an existing SIP session via SIP session token
sub find {
    my ($class, $seskey) = @_;

    my $session = $class->new(seskey => $seskey);
    my $e = $session->editor;

    my $ses = $e->retrieve_sip_session([
        $seskey, {flesh => 1, flesh_fields => {sipses => ['account']}}]);

    if ($ses) {
        $session->{sip_account} = $ses->account;

        $e->authtoken($ses->ils_token);

        return $session if $session->set_ils_account;

        return undef;

    } else {

        $logger->warn("SIP2: No session found for key $seskey");
        return undef;
    }
}

# The editor contains the authtoken and ILS user account (requestor).
sub editor {
    my $self = shift;
    $self->{editor} = new_editor() unless $self->{editor};
    return $self->{editor};
}

sub seskey {
    my $self = shift;
    return $self->{seskey};
}

# SIP account
sub sip_account {
    my $self = shift;
    return $self->{sip_account};
}

# Logs in to Evergreen and caches the auth token/login with the SIP
# account data.
# Returns true on success, false on failure to authenticate.
sub set_ils_account {
    my $self = shift;
    my $e = $self->editor;

    # Verify previously applied authtoken is still valid.
    return 1 if $e->authtoken && $e->checkauth;

    my $seskey = $self->seskey;

    my $auth = $U->simplereq(
        'open-ils.auth_internal',
        'open-ils.auth_internal.session.create', {
        user_id => $self->sip_account->usr,
        workstation => $self->sip_account->workstation->name,
        login_type => 'staff'
    });

    if ($auth->{textcode} ne 'SUCCESS') {
        $logger->warn(
            "SIP2 failed to create an internal login session for ILS user: ".
            $self->sip_account->usr);
        return 0;
    }

    # Ephemeral account sessions are not tracked in the database
    return 1 if $U->is_true($self->sip_account->ephemeral);

    my $ses = Fieldmapper::sip::session->new;
    $ses->key($seskey);
    $ses->ils_token($auth->{payload}->{authtoken});
    $ses->account($self->sip_account->id);

    $e->xact_begin;
    unless ($e->create_sip_session($ses)) {
        $e->rollback;
        return 0;
    }

    $e->xact_commit;

    return 1;
}

1;
