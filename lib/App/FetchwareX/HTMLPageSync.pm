package App::FetchwareX::HTMLPageSync;
# ABSTRACT: An App::Fetchware extension that downloads files based on an HTML page.
use strict;
use warnings;

# Enable Perl 6 knockoffs, and use 5.10.1, because smartmatching and other
# things in 5.10 were changed in 5.10.1+.
use 5.010001;

# Use fetchware's API's to help us out.
use App::Fetchware::Util ':UTIL';
use App::Fetchware::Config ':CONFIG';

# Local imports.
use File::Copy 'cp';
use File::Path 'remove_tree';

# Use App::Fetchware::ExportAPI to specify which App::Fetchware API subroutines
# we are going to "KEEP", import from App::Fetchware, and which API subs we are
# going to "OVERRRIDE", implemente here in this package.
#
# ExportAPI takes care of the grunt work for us by setting our packages @EXPORT
# appropriatly, and even importing Exporter's import() method into our package
# for us, so that our App::Fetchware API subroutines and configuration options
# specified below can be import()ed properly.
use App::Fetchware::ExportAPI
    KEEP => [qw(start end)],
    OVERRIDE =>
    [qw(lookup download verify unarchive build install uninstall)]
;


# Use App::Fetchware::CreateconfigOptions to build our App::Fetchware
# configuration options for us. These are subroutines with correct prototypes to
# turn a perl code file into something that resembles a configuration file.
use App::Fetchware::CreateConfigOptions
    ONE => [qw(
        page_name
        html_page_url
        destination_directory
        user_agent
        html_treebuilder_callback
        download_links_callback
    )],
    BOOLEAN => [qw(keep_destination_directory)]
;



=head1 App::FetchwareX::HTMLPageSync API SUBROUTINES

This is App::FetchwareX::HTMLPageSync's API that fetchware uses to execute any
Fetchwarefile's that make use of App::FetchwareX::HTMLPageSync. This API is the
same that regular old App::Fetchware uses for most standard FOSS software, and
this internal documentation is only needed when debugging HTMLPageSync's code or
when studying it to create your own fetchware extension.

=cut


=head2 start()

    my $temp_file = start();

start() creats a temp dir, chmod 700's it, and chdir()'s to it just like the one
in App::Fetchware does. App::FetchwareX::HTMLPageSync

start() is imported from App::Fetchware, and also exported by
App::FetchwareX::HTMLPageSync. This is how App::FetchwareX::HTMLPageSync
"subclasses" App::Fetchware.

=cut


=head2 lookup()

    my $download_url = lookup();

lookup() downloads the user specified C<html_page_url>, parses it using
HTML::TreeBuilder, and uses C<html_treebuilder_callback> and
C<download_http_url> if specified to maniuplate the tree to determine what
download urls the user wants.

This list of download urls is returned as an array reference, $download_url.

=cut

