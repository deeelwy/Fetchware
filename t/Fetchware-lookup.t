#!perl
# Fetchware-lookup.t tests App::Fetchware's lookup() subroutine, which
# determines if a new version of your program is available.
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '12'; #Update if this changes.

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
BEGIN { use_ok('App::Fetchware', qw(:DEFAULT :OVERRIDE_LOOKUP :TESTING)); }

# Print the subroutines that App::Fetchware imported by default when I used it.
diag("App::Fetchware's default imports [@App::Fetchware::EXPORT]");

my $class = 'App::Fetchware';

# Use extra private sub __FW() to access App::Fetchware's internal state
# variable, so that I can test that the configuration subroutines work properly.
my $FW = App::Fetchware::__FW();

subtest 'OVERRIDE_LOOKUP exports what it should' => sub {
    my @expected_overide_lookup_exports = qw(
        check_lookup_config
        download_directory_listing
        parse_directory_listing
        determine_download_url
        ftp_parse_filelist
        http_parse_filelist
        lookup_by_timestamp
        lookup_by_versionstring
        lookup_determine_downloadurl
    );
    # sort them to make the testing their equality very easy.
    @expected_overide_lookup_exports = sort @expected_overide_lookup_exports;
    my @sorted_lookup_tag = sort @{$App::Fetchware::EXPORT_TAGS{OVERRIDE_LOOKUP}};
    ok(@expected_overide_lookup_exports ~~ @sorted_lookup_tag, 
        'checked for correct OVERRIDE_LOOKUP @EXPORT_TAG');
};




# Test lookup()'s internal dependencies first in the order they appear.


subtest 'test check_lookup_config()' => sub {
    # check for when lookup_url is *not* providied.
    eval_ok(sub {check_lookup_config()}, <<EOS, 'checked check_lookup_config no lookup_url');
App-Fetchware: run-time syntax error: your Fetchwarefile did not specify a
lookup_url. lookup_url is a required configuration option, and must be
specified, because fetchware uses it to located new versions of your program to
download. See perldoc App::Fetchware
EOS

    # Call lookup_url 'url' to set the URL for the rest of the tests.
    lookup_url 'ftp://fake.url';

    # check lookup_method failure.
    lookup_method 'not-timestamp-or-versionstring';
    eval_ok(sub {check_lookup_config()}, <<EOS, 'checked check_lookup_config() invalid lookup_method');
App-Fetchware: run-time syntax error: your Fetchwarefile specified a incorrect
option to lookup_method. lookup_method only supports the options 'timestamp' and
'versionstring'. All others are wrong. See man App::Fetchware.
EOS

    # Change lookup_method to test the other 2 branches of the check_method failure
    # code.
    $FW->{lookup_method} = 'timestamp';
    ok(eval {check_lookup_config(); 1;}, "checked check_lookup_config() 'timestamp'");
    $FW->{lookup_method} = 'versionstring';
    ok(eval {check_lookup_config(); 1;}, "checked check_lookup_config() 'versionstring'");
};


