package OpenILS::Application::SIP2::Common;
use strict; use warnings;

use constant SIP_DATE_FORMAT => "%Y%m%d    %H%M%S";

sub sipdate {
    my ($class, $date) = @_;
    $date ||= DateTime->now;
    return $date->strftime(SIP_DATE_FORMAT);
}

# False == 'N'
sub sipbool {
    my ($class, $bool) = @_;
    return $bool ? 'Y' : 'N';
}

# False == ' '
sub spacebool {
    my ($class, $bool) = @_;
    return $bool ? 'Y' : ' ';
}

sub count4 {
    my ($class, $value) = @_;
    return '    ' unless defined $value;
    return sprintf("%04d", $value);
}

# Returns the value of the first occurrence of the requested SIP code.
sub get_field_value {
    my ($class, $message, $code) = @_;
    for my $field (@{$message->{fields}}) {
        while (my ($c, $v) = each(%$field)) { # one pair per field
            return $v if $c eq $code;
        }
    }

    return undef;
}

1;
