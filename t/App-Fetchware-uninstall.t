#!perl
# App-Fetchware-uninstall.t tests App::Fetchware's uninstall() subroutine,
# uninstalls your program.
# # Pretend to be bin/fetchware, so that I can test App::Fetchware as though
# bin/fetchware was calling it.
package fetchware;
use strict;
use warnings;
use diagnostics;
use 5.010001;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '2'; #Update if this changes.

use File::Spec::Functions qw(splitpath catfile);
use URI::Split 'uri_split';
use Cwd 'cwd';

use Test::Fetchware ':TESTING';

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
# There is no ':OVERRIDE_START' to bother importing.
BEGIN { use_ok('App::Fetchware', qw(:DEFAULT)); }

# Print the subroutines that App::Fetchware imported by default when I used it.
note("App::Fetchware's default imports [@App::Fetchware::EXPORT]");





###BUGALERT### Add actual tests to actually test uninstall(). See the existing
#uninstall tests that are in t/bin-fetchware-uninstall.t.



subtest 'test overriding uninstall()' => sub {
    # switch to *not* being package fetchware, so that I can test uninstall()'s
    # behavior as if its being called from a Fetchwarefile to create a callback
    # that uninstall will later call back in package fetchware.
    package main;
    use App::Fetchware;

    uninstall sub { return 'Overrode uninstall()!' };

    # Switch back to being in package fetchware, so that uninstall() will try out
    # the callback I gave it in the uninstall() call above.
    package fetchware;
    is(uninstall('fake arg'), 'Overrode uninstall()!',
        'checked overiding uninstall() success');
};




# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
