#!perl
# bin-fetchware-upgrade.t tests bin/fetchware's cmd_upgrade() subroutine, which
# upgrades fetchware packages given a fetchware packge name, but not an actual
# fetchware package or Fetchwarefile.
use strict;
use warnings;
use diagnostics;
use 5.010001;


# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '3'; #Update if this changes.

use App::Fetchware::Config ':CONFIG';
use Test::Fetchware ':TESTING';
use Cwd 'cwd';
use File::Copy 'cp';
use File::Spec::Functions qw(catfile splitpath);
use Path::Class;
use File::Temp 'tempdir';


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

subtest 'test cmd_upgrade() success' => sub {
    skip_all_unless_release_testing();

    # Delete all existing httpd fetchware packages in fetchware_database_path(),
    # which will screw up the installation and upgrading of httpd below.
    for my $fetchware_package (glob catfile(fetchware_database_path(), '*')) {
        # Clean up $fetchware_package.
        if ($fetchware_package =~ /httpd/) {
            ok((unlink $fetchware_package),
                'checked cmd_upgrade() clean up fetchware database path')
                if -e $fetchware_package
        }
    }
    # Also delete Apache 2.2.22 from $ENV{FETCHWARE_LOCAL_UPGRADE_PATH}
    my $striped_upgrade_path = $ENV{FETCHWARE_LOCAL_UPGRADE_URL};
    $striped_upgrade_path =~ s!^file://!!;
    my $httpd_upgrade_path
        = catfile($striped_upgrade_path, 'httpd-2.2.22.tar.bz2');
    my $httpd_upgrade_asc
        = catfile($striped_upgrade_path, 'httpd-2.2.22.tar.bz2.asc');
    for ($httpd_upgrade_path, $httpd_upgrade_asc) {
        ok(unlink($_),
            'checked cmd_upgrade() cleanup $ENV{FETCHWARE_LOCAL_UPGRADE_URL}')
            if -e $_;
    }

my $fetchwarefile = <<EOF;
use App::Fetchware;

program 'Apache 2.2';

lookup_url '$ENV{FETCHWARE_LOCAL_UPGRADE_URL}';

filter 'httpd-2.2';
EOF

note('FETCHWAREFILE');
note("$fetchwarefile");
    my $fetchwarefile_path = create_test_fetchwarefile($fetchwarefile);

    ok(-e $fetchwarefile_path,
        'check create_test_fetchwarefile() test Fetchwarefile');

    # I obviously must install apache before I can test upgrading it :)
    my $fetchware_package_path = cmd_install($fetchwarefile_path);
    # And then test if the install was successful.
    ok(grep /httpd-2\.2/, glob(catfile(fetchware_database_path(), '*')),
        'check cmd_install(Fetchware) success.');

    # Clear internal %CONFIG variable, because I have to parse a Fetchwarefile
    # twice, and it's only supported once.
    __clear_CONFIG();
    # Also copy over the latest version of httpd, so that I don't have to change
    # the lookup_url in the Fetchwarefile of the httpd fetchware package.
    my $parent_upgrade_path = dir($striped_upgrade_path)->parent();
    my $httpd_upgrade = catfile($parent_upgrade_path, 'httpd-2.2.22.tar.bz2');
    my $httpd_upgrade_asc = catfile($parent_upgrade_path,
        'httpd-2.2.22.tar.bz2.asc');
note("httpd_upgrade[$httpd_upgrade] stripedupgradepath[$striped_upgrade_path]");
    ok(cp($httpd_upgrade, $striped_upgrade_path),
        'checked cmd_upgrade() cp new version to local upgrade url');
note("httpd_upgrade_asc[$httpd_upgrade_asc]");
    ok(cp($httpd_upgrade_asc, $striped_upgrade_path),
        'checked cmd_upgrade() cp new version asc to local upgrade url');

    # cmd_uninstall accepts a string that needs to be found in the fetchware
    # database. It does *not* take Fetchwarefiles or fetchware packages as
    # arguments.
    my $uninstalled_package_path = cmd_upgrade('httpd');

    print_ok(sub {cmd_list()},
        sub {grep({$_ =~ /httpd-2\.2\.22/} (split "\n", $_[0]))},
        'check cmd_upgrade() success.');


    # Test for when cmd_upgrade() determines that the latest version is
    # installed.
    # Clear internal %CONFIG variable, because I have to pare a Fetchwarefile
    # twice, and it's only supported once.
    __clear_CONFIG();
    is(cmd_upgrade('httpd'), 'No upgrade needed.',
        'checked cmd_upgrade() latest version already installed.');

    # Clean up upgrade path.
    my $httpd_upgrade_to_delete = catfile($striped_upgrade_path,
        file($httpd_upgrade)->basename());
    my $httpd_upgrade_asc_to_delete = catfile($striped_upgrade_path,
        file($httpd_upgrade_asc)->basename());
    ok(unlink($httpd_upgrade_to_delete, $httpd_upgrade_asc_to_delete),
        'checked cmd_upgrade() delete temp upgrade files');
};



