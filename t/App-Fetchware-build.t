#!perl
# App-Fetchware-build.t tests App::Fetchware's build() subroutine, which builds
# your software.
# Pretend to be bin/fetchware, so that I can test App::Fetchware as though
# bin/fetchware was calling it.
package fetchware;
use strict;
use warnings;
use diagnostics;
use 5.010001;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '12'; #Update if this changes.
use File::Copy 'cp';
use Path::Class;
use File::Spec::Functions qw(rel2abs catfile);
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
BEGIN { use_ok('App::Fetchware', qw(:DEFAULT :OVERRIDE_BUILD run_star_commands)); }

# Print the subroutines that App::Fetchware imported by default when I used it.
note(qq{App::Fetchwares default imports [@App::Fetchware::EXPORT]});



subtest 'OVERRIDE_BUILD exports what it should' => sub {
    my @expected_overide_build_exports = qw(
        run_star_commands
        run_configure
    );
    # sort them to make the testing their equality very easy.
    @expected_overide_build_exports = sort @expected_overide_build_exports;
    my @sorted_build_tag = sort @{$App::Fetchware::EXPORT_TAGS{OVERRIDE_BUILD}};
    ok(@expected_overide_build_exports ~~ @sorted_build_tag, 
        'checked for correct OVERRIDE_BUILD @EXPORT_TAG');
};


subtest 'test run_star_commands() success' => sub {
    # Just user the 'perl' command itself as the command to run that way we
    # don't need to use different commands for different platforms.

    # Test just one simple command.
    # NOTE: run_star_commands() returns 0 on success, and nonzero on failure
    # just like commands on the command line do and perl's system() does too.
    ok(run_star_commands('perl -e "1+1;"') == 0,
        'check run_star_commands() simple success.');

    # Now test if it can handle comma (,\s*) seperated commands.
    ok((run_star_commands(q{perl -e "1+1;", perl -e "1+1;"}) == 0),
        'check run_star_commands() double success.');

    # Now test if it can handle a list of single commands..
    ok((run_star_commands('perl -e "1+1;"', 'perl -e "1+1;"') == 0),
        'check run_star_commands() list success.');

    # Now test if it can handle a list of comma separated commands..
    ok((run_star_commands(q{perl -e "1+1;", perl -e "1+1;"},
        q{perl -e "1+1;", perl -e "1+1;"}) == 0),
        'check run_star_commands() double list success.');
};


my $package_path;
my $build_path;
subtest 'Do build() prereqs.' => sub {
    skip_all_unless_release_testing();

    # Call start() to create & cd to a tempdir, so end() called later can delete all
    # of the files that will be downloaded.
    start();
    # Copy the $ENV{FETCHWARE_LOCAL_URL}/$package_path file to the temp dir, which
    # is what download would normally do for fetchware.
    cp("$ENV{FETCHWARE_LOCAL_BUILD_URL}", '.')
        or die "copy $package_path failed: $!";

    # Determine the copied $package_path.
    my $package_path = catfile(cwd(),
        file($ENV{FETCHWARE_LOCAL_BUILD_URL})->basename());

    # I have to unarchive the package before I can build it.
    $build_path = unarchive($package_path);
    ok(-e $build_path,
        'checked build() prereqs.');
};


subtest 'test run_configure() success' => sub {
    skip_all_unless_release_testing();

    # Must chdir() to $build_path!
    # But save cwd first for later chdir()ing back.
    my $old_cwd = cwd();
    ok(chdir($build_path),
        'Failed to chdir() to $build_path!');

    # Test run_configure() success.
    ok(run_configure(),
        'checked run_configure() success.');

    # Test run_configure() with custom configure_options.
    # Use option --help to avoid needing to run make_clean().
    config(configure_options => '--help');
    ok(run_configure(),
        'checked run_configure() configure_options success.');



    # Clear %config between run_configure() runs.
    __clear_CONFIG();


    # Test run_configure() with custom prefix.
    # Use $build_path, so that you know it's a path that exists no matter the
    # platform.
    config(prefix => rel2abs($build_path));
    ok(run_configure(),
        'checked run_configure() prefix success.');


    # Clear %config between run_configure() runs.
    __clear_CONFIG();


    # Test run_configure() with custom prefix and configure_options.
    # Use $build_path, so that you know it's a path that exists no matter the
    # platform.
    config(prefix => rel2abs($build_path));
    config(configure_options => '--help');
    ok(run_configure(),
        'checked run_configure() both success.');


    # Clear %config between run_configure() runs.
    __clear_CONFIG();


    # Test run_configure()'s exception.
    config(configure_options => '--prefix=/doesnt/matter');
    config(prefix => '/doesnt/matter');
    eval_ok(sub {run_configure()},
        <<EOE, 'checked run_configure() exception');
App-Fetchware: run-time error. You specified both the --prefix option twice.
Once in 'prefix' and once in 'configure_options'. You may only specify prefix
once in either configure option. See perldoc App::Fetchware.
EOE

    # Clear %config after last run_configure() run to reset it for later tests.
    __clear_CONFIG();

    # Must chdir() back to $build_path's parent.
    ok(chdir($old_cwd),
        'Failed to chdir() to $build_path!');
    
};


