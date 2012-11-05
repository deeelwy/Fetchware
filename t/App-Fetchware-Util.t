#!perl
# App-Fetchware-Util.t tests App::Fetchware::Util's utility subroutines, which
# provied helper functions such as logging and file & dirlist downloading.
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '16'; #Update if this changes.

use File::Spec::Functions qw(splitpath catfile rel2abs tmpdir);
use URI::Split 'uri_split';
use Cwd 'cwd';
use Test::Fetchware ':TESTING';
use App::Fetchware::Config qw(config config_replace);

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
diag("App::Fetchware's default imports [@App::Fetchware::Util::EXPORT]");



###BUGALERT### Add tests for :UTIL subs that have no tests!!!
subtest 'UTIL export what they should' => sub {
    my @expected_util_exports = qw(
        msg
        vmsg
        run_prog
        download_dirlist
        ftp_download_dirlist
        http_download_dirlist
        file_download_dirlist
        download_file
        download_ftp_url
        download_http_url
        download_file_url
        just_filename
        do_nothing
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
    my $test_dist_path = make_test_dist('test-dist', '1.00', rel2abs('t'));

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

    $temp_dir = create_tempdir(KeepTempDir => 1);
    ok(-e $temp_dir, 'checked create_tempdir() KeepTempDir success.');
note "TEMPDIR[$temp_dir]";

    # Cleanup $temp_dir, because this one won't automatically be cleaned up.
    chdir original_cwd() or fail("Failed to chdir back to original_cwd()!");
    rmdir $temp_dir or fail("Failed to delete temp_dir[$temp_dir]! [$!]");

    # Test create_tempdir() successes with a custom temp_dir set.
    config(temp_dir => tmpdir());
    $temp_dir = create_tempdir();
    ok(-e $temp_dir, 'checked create_tempdir() success.');

    $temp_dir = create_tempdir(KeepTempDir => 1);
    ok(-e $temp_dir, 'checked create_tempdir() KeepTempDir success.');
note "TEMPDIR[$temp_dir]";

    # Cleanup $temp_dir, because this one won't automatically be cleaned up.
    chdir original_cwd() or fail("Failed to chdir back to original_cwd()!");
    rmdir $temp_dir or fail("Failed to delete temp_dir[$temp_dir]! [$!]");

    # Test create_tempdir() failure
    config_replace(temp_dir => ( 'doesnotexist' . int(rand(238378290)) ));
    eval_ok( sub {create_tempdir()},
        <<EOE, 'tested create_tempdir() temp_dir does not exist failure.');
App-Fetchware: run-time error. Fetchware tried to use File::Temp's tempdir()
subroutine to create a temporary file, but tempdir() threw an exception. That
exception was []. See perldoc App::Fetchware.
EOE

    #chdir back to $original_cwd, so that File::Temp's END block can delete
    #this last temp_dir. Otherwise, a warning is printed from File::Temp about
    #this.
    chdir $original_cwd or fail("Failed to chdir back to [$original_cwd]!");
};








# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
