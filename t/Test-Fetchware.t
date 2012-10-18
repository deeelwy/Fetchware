#!perl
# Test-Fetchware.t tests Test::Fetchware's utility subroutines, which
# provied helper functions such as logging and file & dirlist downloading.
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '4'; #Update if this changes.

use File::Spec::Functions qw(splitpath catfile rel2abs tmpdir);
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
BEGIN { use_ok('Test::Fetchware', ':TESTING'); }

# Print the subroutines that App::Fetchware imported by default when I used it.
diag("App::Fetchware's default imports [@Test::Fetchware::EXPORT_OK]");



###BUGALERT### Add tests for :TESTING subs that have no tests!!!
subtest 'TESTING export what they should' => sub {
    my @expected_testing_exports = qw(
        eval_ok
        print_ok
        skip_all_unless_release_testing
        make_clean
        make_test_dist
        md5sum_file
        expected_filename_listing
    );
    # sort them to make the testing their equality very easy.
    @expected_testing_exports = sort @expected_testing_exports;
    my @sorted_testing_tag = sort @{$Test::Fetchware::EXPORT_TAGS{TESTING}};

    for my $i (0..$#sorted_testing_tag) {
        unless ($sorted_testing_tag[$i] eq $expected_testing_exports[$i]) {
            fail('checked for correct TESTING @EXPORT_TAG failed');
        }
    }
    pass('checked for correct TESTING @EXPORT_TAG');
};


subtest 'test make_test_dist()' => sub {
    ###HOWTOTEST### How do I test for mkdir() failure, open() failure, and
    #Archive::Tar->create_archive() failure?

    my $file_name = 'test-dist';
    my $ver_num = '1.00';
    my $retval = make_test_dist($file_name, $ver_num);
    is($retval, rel2abs("$file_name-$ver_num.fpkg"),
        'check make_test_dist() success.');

    ok(unlink $retval, 'checked make_test_dist() cleanup');

    # Test more than one call as used in t/bin-fetchware-upgrade-all.t
    my @filenames = qw(test-dist test-dist);

    my @retvals;
    for my $filename (@filenames) {
        my $retval = make_test_dist($file_name, $ver_num);
        is($retval, rel2abs("$file_name-$ver_num.fpkg"),
            'check make_test_dist() 2 calls  success.');
        push @retvals, $retval;
    }

    ok(unlink @retvals, 'checked make_test_dist() 2 calls cleanup');

    # Test make_test_dist()'s second destination directory argument.
    my $name = 'test-dist-1.00';
    my $return_val = make_test_dist($name, $ver_num, tmpdir());
    is($return_val, catfile(tmpdir(), "$name-$ver_num.fpkg"),
        'check make_test_dist() destination directory success.');

    ok(unlink $return_val, 'checked make_test_dist() cleanup');
};


subtest 'test md5sum_file()' => sub {
    ###HOWTOTEST### How do I test open(), close(), and Digest::MD5 failing?

    my $filename = 'test-dist';
    my $ver_num = '1.00';
    my $test_dist = make_test_dist($filename, $ver_num);
    my $test_dist_md5 = md5sum_file($test_dist);

    ok(-e $test_dist_md5, 'checked md5sum_file() file creation');

    open(my $fh, '<', $test_dist_md5)
        or fail("Failed to open [$test_dist_md5] for testing md5sum_file()[$!]");

    my $got_md5sum = do { local $/; <$fh> };

    close $fh
        or fail("Failed to close [$test_dist_md5] for testing md5sum_file() [$!]");

    # The generated fetchware package is different each time probably because of
    # formatting in tar and gzip.
    like($got_md5sum, qr/[0-9a-f]{32}  test-dist-1.00.fpkg/,
        'checked md5sum_file() success');
};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