sub lookup {
    msg
    "Looking up download urls using html_page_url [@{[config('html_page_url')]}]";
    ###BUGALERT### Create a user changeable version of lookup_check_args??(), so
    #that App::Fetchware 'subclasses' can use it.
    # Download the url the user specified.
    my $filename = do {
        if (defined config('user_agent')) {
            download_http_url(config('html_page_url'),
                user_agent =>  config('user_agent'));
        } else {
            download_http_url(config('html_page_url'));
        }
    };
    vmsg "Downloaded html_page_url to local file [$filename].";

    # Create a HTML::TreeBuilder object for the now downloaded file.
    my $tree = HTML::TreeBuilder->new();
    # Parse $filename into a HTML::Element tree.
    $tree->parse_file($filename);
    vmsg 'Created HTML::TreeBuilder object to parse downloaded html file.';

    my $tree_callback = do {
        if (config('html_treebuilder_callback')) {
            vmsg <<EOM;
Using user supplied html_treebuilder_callback to parse downloaded HTML file:
[
@{[config('html_treebuilder_callback')]}
]
EOM
            config('html_treebuilder_callback');
        } else {
            vmsg <<EOM;
Using built-in default html_treebuilder_callback that only wants images.
EOM
            sub {
                my $tag = shift;
                my $link = $tag->attr('href');
                if (defined $link) {
                    # If the anchor tag is an image...
                    if ($link =~ /\.(jpg|jpeg|png|bmp|tiff?|gif)$/) {
                        # ...return true...
                        return 'True';
                    } else {
                        # ...if not return false.
                        return undef; #false
                    }
                }
            };
        }
    };

    # Find the links that match our default callback or the user specified one
    # if the user specified one.
    my @download_urls = $tree->look_down(
        _tag => 'a',
        $tree_callback
    );
    vmsg <<EOM;
Determined download urls to be:
@download_urls
EOM

    # Sort through the list of HTML::Element tags to finalize the list to
    # download.
    my $links_callback = do {
        if (config('download_links_callback')) {
            vmsg <<EOM;
Determined download_links_callback to be user specified:
[
@{[config('download_links_callback')]}
]
EOM
            config('download_links_callback');
        } else {
            # Strip off HTML::Element crap by default.
            sub {
                vmsg <<EOM;
Using built-in default download_links_callback that turns HTML::Elements into
download urls.
EOM
                my @download_urls = @_;

                for my $link (@download_urls) {
                    $link = $link->attr('href');
                }

                # Must return them, because this coderef was called by value not
                # by reference.
                return @download_urls;
            };
        }
    };

    # Call download_links_callback or call default one to strip off
    # HTML::Element crap.
    @download_urls = $links_callback->(@download_urls);
    vmsg <<EOM;
Determined download urls to be:
[
@{[@download_urls]}
]
EOM

    # The download_urls may be relative links instead of absolute links.
    # Relative ones could just be filenames without any knowledge of what the
    # actual server or path or even scheme is. Fix this by prepending
    # html_page_url to each link if there is no scheme.
    for my $download_url (@download_urls) {
        if ($download_url !~ m!^(ftp|http|file)://!) {
            $download_url = config('html_page_url') . '/' . $download_url;
        }
    }

    # Return a ref to the array of download urls, because lookup()'s API only
    # allows it to return a single value, but that single value does not have to
    # a scalar. It can be a array ref, which is used here. This works, because
    # what is returned here by lookup() is passed unchanged to download(), which
    # is also part of this API, so I can use what I return here as I please
    # inside download().
    return \@download_urls;
}


=head2 download()

    download($temp_dir, $download_url);

download() uses App::Fetchware's utility function download_http_url() to
download all of the urls that lookup() returned. If the user specifed a
C<user_agent> configuration option, then that option is passed along to
download_http_url()'s call to HTTP::Tiny.

=cut

sub download {
    my ($temp_dir, $download_url) = @_;

    msg 'Downloading the download urls lookup() determined.';

    my @download_file_paths;
    # Loop over @$download_url to download all user specified URLs to temp_dir.
    for my $url (@$download_url) {
        # Use user specified agent if they asked for it.
        if (defined config('user_agent')) {
            vmsg <<EOM;
Downloadig url
[$url]
using the user specified user_agent
[@{[config('user_agent')]}]
EOM
            my $downloaded_file =
                download_http_url($url, agent => config('user_agent'));
            push @download_file_paths, $downloaded_file;
        } else {
            vmsg "Downloading url [$url].";
            my $downloaded_file = download_http_url($url);
            push @download_file_paths, $downloaded_file;
        }
    }

    local $" = "\n"; # print each @download_file_paths on its own line.
    vmsg <<EOM;
Downloaded specified urls to the following paths:
[
@{[@download_file_paths]}
]
EOM

    # AKA $package_path.
    return \@download_file_paths;
}


=head2 verify()

    verify($download_url, $package_path);

verify() simply calls App::Fetchware's :UTIL subroutine do_nothing(), which as
you can tell from its name does nothing, but return. The reason for the useless
do_nothing() call is simply for better documentation, and standardizing how to
override a App::Fetchware API subroutine in order for it to do nothing at all,
so that you can prevent the original App::Fetchware subroutine from doing what
it normally does.

