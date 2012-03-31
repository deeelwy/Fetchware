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


##TEST##subtest 'test parse_fetchwarefile(Fetchwarefile)' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    my $correct_fetchwarefile = <<EOF;
##TEST##use App::Fetchware;
##TEST##program 'who cares';
##TEST##
##TEST##lookup_url 'http://doesnt.exist/anywhere';
##TEST##EOF
##TEST##
##TEST##    # Use a scalar ref instead of a real file to avoid having to write and read
##TEST##    # files unnecessarily.
##TEST##    ok(parse_fetchwarefile(\ $correct_fetchwarefile),
##TEST##        'checked parse_fetchwarefile() success');
##TEST##
##TEST##    test_config({program => 'who cares',
##TEST##            lookup_url => 'http://doesnt.exist/anywhere'},
##TEST##        'checked parse_fetchwarefile() success CONFIG');
##TEST##    
##TEST##    eval_ok(sub {parse_fetchwarefile('doesntexist.ever-anywhere')},
##TEST##        <<EOE, 'checked parse_fetchwarefile() failed open');
##TEST##fetchware: run-time error. fetchware failed to open the Fetchwarefile you
##TEST##specified on the command line [doesntexist.ever-anywhere]. Please check permissions
##TEST##and try again. See perldoc App::Fetchware. The system error was [No such file or directory].
##TEST##EOE
##TEST##
##TEST##    ###BUGALERT### How do I test the unlink()ing of the provided filename? Give
##TEST##    #a filename that has read perms, but no delete perms?
##TEST##
##TEST##    my $syntax_errors = <<EOS;
##TEST### J Random syntax error.
##TEST##for {
##TEST##EOS
##TEST##
##TEST##    eval_ok(sub {parse_fetchwarefile(\ $syntax_errors)},
##TEST##        qr/fetchware failed to execute the Fetchwarefile/,
##TEST##        'checked parse_fetchwarefile() failed to execute Fetchwarefile');
##TEST##
##TEST##};


#subtest 'test create_fetchware_package()' => sub {
    skip_all_unless_release_testing();

    my $fetchwarefile_path = create_test_fetchwarefile('# Fake Fetchwarefile for testing');

    # Create a hopefully successful fetchware package using the current working
    # directory (my Fetchware git checkout) and the fake Fetchwarefile I created
    # above.
    is(create_fetchware_package($fetchwarefile_path, cwd()),
        catfile(cwd(), 'App-Fetchware.fpkg'),
        'checked create_fetchware_package() success');

    # Delete generated files.
    ok(unlink('App-Fetchware.fpkg') == 1,
        'checked create_fetchware_package() delete generated files');

    eval_ok(sub {create_fetchware_package('doesntexist.ever-anywhere', cwd())},
        <<EOE, 'checked create_fetchware_package() cp failure');
fetchware: run-time error. Fetchware failed to copy the Fetchwarefile you
specified [doesntexist.ever-anywhere] on the command line or was contained in the
fetchware package you specified to the newly created fetchware package. Please
see perldoc App::Fetchware. OS error [No such file or directory].
EOE

