package App::DumpFirefoxHistory;

# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

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
            default => 'default-release',
            description => <<'_',

You can either provide a name, e.g. `default-release`, the profile directory of
which will be then be searched in `~/.mozilla/firefox/*.<name>`. Or you can also
provide a directory name.

_
        },
        attempt_orig_first => {
            schema => 'bool*',
            default => 0,
            'summary' => 'Attempt to open the original history database '.
                'first instead of directly copying the database',
            'summary.alt.bool.not' => 'Do not attempt to open the original history database '.
                '(and possibly get a "locked" error), proceed directly to copy it',
        },
        copy_size_limit => {
            schema => 'posint*',
            default => 100*1024*1024,
            description => <<'_',

Firefox often locks the History database for a long time. If the size of the
database is not too large (determine by checking against this limit), then the
script will copy the file to a temporary file and extract the data from the
copied database.

_
        },
    },
};
sub dump_firefox_history {
    require DBI;

    my %args = @_;

    my ($profile, $profile_dir);
    $profile = $args{profile} // 'default-release';

    # XXX read list of profiles from ~/.mozilla/firefox/profiles.ini
  GET_PROFILE_DIR:
    {
        if ($profile =~ /\A[\w-]+\z/) {
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

    my @rows;
    my $resmeta = {};
    my $num_attempts;
  SELECT: {
        $num_attempts++;
        goto COPY if $num_attempts == 1 && !$args{attempt_orig_first};

        eval {
            my $dbh = DBI->connect("dbi:SQLite:dbname=$path", "", "", {RaiseError=>1});
            my $sth = $dbh->prepare("SELECT url,title,last_visit_date,visit_count,frecency FROM moz_places ORDER BY last_visit_date");
            $sth->execute;
            while (my $row = $sth->fetchrow_hashref) {
                if ($args{detail}) {
                    push @rows, $row;
                } else {
                    push @rows, $row->{url};
                }
            }
        };
        my $err = $@;
        log_info "Got DBI error: $@" if $err;
      COPY: {
            unless (!$args{attempt_orig_first} && $num_attempts == 1 || $err && $err =~ /database is locked/) {
                last;
            }
            my $size = -s $path;
            unless ($size <= $args{copy_size_limit}) {
                log_trace "Not copying history database to tempfile, size too large (%.1fMB)", $size/1024/1024;
            }
            require File::Copy;
            require File::Temp;
            my ($temp_fh, $temp_path) = File::Temp::tempfile();
            log_trace "Copying $path to $temp_path ...";
            File::Copy::copy($path, $temp_path) or die $err;
            $path = $temp_path;
            redo SELECT;
        }
    } # SELECT

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
