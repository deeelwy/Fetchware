#!perl
# App-Fetchware-Util.t tests App::Fetchware::Util's utility subroutines, which
# provied helper functions such as logging and file & dirlist downloading.
use strict;
use warnings;
use diagnostics;
use 5.010001;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '25'; #Update if this changes.

use File::Spec::Functions qw(splitpath catfile rel2abs tmpdir rootdir);
use URI::Split 'uri_split';
use Cwd 'cwd';
use Test::Fetchware ':TESTING';
use App::Fetchware::Config qw(config config_replace config_delete __clear_CONFIG);
use File::Temp qw(tempdir tempfile);
use Path::Class;
use Perl::OSType 'is_os_type';
use Fcntl ':flock';
use URI::Split qw(uri_split uri_join);

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
# There is no ':OVERRIDE_START' to bother importing.
BEGIN { use_ok('App::Fetchware::Util', ':UTIL'); }

# Print the subroutines that App::Fetchware imported by default when I used it.
note("App::Fetchware::Util's default imports [@App::Fetchware::Util::EXPORT]");



###BUGALERT### Add tests for :UTIL subs that have no tests!!!
subtest 'UTIL export what they should' => sub {
    my @expected_util_exports = qw(
        msg
        vmsg
        run_prog
        no_mirror_download_dirlist
        download_dirlist
        ftp_download_dirlist
        http_download_dirlist
        file_download_dirlist
        no_mirror_download_file
        download_file
        download_ftp_url
        download_http_url
        download_file_url
        just_filename
        do_nothing
        safe_open
        drop_privs
        pipe_write_newline
        pipe_read_newline
        create_tempdir
        original_cwd
        cleanup_tempdir
    );

    # sort them to make the testing their equality very easy.
    @expected_util_exports = sort @expected_util_exports;
    my @sorted_util_tag = sort @{$App::Fetchware::Util::EXPORT_TAGS{UTIL}};

    ok(@expected_util_exports ~~ @sorted_util_tag, 
        'checked for correct UTIL @EXPORT_TAG');
};


###BUGALERT###Need to add tests for :TESTING exports & specifc subtests for eval_ok(),
# skip_all_unless_release_testing(), and clear_CONFIG().


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

##HOWTOTEST##    eval_ok(sub #{ftp_download_dirlist('whatftpserverdoesntsupportanonymous&ispublic?');},
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

    # Test file_download_dirlist()'s Exceptions.
    eval_ok(sub {file_download_dirlist('/akdjf983hfo3e4gghj-doesnotexist')},
        <<EOE, 'checked file_download_dirlist() does not exist exception.');
App-Fetchware-Util: The directory that fetchware is trying to use to determine
if a new version of the software is available does not exist. This directory is
[/akdjf983hfo3e4gghj-doesnotexist], and the OS error is [No such file or directory].
EOE
    my $temp_dir = tempdir("fetchware-test-$$-XXXXXXXXX",
        CLEANUP => 1, TMPDIR => 1);
    eval_ok(sub {file_download_dirlist($temp_dir)},
        qr/if a new version of the software is available is empty. This directory/,
        'checked file_download_dirlist() empty directory exception.');

    # Get a dirlisting for fetchware's testing directory, because it *has* to
    # exist.
    my $test_path = rel2abs('t');
    my $dirlist = file_download_dirlist("file://$test_path");
note explain $dirlist;

    # Check if known files are in the t directory. Regexes are used in case
    # files are changed or added, so I don't have to constantly update a silly
    # listing of all the files in the t directory.
    ok( grep m!t/App-Fetchware-!, @$dirlist,
        'checked file_download_dirlist() for App-Fetchware tests.');
    ok( grep m!t/bin-fetchware-!, @$dirlist,
        'checked file_download_dirlist() for bin-fetchware tests.');
};



