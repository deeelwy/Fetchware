#!perl
# bin-fetchware-util.t tests bin/fetchware's utility subroutines, which provide
# utility and library functionality for bin/fetchware's main command
# subroutines.
use strict;
use warnings;
use diagnostics;
use 5.010;


# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98;# tests => '7'; #Update if this changes.

use App::Fetchware qw(:TESTING config);
use Cwd 'cwd';
use File::Spec::Functions qw(catfile splitpath);
use Perl::OSType 'is_os_type';
use File::Temp 'tempdir';

# Crank up security to 11.
File::Temp->safe_level( File::Temp::HIGH );


# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Load bin/fetchware "manually," because it isn't a real module, and has no .pm
# extenstion use expects.
BEGIN {
    my $fetchware = 'fetchware';
    use lib 'bin';
    require $fetchware;
    fetchware->import(':TESTING');
    ok(defined $INC{$fetchware}, 'checked bin/fetchware loading and import')
}


subtest 'test eval_config_file(Fetchwarefile)' => sub {
    skip_all_unless_release_testing();

    my $correct_fetchwarefile = <<EOF;
use App::Fetchware;
program 'who cares';

lookup_url 'http://doesnt.exist/anywhere';
EOF

    # Use a scalar ref instead of a real file to avoid having to write and read
    # files unnecessarily.
    ok(eval_config_file(\ $correct_fetchwarefile),
        'checked eval_config_file() success');

    test_config({program => 'who cares',
            lookup_url => 'http://doesnt.exist/anywhere'},
        'checked eval_config_file() success CONFIG');
    
    eval_ok(sub {eval_config_file('doesntexist.ever-anywhere')},
        <<EOE, 'checked eval_config_file() failed open');
fetchware: run-time error. fetchware failed to open the Fetchwarefile you
specified on the command line [doesntexist.ever-anywhere]. Please check permissions
and try again. See perldoc App::Fetchware. The system error was [No such file or directory].
EOE

    ###BUGALERT### How do I test the unlink()ing of the provided filename? Give
    #a filename that has read perms, but no delete perms?

    my $syntax_errors = <<EOS;
# J Random syntax error.
for {
EOS

    eval_ok(sub {eval_config_file(\ $syntax_errors)},
        qr/fetchware failed to execute the Fetchwarefile/,
        'checked eval_config_file() failed to execute Fetchwarefile');

};


subtest 'test create_fetchware_package()' => sub {
    skip_all_unless_release_testing();

    my $fetchwarefile_path = create_test_fetchwarefile('# Fake Fetchwarefile for testing');

    # Create a hopefully successful fetchware package using the current working
    # directory (my Fetchware git checkout) and the fake Fetchwarefile I created
    # above.
    is(create_fetchware_package($fetchwarefile_path, cwd()),
        catfile(cwd(), 'App-Fetchware.fpkg'),
        'checked create_fetchware_package() success');

    # Delete generated files.
    ok(unlink('Fetchwarefile', 'App-Fetchware.fpkg') == 2,
        'checked create_fetchware_package() delete generated files');

    eval_ok(sub {create_fetchware_package('doesntexist.ever-anywhere', cwd())},
        <<EOE, 'checked create_fetchware_package() cp failure');
fetchware: run-time error. Fetchware failed to copy the Fetchwarefile you
specified [doesntexist.ever-anywhere] on the command line or was contained in the
fetchware package you specified to the newly created fetchware package. Please
see perldoc App::Fetchware.
EOE

};


subtest 'check fetchware_database_path()' => sub {
    skip_all_unless_release_testing();

    if (is_os_type('Unix', $^O)) {
        # If we're effectively root use a "system" directory.
        if ($> == 0) {
            is(fetchware_database_path(), '/var/log/fetchware',
                'checked fetchware_database_path() as root');
        # else use a "user" directory.
        } else {
            is(fetchware_database_path(), '/home/dly/.local/share/Perl/dist/fetchware',
                'checked fetchware_database_path() as user');
        }
    } elsif ($^O eq "MSWin32") {
        # Load main Windows module to use to see if we're Administrator or not.
        BEGIN {
            if ($^O eq "MSWin32")
            {
                require Win32;
                Module->import();  # assuming you would not be passing arguments to "use Module"
            }
        }
        if (Win32::IsAdminUser()) {
            is(fetchware_database_path(), 'C:\fetchware',
                'checked fetchware_database_path() as Administrator on Win32');
        } else {
            ###BUGALERT### Add support for this test on Windows!
            fail('Must add support for non-admin on Windows!!!');
        }
    # Fall back on File::HomeDir's recommendation if not "Unix" or windows.
    } else {
            ###BUGALERT### Add support for everything else too!!!
            fail('Must add support for your OS!!!');
    }
    
};


subtest 'check determine_fetchware_package_path()' => sub {
    skip_all_unless_release_testing();

    # Write some test files to my fetchware_database_path() to test determining
    # if they're there or not.
    my $fetchware_db_path = fetchware_database_path();
    my @test_files = qw(fake-apache fake-apache2 mariadb qmail nginx);
    for my $file (@test_files) {
        ok(open( my $fh, '>', catfile($fetchware_db_path, $file)),
            "check determine_fetchware_package_path() test file creation [$file]");
        print $fh "# Meaningless test Fetchwarefile $file";
        close $fh;
    }

    # Now test multiple results with one query.
    is(determine_fetchware_package_path('apache'), 2,
        "checked determine_fetchware_package_path() multiple values");

    # Remove both apache's from further tests, because it will return 2 instead
    # of a single scalar like the test assumes.
    my @apacheless_test_files = grep { $_ !~ /apache/ } @test_files;

    for my $file (@apacheless_test_files) {
        like(determine_fetchware_package_path($file), qr/$file/,
            "checked determine_fetchware_package_path() [$file] success");
    }


};


subtest 'check extract_fetchwarefile()' => sub {
    skip_all_unless_release_testing();

    my $test_string = '# Fake Fetchwarefile just for testing';
    my $fetchwarefile_path = create_test_fetchwarefile($test_string);

    # Create a test fetchware package to text extract_fetchwarefile().
    my $fetchware_package_path = create_fetchware_package($fetchwarefile_path, cwd());

    ok(unlink('Fetchwarefile'),
        'checked extract_fetchwarefile() delete test Fetchwarefile');

    diag("TFPP[$fetchware_package_path]");
    is( ( splitpath(extract_fetchwarefile($fetchware_package_path, cwd())) )[2],
        'Fetchwarefile', 'checked extract_fetchwarefile() success');
    my $fh;
    ok(open($fh, '<', './Fetchwarefile'),
        'checked extract_fetchwarefile() success open Fetchwarefile');
    my $got_fetchwarefile;
    {
        local $/;
        undef $/;
        $got_fetchwarefile = <$fh>;
    }
    diag("GF[$got_fetchwarefile]");
    is($got_fetchwarefile, $test_string,
        q{checked extract_fetchwarefile() success Fetchwarefile's match});

    # Delete generated files.
    ok(unlink('Fetchwarefile', 'App-Fetchware.tar.gz'),
        'checked extract_fetchwarefile() delete generated files');
};



subtest 'check copy_fpkg_to_fpkg_database()' => sub {
    skip_all_unless_release_testing();

    # Build a fetchwarefile package needed, so I can test installing it.
    my $test_string = '# Fake Fetchwarefile just for testing';
    my $fetchwarefile_path = create_test_fetchwarefile($test_string);
    my $fetchware_package_path = create_fetchware_package($fetchwarefile_path, cwd());

    copy_fpkg_to_fpkg_database($fetchware_package_path);

    # Get filename from the test packages original path.
    my ($fetchware_package_filename) = ( splitpath($fetchware_package_path) )[2];

    ok(-e catfile(fetchware_database_path(), $fetchware_package_filename),
        'check copy_fpkg_to_fpkg_database() success');

    ###BUGALERT### Use Sub::Override to override fetchware_package_path(), so I
    #can override its behavior and test this subroutine for failure.

    # Delete generated files.
    ok(unlink('Fetchwarefile', 'App-Fetchware.fpkg'),
        'checked extract_fetchwarefile() delete generated files');
};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
done_testing();


sub create_test_fetchwarefile {
    my $fetchwarefile_content = shift;

    # Use a temp dir outside of the installation directory 
    my $tempdir = tempdir ('fetchware-XXXXXXXXXXX', TMPDIR => 1, CLEANUP => 1);
    my $fetchwarefile_path = catfile($tempdir, 'Fetchwarefile');

    # Create a fake Fetchwarefile for our fake fetchware package.
    my $write_fh;
    ok(open($write_fh, '>', $fetchwarefile_path),
        'checked create_fetchware_package() open file');
    
    # Put test stuff in Fetchwarefile.
    print $write_fh "$fetchwarefile_content";

    # Close the file in case it bothers Archive::Tar reading it.
    close $write_fh;

    return $fetchwarefile_path;
}


sub test_config {
    my ($expected_config_hash, $message) = @_;

    for my $expected_key (keys %$expected_config_hash) {
        unless ($expected_config_hash->{$expected_key}
            eq
            config($expected_key)) {
            fail($message);
        }
    }
    pass($message);
}
