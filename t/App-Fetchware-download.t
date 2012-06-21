#!perl
# App-Fetchware-lookup.t tests App::Fetchware's lookup() subroutine, which
# determines if a new version of your program is available.
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '5'; #Update if this changes.

use File::Spec::Functions qw(splitpath catfile);
use URI::Split 'uri_split';
use Cwd 'cwd';

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
BEGIN { use_ok('App::Fetchware', qw(:DEFAULT :OVERRIDE_DOWNLOAD :TESTING)); }

# Print the subroutines that App::Fetchware imported by default when I used it.
diag("App::Fetchware's default imports [@App::Fetchware::EXPORT]");

my $class = 'App::Fetchware';



subtest 'OVERRIDE_DOWNLOAD exports what it should' => sub {
    my @expected_overide_download_exports = qw(
        download_ftp_url
        download_http_url
        determine_package_path
    );
    # sort them to make the testing their equality very easy.
    @expected_overide_download_exports = sort @expected_overide_download_exports;
    my @sorted_download_tag = sort @{$App::Fetchware::EXPORT_TAGS{OVERRIDE_DOWNLOAD}};
    ok(@expected_overide_download_exports ~~ @sorted_download_tag, 
        'checked for correct OVERRIDE_DOWNLOAD @EXPORT_TAG');

};


subtest 'test determine_package_path()' => sub {
    skip_all_unless_release_testing();
    my $cwd = cwd();
    diag("cwd[$cwd]");

    ###BUGALERT### Brittle test!!!
    is(determine_package_path($cwd, 'bin/fetchware'),
        '/home/dly/Desktop/Code/App-Fetchware/bin/fetchware',
        'checked determine_package_path() success');

};


subtest 'test download()' => sub {
    skip_all_unless_release_testing();

    for my $url ($ENV{FETCHWARE_FTP_DOWNLOAD_URL},
        $ENV{FETCHWARE_HTTP_DOWNLOAD_URL}) {
        # manually set $CONFIG{TempDir} to cwd().
        my $cwd = cwd();
        config_replace('temp_dir', "$cwd");

        # Determine $filename for is() test below.
        my ($scheme, $auth, $path, $query, $frag) = uri_split($url);
        my ($volume, $directories, $filename) = splitpath($path);
        is(download($cwd, $url), catfile($cwd, $filename),
            'checked download() success.');

        ok(-e $filename, 'checked download() file exists success');
        ok(unlink $filename, 'checked deleting downloaded file');

    }

};


subtest 'test download() local file success' => sub {
    # manually set $CONFIG{TempDir} to cwd().
    my $cwd = cwd();
    config_replace('temp_dir', "$cwd");

    my $url = "file://t/test-dist-1.00.fpkg";

    # Determine $filename for is() test below.
    my ($scheme, $auth, $path, $query, $frag) = uri_split($url);
    my ($volume, $directories, $filename) = splitpath($path);
    is(download($cwd, $url), catfile($cwd, $filename),
        'checked download() local file success.');

    ok(-e $filename, 'checked download() file exists success');
    ok(unlink $filename, 'checked deleting downloaded file');
};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
