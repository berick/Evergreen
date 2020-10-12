package OpenILS::Application::SIP2::Common;
use strict; use warnings;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenSRF::Utils::Cache;

use constant SIP_DATE_FORMAT => "%Y%m%d    %H%M%S";

my $_cache;
sub cache {
    $_cache = OpenSRF::Utils::Cache->new unless $_cache;
    return $_cache;
}

sub sipdate {
    my ($class, $date) = @_;
    $date ||= DateTime->now;
    return $date->strftime(SIP_DATE_FORMAT);
}

sub sipymd {
    my ($class, $date_str, $to_local_tz) = @_;
    return '' unless $date_str;

    my $dt = DateTime::Format::ISO8601->new
        ->parse_datetime(clean_ISO8601($date_str));

    # actor.usr.dob stores dates without time/timezone, which causes
    # DateTime to assume the date is stored as UTC.  Tell DateTime to
    # use the local time zone, instead.  Other dates will have time
    # zones and should be parsed as-is.
    $dt->set_time_zone('local') if $to_local_tz;

    return $dt->strftime('%Y%m%d');
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

# Determines which class of data the SIP client wants detailed
# information on in the patron info request.
sub patron_summary_list_items {
    my ($class, $summary) = @_;

    my $idx = index($summary, 'Y');

    return 'hold_items'        if $idx == 0;
    return 'overdue_items'     if $idx == 1;
    return 'charged_items'     if $idx == 2;
    return 'fine_items'        if $idx == 3;
    return 'recall_items'      if $idx == 4;
    return 'unavailable_holds' if $idx == 5;
    return '';
}

1;