=cut

sub verify {
    vmsg <<EOM;
Skipping verify subroutine, because HTMLPageSync does not need to verify anything
EOM
    do_nothing();
}


=head2 unarchive()

    unarchive($package_path);

unarchive() takes the $package_path, which is really an array ref of the paths
of the files that download() copied, and copies them the the user specified
destination directory, C<destination_directory>.

=cut

sub unarchive {
    # AKA $package_path.
    my $download_file_paths = shift;

    msg <<EOM;
Copying files downloaded to a local temp directory to final destination directory.
EOM

    # Copy over the files that have been returned by download().
    for my $file_path (@$download_file_paths) {
        vmsg <<EOM;
Copying [$file_path] -> [@{[config('destination_directory')]}].
EOM
        ###BUGALERT### Should this die and all the rest be croaks instead???
        cp($file_path, config('destination_directory')) or die <<EOD;
App-FetchwareX-HTMLPageSync: run-time error. Fetchware failed to copy the file [$file_path] to the
destination directory [@{[config('destination_directory')]}].
The OS error was [$!].
EOD
    }

    vmsg 'Successfully copied files to destination directory.';

    return 'True indicating success!';
}


=head2 build()

    build($build_path);

build() does the same thing as verify(), and that is nothing by calling
App::Fetchware's do_nothing() subroutine to better document the fact
that it does nothing.

=cut

sub build {
    vmsg <<EOM;
Skipping build subroutine, because HTMLPageSync does not need to build anything
EOM
    do_nothing();
}


=head2 install()

    install();

install() does nothing by calling App::Fetchware's :UTIL subroutine
do_nothing(), which does nothing.

=cut

sub install {
    vmsg <<EOM;
Skipping install subroutine, because HTMLPageSync does not need to install anything
EOM
    do_nothing();
}


=head2 end()

    end();

end() chdir()s back to the original directory, and cleans up the temp directory
just like the one in App::Fetchware does. App::FetchwareX::HTMLPageSync


end() is imported from App::Fetchware, and also exported by
App::FetchwareX::HTMLPageSync. This is how App::FetchwareX::HTMLPageSync
"subclasses" App::Fetchware.

=cut


=head2 uninstall()

    uninstall($build_path);

Uninstalls App::FetchwareX::HTMLPageSync by recursivly deleting the
C<destination_directory> where it stores the wallpapers or whatever you
specified it to download for you.

=over
NOTICE: uninstalling your App::FetchwareX::HTMLPageSync packagw B<will> B<delete>
the contents of that package's associated C<destination_directory>! If you would
like to keep your contents of your C<destination_directory> then either manually
delete the pacakge you want to delete from your fetchware database directory, or
just recursively copy the contents of your C<destination_directory> to a backup
directory somewhere else.

=back

=cut

sub uninstall {
    my $build_path = shift;

    # Only delete destination_directory if keep_destination_directory is false.
    unless (config('keep_destination_directory')) {

        msg <<EOM;
Uninstalling this HTMLPageSync package by deleting your destination directory.
EOM

    ###BUGALERT### Before release go though all of Fetchware's API, and subifiy
    #each main component like lookup and download were, the later ones were not
    #done this way. That way I can put say chdir_to_build_path() here instead of
    #basicaly copying and pasting the code like I do below. Also
    #chdir_to_build_path() can be put in :OVERRIDE_UNINSTALL!!! Which I can use
    #here.
        chdir $build_path or die <<EOD;
App-FetchwareX-HTMLPageSync: Failed to uninstall the specified package and specifically to change
working directory to [$build_path] before running make uninstall or the
uninstall_commands provided in the package's Fetchwarefile. Os error [$!].
EOD

        if ( defined config('destination_directory')) {
            # Use File::Path's remove_tree() to delete the destination_directory
            # thereby "uninstalling" this package. Will throw an exception that I'll
            # let the main eval in bin/fetchware catch, print, and exit 1.
            vmsg <<EOM;
Deleting entire destination directory [@{[config('destination_directory')]}].
EOM
            remove_tree(config('destination_directory'));
        } else {
            die <<EOD;
App-FetchwareX-HTMLPageSync: Failed to uninstall the specified App::FetchwareX::HTMLPageSync
package, because no destination_directory is specified in its Fetchwarefile.
This configuration option is required and must be specified.
EOD
        }
    # keep_destination_directory was set, so don't delete destination directory.
    } else {
        msg <<EOM;
Uninstalling this HTMLPageSync package but keeping your destination directory.
EOM

    }

    return 'True for success.';
}