subtest 'test no_mirror_download_dirlist' => sub {
    skip_all_unless_release_testing();

    my $url = 'invalidscheme://fake.url';
    eval_ok(sub {no_mirror_download_dirlist($url)}, <<EOS, 'checked no_mirror_download_dirlist() invalid url scheme');
App-Fetchware: run-time syntax error: the url parameter your provided in
your call to download_dirlist() [invalidscheme://fake.url] does not have a supported URL scheme (the
http:// or ftp:// part). The only supported download types, schemes, are FTP and
HTTP. See perldoc App::Fetchware.
EOS

    ok(no_mirror_download_dirlist($ENV{FETCHWARE_FTP_LOOKUP_URL}),
        'check no_mirror_download_dirlist() ftp success');

    ok(no_mirror_download_dirlist($ENV{FETCHWARE_HTTP_LOOKUP_URL}),
        'check no_mirror_download_dirlist() http success');

    # No cleanup code needed ftp doesn't download files, and http uses
    # HTTP::Tiny, which returns a scalar ref. None of these are files written to
    # the filesystem, so nothing needs cleaning up.
};


subtest 'test download_dirlist' => sub {
    skip_all_unless_release_testing();

    # Ensure we have a clean working environment.
    __clear_CONFIG();

    # Test download_dirlist()'s parameter checking.
    eval_ok(sub {download_dirlist()},
        <<EOE, 'checked download_dirlist() no params exception.');
App-Fetchware-Util: You can only specify either PATH or URL never both. Only
specify one or the other when you call download_dirlist().
EOE
    eval_ok(sub {download_dirlist('one', 'two', 'three')},
        <<EOE, 'checked download_dirlist() too many exception.');
App-Fetchware-Util: You can only specify either PATH or URL never both. Only
specify one or the other when you call download_dirlist().
EOE
    eval_ok(sub {download_dirlist('fake url who cares', PATH => 'some/path')},
        <<EOE, 'checked download_dirlist() wrong param exception.');
App-Fetchware-Util: You can only specify either PATH or URL never both. Only
specify one or the other when you call download_dirlist().
EOE

    eval_ok(sub {download_dirlist(PATH => 'fake/path')},
        <<EOE, 'checked download_dirlist() PATH but no mirrors exception.');
App-Fetchware-Util: You only called download_dirlist() with just a PATH
parameter, but also failed to specify any mirrors in your configuration. Without
any defined mirrors download_dirlist() cannot determine from what host to
download your file. Please specify a mirror and try again.
EOE

    my $url = 'invalidscheme://fake.url';
    # Setup a fake mirror to test the mirror failing too.
    config(mirror => $url);
    eval_ok(sub {download_dirlist($url)}, <<EOS, 'checked download_dirlist() invalid url scheme');
App-Fetchware-Util: Failed to download the specifed URL [invalidscheme://fake.url] or path
[] using the included hostname in the url you specifed or any
mirrors. The mirrors are [invalidscheme://fake.url]. And the urls
that fetchware tried to download were [invalidscheme://fake.url invalidscheme://fake.url ].
EOS
    # Clear previous mirror.
    config_delete('mirror');

    # Determine what we download should look like.
    my $expected_output;
    ok($expected_output = download_dirlist($ENV{FETCHWARE_FTP_LOOKUP_URL}),
        'check download_dirlist() expected ftp success');

    # Setup a mirror that should succeed, but a $url that should fail.
    config(mirror => $ENV{FETCHWARE_FTP_LOOKUP_URL});
    my $got_output = download_dirlist($url);
    ok($got_output,
        'check download_dirlist() ftp mirror success');

    # Compare what no mirror gets to what a failed try with one mirror gets.
    is_deeply($got_output, $expected_output,
        'check download_dirlist() proper output');

    # Now try multiple mirrors.

    # Delete all mirrors.
    config_delete('mirror');

    # Set up mirrors that will fail, and one final mirror that should succeed.
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => $ENV{FETCHWARE_FTP_LOOKUP_URL});

    # Test multiple mirrors.
    ok($got_output = download_dirlist($url),
        'check download_dirlist() multi-mirror ftp success');

    # Compare what no mirror gets to what a failed try with one mirror gets.
    is_deeply($got_output, $expected_output,
        'check download_dirlist() proper output');

    # Test download_dirlist(PATH => $path) support.
    __clear_CONFIG();
    # Set up the mirror so that it has no path.
    my ($scheme, $auth, $path, $query, $frag) =
        uri_split($ENV{FETCHWARE_FTP_LOOKUP_URL});
    config(mirror => uri_join($scheme, $auth, undef, undef, undef));

    # Then test download_dirlist() with what would normally be the mirror's
    # path.
    ok($got_output = download_dirlist(PATH => $path),
        'checked download_dirlists(PATH) ftp success.');
    is_deeply($got_output, $expected_output,
        'check download_dirlist(PATH) ftp proper output');


    # Clean up mirrors again.
    config_delete('mirror');


    # Change $expected_output to http, which is a scalar ref instead of a
    # arrayref.
    ok($expected_output = download_dirlist($ENV{FETCHWARE_HTTP_LOOKUP_URL}),
        'check download_dirlist() expected http success');

    # Set up mirrors that will fail, and one final mirror that should succeed.
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => $ENV{FETCHWARE_HTTP_LOOKUP_URL});

    # Test multiple mirrors.
    ok($got_output = download_dirlist($url),
        'check download_dirlist() multi-mirror http success');
    # Compare what no mirror gets to what a failed try with one mirror gets.
    is_deeply($got_output, $expected_output,
        'check download_dirlist() proper output');

    # Test download_dirlist(PATH => $path) support.
    __clear_CONFIG();
    # Set up the mirror so that it has no path.
    ($scheme, $auth, $path, $query, $frag) =
        uri_split($ENV{FETCHWARE_HTTP_LOOKUP_URL});
    config(mirror => uri_join($scheme, $auth, undef, undef, undef));

    # Then test download_dirlist() with what would normally be the mirror's
    # path.
    ok($got_output = download_dirlist(PATH => $path),
        'checked download_dirlists(PATH) http success.');
    is_deeply($got_output, $expected_output,
        'check download_dirlist(PATH) http proper output');

    # Clean up after ourselves.
    __clear_CONFIG();
};


subtest 'test download_dirlist(file://)' => sub {
    my $got_dirlist;
    ok($got_dirlist = download_dirlist('file://'. catfile(cwd(), 't')),
        'checked download_dirlist(file://) success');
#note explain \$got_dirlist;
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
    my $test_dist_path = make_test_dist('test-dist', '1.00', rel2abs('t'));

    my $filename = download_file_url('file://t/test-dist-1.00.fpkg');

    is($filename, 'test-dist-1.00.fpkg',
        'checked download_file_url() success.');

    # Delete useless test-dist package.
    ok(unlink $test_dist_path, 'checked download_file_url() cleanup.');

    # Delete useless copied file.
    ok(unlink $filename, 'checked download_file_url() cleanup.');
};


subtest 'test download_file()' => sub {
    skip_all_unless_release_testing();

    # Ensure we have a clean working environment.
    __clear_CONFIG();

    # Test download_file()'s parameter checking.
    eval_ok(sub {download_file()},
        <<EOE, 'checked download_file() no params exception.');
App-Fetchware-Util: You can only specify either PATH or URL never both. Only
specify one or the other when you call download_dirlist().
EOE
    eval_ok(sub {download_file('one', 'two', 'three')},
        <<EOE, 'checked download_file() too many exception.');
App-Fetchware-Util: You can only specify either PATH or URL never both. Only
specify one or the other when you call download_dirlist().
EOE
    eval_ok(sub {download_file('fake url who cares', PATH => 'fake/path')},
        <<EOE, 'checked download_file() wrong param exception.');
App-Fetchware-Util: You can only specify either PATH or URL never both. Only
specify one or the other when you call download_dirlist().
EOE

    eval_ok(sub {download_file(PATH => 'fake/path')},
        <<EOE, 'checked download_file() PATH but no mirrors exception.');
App-Fetchware-Util: You only called download_file() with just a PATH parameter,
but also failed to specify any mirrors in your configuration. Without any
defined mirrors download_file() cannot determine from what host to download your
file. Please specify a mirror and try again.
EOE

    my $url = 'invalidscheme://fake.url';
    # Setup a fake mirror to test the mirror failing too.
    config(mirror => $url);
    eval_ok(sub {download_file($url)}, <<EOS, 'checked download_file() invalid url scheme');
App-Fetchware-Util: Failed to download the specifed URL [invalidscheme://fake.url] or path
[] using the included hostname in the url you specifed or any
mirrors. The mirrors are [invalidscheme://fake.url]. And the urls
that fetchware tried to download were [invalidscheme://fake.url invalidscheme://fake.url ].
EOS
    # Clear previous mirror.
    config_delete('mirror');

    # Setup a mirror that should succeed, but a $url that should fail.
    my $filename;
    config(mirror => "$ENV{FETCHWARE_FTP_LOOKUP_URL}/KEYS");
    ok($filename = download_file($url),
        'check download_file() ftp mirror success');
    ok(-e $filename, 'checked download_file() ftp filename success');
    ok(unlink $filename, 'checked deleting downloaded file');

    # Now try multiple mirrors.

    # Delete all mirrors.
    config_delete('mirror');

    # Set up mirrors that will fail, and one final mirror that should succeed.
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => "$ENV{FETCHWARE_FTP_LOOKUP_URL}/KEYS");

    # Test multiple mirrors.
    ok($filename = download_file($url),
        'check download_file() ftp multi-mirror success');
    ok(-e $filename, 'checked download_file() ftp multi-mirror filename success');
    ok(unlink $filename, 'checked deleting downloaded file');

    # Test download_dirlist(PATH => $path) support.
    __clear_CONFIG();
    # Set up the mirror so that it has no path.
    my ($scheme, $auth, $path, $query, $frag) =
        uri_split($ENV{FETCHWARE_FTP_LOOKUP_URL});
    config(mirror => uri_join($scheme, $auth, undef, undef, undef));

    # Then test download_dirlist() with what would normally be the mirror's
    # path.
    ok($filename = download_file(PATH => "$path/KEYS"),
        'checked download_dirlists(PATH) ftp success.');
    ok(-e $filename, 'checked download_file(PATH) ftp success');
    ok(unlink $filename, 'checked deleting downloaded file');

    # Clean up mirrors again.
    config_delete('mirror');

    # Set up mirrors that will fail, and one final mirror that should succeed.
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => $url);
    config(mirror => "$ENV{FETCHWARE_HTTP_LOOKUP_URL}/KEYS");

    # Test multiple mirrors.
    ok($filename = download_file($url),
        'check download_file() http multi-mirror success');
    ok(-e $filename, 'checked download_file() http multi-mirror filename success');
    ok(unlink $filename, 'checked deleting downloaded file');

    # Test download_file(PATH => $path) support.
    __clear_CONFIG();
    # Set up the mirror so that it has no path.
    my ($scheme, $auth, $path, $query, $frag) =
        uri_split($ENV{FETCHWARE_FTP_LOOKUP_URL});
    config(mirror => uri_join($scheme, $auth, undef, undef, undef));

    # Then test download_dirlist() with what would normally be the mirror's
    # path.
    ok($filename = download_file(PATH => "$path/KEYS"),
        'checked download_file(PATH) http success.');
    ok(-e $filename, 'checked download_file(PATH) http success');
    ok(unlink $filename, 'checked deleting downloaded file');

    # clean up after ourselves.
    __clear_CONFIG();
};


subtest 'test download_file(file://)' => sub {
    my $test_dist_path = make_test_dist('test-dist', '1.00');

    my $got_filename;
    ok($got_filename = download_file('file://' . $test_dist_path),
        'checked download_file(file://) success.');

    is(file($got_filename)->basename, file($test_dist_path)->basename,
        'checked download_file(file://) filename success.');
    ok(unlink($test_dist_path),
        'checked download_file(file://) cleanup test file.');
    # Also delete the $got_filename, because download_file() will "download"
    # (copy the file).
    ok(unlink($got_filename),
        'checked download_file(file://) cleanup copied file.');
};


subtest 'test no_mirror_download_file' => sub {
    skip_all_unless_release_testing();

    my $url = 'invalidscheme://fake.url';
    eval_ok(sub {no_mirror_download_file($url)}, <<EOS, 'checked download_file() invalid url scheme');
App-Fetchware: run-time syntax error: the url parameter your provided in
your call to download_file() [invalidscheme://fake.url] does not have a supported URL scheme (the
http:// or ftp:// part). The only supported download types, schemes, are FTP and
HTTP. See perldoc App::Fetchware.
EOS

    # Add /KEYS to the lookup URLs, because download_file() must download an
    # actual file *not* a worthless dirlist. This makes tests brittle.
    my $filename;
    ok($filename = no_mirror_download_file("$ENV{FETCHWARE_FTP_LOOKUP_URL}/KEYS"),
        'check download_file() ftp success');
    ok(-e $filename, 'checked download_ftp_url return success');
    ok(unlink $filename, 'checked deleting downloaded file');

    ok($filename = no_mirror_download_file("$ENV{FETCHWARE_HTTP_LOOKUP_URL}/KEYS"),
        'check download_file() http success');
    ok(-e $filename, 'checked download_http_url return success');
    ok(unlink $filename, 'checked deleting downloaded file');

};


subtest 'test make_test_dist()' => sub {
    ###HOWTOTEST### How do I test for mkdir() failure, open() failure, and
    #Archive::Tar->create_archive() failure?

    my $file_name = 'test-dist';
    my $ver_num = '1.00';
    my $retval = make_test_dist($file_name, $ver_num);
    is(file($retval)->basename(), "$file_name-$ver_num.fpkg",
        'check make_test_dist() success.');

    ok(unlink( $retval), 'checked make_test_dist() cleanup');

    # Test more than one call as used in t/bin-fetchware-upgrade-all.t
    my @filenames = qw(test-dist another-dist);

    my @retvals;
    for my $filename (@filenames) {
        my $retval = make_test_dist($file_name, $ver_num);
        is(file($retval)->basename, "$file_name-$ver_num.fpkg",
            'check make_test_dist() 2 calls  success.');
        push @retvals, $retval;
    }

    ok(unlink(@retvals), 'checked make_test_dist() 2 calls cleanup');

    # Test make_test_dist()'s second destination directory argument.
    my $name = 'test-dist-1.00';
    my $return_val = make_test_dist($name, $ver_num, tmpdir());
    is($return_val, catfile(tmpdir(), "$name-$ver_num.fpkg"),
        'check make_test_dist() destination directory success.');

    ok(unlink($return_val), 'checked make_test_dist() cleanup');
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

    # Clean up junk temp files.
    ok(unlink($test_dist, $test_dist_md5),
        'cleaned up test md5sum_file()');
};


subtest 'test msg()' => sub {
   print_ok(sub {msg("Testing 1...2...3!!!\n")},
       <<EOM, 'test msg() success.');
Testing 1...2...3!!!
EOM

   print_ok(sub {msg("Testing\n", "1...2...3!!!\n")},
       <<EOM, 'test msg() 2 args success.');
Testing
1...2...3!!!
EOM

   print_ok(sub {msg(1,2,3,4,5,6,7,8,9,0,"\n")},
       <<EOM, 'test msg() many args success.');
1234567890
EOM


   print_ok(sub {msg "Testing 1...2...3!!!\n"},
       <<EOM, 'test msg success.');
Testing 1...2...3!!!
EOM

   print_ok(sub {msg "Testing\n", "1...2...3!!!\n"},
       <<EOM, 'test msg 2 args success.');
Testing
1...2...3!!!
EOM

   print_ok(sub {msg 1,2,3,4,5,6,7,8,9,0,"\n"},
       <<EOM, 'test msg many args success.');
1234567890
EOM

   # Test -q (quite) mode works.
   # Set bin/fetchware's $quiet to true.
   $fetchware::quiet = 1;

   ok(sub{msg 'Did I print anything???'}->() eq undef,
       'test msg quiet mode success.');
};


subtest 'test vmsg()' => sub {
    # Set bin/fetchware's $verbose to false.
    $fetchware::verbose = 0;
    # Set bin/fetchware's $quiet to false too!!!
    $fetchware::quiet = 0;
    # Test vmsg() when verbose is *not* turned on!
    ok(sub{vmsg 'Did I print anything???'}->() eq undef,
        'test vmsg not verbose mode success.');

    # Test -v (verbose) mode works.
    # Set bin/fetchware's $verbose to true.
    $fetchware::verbose = 1;

    print_ok(sub {vmsg("Testing 1...2...3!!!\n")},
        <<EOM, 'test vmsg() success.');
Testing 1...2...3!!!
EOM

    print_ok(sub {vmsg("Testing\n", "1...2...3!!!\n")},
        <<EOM, 'test vmsg() 2 args success.');
Testing
1...2...3!!!
EOM

    print_ok(sub {vmsg(1,2,3,4,5,6,7,8,9,0,"\n")},
        <<EOM, 'test vmsg() many args success.');
1234567890
EOM


    print_ok(sub {vmsg "Testing 1...2...3!!!\n"},
        <<EOM, 'test vmsg success.');
Testing 1...2...3!!!
EOM

    print_ok(sub {vmsg "Testing\n", "1...2...3!!!\n"},
        <<EOM, 'test vmsg 2 args success.');
Testing
1...2...3!!!
EOM

    print_ok(sub {vmsg 1,2,3,4,5,6,7,8,9,0,"\n"},
        <<EOM, 'test vmsg many args success.');
1234567890
EOM

    # Test -q (quite) mode works.
    # Set bin/fetchware's $quiet to true.
    $fetchware::quiet = 1;

    ok(sub{vmsg 'Did I print anything???'}->() eq undef,
        'test vmsg quiet mode success.');
};


subtest 'test run_prog()' => sub {
    # Set bin/fetchware's $quiet to false.
    $fetchware::quiet = 0;
    
    # Test using perl itself, because what other program is guaranteed to
    # be availabe on all platforms fetchware supports?
    # The insane >> thing is a "right shift" operator, which shifts the value of
    # system()'s return value 8 bits right, yielding the proper perl return
    # value as bash would return it in its $? (Not Perl's $?, which is the same
    # as system()'s return value.). And then it is tested if it ran successfully
    # in which case it would be 0, which means it ran successfully. See perldoc
    # system for more.
    ok(run_prog("$^X", '-e print "Testing 1...2...3!!!\n"') >> 8 == 0,
        'test run_prog() success');

    # Set bin/fetchware's $quiet to true.
    $fetchware::quiet = 1;

    ok(run_prog("$^X", '-e print "Testing 1...2...3!!!\n"') >> 8 == 0,
        'test run_prog() success');

    # Set bin/fetchware's $quiet to false.
    $fetchware::quiet = 0;
};


subtest 'test create_tempdir()' => sub {
    # Create my own original_cwd(), because it gets tainted, because I chdir
    # more than just once.
    my $original_cwd = cwd();
    # Test create_tempdir() successes.
    my $temp_dir = create_tempdir();
    ok(-e $temp_dir, 'checked create_tempdir() success.');
    ok(-e 'fetchware.sem', 'checked fetchware semaphore creation.');

    # chdir back to original_cwd(), so that this tempdir can be deleted.
    chdir original_cwd() or fail("Failed to chdir back to original_cwd()!");

    $temp_dir = create_tempdir(KeepTempDir => 1);
    ok(-e $temp_dir, 'checked create_tempdir() KeepTempDir success.');
    ok(-e 'fetchware.sem', 'checked fetchware semaphore creation.');
note "TEMPDIR[$temp_dir]";

    # Cleanup $temp_dir, because this one won't automatically be cleaned up.
    unlink 'fetchware.sem' or fail("Failed to delete 'fetchware.sem'! [$!]");
    chdir original_cwd() or fail("Failed to chdir back to original_cwd()!");
    rmdir $temp_dir or fail("Failed to delete temp_dir[$temp_dir]! [$!]");

    # Test create_tempdir() successes with a custom temp_dir set.
    $temp_dir = create_tempdir(TempDir => tmpdir());
    ok(-e $temp_dir, 'checked create_tempdir() success.');


    # Cleanup $temp_dir, because this one won't automatically be cleaned up.
    unlink 'fetchware.sem' or fail("Failed to delete 'fetchware.sem'! [$!]");
    chdir original_cwd() or fail("Failed to chdir back to original_cwd()!");
    rmdir $temp_dir or fail("Failed to delete temp_dir[$temp_dir]! [$!]");

    $temp_dir = create_tempdir(KeepTempDir => 1);
    ok(-e $temp_dir, 'checked create_tempdir() KeepTempDir success.');
    ok(-e 'fetchware.sem', 'checked fetchware semaphore creation.');
note "TEMPDIR[$temp_dir]";

    # Cleanup $temp_dir, because this one won't automatically be cleaned up.
    unlink 'fetchware.sem' or fail("Failed to delete 'fetchware.sem'! [$!]");
    chdir original_cwd() or fail("Failed to chdir back to original_cwd()!");
    rmdir $temp_dir or fail("Failed to delete temp_dir[$temp_dir]! [$!]");

    # Test create_tempdir() failure
    eval_ok( sub {create_tempdir(
                TempDir => 'doesnotexist' . int(rand(238378290)))},
        <<EOE, 'tested create_tempdir() temp_dir does not exist failure.');
App-Fetchware: run-time error. Fetchware tried to use File::Temp's tempdir()
subroutine to create a temporary file, but tempdir() threw an exception. That
exception was []. See perldoc App::Fetchware.
EOE

    #chdir back to $original_cwd, so that File::Temp's END block can delete
    #this last temp_dir. Otherwise, a warning is printed from File::Temp about
    #this.
    chdir original_cwd() or fail("Failed to chdir back to [@{[original_cwd]}]!");
};


subtest 'test cleanup_tempdir()' => sub {
    # Create a tempdir to test cleaning it up.
    my $temp_dir = create_tempdir();
    ok(-e $temp_dir, 'checked create_tempdir() success.');
    ok(-e 'fetchware.sem', 'checked fetchware semaphore creation.');

    # Now test cleaning it up by see if the fetchware semaphore lock file has
    # had its lock released or not.
    cleanup_tempdir();
    ok(open(my $fh_sem, '>', catfile($temp_dir, 'fetchware.sem')),
        'checked cleanup_tempdir() open fetchware lock file success.');
    ok( flock($fh_sem, LOCK_EX | LOCK_NB),
        'checked cleanup_tempdir() success.');
    ok(close $fh_sem,
        'checked cleanup_tempdir() released fetchware lock file success.');
};


subtest 'test drop_privs()' => sub {
    # Note: drop_privs() forks, and Test::More and Test::Builder don't support
    # forking. It's a massive bug that's still not fixed. Test::Builder2 should
    # fix it, but it isn't released yet as far as I know. Therefore I cannot use
    # any Test::More tests inside drop_privs() coderefs :( Instead I'll have to
    # write success to a tempfile, and then read the tempfile in a Test::More
    # test back in the parent, and only run tests in the parent.


    # If we not running as root.
    if ($< != 0) {
        my $previous_uid = $<;
        my $previous_euid = $>;

        drop_privs_ok(
            sub {
                my $fh = shift;
                # Write our real and effective uids to the tempfile.
                print $fh "$$\n";
                print $fh "$<\n";
                print $fh "$>\n";
            }, sub {
                my $rfh = shift;
                chomp(my $child_pid = <$rfh>);
                chomp(my $new_uid = <$rfh>);
                chomp(my $new_euid = <$rfh>);

                # Due to the if above we're nonroot, so check that we did not
                # fork, because only root is supposed to fork.
                ok($child_pid == $$,
                    'checked drop_privs() didnt fork success.');

                is($new_uid, $previous_uid,
                    'checked drop_privs() success.');
                is($new_euid, $previous_euid,
                    'checked drop_privs() success.');
            }
        );

        

    # If we're running as root.
    } elsif ($< == 0) {
        my $previous_uid = $<;
        my $previous_euid = $>;

        # Check drop_privs() with no extra args.
        drop_privs_ok(
            sub {
                my $fh = shift;
                # Write our real and effective uids to the tempfile.
                print $fh "$$\n";
                print $fh "$<\n";
                print $fh "$>\n";
            }, sub {
                my $rfh = shift;
                chomp(my $child_pid = <$rfh>);
                chomp(my $new_uid = <$rfh>);
                chomp(my $new_euid = <$rfh>);

                # Due to the if above we're nonroot, so check that we did not
                # fork, because only root is supposed to fork.
                ok($child_pid != $$,
                    'checked drop_privs() did fork success.');

                ok($new_uid != $previous_uid,
                    'checked drop_privs() uid success.');
                ok($new_euid != $previous_euid,
                    'checked drop_privs() euid success.');
            }
        );


        # Test drop_privs() extra args.
        drop_privs_ok(
            sub {
                my $fh = shift;
                # Write our real and effective uids to the tempfile.
                print $fh "$$\n";
                print $fh "$<\n";
                print $fh "$>\n";
            }, sub {
                my $rfh = shift;
                chomp(my $child_pid = <$rfh>);
                chomp(my $new_uid = <$rfh>);
                chomp(my $new_euid = <$rfh>);

                # Due to the if above we're nonroot, so check that we did not
                # fork, because only root is supposed to fork.
                ok($child_pid != $$,
                    'checked drop_privs() nobody did fork success.');

                ok($new_uid != $previous_uid,
                    'checked drop_privs() nobody uid success.');
                ok($new_euid != $previous_euid,
                    'checked drop_privs() nobody euid success.');
            }, 'nobody'
        );

        # Set stay_root to true to disable priv dropping.
        config(stay_root => 1);

        # Test drop_privs() stay_root.
        drop_privs_ok(
            sub {
                my $fh = shift;
                # Write our real and effective uids to the tempfile.
                print $fh "$$\n";
                print $fh "$<\n";
                print $fh "$>\n";
            }, sub {
                my $rfh = shift;
                chomp(my $child_pid = <$rfh>);
                chomp(my $new_uid = <$rfh>);
                chomp(my $new_euid = <$rfh>);

                # Due to the if above we're nonroot, so check that we did not
                # fork, because only root is supposed to fork.
                ok($child_pid == $$,
                    'checked drop_privs() stay_root no fork success.');

                ok($new_uid == $previous_uid,
                    'checked drop_privs() stay_root uid success.');
                ok($new_euid == $previous_euid,
                    'checked drop_privs() stay_root euid success.');
            }
        );

        # clear stay_root to avoid messing up other tests.
        config_delete('stay_root');


    } else {
        fail('Uhmmmm...this shouldn\'t happen...!?!');
    }

};


SKIP: {
    skip 'Test suite not being run on Unix.', 1 unless do {
        if (is_os_type('Unix')) {
            note('ISUNIX');
            1
        } else {
            # Return false
            note('ISNOTUNIX');
            0
        }
    };



    if (is_os_type('Unix')) {

        subtest 'test pipe_{write,read}_newline()' => sub {
            my @expected = qw(Did it work ?);

            pipe (READONLY, WRITEONLY)
                or fail("Failed to create pipe??? Os error [$!]");
            given (scalar fork) {
                when (undef) {
                    fail("Fork failed??? OS error [$!]");
                # For worked. Child goes here.
                } when (0) {
                    close READONLY
                        or fail("child readonly pipe close failed??? [$!].");
                    my $write_pipe = *WRITEONLY;
                    # Test goes here.


                    # Finally test pipe_write_newline().
                    pipe_write_newline($write_pipe, @expected);


                    # End test start fork and pipe boilerplate.
                    close WRITEONLY
                        or fail("child writeonly pipe close failed??? [$!].");
                    exit 0;
                # For worked. Parent goes here.
                } default {
                    my $kidpid = $_;
                    close WRITEONLY
                        or fail("parent writeonly pipe close failed??? [$!].");
                    my $readonly = *READONLY;
                    my $output;
                    $output .= $_ while (<$readonly>);
                    # Parent test goes here.
                    

                    my @got = pipe_read_newline(\$output);
                    for my $i (0..$#expected) {
                        is($got[$i], $expected[$i],
                            "checked pipe_{write,read}_newline() success [$i]");
                    }
                    fail("Got more than we expected [@got] [@expected]!")
                        if $#got > 3;


                    # End test start fork and pipe boilerplate.
                    close READONLY
                        or fail("parent readonly pipe close failed??? [$!].");
                    waitpid($kidpid, 0);
                    fail("Chil exited with nonzero exit code!")
                        if (($? >>8) != 0);
                }
            }

        };
    } else {
        note("Should be skipped, because you're not running this on Unix! [$^O]");
    }
}


# Share these variables with safe_open()'s tests as root below in the SKIP
# block.
my $tempdir;
my ($fh, $filename);
subtest 'test safe_open()' => sub {
    # Save $original_cwd so I can chdir back to where I came from later on.
    my $original_cwd = cwd();
    # create tempdir
    $tempdir = tempdir("fetchware-test-$$-XXXXXXXXXXXX",
        TMPDIR => 1, CLEANUP => 1);
    # And chdir to it.
    ok(chdir($tempdir), "checked safe_open() changed directory to [$tempdir]");

    # Test open a file in tempdir check it with safe permu
    # DIR is cwd(), because create_tempdir() creates a tempdir and
    #chdir()s to it.
    ($fh, $filename) = tempfile("fetchware-test-$$-XXXXXXXXXXXXXXX", DIR => cwd());
note("FILENAME[$filename]");
    close($fh);
    my $safe_fh = safe_open($filename);
    is_fh($safe_fh, 'checked safe_open() success');
    close ($safe_fh);

    # Test opening the file for writing.
    # The undef is a placeholder for the second arg. The error mesage is not a
    # named argument like WRITE is, because despite being optional, it's always
    # going to be used in fetchware for more helpful error messages.
    is_fh(safe_open($filename, undef,WRITE => 1),
        'checked safe_open write success');

    chmod 0640, $filename; 
    is_fh(safe_open($filename), 'checked safe_open() group readable success');
    chmod 0604, $filename; 
    is_fh(safe_open($filename), 'checked safe_open() other readable success');
    chmod 0644, $filename; 
    is_fh(safe_open($filename),
        'checked safe_open() group and other readable success');
    
    # Change perms to bad perms and check both group and owner
    chmod 0660, $filename;
    eval_ok(sub {safe_open($filename)},
        <<EOE, 'checked safe_open() file group perms unsafe');
App-Fetchware-Util: The file fetchware attempted to open is writable by someone
other than just the owner. Fetchwarefiles and fetchware packages must only be
writable by the owner. Do not only change permissions to fix this error. This
error may have allowed someone to alter the contents of your Fetchwarefile or
fetchware packages. Ensure the file was not altered, then change permissions to
644.
EOE

    # Make a directory inside the tempdir.
    mkdir ('testdir') or fail ('Failed to make testing directory [testdir]');

    # create a file inside the tempdir.
    my ($sdfh, $subdirfilename)
        = tempfile("fetchware-test-$$-XXXXXXXXXXXXXXX", DIR => cwd());
note("FILENAME[$subdirfilename]");

    # Check for success on the file.
    close($sdfh);
    my $sfh = safe_open($subdirfilename);
    is_fh($sfh, 'checked safe_open() success');
    close ($sfh);

    # Change perms for group and owner and recheck.
    chmod 0640, $subdirfilename; 
    is_fh(safe_open($subdirfilename), 'checked safe_open() group readable success');
    chmod 0604, $subdirfilename; 
    is_fh(safe_open($subdirfilename), 'checked safe_open() other readable success');
    chmod 0644, $subdirfilename; 
    is_fh(safe_open($subdirfilename),
        'checked safe_open() group and other readable success');

    # change perms for group and owner of the containing directory you made, and
    # recheck.
    chmod 0660, $subdirfilename;
    eval_ok(sub {safe_open($subdirfilename)},
        <<EOE, 'checked safe_open() file group perms unsafe');
App-Fetchware-Util: The file fetchware attempted to open is writable by someone
other than just the owner. Fetchwarefiles and fetchware packages must only be
writable by the owner. Do not only change permissions to fix this error. This
error may have allowed someone to alter the contents of your Fetchwarefile or
fetchware packages. Ensure the file was not altered, then change permissions to
644.
EOE

    # chdir back to $original_cwd so File::Temp can delete temp files.
    chdir $original_cwd;
};



SKIP: {
    skip 'Test suite not being run as root.', 1 unless do {
        if (is_os_type('Unix')) {
            if ($< == 0 or $> == 0) {
            # Return true
            note('ISUNIXANDROOT');
            1
            } else {
            # Return false
            note('ISUNIXNOTROOT!!!');
            0
            }
        } else {
            # Return false
            note('ISNOTUNIX');
            0
        }
    };


    subtest 'test safe_open() needs root' => sub {
        skip_all_unless_release_testing();


        if ($< == 0 or $> == 0) {
            # Use dir from above. #$tempdir and $filename.
            # Change group and owner perms on nobody owned dir.
            my $parent_dir = dir($filename)->parent();
            chmod 0640, $parent_dir; 
            is_fh(safe_open($parent_dir),
                'checked safe_open() group directory readable success');
            chmod 0604, $parent_dir; 
            is_fh(safe_open($parent_dir),
                'checked safe_open() other directory readable success');
            chmod 0644, $parent_dir; 
            is_fh(safe_open($parent_dir),
                'checked safe_open() group and other directory readable success');
            # Repeat for file too.
            chmod 0640, $filename; 
            is_fh(safe_open($filename),
                'checked safe_open() group file readable success');
            chmod 0604, $filename; 
            is_fh(safe_open($filename),
                'checked safe_open() other file readable success');
            chmod 0644, $filename; 
            is_fh(safe_open($filename),
                'checked safe_open() group and other file readable success');

            # chown the tempdir to nobody, and check for diff owner.
            # This call must happen after other checks, because it will make all
            # checks for $filename fail with the expected exception below, and
            # that change should just be isolated to this one test; therefore it
            # is last.
            chown(scalar getpwnam('nobody'), -1, $filename)
                or fail("Failed to chown [$filename]!");
            
            # Test it for failure.
            my $error_string = <<EOE;
App-Fetchware-Util: The file fetchware attempted to open is not owned by root or
the person who ran fetchware. This means the file could have been dangerously
altered, or it's a simple permissions problem. Do not simly change the
ownership, and rerun fetchware. Please check that the file.*
EOE
            eval_ok(sub {safe_open($filename)},
                qr/$error_string/,
                'checked safe_open() wrong owner failure');

            # Make a custom tempdir in / the root directory.
            my ($fh, $root_filename) =
                tempfile("fetchware-root-test-$$-XXXXXXXXXXXXXXX",
                    DIR => rootdir(),
                    UNLINK => 1
                );
            # Test it on a root dir that won't recurse into subdirs, because they're
            # arn't any.
            chmod 0640, $root_filename; 
            is_fh(safe_open($root_filename),
                'checked safe_open() group file readable success');
            chmod 0604, $root_filename; 
            is_fh(safe_open($root_filename),
                'checked safe_open() other file readable success');
            chmod 0644, $root_filename; 
            is_fh(safe_open($root_filename),
                'checked safe_open() group and other file readable success');
        } else {
            note("Should be skipped, because you're not root! [$<] [$>]");
        }
    };
}




sub is_fh {
    my $fh = shift;
    my $test_name = shift;

    ok(ref($fh) eq 'GLOB', $test_name);
}



# Allows me to test drop_privs() more than once without shitloads of copying and
# pasting the same stupid code over and over again.
# $writer_code is a coderef that does something, and prints values to its one
# argument $fh.
# Then $tester_code, which is a coderef, gets passed $rfh, which is a read-only
# file handle of the same file that $writer_code wrote to, and then $tester_code
# reads from $rfh, and compares the values it gets to what it expects using
# standard Test::More stuff such as is().
# @drop_privs_args is an optional array of options that are passed to
# drop_privs(), but the only option drop_privs() cares about is $regular_user.
sub drop_privs_ok {
    my $writer_code = shift;
    my $tester_code = shift;
    my @drop_privs_args = @_;


    my $output = drop_privs(sub {
        my $write_pipe = shift;
        $writer_code->($write_pipe);
    }, @drop_privs_args);

    # Open $output as a scalar ref to use perl to parse the output.
    open my $output_fh, '<', $output
        or fail("Failed to open [$output] [$$output]. OS error [$!]");

    $tester_code->($output_fh);
}


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
