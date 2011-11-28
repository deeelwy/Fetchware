#!perl
# Fetchware-lookup.t tests App::Fetchware's lookup() subroutine, which
# determines if a new version of your program is available.
use strict;
use warnings;
use diagnostics;
use 5.010;

use Test::More tests => '6'; #Update if this changes.

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

# Use extra private sub __FW() to access App::Fetchware's internal state
# variable, so that I can test that the configuration subroutines work properly.
my $FW = App::Fetchware::__FW();


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
        <<'EOS', 'checked download_http_url bad hostname');
App-Fetchware: run-time error. HTTP::Tiny failed to download a directory listing
of your provided lookup_url. HTTP status code [599 Internal Exception]
HTTP headers [$VAR1 = {
          'content-type' => 'text/plain',
          'content-length' => 157
        };
].
See man App::Fetchware.
EOS

##HOWTOTEST## I don't think the unless length $response->{content} is easily
#testable.

##HOWTOTEST## Also, open failing isn't testable either, because any data I feed
#it will cause the other tests above to fail first.

##HOWTOTEST## How do you test close failing? I don't know if you can easily.

};


subtest 'test determine_package_path()' => sub {
    my $cwd = cwd();
    diag("cwd[$cwd]");
    is(determine_package_path($cwd, 'bin/fetchware'),
        '/home/dly/Desktop/Code/App-Fetchware/bin/fetchware',
        'checked determine_package_path() success');
};


subtest 'test download()' => sub {
    skip_all_unless_release_testing();

    for my $url ($ENV{FETCHWARE_FTP_DOWNLOAD_URL},
        $ENV{FETCHWARE_HTTP_DOWNLOAD_URL}) {
        # manually set DownloadType, which download() depends on.
        my ($scheme, $auth, $path, $query, $frag) = uri_split($url);
        my ($volume, $directories, $filename) = splitpath($path);
        $FW->{DownloadType} = $scheme;
        # Manually set $FW{DownloadURL};
        $FW->{DownloadURL} = $url;
        # manually set $FW{TempDir} to cwd().
        my $cwd = cwd();
        $FW->{TempDir} = $cwd;

        download();

        is($FW->{PackagePath}, catfile($cwd, $filename),
            'checked download() success.');
    }

};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
