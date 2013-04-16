#!perl
# App-Fetchware-install.t tests App::Fetchware's install() subroutine, which
# installs your software.
# Pretend to be bin/fetchware, so that I can test App::Fetchware as though
# bin/fetchware was calling it.
package fetchware;
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '10'; #Update if this changes.
use File::Copy 'cp';
use File::Temp 'tempdir';
use File::Spec::Functions 'tmpdir';
use Cwd 'cwd';

use App::Fetchware::Config ':CONFIG';
use Test::Fetchware ':TESTING';

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
BEGIN { use_ok('App::Fetchware', qw(:DEFAULT :OVERRIDE_INSTALL)); }

# Print the subroutines that App::Fetchware imported by default when I used it.
note("App::Fetchware's default imports [@App::Fetchware::EXPORT]");

my $class = 'App::Fetchware';


subtest 'OVERRIDE_INSTALL exports what it should' => sub {
    my @expected_overide_install_exports = qw(
        chdir_unless_already_at_path
    );
    # sort them to make the testing their equality very easy.
    @expected_overide_install_exports = sort @expected_overide_install_exports;
    my @sorted_install_tag = sort @{$App::Fetchware::EXPORT_TAGS{OVERRIDE_INSTALL}};
    ok(@expected_overide_install_exports ~~ @sorted_install_tag, 
        'checked for correct OVERRIDE_INSTALL @EXPORT_TAG');
};


subtest 'test chdir_unless_already_at_path() success' => sub {
    # Create a temporary directory in tmpdir(), and then chdir to tmpdir(), and
    # then run chdir_unless_already_at_path($the_created_tempdir).
    my $temp_dir = tempdir("fetchware-test-$$-XXXXXXXXXX",
        TMPDIR => 1, CLEANUP => 1);
    # Keep $old_cwd for chdir() back after testing.
    my $old_cwd = cwd();
    ok(chdir(tmpdir()),
        'chdir()d to tmpdir()');
    chdir_unless_already_at_path($temp_dir);
    ok(cwd() eq $temp_dir,
        'checked chdir_unless_already_at_path() success.');

    # Now repeat the call to chdir_unless_already_at_path(), and this time it
    # should do basically nothing, because we're already at the correct path.
    # This is what happens when stay_root is in effect.
    chdir_unless_already_at_path($temp_dir);
    ok(cwd() eq $temp_dir,
        'checked chdir_unless_already_at_path() success.');


    # Undo the chdir().
    ok(chdir($old_cwd),
        'chdir()d back to original working directory.');
};





###BUGALERT### Needs to fail gracefully or su to root when run as non-root.
# I have to unarchive the package before I can build it.
my $build_path;
subtest 'do prerequisites' => sub {
    skip_all_unless_release_testing();

    # Needed my all other subtests.
    my $package_path = $ENV{FETCHWARE_LOCAL_BUILD_URL};
    fail("FETCHWARE environment vars not set!!! Run frt()")
        if not defined $package_path;

    # Call start() to create & cd to a tempdir, so end() called later can delete all
    # of the files that will be downloaded.
    start();
    # Copy the $ENV{FETCHWARE_LOCAL_URL}/$package_path file to the temp dir, which
    # is what download would normally do for fetchware.
    cp("$package_path", '.') or die "copy $package_path failed: $!";

    $build_path = unarchive($package_path);
    ok($build_path, 'prerequisite install() run');
    ok(build($build_path), 'prerequisite build() run');
};


subtest 'test install() default success' => sub {
    skip_all_unless_release_testing();

    ok(install($build_path), 'checked install() success.');
};


subtest 'test install() make_options success' => sub {
    skip_all_unless_release_testing();

    make_options '-j4';
    ok(install($build_path), 'checked install() make_options success.');
    config_delete('make_options');
};


subtest 'test install() install_commands success' => sub {
    skip_all_unless_release_testing();

    install_commands 'make install';
    ok(install($build_path), 'checked install() make_options success.');

    config_delete('install_commands');
    install_commands 'make install', 'make clean';
    ok(install($build_path), 'checked install() install_commands success.');
    config_delete('install_commands');
};


##BUGALERT###Add a make_test_dist() based test for regular users.

subtest 'test install() no_install success' => sub {
    no_install 'True';

    is(install($build_path), 'installation skipped!',
        'checked install() no_install success');
};



subtest 'test overriding install()' => sub {
    # switch to *not* being package fetchware, so that I can test install()'s
    # behavior as if its being called from a Fetchwarefile to create a callback
    # that install will later call back in package fetchware.
    package main;
    use App::Fetchware;

    install sub { return 'Overrode install()!' };

    # Switch back to being in package fetchware, so that install() will try out
    # the callback I gave it in the install() call above.
    package fetchware;
    is(install($build_path), 'Overrode install()!',
        'checked overiding install() success');
};


subtest 'Call end() to delete temporary directory.' => sub {
    # Call end() to delete temp dir created by start().
    ok(end(),
        'ran end() to delete temp dir.');
};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