#use App::Fetchware::ExportAPI
#    KEEP => [qw(start end)],
#    OVERRIDE =>
#    [qw(lookup download verify unarchive build install uninstall)]
#;

1;

__END__


=head1 SYNOPSIS

=head2 Example App::FetchwareX::HTMLPageSync Fetchwarefile.

    page_name 'Cool Wallpapers';

    html_page_url 'http://some-html-page-with-cool.urls';

    destination_directory 'wallpapers';

    # pretend to be firefox
    user_agent 'Mozilla/5.0 (X11; Linux x86_64; rv:15.0) Gecko/20100101 Firefox/15.0.1';

    # Customize the callbacks.
    html_treebuilder_callback sub {
        # Get one HTML::Element.
        my $h = shift;

        # Return true or false to indicate if this HTML::Element shoudd be a
        # download link.
        if (something) {
            return 'True';
        } else {
            return undef;
        }
    };

    download_links_callback sub {
        my @download_urls = @_;

        my @wanted_download_urls;
        for my $link (@download_urls) {
            # Pick ones to keep.
            puse @wanted_download_urls, $link;
        }

        return @wanted_download_urls;
    };

=head2 App::FetchwareX::HTMLPageSync App::Fetchware-like API.

    my $temp_file = start();

    my $download_url = lookup();

    download($temp_dir, $download_url);

    verify($download_url, $package_path);

    unarchive($package_path);

    build($build_path);

    install();

    uninstall($build_path);

=cut


=head1 MOTIVATION

I want to automatically parse a Web page with links to wall papers that I want
to download. Only I want software to do it for me. That's where this
App::Fetchware extension comes in.

=cut


=head1 DESCRIPTION

App::FetchwareX::HTMLPageSync as you can tell from its name is an example
App::Fetchware extension. It's not a large extension, but instead is a simple one
meant to show how easy it is extend App::Fetchware.

App::FetchwareX::HTMLPageSync parses the Web page you specify to create a list of
download links. Then it downloads those links, and installs them to your
C<destination_directory>.

In order to use App::FetchwareX::HTMLPageSync to help you mirror the download
links on a HTML page you need to
L<create a App::FetchwareX::HTMLPageSync Fetchwarefile.|/"CREATING A App::FetchwareX::HTMLPageSync FETCHWAREFILE">
Then you'll need to
L<learn how to use that Fetchwarefile with fetchware.|/"USING YOUR App::FetchwareX::HTMLPageSync FETCHWAREFILE WITH FETCHWARE">

=cut


=head1 CREATING A App::FetchwareX::HTMLPageSync FETCHWAREFILE

In order to use App::FetchwareX::HTMLPageSync you must first create a
Fetchwarefile to use it. In a future release I intend to expand App::Fetchware's
simple API to incude the ability for App::Fetchware extensions to extend
fetchware's simple new command, which will simply ask you a few questions and
create a new Fetchwarefile for you. Till then, you'll have to create one
manually.

=over

=item B<1. Name it>

