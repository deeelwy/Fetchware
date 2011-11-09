#!perl
# Fetchware-config-file.t tests App::Fetchware's configuration file subroutines
# except for fetchware which deserves its own test file.

use strict;
use warnings;
use diagnostics;
use 5.010;

use Test::More tests => '20'; #Update if this changes.

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
BEGIN { use_ok('App::Fetchware'); }

# Print the subroutines that App::Fetchware imported by default when I used it.
diag("App::Fetchware's default imports [@App::Fetchware::EXPORT]");

my $class = 'App::Fetchware';

# Use extra private sub __FW() to access App::Fetchware's internal state
# variable, so that I can test that the configuration subroutines work properly.
my $FW = App::Fetchware::__FW();

# Test 'ONE' and 'BOOLEAN' config subs.
temp_dir 'test';
user 'test';
prefix 'test';
configure_options 'test';
make_options 'test';
build_commands 'test';
install_commands 'test';
lookup_url 'test';
lookup_method 'test';
gpg_key_url 'test';
verify_method 'test';
no_install 'test';
verify_failure_ok 'test';

diag explain $FW;

for my $config_sub (qw(
    temp_dir
    user
    prefix
    configure_options
    make_options
    build_commands
    install_commands
    lookup_url
    lookup_method
    gpg_key_url
    verify_method
    no_install
    verify_failure_ok
)) {
    is($FW->{$config_sub}, 'test', "checked config sub $config_sub");
}

# Test 'MANY' config subs.
mirror 'test';
mirror 'test';
mirror 'test';
mirror 'test';
mirror 'test';

diag explain $FW;

for (my $i = 0; $i <= 4; $i++) { # Its 0 based. 4 is the 5th entry.
    is($FW->{mirror}->[$i], 'test', 'checked config sub mirror');
}
ok($FW->{mirror}->[5] eq undef, 'checked only 5 entries in mirror');


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
