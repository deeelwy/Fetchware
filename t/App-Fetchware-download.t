#!perl
# App-Fetchware-lookup.t tests App::Fetchware's lookup() subroutine, which
# determines if a new version of your program is available.
# Pretend to be bin/fetchware, so that I can test App::Fetchware as though
# bin/fetchware was calling it.
package fetchware;
use strict;
use warnings;
use diagnostics;
use 5.010001;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More ;#0.98 tests => '6'; #Update if this changes.

use File::Spec::Functions qw(splitpath catfile);
use URI::Split qw(uri_split uri_join);
use Cwd 'cwd';

use Test::Fetchware ':TESTING';
use App::Fetchware::Config ':CONFIG';

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
BEGIN { use_ok('App::Fetchware', qw(:DEFAULT :OVERRIDE_DOWNLOAD)); }

# Print the subroutines that App::Fetchware imported by default when I used it.
note("App::Fetchware's default imports [@App::Fetchware::EXPORT]");

my $class = 'App::Fetchware';



##TEST##subtest 'OVERRIDE_DOWNLOAD exports what it should' => sub {
##TEST##    my @expected_overide_download_exports = qw(
##TEST##        determine_package_path
##TEST##    );
##TEST##    # sort them to make the testing their equality very easy.
##TEST##    @expected_overide_download_exports = sort @expected_overide_download_exports;
##TEST##    my @sorted_download_tag = sort @{$App::Fetchware::EXPORT_TAGS{OVERRIDE_DOWNLOAD}};
##TEST##    ok(@expected_overide_download_exports ~~ @sorted_download_tag, 
##TEST##        'checked for correct OVERRIDE_DOWNLOAD @EXPORT_TAG');
##TEST##
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test determine_package_path()' => sub {
##TEST##    my $cwd = cwd();
##TEST##    note("cwd[$cwd]");
##TEST##
##TEST##    is(determine_package_path($cwd, 'bin/fetchware'),
##TEST##        catfile(cwd(), 'bin/fetchware'),
##TEST##        'checked determine_package_path() success');
##TEST##
##TEST##};
##TEST##

##TEST##subtest 'test download()' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    for my $url ($ENV{FETCHWARE_FTP_DOWNLOAD_URL},
##TEST##        $ENV{FETCHWARE_HTTP_DOWNLOAD_URL}) {
##TEST##note("URL[$url]");
##TEST##
##TEST##        eval_ok(sub {download(cwd(), $url)},
##TEST##            qr/App-Fetchware: download\(\) has been passed a full URL \*not\* only a path./,
##TEST##            'checked download() url exception');
##TEST##
##TEST##        # manually set $CONFIG{TempDir} to cwd().
##TEST##        my $cwd = cwd();
##TEST##        config_replace('temp_dir', "$cwd");
##TEST##
##TEST##        # Determine $filename for is() test below.
##TEST##        my ($scheme, $auth, $path, $query, $frag) = uri_split($url);
##TEST##        # Be sure to define a mirror, because with just a path download() can't
##TEST##        # work properly.
##TEST##        config(mirror => uri_join($scheme, $auth, undef, undef, undef));
##TEST##        
##TEST##        my ($volume, $directories, $filename) = splitpath($path);
##TEST##note("FILENAME[$filename]");
##TEST##note("LASTURL[$url] CWD[$cwd]");
##TEST##        # Remeber download() wants a $path not a $url.
##TEST##        is(download($cwd, $path), catfile($cwd, $filename),
##TEST##            'checked download() success.');
##TEST##
##TEST##        ok(-e $filename, 'checked download() file exists success');
##TEST##        ok(unlink $filename, 'checked deleting downloaded file');
##TEST##
##TEST##    }
##TEST##
##TEST##};


#subtest 'test download() local file success' => sub {
    # manually set $CONFIG{TempDir} to cwd().
    my $cwd = cwd();
    config_replace('temp_dir', "$cwd");

    my $test_dist_path = make_test_dist('test-dist', '1.00', 't');
    my $test_dist_md5 = md5sum_file($test_dist_path);
    my $url = "file://$test_dist_path";

    # Determine $filename for is() test below.
    my ($scheme, $auth, $path, $query, $frag) = uri_split($url);
    my ($volume, $directories, $filename) = splitpath($path);
    ###BUGALERT## Remove cwd(), and replace with temp dir, so tests can be run
    #in parallel to speed up development.
    is(download($cwd, $url), catfile($cwd, $filename),
        'checked download() local file success.');

    ok(-e $filename, 'checked download() file exists success');
    ok(unlink $filename, 'checked deleting downloaded file');

    ok(unlink($test_dist_path, $test_dist_md5),
        'checked cmd_list() delete temp files.');
#};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
done_testing();