Use your text editor to create a file with a C<.Fetchwarefile> file extension.
Use of this convention is not required, but it makes it obvious what type of
file it is. Then, just copy and paste the example text below, and replace
C<[page_name]> with what you choose your C<page_name> to be. C<page_name> is
simply a configuration opton that simply names your Fetchwarefile. It is not
actually used for anything other than to name your Fetchwarefile to document
what program or behavior this Fetchwarefile manages.

    use App::FetchwareX::HTMLPageSync;

    # [page_name] - explain what [page_name] does.

    page_name '[page_name]';

Fetchwarefiles are actually small, well structured, Perl programs that can
contain arbitrary perl code to customize fetchware's behavior, or, in most
cases, simply specify a number of fetchware or a fetchware extension's (as in
this case) configuration options. Below is my filled in example
App::FetchwareX::HTMLPageSync fetchwarefile.

    use App::FetchwareX::HTMLPageSync;

    # Cool Wallpapers - Downloads cool wall papers.

    page_name 'Cool Wallpapers';

Notice the C<use App::FetchwareX::HTMLPageSync;> line at the top. That line is
absolutely critical for this Fetchwarefile to work properly, because it is what
allows fetchware to use Perl's own syntax as a nice easy to use syntax for
Fetchwarefiles. If you do not use the matching C<use App::Fetchware...;> line,
then fetchware will spit out crazy errors from Perl's own compiler listing all
of the syntax errors you have. If you ever receive that error, just ensure you
have the correct C<use App::Fetchware...;> line at the top of your
Fetchwarefile.

=item B<2. Determine your html_page_url>

At the heart of App::FetchwareX::HTMLPageSync is its C<html_page_url>, which is
the URL to the HTML page you want HTMLPageSync to download and parse out links
to wallpaper or whatever else you'd like to automate downloading. To figure this
out just use your browser to find the HTML page you want to use, and then copy
and paste the url between the single quotes C<'> as shown in the example below.

    html_page_url '';

And then after you copy the url.

    html_page_url 'http://some.url/something.html';

=item B<3. Determine your destination_directory>

HTMLPageSync also needs to know your C<destination_directory>. This is the
directory that HTMLPageSync will copy your downloaded files to. This directory
will also be deleted when you uninstall this HTMLPageSync fetchware package just
like a standard App::Fetchware package would uninstall any installed software
when it is uninstalled. Just copy and paste the example below, and fill in the
space between the single quotes C<'>.

    destination_directory '';

After pasting it should look like.

    destination_directory '~/wallpapers';

Furthermore, if you want to keep your C<destination_directory> after you
uninstall your HTMLPageSync fetchware package, just set the
C<keep_destination_directory> configuration option to true:

    keep_destination_directory 'True';

If this is set in your HTMLPageSync Fetchwarefile, HTMLPageSync will not delete
your C<destination_directory> when your HTMLPageSync fetchware package is
uninstalled.

=item B<4. Specifiy other options>

That's all there is to it unless you need to further customize HTMLPageSync's
behavior to get just the links you need to download.

At this point you can install your new Fetchwarefile with:

    fetchware install [path to your new fetchwarefile]

Or you can futher customize it as shown next.

=item B<5. Specify an optional user_agent>

Many sites don't like bots downloading stuff from them wasting their bandwidth,
and will even limit what you can do based on your user agent, which is the HTTP
standard's name for your browser. This option allows you to pretend to be
something other than HTMLPageSync's underlying library, L<HTTP::Tiny>. Just copy
and past the example below, and paste what you want you user agent to be between
the single quotes C<'> as before.

    user_agent '';

And after pasting.

    user_agent 'Mozilla/5.0 (X11; Linux x86_64; rv:15.0) Gecko/20100101 Firefox/15.0.1';

=item B<6. Specify an optonal html_treebuilder_callback>

C<html_treebuilder_callback> specifies an optional anonymous Perl subroutine
reference that will replace the default one that HTMLPageSync uses. The default
one limits the download to only image format links, which is flexible enough for
downloading wallpapers.

If you want to download something different, then paste the example below in
your Fetchwarefile.

    html_treebuilder_callback sub {
        # Get one HTML::Element.
        my $h = shift;

        # Return true or false to indicate if this HTML::Element shoudd be a
        # download link.
        if (something) {
            return 'True';
        } else {
            return undef;
        }
    };

