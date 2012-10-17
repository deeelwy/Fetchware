package App::Fetchware::HTMLPageSync;
# ABSTRACT: An App::Fetchware extension that downloads files based on an HTML page.
use strict;
use warnings;

# Enable Perl 6 knockoffs.
use 5.010;

# Load only the fetchware API subroutines that A::P::HTMLPageSync does not
# override by implementing them here in its own subroutine.
use App::Fetchware qw(start end temp_dir mirror config make_config_sub
    do_nothing
    :UTIL);

# Local imports.
use File::Copy 'cp';
use File::Path 'remove_tree';

# Set up Exporter to bring App::Fetchware's API to everyone who use's it
# including fetchware's ability to let you rip into its guts, and customize it
# as you need.
use Exporter qw( import );

# Export HTMLPageSync's version of App::Fetchware's API. This is what does the
# "overriding," when a user puts use App::Fetchware::HTMLPageSync in their
# Fetchwarefile, which will load this module, and import HTMLPageSync's API,
# which implements and replaces (overrides) App::Fetchware's API.
our @EXPORT = qw(
    start
    lookup
    download
    verify
    unarchive
    build
    install
    end
    uninstall

    page_name
    html_page_url
    destination_directory
    user_agent
    html_treebuilder_callback
    download_links_callback
);


# App::Fetchware "subclasses" must forward declare any App::Fetchware api
# subroutines that they will "override" just like App::Fetchware does.
sub lookup (;$);
sub download ($;$);
sub verify ($;$);
sub unarchive ($);
sub build ($);
sub install (;$);
sub uninstall ($);


# Since configuration subs have prototypes, and prototypes must be known at
# compile time in order to be honored, I must wrap my calls to make_config_sub()
# inside a BEGIN block so they happen at compile time.
BEGIN {
    # API functions using make_config_sub() can be ONE, ONEARRREF, MANY, or
    # BOOLEAN. See (###BUGALERT### link to docs in whereever they are.
    my @api_functions = (
        [ page_name => 'ONE' ],
        [ html_page_url => 'ONE' ],
        [ destination_directory => 'ONE' ],
        [ user_agent => 'ONE' ],
        # return true for tags you want to sort through.
        [ html_treebuilder_callback => 'ONE' ],
        # get @download_urls, filter them, and return them again.
        [ download_links_callback => 'ONE' ],
    );

    for my $api_function (@api_functions) {
        make_config_sub(@{$api_function});
    }
}

=head1 MOTIVATION

I want to automatically parse a Web page with links to wall papers that I want
to download. Only I want software to do it for me. That's where this
App::Fetchware "subclass" comes in.

=cut


=head1 App::Fetchware::HTMLPageSync API SUBROUTINES

This is App::Fetchware::HTMLPageSync's API that fetchware uses to execute any
Fetchwarefile's that make use of App::Fetchware::HTMLPageSync. This API is the
same that regular old App::Fetchware uses for most standard FOSS software.


=item my $temp_file = start();

start() creats a temp dir, chmod 700's it, and chdir()'s to it just like the one
in App::Fetchware does. App::Fetchware::HTMLPageSync

=cut


=item my $download_url = lookup();

lookup() downloads the user specified C<html_page_url>, parses it using
HTML::TreeBuilder, and uses various yet to be written config subs if specified
to maniuplate the tree to determine what download urls the user wants.

This list of download urls is returned as an array reference, $download_url.

=cut

sub lookup (;$) {
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

    # Return a ref to the array of download urls, because lookup()'s API only
    # allows it to return a single value, but that single value does not have to
    # a scalar. It can be a array ref, which is used here. This works, because
    # what is returned here by lookup() is passed unchanged to download(), which
    # is also part of this API, so I can use what I return here as I please
    # inside download().
    return \@download_urls;
}


=item download($temp_dir, $download_url);

