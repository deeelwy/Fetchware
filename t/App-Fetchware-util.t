#!perl
# App-Fetchware-util.t tests App::Fetchware's utility subroutines, which
# provied helper functions such as testing & file & dirlist downloading.
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98;# tests => '10'; #Update if this changes.

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
BEGIN { use_ok('App::Fetchware', qw(:TESTING :UTIL)); }

# Print the subroutines that App::Fetchware imported by default when I used it.
diag("App::Fetchware's default imports [@App::Fetchware::EXPORT]");

my $class = 'App::Fetchware';



subtest 'UTIL end TESTING export what they should' => sub {
    my @expected_util_exports = qw(
        download_dirlist
        ftp_download_dirlist
        http_download_dirlist
        file_download_dirlist
        download_file
        download_ftp_url
        download_http_url
        download_file_url
        just_filename
    );

    my @expected_testing_exports = qw(
        eval_ok
        skip_all_unless_release_testing
        __clear_CONFIG
        debug_CONFIG
        config_replace
        config_delete
        make_clean
        make_test_dist
        start
        lookup
        download
        verify
        unarchive
        build
        install
        end
        uninstall
    );
    # sort them to make the testing their equality very easy.
    @expected_util_exports = sort @expected_util_exports;
    @expected_testing_exports = sort @expected_testing_exports;
    my @sorted_util_tag = sort @{$App::Fetchware::EXPORT_TAGS{UTIL}};
    my @sorted_testing_tag = sort @{$App::Fetchware::EXPORT_TAGS{TESTING}};

    ok(@expected_util_exports ~~ @sorted_util_tag, 
        'checked for correct UTIL @EXPORT_TAG');

    for my $i (0..$#sorted_testing_tag) {
        unless ($sorted_testing_tag[$i] eq $expected_testing_exports[$i]) {
            fail('checked for correct TESTING @EXPORT_TAG failed');
        }
    }
    pass('checked for correct TESTING @EXPORT_TAG');

};


###BUGALERT###Need to add tests for :TESTING exports & specifc subtests for eval_ok(),
# skip_all_unless_release_testing(), and clear_CONFIG().
###BUGALERT### Add tests for config*() subs.


