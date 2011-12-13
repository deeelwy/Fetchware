#!perl
# Fetchware-fetchware.t tests App::Fetchware's unarchive() subroutine, which
# unzips or untars your downloaded archived software.
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '4'; #Update if this changes.
use File::Spec::Functions 'devnull';

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
BEGIN { use_ok('App::Fetchware', qw(:DEFAULT :OVERRIDE_UNARCHIVE :TESTING)); }


# Print the subroutines that App::Fetchware imported by default when I used it.
diag("App::Fetchware's default imports [@App::Fetchware::EXPORT]");

my $class = 'App::Fetchware';

# Use extra private sub __FW() to access App::Fetchware's internal state
# variable, so that I can test that the configuration subroutines work properly.
my $FW = App::Fetchware::__FW();

# Call start() to create & cd to a tempdir, so end() called later can delete all
# of the files that will be downloaded.
start();


subtest 'OVERRIDE_UNARCHIVE exports what it should' => sub {
    my @expected_overide_unarchive_exports = qw(
        check_archive_files
    );
    # sort them to make the testing their equality very easy.
    @expected_overide_unarchive_exports = sort @expected_overide_unarchive_exports;
    my @sorted_unarchive_tag = sort
        @{$App::Fetchware::EXPORT_TAGS{OVERRIDE_UNARCHIVE}};
    ok(@expected_overide_unarchive_exports ~~ @sorted_unarchive_tag, 
        'checked for correct OVERRIDE_UNARCHIVE @EXPORT_TAG');
};


subtest 'test check_archive_files' => sub {
    my $fake_file_paths = [qw(
        samedir/blah/file/who.cares
        samedir/not/a/rea/file/but/who.cares
        samedir/a/real/file/just/joking
        samedir/why/am/i/adding/yet/another/worthless/fake.file
    )];

    ok(check_archive_files($fake_file_paths),
        'checked check_archive_files() success');

    push @$fake_file_paths, '/absolute/path/';
    eval_ok(sub {check_archive_files($fake_file_paths)},
        <<EOE, 'checked check_archive_files() absolute path failure');
App-Fetchware: run-time error. The archive you asked fetchware to download has
one or more files with an absolute path. Absolute paths in archives is
dangerous, because the files could potentially overwrite files anywhere in the
filesystem including important system files. That is why this is a fatal error
that cannot be ignored. See perldoc App::Fetchware.
Absolute path [/absolute/path/].
EOE
    pop @$fake_file_paths;


    push @$fake_file_paths, 'differentdir/to/test/differeent/dir/die';
    {
        local $SIG{__WARN__} = sub {
            is($_[0],
                <<EOI, 'checked check_archive_files() different dir failure');
App-Fetchware: run-time warning. The archive you asked Fetchware to download 
does *not* have *all* of its files in one and only one containing directory.
This is not a problem for fetchware, because it does all of its downloading,
unarchive, and building in a temporary directory that makes it easy to
automatically delete all of the files when fetchware is done with them. See
perldoc App::Fetchware.
EOI
        };
        check_archive_files($fake_file_paths);
    }
    pop @$fake_file_paths;
};


subtest 'test unarchive()' => sub {
    skip_all_unless_release_testing(); 

    my $package_path = $ENV{FETCHWARE_LOCAL_URL};
    $package_path =~ s!^file://!!;
    $FW->{PackagePath} = $package_path;

    ok(unarchive(), 'checked unarchive() success');

    $FW->{PackagePath} = devnull();
    eval_ok(sub {unarchive()},
        # note this error message is from Archive::Extract, which croaks on
        # errors.
        qr/Can't call method "files" on an undefined value/,
        'checked unarchive failure');

###HOWTOTEST### I'm not sure how to test unarchive() failing to list and and
#failing to unarchive files. Maybe I could create archives that can get past the
#error above.
};

# Call end() to delete temp dir created by start().
end();


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
