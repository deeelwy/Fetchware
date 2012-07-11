#!perl
# bin-fetchware-list.t tests bin/fetchware's cmd_list() subroutine, which
# lists your installed packages based on fetchware_database_path();
use strict;
use warnings;
use diagnostics;
use 5.010;


# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '2'; #Update if this changes.

use App::Fetchware qw(:TESTING config);
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

#my $fetchware_package_path = '/var/log/fetchware/httpd-2.2.22.fpkg';
my $fetchware_package_path;


subtest 'test cmd_list() success' => sub {
    # First install a test package to make sure there is something for cmd_list()
    # to find.
    cmd_install('t/test-dist-1.00.fpkg');
diag("CWD[@{[cwd()]}]");

    my $stdout;
    my $error;
    {
        # localize stdout, and open it for reading to test cmd_list()'s output.
        local *STDOUT;
        open STDOUT, '>', \$stdout
            or $error = "Can't open STDOUTto test cmd_list()'s output: $!";

        # Writes to STDOUT, which is redirected to $stdout above.
        cmd_list();

        close STDOUT
            or $error = "WTF! close STDOUT actually failed Huh?!?: $!";
    }
    # Catch any errors that will be screwed up, because of STDOUT being stolen.
    fail($error) if defined $error;

    # Test cmd_list()'s output.
        ok(grep { $_ eq 'test-dist-1.00' } (split "\n", $stdout),
            'checked cmd_list() success');

# Annoyingly clean up CONFIG. Shouln't end() do this!!!!:)
__clear_CONFIG();

diag("CWD2[@{[cwd()]}]");
    # Now uninstall the useless test dist.
    cmd_uninstall('test-dist');
};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
