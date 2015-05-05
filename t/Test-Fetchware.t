#!perl
# Test-Fetchware.t tests Test::Fetchware's utility subroutines, which
# provied helper functions such as logging and file & dirlist downloading.
use strict;
use warnings;
use diagnostics;
use 5.010001;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '9'; #Update if this changes.

use File::Spec::Functions qw(splitpath catfile rel2abs tmpdir);
use Path::Class;
use URI::Split 'uri_split';
use Cwd 'cwd';
use File::Temp 'tempdir';

use App::Fetchware::Config ':CONFIG';

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
note("App::Fetchware's default imports [@Test::Fetchware::EXPORT_OK]");


# make_test_dist()'s test need access to bin/fetchware's cmd_install() to
# actually fully test it, so import it as bin/fetchware's own test suite does.
BEGIN {
    my $fetchware = 'fetchware';
    use lib 'bin';
    require $fetchware;
    fetchware->import(':TESTING');
    ok(defined $INC{$fetchware}, 'checked bin/fetchware loading and import')
}



###BUGALERT### Add tests for :TESTING subs that have no tests!!!
subtest 'TESTING export what they should' => sub {
    my @expected_testing_exports = qw(
        eval_ok
        print_ok
        fork_ok
        skip_all_unless_release_testing
        make_clean
        make_test_dist
        md5sum_file
        expected_filename_listing
        verbose_on
        export_ok
        end_ok
        add_prefix_if_nonroot
        create_test_fetchwarefile
    );
    # sort them to make the testing their equality very easy.
    @expected_testing_exports = sort @expected_testing_exports;
    my @sorted_testing_tag = sort @{$Test::Fetchware::EXPORT_TAGS{TESTING}};
    is_deeply(\@sorted_testing_tag, \@expected_testing_exports,
        'checked for correct exports.');
};


subtest 'test print_ok()' => sub {
    # Can't easily test the exceptions print_ok() throws, because they're if
    # open()ing a scalar ref fails, and if calling close() actually failes,
    # which can't easily be forced to fail.

    # Test print_ok() string message.
    my $test_message = 'A test message';
    print_ok(sub {print $test_message},
        $test_message, 'checked print_ok() string message success');

    # Test print_ok() regex.
    print_ok(sub {print $test_message},
        qr/$test_message/, 'checked print_ok() regex message success');

    print_ok(sub {print $test_message},
        sub {return 1 if $_[0] eq $test_message; return;},
        'checked print_ok() simple coderef success');
};


