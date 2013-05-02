#!perl
# bin-fetchware-upgrade-all.t tests bin/fetchware's cmd_upgrade_all()
# subroutine, which upgrades *all* of fetchware's installed packages.
use strict;
use warnings;
use diagnostics;
use 5.010001;


# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '4'; #Update if this changes.

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

subtest 'test cmd_upgrade_all() success' => sub {
    skip_all_unless_release_testing();

    # upgrade_all: Delete ctags packages too!
    # Delete all existing httpd fetchware packages in fetchware_database_path(),
    # which will screw up the installation and upgrading of httpd below.
    for my $fetchware_package (glob catfile(fetchware_database_path(), '*')) {
        # Clean up $fetchware_package.
        if ($fetchware_package =~
            /httpd|ctags|test-dist|another-dist|App-Fetchware/) {
            ok((unlink $fetchware_package),
                'checked cmd_upgrade() clean up fetchware database path')
                if -e $fetchware_package
        }
    }

    my $apache_fetchwarefile = <<EOF;
use App::Fetchware;

program 'Apache 2.2';

lookup_url '$ENV{FETCHWARE_LOCAL_UPGRADE_URL}';

filter 'httpd-2.2';
EOF


    my $ctags_fetchwarefile = <<EOF;
use App::Fetchware;

program 'ctags';

lookup_url '$ENV{FETCHWARE_LOCAL_UPGRADE_URL}';

filter 'ctags';

# Disable verification, because ctags provides none.
verify_failure_ok 'On';
EOF

    my @fetchware_packages;
    for my $fetchwarefile ($apache_fetchwarefile, $ctags_fetchwarefile) {
note('FETCHWAREFILE');
note("$fetchwarefile");
        my $package_name = $fetchwarefile;
        $package_name =~ /(apache-2\.2|ctags)/; 
        $package_name = $1;
note("packagename[$package_name]");
        my $fetchwarefile_path = create_test_fetchwarefile($fetchwarefile);

        ok(-e $fetchwarefile_path,
            'check create_test_fetchwarefile() test Fetchwarefile');

        # I obviously must install apache before I can test upgrading it :)
        push @fetchware_packages, cmd_install($fetchwarefile_path);
        # And then test if the install was successful.
        ok(grep /$package_name/, glob(catfile(fetchware_database_path(), '*')),
            'check cmd_install(Fetchware) success.');

        # Clear internal %CONFIG variable, because I have to parse a Fetchwarefile
        # twice, and it's only supported once.
        __clear_CONFIG();
    }


    # upgrade_all: Copy over new version of ctags too.
    # Also copy over the latest version of httpd, so that I don't have to change
    # the lookup_url in the Fetchwarefile of the httpd fetchware package.
    # httpd copy stuff.
    my $striped_upgrade_path = $ENV{FETCHWARE_LOCAL_UPGRADE_URL};
    $striped_upgrade_path =~ s!^file://!!;
    my $parent_upgrade_path = dir($striped_upgrade_path)->parent();
    my $httpd_upgrade = catfile($parent_upgrade_path, 'httpd-2.2.22.tar.bz2');
    my $httpd_upgrade_asc = catfile($parent_upgrade_path,
        'httpd-2.2.22.tar.bz2.asc');
note("httpd_upgrade[$httpd_upgrade] stripedupgradepath[$striped_upgrade_path]");
    ok(cp($httpd_upgrade, $striped_upgrade_path),
        'checked cmd_upgrade() cp new version  httpd to local upgrade url');
note("httpd_upgrade_asc[$httpd_upgrade_asc]");
    ok(cp($httpd_upgrade_asc, $striped_upgrade_path),
        'checked cmd_upgrade() cp new version httpd asc to local upgrade url');
    # ctags copy stuff.
    my $ctags_upgrade = catfile($parent_upgrade_path, 'ctags-5.8.tar.gz');
note("ctags_upgrade[$ctags_upgrade]");
    ok(cp($ctags_upgrade, $striped_upgrade_path),
        'checked cmd_upgrade() cp new version ctags to local upgrade url');


    # upgrade all packages, which will test if upgrading everything in
    # fetchware_database_path works.
    my @upgraded_package_paths = cmd_upgrade_all();
    note("HERE");
    note explain \@upgraded_package_paths;


    # Test after both packages have been upgraded.
    print_ok(sub {cmd_list()},
        sub {grep({$_ =~ /httpd-2\.2\.22|ctags-5\.8/} (split "\n", $_[0]))},
        'check cmd_upgrade() success.');


    # Test for when cmd_upgrade() determines that the latest version is
    # installed.
    # Clear internal %CONFIG variable, because I have to pare a Fetchwarefile
    # twice, and it's only supported once.
    __clear_CONFIG();
    is(cmd_upgrade_all(), 'No upgrade needed.',
        'checked cmd_upgrade_all() latest version already installed.');

    # Clean up upgrade path.
    my $httpd_upgrade_to_delete = catfile($striped_upgrade_path,
        file($httpd_upgrade)->basename());
    my $httpd_upgrade_asc_to_delete = catfile($striped_upgrade_path,
        file($httpd_upgrade_asc)->basename());
    # upgrade_all: Clean up ctags new package too.
    my $ctags_upgrade_to_delete = catfile($striped_upgrade_path,
        file($ctags_upgrade)->basename());
    ok(unlink($httpd_upgrade_to_delete,
            $httpd_upgrade_asc_to_delete,
            $ctags_upgrade_to_delete),
        'checked cmd_upgrade_all() delete temp upgrade files');
};



