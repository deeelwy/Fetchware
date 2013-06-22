#!perl
# App-FetchwareX-HTMLPageSync.t tests App::FetchwareX::HTMLPageSync.
# Pretend to be bin/fetchware, so that I can test App::Fetchware as though
# bin/fetchware was calling it.
# This is needed in HTMLPageSync, because HTMLPageSync uses start() and end()
# from App::Fetchware, and these subs have different behavior depending on what
# package they are called in. In package fetchware they behave as they will be
# called by bin/fetchware when HTMLPageSync is used in a Fetchwarefile. In other
# packages they have the behavior of configuration subroutines that allow you to
# specify a coderef to override their behavior. Therefore, I need to pretend to
# be bin/fetchware to get the behavior I want.
package fetchware;
use strict;
use warnings;
use diagnostics;
use 5.010001;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '12'; #Update if this changes.
use App::Fetchware '!:DEFAULT';
use Test::Fetchware ':TESTING';
use App::Fetchware::Config ':CONFIG';
use Test::Deep;
use Path::Class;
use File::Spec::Functions 'updir';
use File::Temp 'tempdir';
use Cwd 'cwd';

# Turn on printing of vmsg()s.
verbose_on();

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
# There is no ':OVERRIDE_START' to bother importing.
BEGIN { use_ok('App::FetchwareX::HTMLPageSync', ':DEFAULT'); }

# Print the subroutines that App::FetchwareX::HTMLPageSync imported by default
# when I used it.
note("App::Fetchware's default imports [@App::FetchwareX::HTMLPageSync::EXPORT]");


subtest 'test uninstall() exception' => sub {
    # Delete the destination_directory configuration option to test for the
    # exception of it not existing.
    config_delete('destination_directory');

    eval_ok(sub {uninstall(cwd())},
        <<EOE, 'checked uninstall() destination_directory exception');
App-FetchwareX-HTMLPageSync: Failed to uninstall the specified App::FetchwareX::HTMLPageSync
package, because no destination_directory is specified in its Fetchwarefile.
This configuration option is required and must be specified.
EOE
};

###BUGALERT### Add extension support to make_test_dist(), so that HTMLPageSync
#and any other extensions can use that same mechanism to proved runnable tests
#without FETCHWARE_RELEASE_TESTING set, so HTMLPageSync can actually be tested
#on user's computers.


my $temp_dir; # So uninstall()'s test can access it.
subtest 'test HTMLPageSync start()' => sub {
    skip_all_unless_release_testing();

    $temp_dir = start();

    ok(-e $temp_dir, 'check start() success');
};