download() uses App::Fetchware's utility function download_http_url() to
download all of the urls that lookup() returned. If the user specifed a
C<user_agent> configuration option, then that option is passed along to
download_http_url()'s call to HTTP::Tiny.

=cut

sub download ($;$) {
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

    ###BUGALERT### Should I use a special var to print a \n between each array
    #elelemnt for pretty printing???
    vmsg <<EOM;
Downloaded specified urls to the following paths:
[
@{[@download_file_paths]}
]
EOM

    # AKA $package_path.
    return \@download_file_paths;
}



=item verify($download_url, $package_path);

verify() simply calls App::Fetchware's :UTIL subroutine do_nothing(), which as
you can tell from its name does nothing, but return. The reason for the useless
do_nothing() call is simply for better documentation, and standardizing how to
override a App::Fetchware API subroutine in order for it to do nothing at all,
so that you can prevent the original App::Fetchware subroutine from doing what
it normally does.

=cut

sub verify ($;$) {
    vmsg <<EOM;
Skipping verify subroutine, because HTMLPageSync does not need to verify anything
EOM
    do_nothing();
}


###BUGALERT### Decide if overridden subs should use original names or if they
#should change them. I think they should change them!
=item unarchive($package_path);

unarchive() takes the $package_path, which is really an array ref of the paths
of the files that download() copied, and copies them the the user specified
destination directory, C<destination_directory>.

=cut

sub unarchive ($) {
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
fetchware: run-time error. Fetchware failed to copy the file [$file_path] to the
destination directory [@{[config('destination_directory')]}].
The OS error was [$!].
EOD
    }

    vmsg 'Successfully copied files to destination directory.';

    return 'True indicating success!';
}


=item build($build_path);

build() does the same thing as unarchive() and verify(), and that is nothing by
calling App::Fetchware's do_nothing() subroutine to better document the fact
that it does nothing.

=cut

sub build ($) {
    vmsg <<EOM;
Skipping build subroutine, because HTMLPageSync does not need to build anything
EOM
    do_nothing();
}


=item install();

install() does nothing by calling App::Fetchware's :UTIL subroutine
do_nothing(), which does nothing.

=cut

sub install (;$) {
    vmsg <<EOM;
Skipping install subroutine, because HTMLPageSync does not need to install anything
EOM
    do_nothing();
}


=item end();

end() chdir()s back to the original directory, and cleans up the temp directory
just like the one in App::Fetchware does. App::Fetchware::HTMLPageSync

=cut


=item uninstall($build_path);

Uninstalls App::Fetchware::HTMLPageSync by recursivly deleting the
C<destination_directory> where it stores the wallpapers or whatever you
specified it to download for you.

=over
NOTICE: uninstalling your App::Fetchware::HTMLPageSync packagw B<will> B<delete>
the contents of that package's associated C<destination_directory>! If you would
like to keep your contents of your C<destination_directory> then either manually
delete the pacakge you want to delete from your fetchware database directory, or
just recursively copy the contents of your C<destination_directory> to a backup
directory somewhere else.
=back

=cut

sub uninstall ($) {
    my $build_path = shift;

    msg <<EOM;
Uninstalling this HTMLPageSync package by deleting your destination directory.'
EOM

    ###BUGALERT### Before release go though all of Fetchware's API, and subifiy
    #each main component like lookup and download were, the later ones were not
    #done this way. That way I can put say chdir_to_build_path() here instead of
    #basicaly copying and pasting the code like I do below. Also
    #chdir_to_build_path() can be put in :OVERRIDE_UNINSTALL!!! Which I can use
    #here.
    chdir $build_path or die <<EOD;
fetchware: Failed to uninstall the specified package and specifically to change
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
fetchware: Failed to uninstall the specified App::Fetchware::HTMLPageSync
package, because no destination_directory is specified in its Fetchwarefile.
This configuration option is required and must be specified.
EOD
    }

    return 'True for success.';
}






1;
