#!perl
# App-Fetchware-config-file.t tests App::Fetchware's configuration file
# subroutines except for fetchware which deserves its own test file.

use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '3'; #Update if this changes.

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

# Use extra private sub __CONFIG() to access App::Fetchware's internal state
# variable, so that I can test that the configuration subroutines work properly.
my $CONFIG = App::Fetchware::__CONFIG();

subtest 'test config file subs' => sub {
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

    diag explain $CONFIG;

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
        is($CONFIG->{$config_sub}, 'test', "checked config sub $config_sub");
    }

    # Test 'MANY' config subs.
    mirror 'test';
    mirror 'test';
    mirror 'test';
    mirror 'test';
    mirror 'test';

    diag explain $CONFIG;

    for (my $i = 0; $i <= 4; $i++) { # Its 0 based. 4 is the 5th entry.
        is($CONFIG->{mirror}->[$i], 'test', 'checked config sub mirror');
    }
    ok('Succeed', 'checked only 5 entries in mirror') if not defined $CONFIG->{mirror}->[5];

};

# Clear %CONFIG
%$CONFIG = ();

subtest 'test ONEARRREF config_file_subs()' => sub {
    my @onearrref_or_not = (
        [ filter => 'ONE' ],
        [ temp_dir => 'ONE' ],
        [ user => 'ONE' ],
        [ prefix => 'ONE' ],
        [ configure_options=> 'ONEARRREF' ],
        [ make_options => 'ONEARRREF' ],
        [ build_commands => 'ONEARRREF' ],
        [ install_commands => 'ONEARRREF' ],
        [ lookup_url => 'ONE' ],
        [ lookup_method => 'ONE' ],
        [ gpg_key_url => 'ONE' ],
        [ sha1_url => 'ONE' ],
        [ md5_url => 'ONE' ],
        [ verify_method => 'ONE' ],
        [ mirror => 'MANY' ],
        [ no_install => 'BOOLEAN' ],
        [ verify_failure_ok => 'BOOLEAN' ],
    );

    { no strict 'refs';

        for my $config_sub (@onearrref_or_not) {
            if ($config_sub->[1] eq 'ONE'
                or $config_sub->[1] eq 'BOOLEAN') {
#            eval_ok( sub {eval "$config_sub->[0] 'onevalue', 'twovalues';"},
                eval_ok( sub {("$config_sub->[0]")->('onevalue', 'twovalues');},
                    <<EOE, "checked $config_sub->[0] ONEARRREF support");
App-Fetchware: internal syntax error. $config_sub->[0] was called with more than one
option. $config_sub->[0] only supports just one option such as '$config_sub->[0] 'option';'. It does
not support more than one option such as '$config_sub->[0] 'option', 'another option';'.
Please chose one option not both, or combine both into one option. See perldoc
App::Fetchware.
EOE
                
            } elsif ($config_sub->[1] eq 'ONEARRREF'
                or $config_sub->[1] eq 'MANY') {
#            eval "$config_sub->[0] 'onevalue', 'twovalues';"
                ("$config_sub->[0]")->('onevalue', 'twovalues');
            } else {
                fail('Unknown config sub type!');
            }
        }
    }
};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();