subtest 'test build() default success' => sub {
    skip_all_unless_release_testing();

    ok(build($build_path), 'checked build() success.');
};


subtest 'test build() build_commands' => sub {
    skip_all_unless_release_testing();

    # Clean up after previous build() run.
    make_clean();
    __clear_CONFIG();

note("CWD[@{[cwd()]}]");

    build_commands './configure, make';
    ok(build($build_path), 'checked build() build_command success.');

    # Clean up after previous build() run.
    make_clean();

    config_delete('build_commands');
    build_commands './configure', 'make';
    ok(build($build_path), 'checked build() build_command success again.');

    # Clear $CONFIG of build_commands for next subtest.
    config_delete('build_commands');
};


subtest 'test build() configure_options' => sub {
    skip_all_unless_release_testing();

    # Clean up after previous build() run.
    make_clean();

    configure_options '--enable-etags';
    ok(build($build_path), 'checked build() configure_options success.');

    # Clean up after previous build() run.
    make_clean();
    
    config_delete('configure_options');
    configure_options '--enable-etags', '--enable-tmpdir=/var/tmp';
    ok(build($build_path), 'checked build() configure_options success.');

    # Clear $CONFIG of configure_options for next subtest.
    config_delete('configure_options');
};


subtest 'test build() prefix success' => sub {
    skip_all_unless_release_testing();

    # Clean up after previous build() run.
    make_clean();

    prefix '/usr/local';
    ok(build($build_path), 'checked build() prefix success.');

    # Clean up after previous build() run.
    make_clean();
    
    config_delete('prefix');
    # prefix only supports one and only one option.
    eval_ok(sub {prefix '/usr/', '--enable-tmpdir=/var/tmp'},
        <<EOD, 'checked build() prefix success.');
App-Fetchware: internal syntax error. prefix was called with more than one
option. prefix only supports just one option such as 'prefix 'option';'. It does
not support more than one option such as 'prefix 'option', 'another option';'.
Please chose one option not both, or combine both into one option. See perldoc
App::Fetchware.
EOD

    # Clear $CONFIG of prefix for next subtest.
    config_delete('prefix');
};


subtest 'test build() build_commands and other options exception' => sub {
    skip_all_unless_release_testing();

    my %other_build_opts = (
        make_options => '-j 4',
        configure_options => '--enable-etags',
        prefix => '/usr/local',
    );

    # Set build_commands *and* any of the other build() options.
    for my $other_build_opt (keys %other_build_opts) {
        # Clean up after previous build() run.
        __clear_CONFIG();

        # Set build_commands.
        build_commands './configure, make';

        # Now set the current $other_build_opt;
        # Just use config() to avoid using crazy symbolic references.
        config($other_build_opt => $other_build_opts{$other_build_opt});

        eval_ok(sub {build($build_path)},
            <<EOE, "checked build() build_command($other_build_opt) exception.");
App-Fetchware: You cannot specify any other build options when you specify
build_commands, because build_commands overrides all of those other options.
Please fix your Fetchwarefile by adding the other options in with your
build_commands or remove the build_commands, and just use the other options if
possible.
EOE
    }
};



# Do *not* clean up after previous build() run, because make was not actually
# run.


subtest 'test build() make_options success' => sub {
    skip_all_unless_release_testing();

    # Clean up after previous build() run.
    __clear_CONFIG();

    make_options '-j4';
    ok(build($build_path), 'checked build() make_options success.');

    # Clean up after previous build() run.
    make_clean();
    
    config_delete('make_options');
    make_options '-j', '4';
    ok(build($build_path), 'checked build() make_options success.');

    # Clear $CONFIG of configure_options for next subtest.
    config_delete('make_options');
};


subtest 'Call end() to delete temporary directory.' => sub {
    skip_all_unless_release_testing();
    # Call end() to delete temp dir created by start().
    ok(end(),
        'checked calling end() to delete tempdir');
};


###BUGALERT### Add a build() test that uses make_test_dist to test building when
#FETCHWARE_RELEASE_TESTING is not set.


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
