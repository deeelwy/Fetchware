#!perl
# bin-fetchware-util.t tests bin/fetchware's utility subroutines, which provide
# utility and library functionality for bin/fetchware's main command
# subroutines.
use strict;
use warnings;
use diagnostics;
use 5.010;


# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '7'; #Update if this changes.

use App::Fetchware qw(:TESTING config);
use Cwd 'cwd';
use File::Spec::Functions qw(catfile splitpath splitdir catdir catpath);
use Path::Class;
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


subtest 'test parse_fetchwarefile(Fetchwarefile)' => sub {
    skip_all_unless_release_testing();

    my $correct_fetchwarefile = <<EOF;
use App::Fetchware;
program 'who cares';

lookup_url 'http://doesnt.exist/anywhere';
EOF

    # Use a scalar ref instead of a real file to avoid having to write and read
    # files unnecessarily.
    ok(parse_fetchwarefile(\ $correct_fetchwarefile),
        'checked parse_fetchwarefile() success');

    test_config({program => 'who cares',
            lookup_url => 'http://doesnt.exist/anywhere'},
        'checked parse_fetchwarefile() success CONFIG');
    
    eval_ok(sub {parse_fetchwarefile('doesntexist.ever-anywhere')},
        <<EOE, 'checked parse_fetchwarefile() failed open');
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

    eval_ok(sub {parse_fetchwarefile(\ $syntax_errors)},
        qr/fetchware failed to execute the Fetchwarefile/,
        'checked parse_fetchwarefile() failed to execute Fetchwarefile');

};


subtest 'test create_fetchware_package()' => sub {
    ###BUGALERT### Must add tests for adding the gpg generated files to the
    #fetchware package, so that gpg doesn't have to download the keys again.
    #Also, I must actually add code for this in bin/fetchware.
    skip_all_unless_release_testing();

    my $fetchwarefile_path = create_test_fetchwarefile('# Fake Fetchwarefile for testing');

    # Create a hopefully successful fetchware package using the current working
    # directory (my Fetchware git checkout) and the fake Fetchwarefile I created
    # above.
    my $cwd = dir(cwd());
    my $cwd_parent = $cwd->parent();
    is(create_fetchware_package($fetchwarefile_path, cwd()),
        catfile($cwd_parent, 'App-Fetchware.fpkg'),
        'checked create_fetchware_package() success');

    # Delete generated files.
    ok(unlink(catfile($cwd_parent,'App-Fetchware.fpkg')) == 1,
        'checked create_fetchware_package() delete generated files');

##CANNOTTEST## Can't test anymore, because the doesntexist.ever-anywhere file
#will fail the unless conditional and skip the cp() call, so I can't test for
#this specifically anymore.
##CANNOTTEST##    eval_ok(sub {create_fetchware_package('doesntexist.ever-anywhere', cwd())},
##CANNOTTEST##        <<EOE, 'checked create_fetchware_package() cp failure');
##CANNOTTEST##fetchware: run-time error. Fetchware failed to copy the Fetchwarefile you
##CANNOTTEST##specified [doesntexist.ever-anywhere] on the command line or was contained in the
##CANNOTTEST##fetchware package you specified to the newly created fetchware package. Please
##CANNOTTEST##see perldoc App::Fetchware. OS error [No such file or directory].
##CANNOTTEST##EOE

    ok(chdir($cwd), 'checked create_fetchware_package() chdir back to base directory');

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
    eval_ok(sub {determine_fetchware_package_path('apache')},
        <<EOE, 'checked determine_fetchware_package_path() multiple values');
Choose which package from the list above you want to upgrade, and rerun
fetchware upgrade using it as the argument for the package you want to upgrade.
EOE

    # Remove both apache's from further tests, because it will return 2 instead
    # of a single scalar like the test assumes.
    my @apacheless_test_files = grep { $_ !~ /apache/ } @test_files;

    for my $file (@apacheless_test_files) {
        like(determine_fetchware_package_path($file), qr/$file/,
            "checked determine_fetchware_package_path() [$file] success");
    }
    
    ok( ( map { unlink catfile($fetchware_db_path, $_) } @test_files ) == 5,
        'checked determine_fetchware_package_path() delete test files');

};


subtest 'check extract_fetchwarefile()' => sub {
    skip_all_unless_release_testing();

    my $test_string = '# Fake Fetchwarefile just for testing';
    my $fetchwarefile_path = create_test_fetchwarefile($test_string);

    my $pc = dir(cwd());
    my $last_dir = $pc->dir_list(-1, 1);
    diag("LASTDIR[$last_dir]");

    diag("CWD[@{[cwd()]}]");
    


    # Create a test fetchware package to text extract_fetchwarefile().
    my $fetchware_package_path = create_fetchware_package($fetchwarefile_path, $last_dir);

    diag("TFPP[$fetchware_package_path]");

    is( ( splitpath(extract_fetchwarefile($fetchware_package_path, cwd())) )[2],
        'Fetchwarefile', 'checked extract_fetchwarefile() success');
    my $fh;
    ok(open($fh, '<', $fetchwarefile_path),
        "checked extract_fetchwarefile() success open [$fetchwarefile_path]");
    my $got_fetchwarefile;
    {
        local $/;
        undef $/;
        $got_fetchwarefile = <$fh>;
    }
    diag("GF[$got_fetchwarefile]");
    is($got_fetchwarefile, $test_string,
        q{checked extract_fetchwarefile() success Fetchwarefile's match});

    # Test existence of generated files.
    ok(-e '../App-Fetchware.fpkg' && -e './Fetchwarefile',
        'checked extract_fetchwarefile() existence of generated files');
    
    # Delete generated files.
    ok(unlink('../App-Fetchware.fpkg', './Fetchwarefile') == 2,
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
    ok(unlink('../Fetchwarefile', '../App-Fetchware.fpkg'),
        'checked extract_fetchwarefile() delete generated files');
};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();


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
