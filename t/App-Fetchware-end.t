#!perl
# App-Fetchware-end.t tests App::Fetchware's end() subroutine, which
# determines if a new version of your program is available.
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '2'; #Update if this changes.

use File::Temp 'tempdir';

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
# There is no ':OVERRIDE_START' to bother importing.
BEGIN { use_ok('App::Fetchware', qw(:DEFAULT :TESTING)); }

# Print the subroutines that App::Fetchware imported by default when I used it.
diag("App::Fetchware's default imports [@App::Fetchware::EXPORT]");

my $class = 'App::Fetchware';

# Use extra private sub __CONFIG() to access App::Fetchware's internal state
# variable, so that I can test that the configuration subroutines work properly.
my $CONFIG = App::Fetchware::__CONFIG();


subtest 'test end()' => sub {
    skip_all_unless_release_testing();

    my $tempdir = tempdir("fetchware-$$-XXXXXXXXXX", TMPDIR => 1, CLEANUP => 1);
    diag("td[$tempdir]");

    ok(-e $tempdir, 'checked end() tempdir creationg');

    end();

    ok( (not -e $tempdir) , 'checked end() success');

    done_testing();
};




# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
