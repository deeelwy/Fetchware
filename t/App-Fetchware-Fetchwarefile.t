#!perl
# App-Fetchware-Fetchwarefile.t tests App::Fetchware's Fetchwarefile object that
# represents Fetchwarefile's when new() makes them. It has nothing to do with
# Fetchwarefile's during any other command.
use strict;
use warnings;
use diagnostics;
use 5.010001;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '6'; #Update if this changes.

use File::Spec::Functions qw(splitpath catfile rel2abs tmpdir);
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
BEGIN { use_ok('App::Fetchware::Fetchwarefile'); }

# "Manually" import _append_to_fetchwarefile, because it's an internal
# subroutine that only generate() should us.
*main::_append_to_fetchwarefile =
*App::Fetchware::Fetchwarefile::_append_to_fetchwarefile;



subtest 'check new() exceptions' => sub {
    eval_ok(sub {App::Fetchware::Fetchwarefile->new()},
        qr/Fetchwarefile: you failed to include a header option in your call to/,
        'checked new() header exception');

    eval_ok(sub {App::Fetchware::Fetchwarefile->new(
            header => 'Test Header')},
        qr/Fetchwarefile: you failed to include a descriptions hash option in your call to/,
        'checked new() descriptions exception');


    eval_ok(sub {App::Fetchware::Fetchwarefile->new(
            header => 'Test Header',
            descriptions => 'Not a hashref'
        )},
        qr/Fetchwarefile: the descriptions hash value must be a hash ref whoose keys are/,
        'checked new() header exception');
};


subtest 'check new() success' => sub {

    my $fetchwarefile = App::Fetchware::Fetchwarefile->new(
        header => <<EOF,
use App::Fetchware;
# Auto generated @{[localtime()]} by fetchware's new command.
# However, feel free to edit this file if fetchware's new command's
# autoconfiguration is not enough.
# 
# Please look up fetchware's documentation of its configuration file syntax at
# perldoc App::Fetchware, and only if its configuration file syntax is not
# malleable enough for your application should you resort to customizing
# fetchware's behavior. For extra flexible customization see perldoc
# App::Fetchware.
EOF
        descriptions => {
            program => <<EOD,
program simply names the program the Fetchwarefile is responsible for
downloading, building, and installing.
EOD
            temp_dir => <<EOD,
temp_dir specifies what temporary directory fetchware will use to download and
build this program.
EOD
        }
    );

    isa_ok($fetchwarefile, 'App::Fetchware::Fetchwarefile');

    # Check if $fetchwarefile's internals are right.
    ok(exists $fetchwarefile->{header},
        'checked new() internals for header');
    ok(exists $fetchwarefile->{descriptions},
        'checked new() internals for descriptions');
};


subtest 'test config_options() success' => sub {
    
    # Need a $fetchwarefile object to test config_options().
    my $fetchwarefile = App::Fetchware::Fetchwarefile->new(
        header => <<EOF,
use App::Fetchware;
# Auto generated @{[localtime()]} by fetchware's new command.
# However, feel free to edit this file if fetchware's new command's
# autoconfiguration is not enough.
# 
# Please look up fetchware's documentation of its configuration file syntax at
# perldoc App::Fetchware, and only if its configuration file syntax is not
# malleable enough for your application should you resort to customizing
# fetchware's behavior. For extra flexible customization see perldoc
# App::Fetchware.
EOF
        descriptions => {
            program => <<EOD,
program simply names the program the Fetchwarefile is responsible for
downloading, building, and installing.
EOD
            temp_dir => <<EOD,
temp_dir specifies what temporary directory fetchware will use to download and
build this program.
EOD
        }
    );

    my %test_config_options = (
        program => ['Test Program'],
        temp_dir => ['/var/tmp'],
    );
 
    # Add the test config options to the $fetchwarefile object.
    $fetchwarefile->config_options($_, @{$test_config_options{$_}})
        for keys %test_config_options;

    is_deeply($fetchwarefile->{config_options}, \%test_config_options,
        'checked config_options() adding new options');

    # Test config_options() as an accessor.
    for my $test_config_option (keys %test_config_options) {
        is_deeply([$fetchwarefile->config_options($test_config_option)],
            $test_config_options{$test_config_option},
            "checked config_options() getter [$test_config_option]");
    }

    # Fetchwarefile supports 'MANY' and 'ONEARRREF' types, so test config
    # options that have more than one value.
    $fetchwarefile->config_options(mirror => $_) for 1 .. 5;

    is_deeply([@{$fetchwarefile->{config_options}->{mirror}}],
        [1 .. 5],
        'checked config_options multiple options');

    is_deeply([$fetchwarefile->config_options('mirror')],
        [1 .. 5],
        'checked config_options getter multiple options');
};


