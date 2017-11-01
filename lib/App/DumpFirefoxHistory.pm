package App::DumpFirefoxHistory;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our %SPEC;

$SPEC{dump_firefox_history} = {
    v => 1.1,
    summary => 'Dump Firefox history',
    args => {
        detail => {
            schema => 'bool*',
            cmdline_aliases => {l=>{}},
        },
        profile => {
            summary => 'Select profile to use',
            schema => 'str*',
            default => 'default',
            description => <<'_',

You can either provide a name, e.g. `default`, the profile directory of which
will be then be searched in `~/.mozilla/firefox/*.<name>`. Or you can also
provide a directory name.

_
        },
    },
};
sub dump_firefox_history {
    require DBI;

    my %args = @_;

    my ($profile, $profile_dir);
    $profile = $args{profile} // 'default';

    # XXX read list of profiles from ~/.mozilla/firefox/profiles.ini
  GET_PROFILE_DIR:
    {
        if ($profile =~ /\A\w+\z/) {
            # search profile name in profiles directory
            my @dirs = glob "$ENV{HOME}/.mozilla/firefox/*.*";
            return [412, "Can't find any profile directory under ~/.mozilla/firefox"]
                unless @dirs;
            for my $dir (@dirs) {
                if ($dir =~ /\.\Q$profile\E(?:-\d+)?\z/) {
                    $profile_dir = $dir;
                    last GET_PROFILE_DIR;
                }
            }
        }
        if (-d $profile) {
            $profile_dir = $profile;
        } else {
            return [412, "No such profile/profile directory '$profile'"];
        }
    }

    my $path = "$profile_dir/places.sqlite";
    return [412, "Can't find $path"] unless -f $path;

    my $dbh = DBI->connect("dbi:SQLite:dbname=$path", "", "", {RaiseError=>1});
    my $sth = $dbh->prepare("SELECT url,title,last_visit_date,visit_count,frecency FROM moz_places ORDER BY last_visit_date");
    $sth->execute;
    my @rows;
    my $resmeta = {};
    while (my $row = $sth->fetchrow_hashref) {
        if ($args{detail}) {
            push @rows, $row;
        } else {
            push @rows, $row->{url};
        }
    }

    $resmeta->{'table.fields'} = [qw/url title last_visit_date visit_count frecency/]
        if $args{detail};
    [200, "OK", \@rows, $resmeta];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the included script L<dump-firefox-history>.


=head1 SEE ALSO

L<App::DumpChromeHistory>

L<App::DumpOperaHistory>