And create a Perl anonymous subroutine C<CODEREF> that will
be executed instead of the default one. This requires knowledge of the Perl
programming language. The one below limits itself to only pdfs and MS word
documents.

    # Download pdfs and word documents only.
    html_treebuilder_callback sub {
        my $tag = shift;
        my $link = $tag->attr('href');
        if (defined $link) {
            # If the anchor tag is an image...
            if ($link =~ /\.(pdf|doc|docx)$/) {
                # ...return true...
                return 'True';
            } else {
                # ...if not return false.
                return undef; #false
            }
        }
    };

=item B<7. Specify an optional download_links_callbacks>

C<download_links_callback> specifies an optional anonymous Perl subroutine
reference that will replace the default one that HTMLPageSync uses. The default
one removes the HTML::Element skin each download link is wrapped in, because of
the use of L<HTML::TreeBuilder>. This simply strips off the object-oriented crap
its wrapped in, and turns it into a simply string scalar.

If you want to post process the download link in some other way, then just copy
and paste the code below into your Fetchwarefile, and add whatever other Perl
code you may need. This requires knowledge of the Perl programming language.

    download_links_callback sub {
        my @download_urls = @_;

        my @wanted_download_urls;
        for my $link (@download_urls) {
            # Pick ones to keep.
            puse @wanted_download_urls, $link;
        }

        return @wanted_download_urls;
    };

=back

=cut


=head1 USING YOUR App::FetchwareX::HTMLPageSync FETCHWAREFILE WITH FETCHWARE

After you have
L<created your Fetchwarefile|/"CREATING A App::FetchwareX::HTMLPageSync FETCHWAREFILE">
as shown above you need to actually use the fetchware command line program to
install, upgrade, and uninstall your App::FetchwareX::HTMLPageSync Fetchwarefile.

Take note how fetchware's package management metaphor does not quite line up
with what App::FetchwareX::HTMLPageSync does. Why would a HTML page mirroring
script be installed, upgraded, or uninstalled? Well HTMLPageSync simply adapts
fetchware's package management metaphor to its own enviroment performing the
likely action for when one of fetchware's behaviors are executed.

=over

=item B<install>

A C<fetchware install> while using a HTMLPageSync Fetchwarefile causes fetchware
to download your C<html_page_url>, parse it, download any matching links, and
then copy them to your C<destination_directory> as you specify in your
Fetchwarefile.

=item B<upgrade>

A C<fetchware upgrade> while using a HTMLPageSync Fetchwarefile will simply run
the same thing as install all over again.

=item B<uninstall>

A C<fetchware uninstall> will cause fetchware to delete this fetchware package
from its database as well as recursively deleting everything inside your
C<destination_directory> as well as that directory itself. So when you uninstall
a HTMLPageSync fetchware package ensure that you really want to, because it will
delete whatever files it downloaded for you in the first place.

However, if you would like fetchware to preserve your C<destination_directory>,
you can set the boolean C<keep_destination_directory> configuration option to
true, like C<keep_destination_directory 'True';>, to keep HTMLPageSync from
deleting your destination directory.

=back

=cut


=head1 HOW App::FetchwareX::HTMLPageSync OVERRIDES App::Fetchware

This sections documents how App::FetchwareX::HTMLPageSync overrides
App::Fetchware's API, and is only interesting if you're debugging
App::FetchwareX::HTMLPageSync, or you're writing your own App::Fetcwhare
extension. If not, you don't need to know these details.

=head2 App::Fetchware API Subroutines

HTMLPageSync is a App::Fetchware extension, which just means that it properly
implements  and exports App::Fetchware's API. See
L<something I haven't written yet for more details>

=head3 start() and end()

HTMLPageSync just imports start() and end() from App::Fetchware to take
advantage of their ability to manage a temporary directory.

=head3 lookup()

