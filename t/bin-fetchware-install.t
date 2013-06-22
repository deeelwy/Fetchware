#!perl
# bin-fetchware-install.t tests bin/fetchware's cmd_install() subroutine, which
# installs fetchware packages and from a Fetchwarefile.
use strict;
use warnings;
use diagnostics;
use 5.010001;


# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '5'; #Update if this changes.

use App::Fetchware::Config ':CONFIG';
use Test::Fetchware ':TESTING';
use Cwd 'cwd';
use File::Copy 'mv';
use File::Spec::Functions qw(catfile splitpath tmpdir);
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

#my $fetchware_package_path = '/var/log/fetchware/httpd-2.2.22.fpkg';
my $fetchware_package_path;
subtest 'test cmd_install(Fetchwarefile)' => sub {
    skip_all_unless_release_testing();

my $fetchwarefile = <<EOF;
use App::Fetchware;

program 'Apache 2.2';

lookup_url '$ENV{FETCHWARE_HTTP_LOOKUP_URL}';

mirror '$ENV{FETCHWARE_FTP_MIRROR_URL}';

filter 'httpd-2.2';
EOF

note('FETCHWAREFILE');
note("$fetchwarefile");
    my $fetchwarefile_path = create_test_fetchwarefile($fetchwarefile);

    ok(-e $fetchwarefile_path,
        'check create_test_fetchwarefile() test Fetchwarefile');

    $fetchware_package_path = cmd_install($fetchwarefile_path);

    ok(grep /httpd-2\.2/, glob(catfile(fetchware_database_path(), '*')),
        'check cmd_install(Fetchware) success.');

    # *Don't delete httpd-2.2*.fpkg to clean up this test, because the next
    # test attempts to use that file to test fetchware install *.fpkg.
};



subtest 'test cmd_install(*.fpkg)' => sub {
    skip_all_unless_release_testing();

    # Clear App::Fetchware's internal configuration information, which I must do
    # if I parse more than one Fetchwarefile in a running of fetchware.
    __clear_CONFIG();
    
    # Copy existing fetchware package to tmpdir(), so that after I try installing
    # it I can test if it was successful by seeing if it was copied back to the
    # fetchware database dir.
    # It must be a dir with the sticky bit set or owned by the user running the
    # program to pass safe_open()'s security tests.
    note("FPP[$fetchware_package_path]");
    my $temp_dir = tempdir("fetchware-test-$$-XXXXXXXXXXXX",
        TMPDIR => 1, CLEANUP => 1);
    mv($fetchware_package_path, $temp_dir)
        ? pass("checked cmd_install() *.fpkg move fpkg.")
        : fail("Failed to cp [$fetchware_package_path] to cwd os error [$!].");

    # Steal the *.fpkg that was created in the previous step!
    my $new_fetchware_package_path
        =
        cmd_install(
            catfile($temp_dir, ( splitpath($fetchware_package_path) )[2] )
        );

    is($new_fetchware_package_path, $fetchware_package_path,
        'checked cmd_install(*.fpkg) success.');
};


subtest 'test test-dist.fpkg cmd_install' => sub {
    # Clear App::Fetchware's internal configuration information, which I must do
    # if I parse more than one Fetchwarefile in a running of fetchware.
    __clear_CONFIG();

    my $test_dist_path = make_test_dist('test-dist', '1.00');
    my $test_dist_md5 = md5sum_file($test_dist_path);

verbose_on();

    my $install_success = cmd_install($test_dist_path);
    note("IS[$install_success");

    ok($install_success,
        'check test-dist.fpkg cmd_install');

    # Now uninstall the useless test dist.
    ok(cmd_uninstall('test-dist-1.00'),
        'checked cmd_install() clean up installed test-dist.');

    ok(unlink($test_dist_path, $test_dist_md5),
        'checked cmd_install() delete temp files.');
};



subtest 'test cmd_install(else)' => sub {
    eval_ok(sub {cmd_install()}, <<EOE, 'checked cmd_install() no args');
fetchware: You called fetchware install incorrectly. You must also specify
either a Fetchwarefile or a fetchware package that ends with [.fpkg].
EOE

    eval_ok(sub {cmd_install('fetchware-test' . rand(3739929293))},
        <<EOE, 'checked cmd_install() file existence');
fetchware: You called fetchware install incorrectly. You must also specify
either a Fetchwarefile or a fetchware package that ends with [.fpkg].
EOE


};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
