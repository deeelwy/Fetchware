#!perl
# bin-fetchware-look.t tests bin/fetchware's look() subroutine, which
# is fetchware's version of cpan's look command.
use strict;
use warnings;
use diagnostics;
use 5.010001;


# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '3'; #Update if this changes.

use App::Fetchware::Config ':CONFIG';
use Test::Fetchware ':TESTING';
use Cwd 'cwd';
use File::Copy 'mv';
use File::Spec::Functions qw(catfile splitpath);
use Path::Class;


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


# Save cwd to chdir to it later, because cmd_look() completes with a changed cwd(),
# which messes up the relative path that the next subtest uses, so this lame
# cwd() and chdir hack is used. I should refactor these out of fetchware's test
# suite.
my $original_cwd = cwd();


subtest 'test cmd_look() success' => sub {
    skip_all_unless_release_testing();

my $fetchwarefile = <<EOF;
use App::Fetchware;

program 'Apache 2.2';

lookup_url '$ENV{FETCHWARE_HTTP_LOOKUP_URL}';

mirror '$ENV{FETCHWARE_FTP_MIRROR_URL}';

filter 'httpd-2.2';
EOF

    my $fetchwarefile_path = create_test_fetchwarefile($fetchwarefile);
note("FFP[$fetchwarefile_path]");
    ok(-e $fetchwarefile_path,
        'check create_test_fetchwarefile() test Fetchwarefile');

    my $look_path = cmd_look($fetchwarefile_path);
note("LP[$look_path]");
    # And then test if cmd_look() was successful.
    like($look_path, qr/@{[config('filter')]}/,
        'check cmd_look(Fetchware) success.');
};


# Chdir to $original_cwd so next tests run correctly.
chdir $original_cwd 
    or fail("Failed to chdir! Causing next subtest to fail!");

# And clear CONFIG.
__clear_CONFIG();


subtest 'test cmd_look() test-dist success' => sub {
    my $test_dist_path = make_test_dist('test-dist', '1.00');
    my $test_dist_md5 = md5sum_file($test_dist_path);

    my $look_path = cmd_look($test_dist_path);
note("LOOKPATH[$look_path]");

    like($look_path, qr/test-dist-1\.00/,
        'check cmd_look(test-dist) success.');

    # Cleanup the test-dist crap.
    ok(unlink($test_dist_path, $test_dist_md5),
        'checked cmd_list() delete temp files.');
};




# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