lookup() is overridden, and downloads the C<html_page_url>, which is the main
configuration option that HTMLPageSync uses. Then lookup() parses that
C<html_page_url>, and determines what the download urls should be. If the
C<html_trebuilder_callback> and C<download_links_callbacks> exist, then they are
called to customize lookup()'s default bahavior. See their descriptions below.

=head3 download()

download() downloads the array ref of download links that lookup() returns.

=head3 verify()

verify() is overridden to do nothing.

=head3 unarchive()

unarchive() takes its argument, which is an arrayref of of the paths of the
files that were downloaded to the tempdir created by start(), and copies them to
the user's provided C<destination_directory>.

=head3 build() and install()

Both are overridden to do nothing.

=head3 uninstall()

uninstall() recursively deletes your C<destination_directory> where it stores
whatever links you choose to download.

=head3 end() and start()

HTMLPageSync just imports end() and start() from App::Fetchware to take
advantage of their ability to manage a temporary directory.


=head2 App::FetchwareX::HTMLPageSync's Configuration Subroutines

Because HTMLPageSync is a App::Fetchware extension, it can not just use the same
configuration subroutines that App::Fetchware uses. Instead, it must create its
own configuration subroutines with App::Fetchware::CreateConfigOptions. These
configuration subroutines are the configuration options that you use in your
App::Fetchware or App::Fetchware extension.

=head3 page_name [MANDATORY]

HTMLPageSync's equivelent to App::Fetchware's C<program_name>. It's simply the
name of the page or what you want to download on that page.

=head3 html_page_url [MANDATORY]

HTMLPageSync's equivelent to App::Fetchware's C<lookup_url>, and is just as
mandatory. This is the url of the HTML page that will be downloaded and
processed.

=head3 destination_directory [MANDATORY]

This option is also mandatory, and it specifies the directory where the files
that you want to download are downloaded to.

=head3 user_agent [OPTIONAL]

This option is optional, and it allows you to have HTML::Tiny pretend to be a
Web browser or perhaps bot if you want to.

=head3 html_treebuilder_callback [OPTIONAL]

This optional option allows you to specify a perl C<CODEREF> that lookup() will
execute instead of its default callback that just looks for images.

It receives one parameter, which is an HTML::Element at the first C<a>,
anchor/link tag.

It must C<return 'True';> to indicate that that link should be included in the
list of download links, or return false, C<return undef>, to indicate that that
link should not be included in the list of download links.

=head3 download_links_callback [OPTIONAL]

This optional option specifies an optional callback that will allow you to do
post processing of the list of downloaded urls. This is needed, because the
result sof the C<html_treebuilder_callback> are still HTML::Element objects that
need to be converted to just string download urls. That is what the default
C<download_links_callback> does.

It receives a list of all of the download HTML::Elements that
C<html_treebuilder_callback> returned true on. It is called only once, and
should return a list of string download links for download later by HTML::Tiny
in download().

=cut


=head1 ERRORS

As with the rest of App::Fetchware, App::Fetchware::Config does not return any
error codes; instead, all errors are die()'d if it's App::Fetchware::Config's
error, or croak()'d if its the caller's fault. These exceptions are simple
strings, and are listed in the L</DIAGNOSTICS> section below.
###BUGALERT### Actually implement croak or more likely confess() support!!!

=cut


=head1 CAVEATS

Certain features of App::FetchwareX::HTMLPageSync require knowledge of the Perl
programming language in order for you to make use of them. However, this is
limited to optional callbacks that are not needed for most uses. These features
are the C<html_treebuilder_callback> and C<download_links_callback> callbacks.

=cut



##TODO##=head1 DIAGNOSTICS
##TODO##
##TODO##App::Fetchware throws many exceptions. These exceptions are not listed below,
##TODO##because I have not yet added additional information explaining them. This is
##TODO##because fetchware throws very verbose error messages that don't need extra
##TODO##explanation. This section is reserved for when I have to actually add further
##TODO##information regarding one of these exceptions.
##TODO##
##TODO##=cut
