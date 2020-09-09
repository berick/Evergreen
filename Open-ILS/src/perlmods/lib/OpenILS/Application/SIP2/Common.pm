package OpenILS::Application::SIP2::Common;
use strict; use warnings;
use OpenILS::Utils::DateTime qw/:datetime/;

use constant SIP_DATE_FORMAT => "%Y%m%d    %H%M%S";

sub sipdate {
    my ($class, $date) = @_;
    $date ||= DateTime->now;
    return $date->strftime(SIP_DATE_FORMAT);
}

sub format_date {
    my ($class, $session, $date, $type) = @_;
    $type ||= '';

    return "" unless $date;

    my $dt = DateTime::Format::ISO8601->new-> parse_datetime(clean_ISO8601($date));

    # actor.usr.dob stores dates without time/timezone, which causes
    # DateTime to assume the date is stored as UTC.  Tell DateTime
    # to use the local time zone, instead.
    # Other dates will have time zones and should be parsed as-is.
    $dt->set_time_zone('local') if $type eq 'dob';

    my @time = localtime($dt->epoch);

    my $year   = $time[5]+1900;
    my $mon    = $time[4]+1;
    my $day    = $time[3];
    my $hour   = $time[2];
    my $minute = $time[1];
    my $second = $time[0];
  
    $date = sprintf("%04d%02d%02d", $year, $mon, $day);

    # Due dates need hyphen separators and time of day as well
    if ($type eq 'due') {

        if ($session->config->{due_date_use_sip_date_format}) {
            $date = $class->sipdate($dt);

        } else {
            $date = sprintf("%04d-%02d-%02d %02d:%02d:%02d", 
                $year, $mon, $day, $hour, $minute, $second);
        }
    }

    return $date;
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
