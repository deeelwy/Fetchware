#!perl
# Fetchware-start.t tests App::Fetchware's start() subroutine, which
# determines if a new version of your program is available.
use strict;
use warnings;
use diagnostics;
use 5.010;

use Test::More tests => '2'; #Update if this changes.

use File::Spec::Functions qw(splitpath catfile);
use URI::Split 'uri_split';
use Cwd 'cwd';

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

# Use extra private sub __FW() to access App::Fetchware's internal state
# variable, so that I can test that the configuration subroutines work properly.
my $FW = App::Fetchware::__FW();


subtest 'test start()' => sub {
    skip_all_unless_release_testing();

    start();

    ok(-e $FW->{TempDir}, 'check start() success');
    
    # chdir() so File::Temp can delete the tempdir.
    chdir();
};




# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