# Clear internal %CONFIG variable, because I have to parse a Fetchwarefile
# many times, and it's only supported once.
__clear_CONFIG();


subtest 'test cmd_upgrade_all() test-dist' => sub {
    # Actually test during user install!!!

    # Delete all existing httpd fetchware packages in fetchware_database_path(),
    # which will screw up the installation and upgrading of httpd below.
    for my $fetchware_package (glob catfile(fetchware_database_path(), '*')) {
        # Delete *only* ctags, httpd, and the test-dists.
        if ($fetchware_package =~ /ctags|httpd|test-dist|another-dist/) {
            # Clean up $fetchware_package.
            ok((unlink $fetchware_package),
                'checked cmd_upgrade() clean up fetchware database path')
                if -e $fetchware_package;
        }
    }

    # Create a $temp_dir for make_test_dist() to use. I need to do this, so that
    # both the old and new test dists can be in the same directory.
    my $upgrade_temp_dir = tempdir("fetchware-$$-XXXXXXXXXX",
        CLEANUP => 1, TMPDIR => 1);

note("UPGRADETD[$upgrade_temp_dir]");

    my $old_test_dist_path = make_test_dist('test-dist', '1.00', $upgrade_temp_dir);
    my $old_another_dist_path = make_test_dist('another-dist', '1.00', $upgrade_temp_dir);

    my $old_test_dist_path_md5 = md5sum_file($old_test_dist_path);
    my $old_another_dist_path_md5 = md5sum_file($old_another_dist_path);


    # I obviously must install test-dist before I can test upgrading it :)
    for my $fpkg_to_install ($old_test_dist_path, $old_another_dist_path) {
        my $fetchware_package_path = cmd_install($fpkg_to_install);
        # And then test if the install was successful.
        ok(grep /test-dist|another-dist/,
            glob(catfile(fetchware_database_path(), '*')),
            'check cmd_install(Fetchware) success.');

        # Clear internal %CONFIG variable, because I have to parse a Fetchwarefile
        # twice, and it's only supported once.
        __clear_CONFIG();
    }


    # Sleep for 2 seconds to ensure that the new version is a least a couple of
    # seconds newer than the original version. Perl is pretty fast, so it can
    # actually execute this whole friggin subtest on my decent desktop system
    # in less thatn one second.
    sleep 2;


    # Create new test fpkgs and md5s in same dir for cmd_upgrade_all() to work.
    my $new_test_dist_path = make_test_dist('test-dist', '1.01', $upgrade_temp_dir);
    my $new_another_dist_path = make_test_dist('another-dist', '1.01', $upgrade_temp_dir);

    my $new_test_dist_path_md5 = md5sum_file($new_test_dist_path);
    my $new_another_dist_path_md5 = md5sum_file($new_another_dist_path);


    # Upgrade all installed fetchware packages.
    my @upgraded_packages = cmd_upgrade_all();
note("UPGRADED_PACKAGES[@upgraded_packages]");
    for my $upgraded_package (@upgraded_packages) {
        like($upgraded_package, qr/(test|another)-dist-1\.01/,
            'checked cmd_upgrade_all() success.');
    }

    print_ok(sub {cmd_list()},
        sub {grep({$_ =~ /(test|another)-dist-1\.01/} (split "\n", $_[0]))},
        'check cmd_upgrade_all() success.');


    # Test for when cmd_upgrade() determines that the latest version is
    # installed.
    # Clear internal %CONFIG variable, because I have to pare a Fetchwarefile
    # twice, and it's only supported once.
    __clear_CONFIG();
    is(cmd_upgrade_all(), 'No upgrade needed.',
        'checked cmd_upgrade() latest version already installed.');

    # Clean up upgrade path.
    ok(unlink($old_test_dist_path, $old_test_dist_path_md5,
        $old_another_dist_path, $old_another_dist_path_md5,
        $new_test_dist_path, $new_test_dist_path_md5,
        $new_another_dist_path, $new_another_dist_path_md5,
        ), 'checked cmd_upgrade() delete temp upgrade files');
};


subtest 'check cmd_upgrade_all(argument) error' => sub {
    eval_ok(sub {cmd_upgrade_all('some arg')},
        <<EOE, 'checked cmd_upgrade_all(argument) error');
fetchware: fetchware's upgrade-all command takes no arguments. Instead, it
simply loops through fetchware's package database, and upgrades all already
installed fetchware packages. Please rerun fetchware upgrade-all without any
arguments to upgrade all already installed packages, or run fetchware help for
usage instructions.
EOE

};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