# Clear internal %CONFIG variable, because I have to parse a Fetchwarefile
# many times, and it's only supported once.
__clear_CONFIG();


subtest 'test cmd_upgrade() test-dist' => sub {
    # Actually test during user install!!!
    # Delete all existing httpd fetchware packages in fetchware_database_path(),
    # which will screw up the installation and upgrading of httpd below.
    for my $fetchware_package (glob catfile(fetchware_database_path(), '*')) {
        # Clean up $fetchware_package.
        if ($fetchware_package =~ /test-dist/) {
            ok((unlink $fetchware_package),
                'checked cmd_upgrade() clean up fetchware database path')
                if -e $fetchware_package
        }
    }

    # Create a $temp_dir for make_test_dist() to use. I need to do this, so that
    # both the old and new test dists can be in the same directory.
    my $upgrade_temp_dir = tempdir("fetchware-$$-XXXXXXXXXX",
        CLEANUP => 1, TMPDIR => 1);

note("UPGRADETD[$upgrade_temp_dir]");

    my $old_test_dist_path = make_test_dist('test-dist', '1.00',
        $upgrade_temp_dir);
    
    my $old_test_dist_path_md5 = md5sum_file($old_test_dist_path);

    # Delete all existing httpd fetchware packages in fetchware_database_path(),
    # which will screw up the installation and upgrading of httpd below.
    for my $fetchware_package (glob catfile(fetchware_database_path(), '*')) {
        # Delete *only* httpd.
        if ($fetchware_package =~ /test-dist/) {
            # Clean up $fetchware_package.
            ok((unlink $fetchware_package),
                'checked cmd_upgrade() clean up fetchware database path')
                if -e $fetchware_package;
        }
    }

note("INSTALLPATH[$old_test_dist_path]");

    # I obviously must install test-dist before I can test upgrading it :)
    my $fetchware_package_path = cmd_install($old_test_dist_path);
    # And then test if the install was successful.
    ok(grep /test-dist/, glob(catfile(fetchware_database_path(), '*')),
        'check cmd_install(Fetchware) success.');


    # Clear internal %CONFIG variable, because I have to parse a Fetchwarefile
    # twice, and it's only supported once.
    __clear_CONFIG();


    # Sleep for 2 seconds to ensure that the new version is a least a couple of
    # seconds newer than the original version. Perl is pretty fast, so it can
    # actually execute this whole friggin subtest in less than one second on my
    # decent desktop system.
    sleep 2;


    my $new_test_dist_path = make_test_dist('test-dist', '1.01',
        $upgrade_temp_dir);

    my $new_test_dist_path_md5 = md5sum_file($new_test_dist_path);

note("upgradepath[");
system('ls', '-lh', $upgrade_temp_dir);
note("]");

    # cmd_uninstall accepts a string that needs to be found in the fetchware
    # database. It does *not* take Fetchwarefiles or fetchware packages as
    # arguments.
    like(cmd_upgrade('test-dist'), qr/test-dist-1\.01/,
        'checked cmd_upgrade() success');

    print_ok(sub {cmd_list()},
        sub {grep({$_ =~ /test-dist-1\.01/} (split "\n", $_[0]))},
        'check cmd_upgrade() success.');



    # Test for when cmd_upgrade() determines that the latest version is
    # installed.
    # Clear internal %CONFIG variable, because I have to pare a Fetchwarefile
    # twice, and it's only supported once.
    __clear_CONFIG();
    is(cmd_upgrade('test-dist'), 'No upgrade needed.',
        'checked cmd_upgrade() latest version already installed.');

    # Clean up upgrade path.
    ok(unlink($old_test_dist_path, $old_test_dist_path_md5,
            $new_test_dist_path, $new_test_dist_path_md5),
        'checked cmd_upgrade() delete temp upgrade files');
};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
