package OpenILS::Application::SIPSession;
use strict; use warnings;
use JSON::XS;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor q/:funcs/;
my $U = 'OpenILS::Application::AppUtils';
my $json = JSON::XS->new;
$json->ascii(1);
$json->allow_nonref(1);

# Supported Messages (BX)
# Currently hard-coded, since it's based on availabilty of functionality
# in the code, but it could be moved into the database to limit access for 
# specific institutions.
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

# Cache instances cannot be created until opensrf is connected.
my $_cache;
sub cache {
    $_cache = OpenSRF::Utils::Cache->new unless $_cache;
    return $_cache;
}

sub new {
    my ($class, %args) = @_;
    return bless(\%args, $class);
}

sub config {
    my $self = shift;
    return $self->{config} if $self->{config};

    my $inst = $self->sip_account->institution;

    my $config = {
        institution => $inst,
        settings => {
            currency => 'USD' # TODO add db setting
        },
        supports => INSTITUTION_SUPPORTS
    };

    # Institution "*" provides default values for all institution configs.
    my $settings = 
        $self->editor->search_config_sip_setting({institution => ['*', $inst]});

    # Institution specific settings.
    for my $set (grep {$_->institution eq $inst} @$settings) {
        $config->{settings}->{$set->name} = $json->decode($set->value);
    }

    # Apply values for global settings without replacing 
    # institution-specific values.
    for my $set (grep {$_->institution eq '*'} @$settings) {
        my $name = $set->name;
        my $value = $json->decode($set->value);

        $config->{settings}->{$name} = $value 
            unless exists $config->{settings}->{$name};
    }

    return $self->{config} = $config;
}

# Create a new sessesion from cached data.
sub from_cache {
    my ($class, $seskey) = @_;

    my $ses = cache()->get_cache("sip2_$seskey");

    if ($ses) {

        my $session = $class->new(
            seskey => $seskey, 
            sip_account => $ses->{sip_account}
        );

        $session->editor->authtoken($ses->{ils_authtoken});

        return $session if $session->set_ils_account;

        return undef;

    } else {

        $logger->warn("SIP2: No session found in cache for key $seskey");
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

    # Verify previously applied authtoken is still valid.
    return 1 if $self->editor->authtoken && $self->editor->checkauth;

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

    my $ses = {
        sip_account => $self->sip_account, 
        ils_authtoken => $auth->{payload}->{authtoken}
    };

    $self->editor->authtoken($ses->{ils_authtoken});
    $self->editor->checkauth;

    cache()->put_cache("sip2_$seskey", $ses);
    return 1;
}

1;