subtest 'test ftp_download_dirlist()' => sub {
    skip_all_unless_release_testing();

    # Test its success.
    # Note link below may change. If it does just find a another anonymous ftp
    # mirror.
    ok(ftp_download_dirlist($ENV{FETCHWARE_FTP_LOOKUP_URL}),
        'check ftp_download_dirlist() success');

    eval_ok(sub {ftp_download_dirlist('ftp://doesntexist.ever')},
        <<EOS, 'checked determine_download_url() connect failure');
App-Fetchware: run-time error. fetchware failed to connect to the ftp server at
domain [doesntexist.ever]. The system error was [Net::FTP: Bad hostname 'doesntexist.ever'].
See man App::Fetchware.
EOS

##HOWTOTEST##    eval_ok(sub {ftp_download_dirlist('whatftpserverdoesntsupportanonymous&ispublic?');,
##HOWTOTEST##        <<EOS, 'checked ftp_download_dirlist() anonymous loginfailure');
##HOWTOTEST##App-Fetchware: run-time error. fetchware failed to log in to the ftp server at
##HOWTOTEST##domain [$site]. The ftp error was [@{[$ftp->message]}]. See man App::Fetchware.
##HOWTOTEST##EOS

    $ENV{FETCHWARE_FTP_LOOKUP_URL} =~ m!^(ftp://[-a-z,A-Z,0-9,\.]+)(/.*)?!;
    my $site = $1;
    eval_ok(sub {ftp_download_dirlist( "$site/doesntexist.ever")},
        <<'EOS', 'check ftp_download_dirlist() Net::FTP->dir($path) failure');
App-Fetchware: run-time error. fetchware failed to get a long directory listing
of [/doesntexist.ever] on server [carroll.cac.psu.edu]. The ftp error was [Here comes the directory listing.
 Directory send OK.
]. See man App::Fetchware.
EOS

};


subtest 'test http_download_dirlist()' => sub {
    skip_all_unless_release_testing();

    # Test success.
    ok(http_download_dirlist($ENV{FETCHWARE_HTTP_LOOKUP_URL}),
        'checked http_download_dirlist() success');

    eval_ok(sub {http_download_dirlist('http://meanttofail.fake/gonna/fail');},
        qr/.*?HTTP::Tiny failed to download.*?/,
        'checked http_download_dirlist() download failure');

##HOWTOTEST##    eval_ok(sub {http_download_dirlist('whatshouldthisbe??????');,
##HOWTOTEST##        <<EOS, 'checked http_download_dirlist() empty content failure');
##HOWTOTEST##App-Fetchware: run-time error. The lookup_url you provided downloaded nothing.
##HOWTOTEST##HTTP status code [$response->{status} $response->{reason}]
##HOWTOTEST##HTTP headers [@{[Data::Dumper::Dumper($response)]}].
##HOWTOTEST##See man App::Fetchware.
##HOWTOTEST##EOS

};


subtest 'test file_download_dirlist()' => sub {
    skip_all_unless_release_testing();

    # Get a dirlisting for fetchware's testing directory, because it *has* to
    # exist.
    my $test_path = rel2abs('t');
    my $dirlist = file_download_dirlist("file://$test_path");
diag explain $dirlist;

    # Check if known files are in the t directory. Regexes are used in case
    # files are changed or added, so I don't have to constantly update a silly
    # listing of all the files in the t directory.
    ok( grep m!t/App-Fetchware-!, @$dirlist,
        'checked file_download_dirlist() for App-Fetchware tests.');
    ok( grep m!t/bin-fetchware-!, @$dirlist,
        'checked file_download_dirlist() for bin-fetchware tests.');
};


subtest 'test download_dirlist' => sub {
    skip_all_unless_release_testing();

    my $url = 'invalidscheme://fake.url';
    eval_ok(sub {download_dirlist($url)}, <<EOS, 'checked download_dirlist() invalid url scheme');
App-Fetchware: run-time syntax error: the url parameter your provided in
your call to download_dirlist() [invalidscheme://fake.url] does not have a supported URL scheme (the
http:// or ftp:// part). The only supported download types, schemes, are FTP and
HTTP. See perldoc App::Fetchware.
EOS

    ok(download_dirlist($ENV{FETCHWARE_FTP_LOOKUP_URL}),
        'check download_dirlist() ftp success');

    ok(download_dirlist($ENV{FETCHWARE_HTTP_LOOKUP_URL}),
        'check download_dirlist() http success');

};


subtest 'test download_ftp_url()' => sub {
    skip_all_unless_release_testing();

    download_ftp_url($ENV{FETCHWARE_FTP_DOWNLOAD_URL});
    my $url_path = $ENV{FETCHWARE_FTP_DOWNLOAD_URL};
    $url_path =~ s!^ftp://!!;
    my ($scheme, $auth, $path, $query, $frag) = uri_split($ENV{FETCHWARE_FTP_DOWNLOAD_URL});
    my ($volume, $directories, $filename) = splitpath($path);
    ok(-e $filename, 'checked download_ftp_url success');

    ok(unlink $filename, 'checked deleting downloaded file');


    eval_ok(sub {download_ftp_url('ftp://doesntexist.ever')},
        <<EOS, 'checked determine_download_url() connect failure');
App-Fetchware: run-time error. fetchware failed to connect to the ftp server at
domain [doesntexist.ever]. The system error was [Net::FTP: Bad hostname 'doesntexist.ever'].
See man App::Fetchware.
EOS

##HOWTOTEST## How do I test the switching to binary mode error?  Can it even
#fail?

##HOWTOTEST##    eval_ok(sub {download_ftp_url('whatftpserverdoesntsupportanonymous&ispublic?');,
##HOWTOTEST##        <<EOS, 'checked download_ftp_url() empty content failure');
##HOWTOTEST##App-Fetchware: run-time error. fetchware failed to log in to the ftp server at
##HOWTOTEST##domain [$site]. The ftp error was [@{[$ftp->message]}]. See man App::Fetchware.
##HOWTOTEST##EOS
    

    eval_ok( sub {download_ftp_url("$scheme://$auth/doesnt/exist/anywhere")},
        <<EOS, 'check download_ftp_url() failed to chdir');
App-Fetchware: run-time error. fetchware failed to cwd() to [/doesnt/exist/anywhere] on site
[carroll.cac.psu.edu]. The ftp error was [Failed to change directory.
]. See perldoc App::Fetchware.
EOS

    eval_ok(sub {download_ftp_url("$scheme://$auth/$directories/filedoesntexist")},
        <<EOS, 'checked download_ftp_url() cant Net::FTP->get() file');
App-Fetchware: run-time error. fetchware failed to download the file [filedoesntexist]
from path [//pub/apache/httpd//filedoesntexist] on server [carroll.cac.psu.edu]. The ftp error message was
[Failed to open file.
]. See perldoc App::Fetchware.
EOS
    
##BUGALERT### Must add test for download_ftp_url() returning the $filename.

};


subtest 'test download_http_url()' => sub {
    skip_all_unless_release_testing();

###BUGALERT### the 2 lins below are copied & pasted 3 times subify them!
    my ($scheme, $auth, $path, $query, $frag) = uri_split($ENV{FETCHWARE_FTP_DOWNLOAD_URL});
    my ($volume, $directories, $filename) = splitpath($path);
    is(download_http_url($ENV{FETCHWARE_HTTP_DOWNLOAD_URL}),
        $filename, 'checked download_http_url() success.');
    ok(-e $filename, 'checked download_ftp_url success');
    ok(unlink $filename, 'checked deleting downloaded file');

    eval_ok(sub {download_http_url('http://fake.url')},
        qr/599 Internal Exception/, 'checked download_http_url bad hostname');

##HOWTOTEST## I don't think the unless length $response->{content} is easily
#testable.

##HOWTOTEST## Also, open failing isn't testable either, because any data I feed
#it will cause the other tests above to fail first.

##HOWTOTEST## How do you test close failing? I don't know if you can easily.

};


subtest 'test download_file_url' => sub {
    skip_all_unless_release_testing();

    # Create test file to download.
    my $test_dist_path = make_test_dist('test-dist-1.00', rel2abs('t'));

    my $filename = download_file_url('file://t/test-dist-1.00.fpkg');

    is($filename, 'test-dist-1.00.fpkg',
        'checked download_file_url() success.');

    # Delete useless test-dist package.
    ok(unlink $test_dist_path, 'checked download_file_url() cleanup.');

    # Delete useless copied file.
    ok(unlink $filename, 'checked download_file_url() cleanup.');
};


subtest 'test download_file' => sub {
    skip_all_unless_release_testing();

    my $url = 'invalidscheme://fake.url';
    eval_ok(sub {download_file($url)}, <<EOS, 'checked download_file() invalid url scheme');
App-Fetchware: run-time syntax error: the url parameter your provided in
your call to download_file() [invalidscheme://fake.url] does not have a supported URL scheme (the
http:// or ftp:// part). The only supported download types, schemes, are FTP and
HTTP. See perldoc App::Fetchware.
EOS

    # Add /KEYS to the lookup URLs, because download_file() must download an
    # actual file *not* a worthless dirlist. This makes tese brittle tests.
    my $filename;
    ok($filename = download_file("$ENV{FETCHWARE_FTP_LOOKUP_URL}/KEYS"),
        'check download_file() ftp success');
    ok(-e $filename, 'checked download_ftp_url return success');
    ok(unlink $filename, 'checked deleting downloaded file');

    ok($filename = download_file("$ENV{FETCHWARE_HTTP_LOOKUP_URL}/KEYS"),
        'check download_file() http success');
    ok(-e $filename, 'checked download_http_url return success');
    ok(unlink $filename, 'checked deleting downloaded file');

};


subtest 'test make_test_dist' => sub {
    ###HOWTOTEST### How do I test for mkdir() failure, open() failure, and
    #Archive::Tar->create_archive() failure?

    my $file_name = 'test-dist-1.00';
    my $retval = make_test_dist($file_name);
    is($retval, rel2abs("$file_name.fpkg"),
        'check make_test_dist() success.');

    ok(unlink $retval, 'checked make_test_dist() cleanup');

    # Test more than one call as used in t/bin-fetchware-upgrade-all.t
    my @filenames = qw(test-dist-1.00 test-dist-1.01);

    my @retvals;
    for my $filename (@filenames) {
        my $retval = make_test_dist($file_name);
        is($retval, rel2abs("$file_name.fpkg"),
            'check make_test_dist() 2 calls  success.');
        push @retvals, $retval;
    }

    ok(unlink @retvals, 'checked make_test_dist() 2 calls cleanup');

    # Test make_test_dist()'s second destination directory argument.
    my $name = 'test-dist-1.00';
    my $return_val = make_test_dist($name, tmpdir());
    is($return_val, catfile(tmpdir(), "$name.fpkg"),
        'check make_test_dist() destination directory success.');

    ok(unlink $return_val, 'checked make_test_dist() cleanup');
};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
done_testing();