subtest 'test _append_to_fetchwarefile() success' => sub {
    my $fetchwarefile;

    _append_to_fetchwarefile(\$fetchwarefile,
        'program', 'test-dist', 'A meaningless test example.');
    is($fetchwarefile,
        <<EOE, 'checked _append_to_fetchwarefile() success.');


# A meaningless test example.
program 'test-dist';
EOE

    undef $fetchwarefile;

    # Test a description with more than 80 chars.
    _append_to_fetchwarefile(\$fetchwarefile,
                'program', 'test-dist',
            q{test with more than 80 chars to test the logic that chops it up into lines that are only 80 chars long. Do you think it will work?? Well, let's hope so!
    });
    is($fetchwarefile,
        <<EOE, 'checked _append_to_fetchwarefile() success.');


# test with more than 80 chars to test the logic that chops it up into lines
# that are only 80 chars long. Do you think it will work?? Well, let's hope so!
program 'test-dist';
EOE

    eval_ok(sub {_append_to_fetchwarefile($fetchwarefile,
        'program', 'test-dist', 'description')},
    <<EOE, 'checked _append_to_fetchwarefile() excpetion');
fetchware: run-time error. You called _append_to_fetchwarefile() with a
fetchwarefile argument that is not a scalar reference. Please add the need
backslash reference operator to your call to _append_to_fetchwarefile() and try
again.
EOE
};


subtest 'Test genrate() success' => sub {
    
    # Need a $fetchwarefile object to test config_options().
    my $fetchwarefile = App::Fetchware::Fetchwarefile->new(
        header => <<EOF,
use App::Fetchware;
# Auto generated by fetchware's new command.
# However, feel free to edit this file if fetchware's new command's
# autoconfiguration is not enough.
#
# Please look up fetchware's documentation of its configuration file syntax at
# perldoc App::Fetchware, and only if its configuration file syntax is not
# malleable enough for your application should you resort to customizing
# fetchware's behavior. For extra flexible customization see perldoc
# App::Fetchware.
EOF
        descriptions => {
            program => <<EOD,
program simply names the program the Fetchwarefile is responsible for
downloading, building, and installing.
EOD
            temp_dir => <<EOD,
temp_dir specifies what temporary directory fetchware will use to download and
build this program.
EOD
        }
    );

    # Add some options to my $fetchwarefile.
    $fetchwarefile->config_options(
        program => 'Test Program',
        temp_dir => '/var/tmp',
    );

    my $expected_fetchwarefile = <<EOF;
use App::Fetchware;
# Auto generated by fetchware's new command.
# However, feel free to edit this file if fetchware's new command's
# autoconfiguration is not enough.
#
# Please look up fetchware's documentation of its configuration file syntax at
# perldoc App::Fetchware, and only if its configuration file syntax is not
# malleable enough for your application should you resort to customizing
# fetchware's behavior. For extra flexible customization see perldoc
# App::Fetchware.


# temp_dir specifies what temporary directory fetchware will use to download and
# build this program.
temp_dir '/var/tmp';


# program simply names the program the Fetchwarefile is responsible for
# downloading, building, and installing.
program 'Test Program';
EOF

    is($fetchwarefile->generate(),
        $expected_fetchwarefile,
        'checked generate() success');
};



# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