subtest 'test download_directory_listing()' => sub {
    skip_all_unless_release_testing();

    for my $lookup_url (
        $ENV{FETCHWARE_FTP_LOOKUP_URL},
        $ENV{FETCHWARE_HTTP_LOOKUP_URL}
    ) {
        # Clear %FW, so I can call lookup_url again.
        clear_FW();
        # Set download type.
        # Make this a FETCHWARE_FTP_REMOTE env var in frt().
        lookup_url $lookup_url;

        # Do needed operations before I can test download_directory_listing().
        check_lookup_config();

        # Test download_directory_listing().
        $lookup_url =~ m!^(ftp|http)(:?://.*)?!;
        my $scheme = $1;
        ok(download_directory_listing(), "checked download_directory_listing() $scheme success");
    }
};


subtest 'test ftp_parse_filelist()' => sub {
    skip_all_unless_release_testing();

    # Clear %FW, so I can call lookup_url again.
    clear_FW();
    # Set download type.
    # Make this a FETCHWARE_FTP_REMOTE env var in frt().
    lookup_url $ENV{FETCHWARE_FTP_LOOKUP_URL};

    my $directory_listing = download_directory_listing();
    
    my $filename_listing = ftp_parse_filelist($directory_listing);

    is_deeply($filename_listing, test_filename_listing(),
        'checked ftp_parse_listing() success');
    pass('fixin it');

};


subtest 'test http_parse_filelist()' => sub {
    skip_all_unless_release_testing();

    my $expected_filename_listing = [
        [ 'httpd-2.0.64.tar.bz2', '201010180432' ],
        [ 'httpd-2.0.64.tar.gz', '201010180432' ],
        [ 'httpd-2.2.21.tar.bz2', '201109121302' ],
        [ 'httpd-2.2.21.tar.gz', '201109121302' ],
        [ 'httpd-2.3.15-beta-deps.tar.bz2', '201111131437' ],
        [ 'httpd-2.3.15-beta-deps.tar.gz', '201111131437' ],
        [ 'httpd-2.3.15-beta.tar.bz2', '201111131437' ],
        [ 'httpd-2.3.15-beta.tar.gz', '201111131437' ]
    ];

    my $filename_listing = http_parse_filelist(return_html_listing());

    is_deeply($filename_listing, $expected_filename_listing,
        'checked http_parse_listing() success');

};


subtest 'test parse_directory_listing()' => sub {
    skip_all_unless_release_testing();

    # Clear App::Fetchware's %FW variable.
    clear_FW();

    ###BUGALERT### Add loop after http_parse_listing() is finished to test this
    #sub's http functionality too.
    lookup_url $ENV{FETCHWARE_FTP_LOOKUP_URL};

    # Do the stuff parse_directory_listing() depends on.
    check_lookup_config();
    my $directory_listing = download_directory_listing();

    ###BUGALERT### NOTE THIS TEST IS BRITLE, BUT IT WILL ONLY BE RUN WHEN I
    #RELEASE A NEW VERSION OF FETCHWARE. FIX WITH SUB::OVERRIDE??
    is_deeply(parse_directory_listing($directory_listing), test_filename_listing(),
        'checked parse_directory_listing() ftp success.');

};




subtest 'test lookup_determine_downloadurl()' => sub {
    skip_all_unless_release_testing();

    # Clear App::Fetchware's %FW variable.
    clear_FW();
    
    ###BUGALERT### NOTE THIS TEST IS BRITLE, AND DEPENDS ON YOU SELECTING AN
    #APACHE LOOKUP_URL. THIS ISN'T THAT BIG A DEAL, BECAUSE THIS TEST WILL ONLY
    #BE RUN FOR FETCHWARE RELEASE TESTING.
    lookup_url $ENV{FETCHWARE_FTP_LOOKUP_URL};

    # Select one of the different apache versions 'httpd-2.{0,2,3}'.
    filter 'httpd-2.2';

    # Test lookup_determine_downloadurl() with 'CURRENT_IS_VER_NO' in the
    # file listing.
    my $current_file_list =
    [
        [ 'CURRENT-IS-2.2.21', '999910051831' ],
        [ 'httpd-2.2.21-win32-src.zip', '999909121702' ],
        [ 'httpd-2.2.21-win32-src.zip.asc', '999909121702' ],
        [ 'httpd-2.2.21.tar.bz2', '999909121702' ],
        [ 'httpd-2.2.21.tar.bz2.asc', '999909121702' ],
        [ 'httpd-2.2.21.tar.gz', '999909121702' ],
        [ 'httpd-2.2.21.tar.gz.asc', '999909121702' ],
    ];
    is(lookup_determine_downloadurl($current_file_list),
        'ftp://carroll.cac.psu.edu/pub/apache/httpd/httpd-2.2.21.tar.bz2',
        'checked lookup_determine_downloadurl() success.');

###BUGALERT### Make test_filename_listing() usable again supporting both ftp and
    #http, or make separate sub for each or something.
        my $no_current_file_list;
        @$no_current_file_list =
            grep { $_->[0] !~ /^(:?latest|current)[_-]is(.*)$/i } @$current_file_list;

    is(lookup_determine_downloadurl($no_current_file_list),
        'ftp://carroll.cac.psu.edu/pub/apache/httpd/httpd-2.2.21.tar.bz2',
        'checked lookup_determine_downloadurl() success.');

    # The weird argument below needs to be a array of arrays.
    eval_ok(sub {lookup_determine_downloadurl([ ['doesntend.right', 'fake timestamp'] ])},
        <<EOS, 'checked lookup_determine_downloadurl() failure');
App-Fetchware: run-time error. Fetchware failed to determine what URL it should
use to download your software. This URL is based on the lookup_url you
specified. See perldoc App::Fetchware.
EOS

};


subtest 'test lookup_by_timestamp()' => sub {
    skip_all_unless_release_testing();

    is(lookup_by_timestamp(test_filename_listing('no current')),
        'ftp://carroll.cac.psu.edu/pub/apache/httpd/httpd-2.2.21.tar.bz2',
        'check lookup_by_timestamp() success.');

};


subtest 'test lookup_by_versionstring()' => sub {
    skip_all_unless_release_testing();

    is(lookup_by_versionstring(test_filename_listing('no current')),
        'ftp://carroll.cac.psu.edu/pub/apache/httpd/httpd-2.2.21.tar.bz2',
        'check lookup_by_versionstring() success.');

}; 

subtest 'test determine_download_url()' => sub {
    ###BUGALERT### Double-check which subtests actually need to be skipped.
    skip_all_unless_release_testing();

    # Clear App::Fetchware's %FW variable.
    clear_FW();

    # This must be set for lookup() to work on Apache's mirror format.
    filter 'httpd-2.2';

    # Set needed config variables.
    lookup_url $ENV{FETCHWARE_FTP_LOOKUP_URL};

    check_lookup_config();
    my $directory_listing = download_directory_listing();
    my $filename_listing = parse_directory_listing($directory_listing);
    
    is(determine_download_url($filename_listing),
        'ftp://carroll.cac.psu.edu/pub/apache/httpd/httpd-2.2.21.tar.bz2',
        'checked lookup_determine_downloadurl() success.');
    
    # Clear App::Fetchware's %FW variable so I can test it with custom
    # lookup_methods.
    clear_FW();

    # This must be set for lookup() to work on Apache's mirror format.
    filter 'httpd-2.2';

    # Set needed config variables.
    lookup_url $ENV{FETCHWARE_FTP_LOOKUP_URL};

    lookup_method 'versionstring';

    check_lookup_config();
    $directory_listing = download_directory_listing();
    $filename_listing = parse_directory_listing($directory_listing);
    
    is(determine_download_url($filename_listing),
        'ftp://carroll.cac.psu.edu/pub/apache/httpd/httpd-2.2.21.tar.bz2',
        'checked lookup_determine_downloadurl() success.');

};


subtest 'test lookup()' => sub {
    ###BUGALERT### Double-check which subtests actually need to be skipped.
    skip_all_unless_release_testing();

    # Clear App::Fetchware's %FW variable.
    clear_FW();

    # This must be set for lookup() to work on Apache's mirror format.
    filter 'httpd-2.2';

    # Set needed config variables.
    lookup_url $ENV{FETCHWARE_FTP_LOOKUP_URL};

    is(lookup(),
        'ftp://carroll.cac.psu.edu/pub/apache/httpd/httpd-2.2.21.tar.bz2',
        'checked lookup_determine_downloadurl() success.');

};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();


# Testing subroutine only used in this test file.
###BUGALERT### Not as useful anymore refactor.
###BUGALERT### This is crap code rewrite now!!!!!!!!!!!!!!!!!!!!!!!!!!!!
sub test_filename_listing {
    my $no_current = shift;

    my $filename_listing = 
    [
        [ 'Announcement2.0.html', '201010190000' ],
        [ 'Announcement2.0.txt', '201010190000' ],
        [ 'Announcement2.2.html', '999909140621' ],
        [ 'Announcement2.2.txt', '999909140621' ],
        [ 'Announcement2.3.txt', '999912191335' ],
        [ 'CHANGES_2.0', '201010180000' ],
        [ 'CHANGES_2.0.64', '201010180000' ],
        [ 'CHANGES_2.2', '999909121702' ],
        [ 'CHANGES_2.2.21', '999909121702' ],
        [ 'CHANGES_2.3', '999912191335' ],
        [ 'CHANGES_2.3.16', '999912191335' ],
        [ 'CURRENT-IS-2.2.21', '999910051831' ],
        [ 'HEADER.html', '200910030000' ],
        [ 'KEYS', '999908310511' ],
        [ 'README.html', '200910030000' ],
        [ 'binaries', '201105110000' ],
        [ 'docs', '201012110000' ],
        [ 'flood', '200912080000' ],
        [ 'httpd-2.0.64-win32-src.zip', '201010180000' ],
        [ 'httpd-2.0.64-win32-src.zip.asc', '201010180000' ],
        [ 'httpd-2.0.64.tar.bz2', '201010180000' ],
        [ 'httpd-2.0.64.tar.bz2.asc', '201010180000' ],
        [ 'httpd-2.0.64.tar.gz', '201010180000' ],
        [ 'httpd-2.0.64.tar.gz.asc', '201010180000' ],
        [ 'httpd-2.2.21-win32-src.zip', '999909121702' ],
        [ 'httpd-2.2.21-win32-src.zip.asc', '999909121702' ],
        [ 'httpd-2.2.21.tar.bz2', '999909121702' ],
        [ 'httpd-2.2.21.tar.bz2.asc', '999909121702' ],
        [ 'httpd-2.2.21.tar.gz', '999909121702' ],
        [ 'httpd-2.2.21.tar.gz.asc', '999909121702' ],
        [ 'httpd-2.3.16-beta-deps.tar.bz2', '999912191335' ],
        [ 'httpd-2.3.16-beta-deps.tar.bz2.asc', '999912191335' ],
        [ 'httpd-2.3.16-beta-deps.tar.gz', '999912191335' ],
        [ 'httpd-2.3.16-beta-deps.tar.gz.asc', '999912191335' ],
        [ 'httpd-2.3.16-beta.tar.bz2', '999912191335' ],
        [ 'httpd-2.3.16-beta.tar.bz2.asc', '999912191335' ],
        [ 'httpd-2.3.16-beta.tar.gz', '999912191335' ],
        [ 'httpd-2.3.16-beta.tar.gz.asc', '999912191335' ],
        [ 'libapreq', '201104270000' ],
        [ 'mod_fcgid', '201011230000' ],
        [ 'mod_ftp', '200912080000' ],
        [ 'patches', '999910051427' ]
    ];

    if (not $no_current) {
        return $filename_listing;
    } elsif ($no_current) {
        my $no_current_listing;
        @$no_current_listing = grep { $_->[0] !~ /^(:?latest|current)[_-]is(.*)$/i } @$filename_listing;
        return $no_current_listing;
    }
}

sub return_html_listing {
    my $html_listing = <<EOH;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">
<html>
 <head>
  <title>Index of /pub/software/apache//httpd</title>
 </head>
 <body>
<h1>Index of /dist/httpd</h1>

<h2>Apache HTTP Server <u>Source Code</u> Distributions</h2>

<p>This download page includes <strong>only the sources</strong> to compile 
   and build Apache yourself with the proper tools.  Download 
   the precompiled distribution for your platform from 
   <a href="binaries/">binaries/</a>.</p>

<h2>Important Notices</h2>

<ul>
<li><a href="#mirrors">Download from your nearest mirror site!</a></li>
<li><a href="#binaries">Binary Releases</a></li>

<li><a href="#releases">Current Releases</a></li>
<li><a href="#archive">Older Releases</a></li>
<li><a href="#sig">PGP Signatures</a></li>
<li><a href="#patches">Official Patches</a></li>
</ul>

<pre><img src="/icons/blank.gif" alt="Icon "> <a href="?C=N;O=D">Name</a>                               <a href="?C=M;O=A">Last modified</a>      <a href="?C=S;O=A">Size</a>  <a href="?C=D;O=A">Description</a><hr><img src="/icons/back.gif" alt="[DIR]"> <a href="/pub/software/apache//">Parent Directory</a>                                        -   HTTP Server project

<img src="/icons/folder.gif" alt="[DIR]"> <a href="binaries/">binaries/</a>                          11-May-2011 02:54    -   Binary distributions
<img src="/icons/folder.gif" alt="[DIR]"> <a href="docs/">docs/</a>                              11-Dec-2010 17:57    -   Extra documentation packages
<img src="/icons/folder.gif" alt="[DIR]"> <a href="flood/">flood/</a>                             07-Dec-2009 21:29    -   HTTP Server project
<img src="/icons/folder.gif" alt="[DIR]"> <a href="libapreq/">libapreq/</a>                          27-Apr-2011 08:35    -   HTTP Server project
<img src="/icons/folder.gif" alt="[DIR]"> <a href="mod_fcgid/">mod_fcgid/</a>                         22-Nov-2010 21:09    -   HTTP Server project

<img src="/icons/folder.gif" alt="[DIR]"> <a href="mod_ftp/">mod_ftp/</a>                           07-Dec-2009 21:29    -   HTTP Server project
<img src="/icons/folder.gif" alt="[DIR]"> <a href="patches/">patches/</a>                           05-Oct-2011 10:27    -   Official patches
<img src="/icons/text.gif" alt="[TXT]"> <a href="Announcement2.0.html">Announcement2.0.html</a>               19-Oct-2010 00:50  5.5K  Apache 2.0 Release Note
<img src="/icons/text.gif" alt="[TXT]"> <a href="Announcement2.0.txt">Announcement2.0.txt</a>                19-Oct-2010 00:50  4.2K  Apache 2.0 Release Note
<img src="/icons/text.gif" alt="[TXT]"> <a href="Announcement2.2.html">Announcement2.2.html</a>               14-Sep-2011 02:21  3.8K  Apache 2.2 Release Note

<img src="/icons/text.gif" alt="[TXT]"> <a href="Announcement2.2.txt">Announcement2.2.txt</a>                14-Sep-2011 02:21  2.7K  Apache 2.2 Release Note
<img src="/icons/text.gif" alt="[TXT]"> <a href="Announcement2.3.txt">Announcement2.3.txt</a>                13-Nov-2011 14:39  1.4K  HTTP Server project
<img src="/icons/text.gif" alt="[TXT]"> <a href="CHANGES_2.0">CHANGES_2.0</a>                        18-Oct-2010 04:32  316K  List of changes in 2.0
<img src="/icons/text.gif" alt="[TXT]"> <a href="CHANGES_2.0.64">CHANGES_2.0.64</a>                     18-Oct-2010 04:32  3.2K  List of changes in 2.0
<img src="/icons/unknown.gif" alt="[   ]"> <a href="CHANGES_2.2">CHANGES_2.2</a>                        12-Sep-2011 13:02  116K  List of changes in 2.2

<img src="/icons/unknown.gif" alt="[   ]"> <a href="CHANGES_2.2.21">CHANGES_2.2.21</a>                     12-Sep-2011 13:02  1.4K  List of changes in 2.2
<img src="/icons/unknown.gif" alt="[   ]"> <a href="CHANGES_2.3">CHANGES_2.3</a>                        13-Nov-2011 14:37   98K  HTTP Server project
<img src="/icons/unknown.gif" alt="[   ]"> <a href="CHANGES_2.3.15">CHANGES_2.3.15</a>                     13-Nov-2011 14:37   11K  HTTP Server project
<img src="/icons/unknown.gif" alt="[   ]"> <a href="CURRENT-IS-2.2.21">CURRENT-IS-2.2.21</a>                  05-Oct-2011 14:31    0   HTTP Server project
<img src="/icons/quill.gif" alt="[SIG]"> <a href="KEYS">KEYS</a>                               31-Aug-2011 01:11  364K  Developer PGP/GPG keys

<img src="/icons/compressed.gif" alt="[ZIP]"> <a href="httpd-2.0.64-win32-src.zip">httpd-2.0.64-win32-src.zip</a>         18-Oct-2010 04:32   11M  HTTP Server project
<img src="/icons/quill.gif" alt="[SIG]"> <a href="httpd-2.0.64-win32-src.zip.asc">httpd-2.0.64-win32-src.zip.asc</a>     18-Oct-2010 04:32  850   PGP signature
<img src="/icons/compressed.gif" alt="[TGZ]"> <a href="httpd-2.0.64.tar.bz2">httpd-2.0.64.tar.bz2</a>               18-Oct-2010 04:32  4.7M  HTTP Server project
<img src="/icons/quill.gif" alt="[SIG]"> <a href="httpd-2.0.64.tar.bz2.asc">httpd-2.0.64.tar.bz2.asc</a>           18-Oct-2010 04:32  833   PGP signature
<img src="/icons/compressed.gif" alt="[TGZ]"> <a href="httpd-2.0.64.tar.gz">httpd-2.0.64.tar.gz</a>                18-Oct-2010 04:32  6.1M  HTTP Server project

<img src="/icons/quill.gif" alt="[SIG]"> <a href="httpd-2.0.64.tar.gz.asc">httpd-2.0.64.tar.gz.asc</a>            18-Oct-2010 04:32  833   PGP signature
<img src="/icons/compressed.gif" alt="[ZIP]"> <a href="httpd-2.2.21-win32-src.zip">httpd-2.2.21-win32-src.zip</a>         12-Sep-2011 13:02  9.8M  HTTP Server project
<img src="/icons/quill.gif" alt="[SIG]"> <a href="httpd-2.2.21-win32-src.zip.asc">httpd-2.2.21-win32-src.zip.asc</a>     12-Sep-2011 13:02  835   PGP signature
<img src="/icons/compressed.gif" alt="[TGZ]"> <a href="httpd-2.2.21.tar.bz2">httpd-2.2.21.tar.bz2</a>               12-Sep-2011 13:02  5.1M  HTTP Server project
<img src="/icons/quill.gif" alt="[SIG]"> <a href="httpd-2.2.21.tar.bz2.asc">httpd-2.2.21.tar.bz2.asc</a>           12-Sep-2011 13:02  835   PGP signature

<img src="/icons/compressed.gif" alt="[TGZ]"> <a href="httpd-2.2.21.tar.gz">httpd-2.2.21.tar.gz</a>                12-Sep-2011 13:02  6.8M  HTTP Server project
<img src="/icons/quill.gif" alt="[SIG]"> <a href="httpd-2.2.21.tar.gz.asc">httpd-2.2.21.tar.gz.asc</a>            12-Sep-2011 13:02  835   PGP signature
<img src="/icons/compressed.gif" alt="[TGZ]"> <a href="httpd-2.3.15-beta-deps.tar.bz2">httpd-2.3.15-beta-deps.tar.bz2</a>     13-Nov-2011 14:37  1.3M  HTTP Server project
<img src="/icons/quill.gif" alt="[SIG]"> <a href="httpd-2.3.15-beta-deps.tar.bz2.asc">httpd-2.3.15-beta-deps.tar.bz2.asc</a> 13-Nov-2011 14:37  825   PGP signature
<img src="/icons/compressed.gif" alt="[TGZ]"> <a href="httpd-2.3.15-beta-deps.tar.gz">httpd-2.3.15-beta-deps.tar.gz</a>      13-Nov-2011 14:37  1.6M  HTTP Server project

<img src="/icons/quill.gif" alt="[SIG]"> <a href="httpd-2.3.15-beta-deps.tar.gz.asc">httpd-2.3.15-beta-deps.tar.gz.asc</a>  13-Nov-2011 14:37  825   PGP signature
<img src="/icons/compressed.gif" alt="[TGZ]"> <a href="httpd-2.3.15-beta.tar.bz2">httpd-2.3.15-beta.tar.bz2</a>          13-Nov-2011 14:37  3.9M  HTTP Server project
<img src="/icons/quill.gif" alt="[SIG]"> <a href="httpd-2.3.15-beta.tar.bz2.asc">httpd-2.3.15-beta.tar.bz2.asc</a>      13-Nov-2011 14:37  825   PGP signature
<img src="/icons/compressed.gif" alt="[TGZ]"> <a href="httpd-2.3.15-beta.tar.gz">httpd-2.3.15-beta.tar.gz</a>           13-Nov-2011 14:37  5.3M  HTTP Server project
<img src="/icons/quill.gif" alt="[SIG]"> <a href="httpd-2.3.15-beta.tar.gz.asc">httpd-2.3.15-beta.tar.gz.asc</a>       13-Nov-2011 14:37  825   PGP signature

<hr></pre>
<h2><a name="mirrors">Download from your
    <a href="http://www.apache.org/dyn/closer.cgi/httpd/"
      >nearest mirror site!</a></a></h2>

<p>Do not download from www.apache.org.  Please use a mirror site
   to help us save apache.org bandwidth.
   <a href="http://www.apache.org/dyn/closer.cgi/httpd/">Go 
   here to find your nearest mirror.</a></p>

<h2><a name="binaries">Binary Releases</a></h2>

<p>Are available in the <a href="binaries/">binaries/</a> directory.
   Every binary distribution contains an install script. See README 
   for details.</p>

<h2><a name="releases">Current Releases</a></h2>

<p>For details on current releases, please see the 
   <a href="http://httpd.apache.org/download.cgi">Apache HTTP
   Server Download Page</a>.</p>

<p>Note; the -win32-src.zip versions of Apache are nearly identical to the
   .tar.gz versions.  However, they offer the source files in DOS/Windows 
   CR/LF text format, and include the Win32 build files.  
   These -win32-src.zip files <strong>do NOT contain binaries!</strong>
   See the <a href="binaries/win32/">binaries/win32/</a> 
   directory for the Windows binary distributions.</p>

<h2><a name="archive">Older Releases</a></h2>

<p>Only current, recommended releases are available on www.apache.org
   and the mirror sites.  Older releases can be obtained from the <a
   href="http://archive.apache.org/dist/httpd/">archive site</a>.</p>

<h2><a name="sig">PGP Signatures</a></h2>

<p>All of the release distribution packages have been digitally signed
   (using PGP or GPG) by the Apache Group members that constructed them.
   There will be an accompanying <SAMP><EM>distribution</EM>.asc</SAMP> file
   in the same directory as the distribution.  The PGP keys can be found
   at the MIT key repository and within this project's
   <a href="http://www.apache.org/dist/httpd/KEYS">KEYS file</a>.</p>

<p>Always use the signature files to verify the authenticity
   of the distribution, <i>e.g.</i>,</p>

<pre>
% pgpk -a KEYS
% pgpv httpd-2.2.8.tar.gz.asc
<i>or</i>,
% pgp -ka KEYS
% pgp httpd-2.2.8.tar.gz.asc
<i>or</i>,
% gpg --import KEYS
% gpg --verify httpd-2.2.8.tar.gz.asc
</pre>

<p>We offer MD5 hashes as an alternative to validate the integrity
   of the downloaded files. A unix program called <code>md5</code> or
   <code>md5sum</code> is included in many unix distributions.  It is
   also available as part of <a
   href="http://www.gnu.org/software/textutils/textutils.html">GNU
   Textutils</a>.  Windows users can get binary md5 programs from <a
   href="http://www.fourmilab.ch/md5/">here</a>, <a
   href="http://www.pc-tools.net/win32/freeware/console/">here</a>, or
   <a href="http://www.slavasoft.com/fsum/">here</a>.</p>

<h2><a name="patches">Official Patches</a></h2>

<p>When we have patches to a minor bug or two, or features which we
   haven't yet included in a new release, we will put them in the
   <A HREF="patches/">patches</A>
   subdirectory so people can get access to it before we roll another
   complete release.</p>
</body></html>
EOH
    return $html_listing;
}
