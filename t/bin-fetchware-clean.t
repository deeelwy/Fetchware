#!perl
# bin-fetchware-clean.t tests bin/fetchware's cmd_clean() subroutine, which
# deletes left over unused fetchware temporary directories.
use strict;
use warnings;
use diagnostics;
use 5.010001;


# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '2'; #Update if this changes.

use App::Fetchware::Config ':CONFIG';
use App::Fetchware::Util ':UTIL';
use Test::Fetchware ':TESTING';

use File::Temp 'tempdir';
use Cwd;

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


subtest 'test cmd_clean() success' => sub {
    # Use create_tempdir(), which creates a semaphore and print_ok to test if
    # cmd_clean skips locked temp dirs.
    my $tempdir = create_tempdir();
    ok(-e $tempdir, 'checked creating a temporary directory.');

    print_ok(sub {cmd_clean()},
        qr/.*?] locked by another fetchware process\. Skipping\./,
        'checked cmd_clean skipping locked fetchware directories.');

    ok(chdir(original_cwd()), 'chdir() out of tempdir, so we can delete it');

    # Create one fetchware temporary directory to test cmd_clean()'s ability to
    # delete it.
    $tempdir = tempdir("fetchware-$$-XXXXXX", TMPDIR => 1, CLEANUP => 1);
    ok(-e $tempdir, 'checked creating a temporary directory.');

    # Delete the newly created tempdir.
    cmd_clean();

    ok(! -e $tempdir, 'checked cmd_clean() delete success.');

    # Test cmd_clean()'s ability to test user specfied directories.
    $tempdir = tempdir("fetchware-$$-XXXXXX", TMPDIR => 1,
        CLEANUP => 1);
    my $extra_tempdir = tempdir("fetchware-$$-XXXXXX", DIR => $tempdir);

    ok(-e $tempdir, 'checked creating a temporary directory.');
    ok(-e $extra_tempdir, 'checked creating an extra temporary directory.');

    # Delete the newly created tempdir.
    cmd_clean($extra_tempdir);

    ok(! -e $tempdir, 'checked cmd_clean() delete success.');

    # Test cmd_clean()'s ability to delete temporary files that start with
    # fetchware-* or Fetchwarefile-*.
    my $fetchware_tempdir = tempdir("fetchware-$$-XXXXXXXXX", TMPDIR => 1,
        CLEANUP => 1);
    my $fetchwarefile_tempdir = tempdir("Fetchwarefile-$$-XXXXXXXXX", TMPDIR => 1,
        CLEANUP => 1);

    ok(-e $fetchware_tempdir, 'checked creating fetchware temporary directory.');
    ok(-e $fetchwarefile_tempdir, 'checked creating Fetchwarefile temporary directory.');

    # Delete newly created tempfiles.
    cmd_clean();

    ok(! -e $fetchware_tempdir,
        'checked deleting fetchware temporary directory success.');
    ok(! -e $fetchwarefile_tempdir,
        'checked deleting Fetchwarefile temporary directory success.');

};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