my $dest_dir;
subtest 'test HTMLPageSync lookup()' => sub {
    skip_all_unless_release_testing();

    # Test the page that is the only reason I wrote this!
    html_page_url $ENV{FETCHWARE_HTTP_LOOKUP_URL};

    $dest_dir = tempdir("fetchware-$$-XXXXXXXXXX", TMPDIR => 1, CLEANUP => 1);
    ok(-e $temp_dir,
        'checked lookup() temporary destination directory creation');

    destination_directory "$dest_dir";
    user_agent
        'Mozilla/5.0 (X11; Linux x86_64; rv:15.0) Gecko/20100101 Firefox/15.0.1';

    my $wallpaper_urls = lookup();

    cmp_deeply(
        $wallpaper_urls,
        eval(expected_filename_listing()),
        'checked lookup()s return value for acceptable values.'
    );

    # Test for extracting out links.
    html_treebuilder_callback sub {
    my $h = shift;

    #parse out archive name.
    my $link = $h->as_text();
        if ($link =~ /\.(tar\.(gz|bz2|xz)|(tgz|tbz2|txz))$/) {
            # If its an archive return true indicating we should keep this
            # HTML::Element.
            return 'True';
        } else {
            return undef; # return false indicating do not keep this one.
        }
    };

    my $html_urls = lookup();

    cmp_deeply(
        $html_urls,
        array_each(
            re(qr/\.(tar\.(gz|bz2|xz)|(tgz|tbz2|txz))$/)
        ),
        'checked lookup()s return value for acceptable values again.'
    );

    download_links_callback sub {
        my @download_urls = @_;

        my @filtered_urls;
        for my $link (@download_urls) {
            # Strip off HTML::Element crap.
            $link = $link->attr('href');
            # Keep links that are absolute.
            # And make change relative links to absolute.
            if ($link !~ m!^(ftp|http|file)://!) {
                push @filtered_urls, config('html_page_url') . '/' . $link;
            }
        }

        # Return the filtered urls not the provided unfiltered @download_urls.
        return @filtered_urls;
    };

    my $abs_urls = lookup();

    cmp_deeply(
        $abs_urls,
        array_each(
            re(qr!^(ftp|http|file)://!)
        ),
        'checked lookup()s return value for acceptable values yet again.'
    );
};

# Created here so it can be shared with unarchive()'s subtest.
my $download_file_paths;
subtest 'test HTMLPageSync download()' => sub {
    skip_all_unless_release_testing();


    # FETCHWARE_HTTP_DOWNLOAD_URL is manually updated will break whenever a new
    # version of Apache 2.2 comes out.
    # download() wants an array ref.
    $download_file_paths = download($temp_dir,
        [ $ENV{FETCHWARE_HTTP_DOWNLOAD_URL} ]);
    note("DFP");
    note explain $download_file_paths;

    ok(@$download_file_paths == 1,
        'checked download() correct number of files');

    is($download_file_paths->[0],
        file($ENV{FETCHWARE_HTTP_DOWNLOAD_URL})->basename(),
        'checked download() success.');

    ok(-e $download_file_paths->[0],
        'checked download()ed file existence');
};


subtest 'test HTMLPageSync verify()' => sub {
    is(verify('dummy', 'args'), undef, 'checked verify() success.');
};


subtest 'test HTMLPageSync unarchive()' => sub {
    skip_all_unless_release_testing();

    ok(unarchive($download_file_paths),
        'checked unarchive() success');

    # unarchive() needs an array reference.
    eval_ok(sub { unarchive([ "file-that-doesn-t-exist-$$" ])},
        qr/App-FetchwareX-HTMLPageSync: run-time error. Fetchware failed to copy the file \[/,
        'checked unarchive exception');
};


subtest 'test HTMLPageSync build()' => sub {
    is(verify('dummy arg'), undef, 'checked build() success.');
};


subtest 'test HTMLPageSync install()' => sub {
    is(install(), undef, 'checked install() success.');
};


subtest 'test HTMLPageSync uninstall()' => sub {
    skip_all_unless_release_testing();

    # Will delete destination_directory, but the destination_directory is a
    # tempdir(), so it will be delete anyway.
    # Just ignore the warning File::Temp prints, because I deleted its tempdir()
    # instead of it doing it itself.
    ok(uninstall(cwd()),
        'checked uninstall() success');
    ok(! -e $dest_dir,
        'checked uninstall() tempdir removal');


    # Test uninstall()s exceptions.
    eval_ok(sub {uninstall("$$-@{[int(rand(383889))]}")},
        qr/App-FetchwareX-HTMLPageSync: Failed to uninstall the specified package and specifically/,
        'checked uninstall() $build_path exception');
};


subtest 'test uninstall() keep_destination_directory' => sub {
    skip_all_unless_release_testing();

    # Create another tempdir, because the previous uninstall() deleted it.
    my $tempdir = tempdir("fetchware-$$-XXXXXXXXXX", TMPDIR => 1, CLEANUP => 1);
    ok(-e $tempdir,
        'checked lookup() temporary destination directory creation');
    # Use new destination_directory.
    config_replace(destination_directory => $tempdir);

    # Install HTMLPageSync again to test keep_destination_directory.
    my $wallpaper_urls = lookup();
note explain $wallpaper_urls;
debug_CONFIG();
    cmp_deeply(
        $wallpaper_urls,
        array_each(any(
            re(qr/Announcement2.\d.(html|txt)/),
            re(qr/CHANGES_2\.\d(\.\d+)?/),
            re(qr/CURRENT(-|_)IS(-|_)\d\.\d+?\.\d+/),
            re(qr/
                HEADER.html
                |
                KEYS
                |
                README.html
                |
                binaries
                |
                docs
                |
                flood
            /x),
            re(qr/httpd-2\.\d\.\d+?-win32-src\.zip(\.asc)?/),
            re(qr/httpd-2\.\d\.\d+?\.tar\.(bz2|gz)(\.asc)?/),
            re(qr/httpd-2\.\d\.\d+?-deps\.tar\.(bz2|gz)(\.asc)?/),
            re(qr/
                libapreq
                |
                mod_fcgid
                |
                mod_ftp
                |
                patches
            /x),
            re(qr/\d{12}/)
            ) # end any
        ),
        'checked lookup()s return value for acceptable values.'
    );

    $download_file_paths = download($tempdir, $wallpaper_urls);
    # Transform the gotten url basenames with the expected url basenames to
    # determine if everything was downloaded properly.
note "HERE";
note explain $download_file_paths;
    my $download_file_path_basenames
        =
        map {$_ = file($_)->basename()} @$download_file_paths;
note explain $download_file_path_basenames;
    my $wallpaper_url_basenames
        =
        map {$_ = file($_)->basename()} @$wallpaper_urls;
    cmp_deeply(
        $download_file_path_basenames,
        $wallpaper_url_basenames,
        'checked download()s return value for acceptable values.'
    );

    ok(unarchive($download_file_paths),
        'checked unarchive() success');

    # Test uninstall's keep_destination_directory option.
    keep_destination_directory 'True';
    ok(uninstall(cwd()),
        'checked uninstall() success');
    # $tempdir should still exist. Don't clean it up, because the uninstall()
    # subtest below will do that for me.
    ok( -e $tempdir,
        'checked uninstall() tempdir removal');

};


###BUGALERT### Create a customizable version of make_test_dist() to create a
#user testable version of this module.


subtest 'test HTMLPageSync end()' => sub {
    skip_all_unless_release_testing();

    end();

    # Use Test::Fetchware's end_ok() to test if end did it's job correctly.
    end_ok($temp_dir);
};



###BUGALERT### Add tests for bin/fetchware's cmd_*() subroutines!!! This
#subclasses test suite is incomplete without tests for those too!!!


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