subtest 'test make_test_dist()' => sub {
    ###HOWTOTEST### How do I test for mkdir() failure, open() failure, and
    #Archive::Tar->create_archive() failure?

    my $file_name = 'test-dist';
    my $ver_num = '1.00';
    my $retval = make_test_dist(file_name => $file_name, ver_num => $ver_num);
    is(file($retval)->basename(), "$file_name-$ver_num.fpkg",
        'check make_test_dist() success.');
    ok(-e $retval, 'check make_test_dist() existence.');

    ok(unlink $retval, 'checked make_test_dist() cleanup');

    # Test more than one call as used in t/bin-fetchware-upgrade-all.t
    my @filenames = qw(test-dist another-dist);

    my @retvals;
    for my $filename (@filenames) {
        my $retval = make_test_dist(file_name => $file_name, ver_num => $ver_num);
        is(file($retval)->basename(), "$file_name-$ver_num.fpkg",
            'check make_test_dist() 2 calls  success.');
        ok(-e $retval, 'check make_test_dist() 2 calls existence.');
        push @retvals, $retval;
    }

    ok(unlink @retvals, 'checked make_test_dist() 2 calls cleanup');

    # Test make_test_dist()'s second destination directory argument.
    my $name = 'test-dist';
    my $return_val = make_test_dist(file_name => $file_name, ver_num => $ver_num,
        destination_directory => 't');
    is($return_val, rel2abs(catfile('t', "$name-$ver_num.fpkg")),
        'check make_test_dist() destination directory success.');
    ok(-e $return_val, 'check make_test_dist() destination directory existence.');

    ok(unlink $return_val, 'checked make_test_dist() cleanup');


    # Test make_test_dist()'s second destination directory argument in a
    # temp_dir.
    my $name2 = 'test-dist';
    my $rv = make_test_dist(file_name => $name2, ver_num => $ver_num,
        destination_directory => tmpdir());
    is(file($rv)->basename(), "$name2-$ver_num.fpkg",
        'check make_test_dist() temp_dir destination directory success.');
    ok(-e $rv, 'check make_test_dist() temp_dir destination directory existence.');

    ok(unlink $rv, 'checked make_test_dist() cleanup');


    # Test the Fetchwarefile optional named parameter.
    $name2 = 'test-dist';
    my $fetchwarefile = '# A useless testing Fetchwarefile.';
    $rv = make_test_dist(file_name => $name2, ver_num => $ver_num,
        destination_directory => tmpdir(), fetchwarefile => $fetchwarefile);
    is(file($rv)->basename(), "$name2-$ver_num.fpkg",
        'check make_test_dist() Fetchware temp_dir destination directory success.');
    ok(-e $rv, 'check make_test_dist() Fetchware temp_dir destination directory existence.');

    ok(unlink $rv, 'checked make_test_dist() cleanup');


    # Test the AppendOption optional named parameter.
    $name2 = 'test-dist';
    my $fetchwarefile_option = q{fetchware_option 'some value';};
    $rv = make_test_dist(file_name => $name2, ver_num => $ver_num,
        destination_directory => tmpdir(), append_option => $fetchwarefile_option);
    is(file($rv)->basename(), "$name2-$ver_num.fpkg",
        'check make_test_dist() temp_dir destination directory success.');
    ok(-e $rv, 'check make_test_dist() existence.');

    ok(unlink $rv, 'checked make_test_dist() cleanup');
};


subtest 'test md5sum_file()' => sub {
    ###HOWTOTEST### How do I test open(), close(), and Digest::MD5 failing?

    my $file_name = 'test-dist';
    my $ver_num = '1.00';
    my $test_dist = make_test_dist(file_name => $file_name, ver_num => $ver_num);
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

    ok(unlink($test_dist, $test_dist_md5), 'checked md5sum_file() cleanup.');
};


subtest 'test verbose_on()' => sub {
    # turn on verbose.
    verbose_on();

    # Test if $fetchware::verbose has been set to true.
    ok($fetchware::verbose,
        'checked verbose_on() success.');
};


subtest 'test add_prefix_if_nonroot() success' => sub {
    # Skip all of add_prefix_if_nonroot()'s tests if run as nonroot, because
    # this subtest only tests for correct output when run as nonroot. When run
    # as root add_prefix_if_nonroot() returns undef, which the test does not
    # account for.
    plan(skip_all => q{Only test add_prefix_if_nonroot() if we're nonroot})
        if $> == 0;
    # Clear out any other use of config().
    __clear_CONFIG();

    my $prefix = add_prefix_if_nonroot();
    ok(-e (config('prefix')),
        'checked add_prefix_if_nonroot() tempfile creation.');
    ok(-e $prefix,
        'checked add_prefix_if_nonroot() prefix existence.');

    # Clear prefix between test runs.
    __clear_CONFIG();

    $prefix = add_prefix_if_nonroot(sub {
            $prefix = tempdir("fetchware-test-$$-XXXXXXXXXX",
                TMPDIR => 1, CLEANUP => 1);
            config(prefix => $prefix);
            return $prefix;
        }
    );
    ok(-e (config('prefix')),
        'checked add_prefix_if_nonroot() tempfile creation.');
    ok(-e $prefix,
        'checked add_prefix_if_nonroot() prefix existence.');
};


subtest 'test fork_ok()' => sub {
    fork_ok(sub {ok(1, 'successful fork_ok() test.')},
        'checked fork_ok() success.');

    # Abuse a TODO block to test fork_ok() failure by turning that failure into
    # success. When this test fails it succeeds, because it is testing failure.
    TODO: {
        todo_skip 'Turn failure into success.', 1;

        fork_ok(sub { return 0 },
            'checked fork_ok() failure.');
    }
};

# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
