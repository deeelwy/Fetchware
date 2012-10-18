#!perl
# App-Fetchware-Config.t tests App::Fetchware's %CONFIG data structure that
# holds fetchware's internal represenation of Fetchwarefiles.
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '2'; #Update if this changes.

use File::Spec::Functions qw(splitpath catfile rel2abs tmpdir);
use URI::Split 'uri_split';
use Cwd 'cwd';
use Test::Fetchware ':TESTING';

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
# There is no ':OVERRIDE_START' to bother importing.
BEGIN { use_ok('App::Fetchware::Config', ':CONFIG'); }

# Print the subroutines that App::Fetchware imported by default when I used it.
diag("App::Fetchware::Config's default imports [@App::Fetchware::Config::EXPORT_OK]");


###BUGALERT### config*() subroutines have *zero* tests!!!



###BUGALERT### Add tests for :CONFIG subs that have no tests!!!
#subtest 'CONFIG export what they should' => sub {
    my @expected_util_exports = qw(
        config
        config_replace
        config_delete
        __clear_CONFIG
        debug_CONFIG
    );

    # sort them to make the testing their equality very easy.
    @expected_util_exports = sort @expected_util_exports;

    my @sorted_util_tag = sort @{$App::Fetchware::Config::EXPORT_TAGS{CONFIG}};

    ok(@expected_util_exports ~~ @sorted_util_tag, 
        'checked for correct CONFIG @EXPORT_TAG');
#};


###BUGALERT###Need to add tests for :TESTING exports & specifc subtests for eval_ok(),
# skip_all_unless_release_testing(), and clear_CONFIG().


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