#};
##TEST##
##TEST##
##TEST##subtest 'check fetchware_database_path()' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    if (is_os_type('Unix', $^O)) {
##TEST##        # If we're effectively root use a "system" directory.
##TEST##        if ($> == 0) {
##TEST##            is(fetchware_database_path(), '/var/log/fetchware',
##TEST##                'checked fetchware_database_path() as root');
##TEST##        # else use a "user" directory.
##TEST##        } else {
##TEST##            is(fetchware_database_path(), '/home/dly/.local/share/Perl/dist/fetchware',
##TEST##                'checked fetchware_database_path() as user');
##TEST##        }
##TEST##    } elsif ($^O eq "MSWin32") {
##TEST##        # Load main Windows module to use to see if we're Administrator or not.
##TEST##        BEGIN {
##TEST##            if ($^O eq "MSWin32")
##TEST##            {
##TEST##                require Win32;
##TEST##                Module->import();  # assuming you would not be passing arguments to "use Module"
##TEST##            }
##TEST##        }
##TEST##        if (Win32::IsAdminUser()) {
##TEST##            is(fetchware_database_path(), 'C:\fetchware',
##TEST##                'checked fetchware_database_path() as Administrator on Win32');
##TEST##        } else {
##TEST##            ###BUGALERT### Add support for this test on Windows!
##TEST##            fail('Must add support for non-admin on Windows!!!');
##TEST##        }
##TEST##    # Fall back on File::HomeDir's recommendation if not "Unix" or windows.
##TEST##    } else {
##TEST##            ###BUGALERT### Add support for everything else too!!!
##TEST##            fail('Must add support for your OS!!!');
##TEST##    }
##TEST##    
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'check determine_fetchware_package_path()' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    # Write some test files to my fetchware_database_path() to test determining
##TEST##    # if they're there or not.
##TEST##    my $fetchware_db_path = fetchware_database_path();
##TEST##    my @test_files = qw(fake-apache fake-apache2 mariadb qmail nginx);
##TEST##    for my $file (@test_files) {
##TEST##        ok(open( my $fh, '>', catfile($fetchware_db_path, $file)),
##TEST##            "check determine_fetchware_package_path() test file creation [$file]");
##TEST##        print $fh "# Meaningless test Fetchwarefile $file";
##TEST##        close $fh;
##TEST##    }
##TEST##
##TEST##    # Now test multiple results with one query.
##TEST##    is(determine_fetchware_package_path('apache'), 2,
##TEST##        "checked determine_fetchware_package_path() multiple values");
##TEST##
##TEST##    # Remove both apache's from further tests, because it will return 2 instead
##TEST##    # of a single scalar like the test assumes.
##TEST##    my @apacheless_test_files = grep { $_ !~ /apache/ } @test_files;
##TEST##
##TEST##    for my $file (@apacheless_test_files) {
##TEST##        like(determine_fetchware_package_path($file), qr/$file/,
##TEST##            "checked determine_fetchware_package_path() [$file] success");
##TEST##    }
##TEST##
##TEST##
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'check extract_fetchwarefile()' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    my $test_string = '# Fake Fetchwarefile just for testing';
##TEST##    my $fetchwarefile_path = create_test_fetchwarefile($test_string);
##TEST##
##TEST##    # Create a test fetchware package to text extract_fetchwarefile().
##TEST##    my $fetchware_package_path = create_fetchware_package($fetchwarefile_path, cwd());
##TEST##
##TEST##    ok(unlink('Fetchwarefile'),
##TEST##        'checked extract_fetchwarefile() delete test Fetchwarefile');
##TEST##
##TEST##    diag("TFPP[$fetchware_package_path]");
##TEST##    is( ( splitpath(extract_fetchwarefile($fetchware_package_path, cwd())) )[2],
##TEST##        'Fetchwarefile', 'checked extract_fetchwarefile() success');
##TEST##    my $fh;
##TEST##    ok(open($fh, '<', './Fetchwarefile'),
##TEST##        'checked extract_fetchwarefile() success open Fetchwarefile');
##TEST##    my $got_fetchwarefile;
##TEST##    {
##TEST##        local $/;
##TEST##        undef $/;
##TEST##        $got_fetchwarefile = <$fh>;
##TEST##    }
##TEST##    diag("GF[$got_fetchwarefile]");
##TEST##    is($got_fetchwarefile, $test_string,
##TEST##        q{checked extract_fetchwarefile() success Fetchwarefile's match});
##TEST##
##TEST##    # Delete generated files.
##TEST##    ok(unlink('App-Fetchware.tar.gz'),
##TEST##        'checked extract_fetchwarefile() delete generated files');
##TEST##};
##TEST##
##TEST##
##TEST##
##TEST##subtest 'check copy_fpkg_to_fpkg_database()' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    # Build a fetchwarefile package needed, so I can test installing it.
##TEST##    my $test_string = '# Fake Fetchwarefile just for testing';
##TEST##    my $fetchwarefile_path = create_test_fetchwarefile($test_string);
##TEST##    my $fetchware_package_path = create_fetchware_package($fetchwarefile_path, cwd());
##TEST##
##TEST##    copy_fpkg_to_fpkg_database($fetchware_package_path);
##TEST##
##TEST##    # Get filename from the test packages original path.
##TEST##    my ($fetchware_package_filename) = ( splitpath($fetchware_package_path) )[2];
##TEST##
##TEST##    ok(-e catfile(fetchware_database_path(), $fetchware_package_filename),
##TEST##        'check copy_fpkg_to_fpkg_database() success');
##TEST##
##TEST##    ###BUGALERT### Use Sub::Override to override fetchware_package_path(), so I
##TEST##    #can override its behavior and test this subroutine for failure.
##TEST##
##TEST##    # Delete generated files.
##TEST##    ok(unlink('Fetchwarefile', 'App-Fetchware.fpkg'),
##TEST##        'checked extract_fetchwarefile() delete generated files');
##TEST##};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
done_testing();


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
