#!perl
# Fetchware-fetchware.t tests App::Fetchware's build() subroutine, which builds
# your software.
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '7'; #Update if this changes.
use File::Copy 'cp';
use IPC::System::Simple 'system';
use File::Spec::Functions 'updir';

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
BEGIN { use_ok('App::Fetchware', qw(:DEFAULT :OVERRIDE_BUILD :TESTING)); }

# Print the subroutines that App::Fetchware imported by default when I used it.
diag("App::Fetchware's default imports [@App::Fetchware::EXPORT]");

my $class = 'App::Fetchware';

# Use extra private sub __FW() to access App::Fetchware's internal state
# variable, so that I can test that the configuration subroutines work properly.
my $FW = App::Fetchware::__FW();

subtest 'OVERRIDE_BUILD exports what it should' => sub {
    my @expected_overide_build_exports = qw(
    );
    # sort them to make the testing their equality very easy.
    @expected_overide_build_exports = sort @expected_overide_build_exports;
    my @sorted_build_tag = sort @{$App::Fetchware::EXPORT_TAGS{OVERRIDE_BUILD}};
    ok(@expected_overide_build_exports ~~ @sorted_build_tag, 
        'checked for correct OVERRIDE_BUILD @EXPORT_TAG');
};

# Needed my all other subtests.
my $package_path = $ENV{FETCHWARE_LOCAL_BUILD_URL};


# Call start() to create & cd to a tempdir, so end() called later can delete all
# of the files that will be downloaded.
start();
# Copy the $ENV{FETCHWARE_LOCAL_URL}/$package_path file to the temp dir, which
# is what download would normally do for fetchware.
cp("$package_path", '.') or die "copy $package_path failed: $!";

# I have to unarchive the package before I can build it.
$FW->{PackagePath} = $package_path;
unarchive() unless skip_all_unless_release_testing();

subtest 'test build() default success' => sub {
    skip_all_unless_release_testing();

    ok(build(), 'checked build() success.');
};


# Clean up after previous build() run.
make_clean();


subtest 'test build() build_commands' => sub {
    skip_all_unless_release_testing();

    build_commands './configure, make';
    ok(build(), 'checked build() build_command success.');

    # Clean up after previous build() run.
    make_clean();

    delete $FW->{build_commands};
    build_commands './configure', 'make';
    ok(build(), 'checked build() build_command success.');

    # Clear $FW of build_commands for next subtest.
    delete $FW->{build_commands};
};



# Clean up after previous build() run.
make_clean();


subtest 'test build() configure_options' => sub {
    skip_all_unless_release_testing();

    configure_options '--enable-etags';
    ok(build(), 'checked build() configure_options success.');

    # Clean up after previous build() run.
    make_clean();
    
    delete $FW->{configure_options};
    configure_options '--enable-etags', '--enable-tmpdir=/var/tmp';
    ok(build(), 'checked build() configure_options success.');

    # Clear $FW of configure_options for next subtest.
    delete $FW->{configure_options};
};



# Clean up after previous build() run.
make_clean();


subtest 'test build() prefix success' => sub {
    skip_all_unless_release_testing();

    prefix '/usr/local';
    ok(build(), 'checked build() prefix success.');

    # Clean up after previous build() run.
    make_clean();
    
    delete $FW->{prefix};
    # prefix only supports one and only one option.
    eval_ok(sub {prefix '/usr/', '--enable-tmpdir=/var/tmp'},
        <<EOD, 'checked build() prefix success.');
App-Fetchware: internal syntax error. prefix was called with more than one
option. prefix only supports just one option such as 'prefix 'option';'. It does
not support more than one option such as 'prefix 'option', 'another option';'.
Please chose one option not both, or combine both into one option. See perldoc
App::Fetchware.
EOD

    # Clear $FW of prefix for next subtest.
    delete $FW->{prefix};
};



# Clean up after previous build() run.
# Commented out, because previous test didn't actually pollute make!
#make_clean();


subtest 'test build() make_options success' => sub {
    skip_all_unless_release_testing();

    make_options '-j4';
    ok(build(), 'checked build() make_options success.');

    # Clean up after previous build() run.
    make_clean();
    
    delete $FW->{make_options};
    make_options '-j', '4';
    ok(build(), 'checked build() make_options success.');

    # Clear $FW of configure_options for next subtest.
    delete $FW->{make_options};
};

# Call end() to delete temp dir created by start().
end();


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
