#!perl
# Fetchware-fetchware.t tests App::Fetchware's fetchware() subroutine.
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '2'; #Update if this changes.

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
BEGIN { use_ok('App::Fetchware', qw(:DEFAULT :TESTING)); }


# Print the subroutines that App::Fetchware imported by default when I used it.
diag("App::Fetchware's default imports [@App::Fetchware::EXPORT]");

my $class = 'App::Fetchware';

# Use extra private sub __FW() to access App::Fetchware's internal state
# variable, so that I can test that the configuration subroutines work properly.
my $FW = App::Fetchware::__FW();

subtest 'fetchware success' => sub {
    skip_all_unless_release_testing();

    # All fetchware really needs is just a lookup_url...
    lookup_url "$ENV{FETCHWARE_FTP_LOOKUP_URL}";

    # ...Except that httpd has beta builds with a different dir structure on
    # their mirror, so a fiter is called for.
    filter 'httpd-2.2';

    ok(fetchware, 'checked fetchware success');

};

# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
