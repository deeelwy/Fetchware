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
use App::Fetchware::Fetchwarefile;
use App::Fetchware qw(
    :OVERRIDE_NEW
    :OVERRIDE_NEW_INSTALL
    :OVERRIDE_CHECK_SYNTAX
);

# Local imports.
use File::Copy 'cp';
use File::Path 'remove_tree';
use URI::Split 'uri_split';
use File::Spec 'splitpath';
use Data::Dumper;
use Scalar::Util 'blessed';

# Use App::Fetchware::ExportAPI to specify which App::Fetchware API subroutines
# we are going to "KEEP", import from App::Fetchware, and which API subs we are
# going to "OVERRRIDE", implemente here in this package.
#
# ExportAPI takes care of the grunt work for us by setting our packages @EXPORT
# appropriatly, and even importing Exporter's import() method into our package
# for us, so that our App::Fetchware API subroutines and configuration options
# specified below can be import()ed properly.
use App::Fetchware::ExportAPI
    # KEEP or "inherit" new_install, because I want my new_install to just call
    # ask_to_install_now_to_test_fetchwarefile(), and App::Fetchware's does that
    # already for me. And start() and end() are to create and manage the
    # temporary directory for me, so I don't have to worry about polluting the
    # current working directory with temporary files.
    KEEP => [qw(new_install start end)],
    # OVERRIDE everything else.
    OVERRIDE =>
        [qw(new check_syntax lookup download verify unarchive build install
        uninstall upgrade)]
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


use Exporter 'import';
our %EXPORT_TAGS = (
    TESTING => [qw(
        get_html_page_url
        get_destination_directory
        ask_about_keep_destination_directory
        new
        new_install
    )]
);
our @EXPORT_OK = map {@{$_}} values %EXPORT_TAGS;



=head1 App::FetchwareX::HTMLPageSync API SUBROUTINES

This is App::FetchwareX::HTMLPageSync's API that fetchware uses to execute any
Fetchwarefile's that make use of App::FetchwareX::HTMLPageSync. This API is the
same that regular old App::Fetchware uses for most standard FOSS software, and
this internal documentation is only needed when debugging HTMLPageSync's code or
when studying it to create your own fetchware extension.

=cut

=head2 new()

    my ($program_name, $fetchwarefile) = new($term, $program_name);

    # Or in an extension, you can return whatever list of variables you want,
    # and then cmd_new() will provide them as arguments to new_install() except
    # a $term Term::ReadLine object will precede the others.
    my ($term, $program_name, $fetchwarefile, $custom_argument1, $custom_argument2)
        = new($term, $program_name);

new() is App::Fetchware's API subroutine that implements fetchware's new
command. It simply uses Term::UI to ask the user some questions that determine
what configuration options will be added to the genereted Fetchwarefile. new()
takes a $term, Term::UI/Term::Readline object, and the optional name of the
program or Website in this case that HTMLPageSync is page syncing.

Whatever scalars (not references just regular strings) that new() returns will
be shared with new()'s sister API subroutine new_install() that is called after
new() is called by cmd_install(), which implements fetchware's new command.
new_install() is called in the parent process, so it does have root permissions,
so be sure to test it as root as well.

=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

This subroutine is B<not> run as root; instead, it is run as a regular user
unless the C<stay_root> configuration option has been set to true.

=back

=back

=cut

sub new {
    my ($term, $page_name) = @_;

    # Instantiate a new Fetchwarefile object for managing and generating a
    # Fetchwarefile, which we'll write to a file for the user or use to
    # build a associated Fetchware package.
    my $now = localtime;
    my $fetchwarefile = App::Fetchware::Fetchwarefile->new(
        header => <<EOF,
use App::FetchwareX::HTMLPageSync;
# Auto generated $now by HTMLPageSync's fetchware new command.
# However, feel free to edit this file if HTMLPageSync's new command's
# autoconfiguration is not enough.
# 
# Please look up HTMLPageSync's documentation of its configuration file syntax at
# perldoc App::FetchwareX::HTMLPageSync, and only if its configuration file
# syntax is not malleable enough for your application should you resort to
# customizing fetchware's behavior. For extra flexible customization see perldoc
# App::Fetchwarex::HTMLPageSync.
EOF
        descriptions => {

            page_name => <<EOA,
page_name simply names the HTML page the Fetchwarefile is responsible for
downloading, analyzing via optional callbacks, and copying to your
destination_directory.
EOA
            html_page_url => <<EOA,
html_page_url is HTMLPageSync's lookup_url equivalent. It specifies a HTTP url
that returns a page of HTML that can be easily parsed of links to later
download.
EOA
            destination_directory => <<EOA,
destination_directory is the directory on your computer where you want the files
that you configure HTMLPageSync to parse to be copied to.
EOA
            user_agent => <<EOA,
user_agent, if specified, will be passed to HTML::Tiny, the Perl HTTP library
Fetchware uses, where the library will lie to the Web server you are Web
scraping from to hopefully prevent the Web sever from banning you, or updating
the page you want to scrap to use too much Javascript, which would prevent the
simple parser HTMLPageSync uses from working on the specified html_page_url.
EOA
            html_treebuilder_callback => <<EOA,
html_treebuilder_callback allows you to specify a perl CODEREF that HTMLPageSync
will execute instead of its default callback that just looks for images.

It receives one parameter, which is an HTML::Element at the first C<a>,
anchor/link tag.

It must [return 'True';] to indicate that that link should be included in the
list of download links, or return false, [return undef], to indicate that that
link should not be included in the list of download links.
EOA
            download_links_callback => <<EOA,
download_links_callback specifies an optional callback that will allow you to do
post processing of the list of downloaded urls. This is needed, because the
results of the html_treebuilder_callback are still HTML::Element objects that
need to be converted to just string download urls. That is what the default
C<download_links_callback> does.

It receives a list of all of the download HTML::Elements that
C<html_treebuilder_callback> returned true on. It is called only once, and
should return a list of string download links for download later by
HTMLPageSync.
EOA
            keep_destination_directory => <<EOA,
keep_destination_directory is a boolean true or false configuration option that
when true prevents HTMLPageSync from deleting your destination_directory when
you run fetchware uninstall.
EOA
        }
    );

    extension_name(__PACKAGE__);

    opening_message(<<EOM);
HTMLPageSync's new command is not as sophistocated as Fetchware's. Unless you
only want to download images, you will have to get your hands dirty, and code up
some custom Perl callbacks to customize HTMLPageSync's behavior. However, it
will ask you quite nicely the basic options, so if those are all you need, then
this command will successfully generate a HTMLPageSync Fetchwarefile for you.

After it lets you choose the easy options of page_name, html_page_url,
and destination_directory, it will give you an opportunity to modify the
user_agent string HTMLPageSync uses to avoid betting banned or having your
scraping stick out like a sore thumb in the target Web server's logs. Then,
you'll be asked about the advanced options. If you want them it will add generic
ones to the Fetchwarefile that you can then fill in later on when HTMLPageSync
asks you if you want to edit the generated Fetchwarefile manually.  Finally,
after your Fetchwarefile is generated HTMLPageSync will ask you if you would
like to install your generated Fetchwarefile to test it out.
EOM

    # Ask the user for the basic configuration options.
    $page_name = fetchwarefile_name(page_name => $page_name);
    vmsg "Determined your page_name option to be [$page_name]";

    $fetchwarefile->config_options(page_name => $page_name);
    vmsg "Appended page_name [$page_name] configuration option to Fetchwarefile";

    my $html_page_url = get_html_page_url($term);
    vmsg "Asked user for html_page_url [$html_page_url] from user.";

    $fetchwarefile->config_options(html_page_url => $html_page_url);
    vmsg "Appended html_page_url [$html_page_url] configuration option to Fetchwarefile";

    my $destination_directory = get_destination_directory($term);
    vmsg "Asked user for destination_directory [$destination_directory] from user.";

    $fetchwarefile->config_options(destination_directory => $destination_directory);
    vmsg <<EOM;
Appended destination_directory [$destination_directory] configuration option to
your Fetchwarefile";
EOM

    # Asks and sets the keep_destination_directory configuratio option if the
    # user wants to set it.
    ask_about_keep_destination_directory($term, $fetchwarefile);

    vmsg 'Prompting for other options that may be needed.';
    my $other_options_hashref = prompt_for_other_options($term,
        user_agent => {
            prompt => <<EOP,
What user_agent configuration option would you like? 
EOP
            print_me => <<EOP
user_agent, if specified, will be passed to HTML::Tiny, the Perl HTTP library
Fetchware uses, where the library will lie to the Web server you are Web
scraping from to hopefully prevent the Web sever from banning you, or updating
the page you want to scrap to use too much Javascript, which would prevent the
simple parser HTMLPageSync uses from working on the specified html_page_url.
EOP
        },
        html_treebuilder_callback => {
            prompt => <<EOP,
What html_treebuilder_callback configuration option would you like? 
EOP
            print_me => <<EOP,
html_treebuilder_callback allows you to specify a perl CODEREF that HTMLPageSync
will execute instead of its default callback that just looks for images.

It receives one parameter, which is an HTML::Element at the first C<a>,
anchor/link tag.

It must [return 'True';] to indicate that that link should be included in the
list of download links, or return false, [return undef], to indicate that that
link should not be included in the list of download links.

Because Term::UI's imput is limited to just one line, please just press enter,
and a dummy value will go into your Fetchwarefile, where you can then replace
that dummy value with a proper Perl callback next, when Fetchware gives you the
option to edit your Fetchwarefile manually.
EOP
            default => 'sub { my $h = shift; die "Dummy placeholder fill me in."; }',
        },
        download_links_callback => {
            prompt => <<EOP,
What download_links_callback configuration option would you like? 
EOP
            print_me => <<EOP,
download_links_callback specifies an optional callback that will allow you to do
post processing of the list of downloaded urls. This is needed, because the
results of the html_treebuilder_callback are still HTML::Element objects that
need to be converted to just string download urls. That is what the default
C<download_links_callback> does.

It receives a list of all of the download HTML::Elements that
C<html_treebuilder_callback> returned true on. It is called only once, and
should return a list of string download links for download later by
HTMLPageSync.

Because Term::UI's imput is limited to just one line, please just press enter,
and a dummy value will go into your Fetchwarefile, where you can then replace
that dummy value with a proper Perl callback next, when Fetchware gives you the
option to edit your Fetchwarefile manually.
EOP
            default => 'sub { my @download_urls = @_; die "Dummy placeholder fill me in."; }',
        },
    );
    vmsg 'User entered the following options.';
    vmsg Dumper($other_options_hashref);

    # Append all other options to the Fetchwarefile.
    $fetchwarefile->config_options(%$other_options_hashref);
    vmsg 'Appended all other options listed above to Fetchwarefile.';

    my $edited_fetchwarefile = edit_manually($term, $fetchwarefile);
    vmsg <<EOM;
Asked user if they would like to edit their generated Fetchwarefile manually.
EOM
    # Generate Fetchwarefile.
    # If edit_manually() did not modify the Fetchwarefile, then generate it.
    if (blessed($edited_fetchwarefile)
        and
    $edited_fetchwarefile->isa('App::Fetchware::Fetchwarefile')) {
        $fetchwarefile = $fetchwarefile->generate(); 
    # If edit_manually() modified the Fetchwarefile, then do not generate it,
    # and replace the Fetchwarefile object with the new string that represents
    # the user's edited Fetchwarefile.
    } else {
        $fetchwarefile = $edited_fetchwarefile;
    }

    # Whatever variables the new() API subroutine returns are written via a pipe
    # back to the parent, and then the parent reads the variables back, and
    # makes then available to new_install(), back in the parent, as arguments.
    return $page_name, $fetchwarefile;
}


=head3 get_html_page_url()

    my $html_page_url = get_html_page_url($term);

Uses $term argument as a L<Term::ReadLine>/L<Term::UI> object to interactively
explain what a L<html_page_url> is, and to ask the user to provide one and press
enter.

=cut

sub get_html_page_url {
    my $term = shift;


    # prompt for lookup_url.
    my $html_page_url = $term->get_reply(
        print_me => <<EOP,
Fetchware's heart and soul is its html_page_url. This is the configuration option
that tells fetchware where to check if any new links have been added to the
specified Web page that match your criteria for download.

How to determine your application's html_page_url:
    1. Simply specify the URL that of the Web page that has the images that you
    would like to have Fetchware download for you.
EOP
        prompt => q{What is your Web page's html_page_url? },
        allow => qr!(ftp|http|file)://!);

    return $html_page_url;
}


=head3 get_destination_directory()

    my $destination_directory = get_destination_directory($term);

Uses $term argument as a L<Term::ReadLine>/L<Term::UI> object to interactively
explain what a C<destination_directory> is, and to ask the user to provide one
and press enter.

=cut

sub get_destination_directory {
    my $term = shift;

    # prompt for lookup_url.
    my $destination_directory = $term->get_reply(
        print_me => <<EOP,
destination_directory is the directory on your computer where you want the files
that you configure HTMLPageSync to parse to be copied to.
EOP
        prompt => q{What is your destination_directory? });

    return $destination_directory;
}


=head3 ask_about_keep_destination_directory()

    ask_about_keep_destination_directory($term, $fetchwarefile);

ask_about_keep_destination_directory() does just that it asks the user if they
would like to enable the C<keep_destination_directory> configuration option to
preserve their C<destination_directory> when they uninstall the assocated
Fetchware package or Fetchwarefile. If they answer Y,
C<keep_destination_directory> is added to their Fetchwarefile, and if not
nothing is added, because deleteing their C<destination_directory> is the
default that will happen even if the C<keep_destination_directory> is not even
in the Fetchwarefile.

=cut

sub ask_about_keep_destination_directory {
    my ($term, $fetchwarefile) = @_;

    if (
        $term->ask_yn(
        print_me => <<EOP,
By default, HTMLPageSync deletes your destination_directory when you uninstall
that destination_directory's assocated Fetchware package or Fetchwarefile. This
is done, because your deleting the Fetchware package, so it makes sense to
delete that package's associated data.

If you wish to keep your destination_directory after you uninstall this
HTMLPageSync Fetchware package, then answer N below.
EOP
        prompt => 'Is deleting your destination_directory on uninstall OK? ',
        default => 'y',
        )
    ) {
        vmsg <<EOM;
User wants [keep_destination_directory 'True';] added to their Fetchwarefile.
EOM

        $fetchwarefile->config_options(keep_destination_directory => 'True');
        vmsg <<EOM;
Appended [keep_destination_directory 'True';] to user's Fetchwarefile.
EOM
    }
}


=head2 new_install()

    my $fetchware_package_path = new_install($page_name, $fetchwarefile);

new_install() asks the user if they would like to install the previously
generated Fetchwarefile that new() created. If they answer yes, then that
program associated with that Fetchwarefile is installed. In our case, that means
that whatever files are configured for download will be downloaded. If they
answer no, then the path to the generated Fetchwarefile will be printed.

new_install() is imported by L<App::Fetchware::ExportAPI> from App::Fetchware,
and also exported by App::FetchwareX::HTMLPageSync. This is how
App::FetchwareX::HTMLPageSync "subclasses" App::Fetchware.

=cut


=head2 check_syntax()

    'Syntax Ok' = check_syntax()

=over

=item Configuration subroutines used:

=over

=item none

=back

=back

Calls check_config_options() to check for the following syntax errors in
Fetchwarefiles. Note by the time check_syntax() has been called
parse_fetchwarefile() has already parsed the Fetchwarefile, and any syntax
errors in the user's Fetchwarefile will have already been reported by Perl.

This may seem like a bug, but it's not. Do you really want to try to use regexes
or something to try to parse the Fetchwarefile reliably, and then report errors
to users? Or add PPI of all insane Perl modules as a dependency just to write
syntax checking code that most of the time says the syntax is Ok anyway, and
therefore a complete waste of time and effort? I don't want to deal with any of
that insanity.

Instead, check_syntax() uses config() to examine the already parsed
Fetchwarefile for "higher-level" or "Fetchware-level" syntax errors. Syntax
errors that are B<Fetchware> syntax errors instead of just Perl syntax errors.

For yours and my own convienience I created check_config_options() helper
subroutine. Its data driven, and will check Fetchwarefile's for three different
types of common syntax errors that occur in App::Fetchware's Fetchwarefile
syntax. These errors are more at the level of I<logic errors> than actual syntax
errors. See its POD below for additional details.

Below briefly lists what App::Fetchware's implementation of check_syntax()
checks.

=over

=item * Mandatory configuration options

=over

=item * page_name, html_page_url, and destination_directory are required for all Fetchwarefiles.

=back

=back


=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

check_syntax() is run in the parent process before even start() has run, so no
temporary directory is available for use.

=back

=back

=cut

sub check_syntax {

    # Use check_config_options() to run config() a bunch of times to check the
    # already parsed Fetchwarefile.
    return check_config_options(
        Mandatory => [ 'page_name', <<EOM ],
App-Fetchware: Your Fetchwarefile must specify a page_name configuration
option. Please add one, and try again.
EOM
        Mandatory => [ 'html_page_url', <<EOM ],
App-Fetchware: Your Fetchwarefile must specify a html_page_url configuration
option. Please add one, and try again.
EOM
        Mandatory => [ 'destination_directory', <<EOM ],
App-Fetchware: Your Fetchwarefile must specify a destination_directory
configuration option. Please add one, and try again.
EOM
    );
}


=head2 start()

    my $temp_file = start();

start() creats a temp dir, chmod 700's it, and chdir()'s to it just like the one
in App::Fetchware does. App::FetchwareX::HTMLPageSync

start() is imported use L<App::Fetchware::ExportAPI> from App::Fetchware,
and also exported by App::FetchwareX::HTMLPageSync. This is how
App::FetchwareX::HTMLPageSync "subclasses" App::Fetchware.

=cut


=head2 lookup()

    my $download_url = lookup();

lookup() downloads the user specified C<html_page_url>, parses it using
HTML::TreeBuilder, and uses C<html_treebuilder_callback> and
C<download_http_url> if specified to maniuplate the tree to determine what
download urls the user wants.

This list of download urls is returned as an array reference, $download_url.

=cut

###BUGALERT### lookup() returns all files each time it is run; therefore, it
#breaks the way Fetchware is supposed to work! lookup() is supposed to return
#"the latest version." And in HTMLPageSync's case, it should not include files
#already downloaded, because it should only return "new files" by comparing the
#"availabe list of files" to the "already downloaded one."
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

    unarchive();

unarchive() does nothing by calling App::Fetchware's :UTIL subroutine
do_nothing(), which does nothing.

=cut

sub unarchive {
    vmsg <<EOM;
Skipping unarchive subroutine, because HTMLPageSync does not need to unarchive
anything
EOM
    do_nothing();
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

    install($package_path);

install() takes the $package_path, which is really an array ref of the paths
of the files that download() copied, and copies them the the user specified
destination directory, C<destination_directory>.

=cut

sub install {
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


=head2 end()

    end();

end() chdir()s back to the original directory, and cleans up the temp directory
just like the one in App::Fetchware does. App::FetchwareX::HTMLPageSync


end() is imported use L<App::Fetchware::ExportAPI> from App::Fetchware,
and also exported by App::FetchwareX::HTMLPageSync. This is how
App::FetchwareX::HTMLPageSync "subclasses" App::Fetchware.

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



=head2 upgrade()

    my $upgrade = upgrade($download_path, $fetchware_package_path)

    if ($upgrade) {
        ...
    }

=over

=item Configuration subroutines used:

=over

=item none

=back

=back

Uses $download_path, an arrayref of URLs to download in HTMLPageSync, and
compares it against the list of files that has already been downloaded by
glob()ing C<destination_directory>. And then comparing  the file names of the
specified files.

Returns true if $download_path has any URLs that have not already been
downloaded into C<destination_directory>. Note: HEAD HTTP querries are B<not>
used to check if any already downloaded files are I<newer> than the files in
the C<destination_directory>.

Returns false if $download_path is the same as C<destination_directory>.
=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

upgrade() is run in the B<child> process as nobody or C<user>, because the child
needs to know if it should actually bother running the rest of fetchware's API
subroutines.

=back

=back

=cut

sub upgrade {
    my $download_path = shift; # $fetchware_package_path is not used in HTMLPageSync.

    # Get the listing of already downloaded file names.
    my @installed_downloads = glob(config('destination_directory'));

    # Preprocess both @$download_path and @installed_downloads to ensure that
    # URL crap or differing full paths won't screw up the "comparisons". The
    # clever delete hashslice does the "comparisons" if you will.
    my @download_path_filenames = map { ( uri_split($_) )[2] } @$download_path;
    my @installed_downloads_filenames = map { ( splitpath($_) ) [2] }
        @installed_downloads;

    # Determine what files are in @$download_path, but not in
    # @installed_downloads.
    # Algo based on code from Perl Cookbook pg. 126.
    my %seen;
    @seen{@$download_path} = ();
    delete @seen{@installed_downloads};

    my @new_urls_to_download = keys %seen;

    if (@new_urls_to_download > 0) {
        # Alter $download_path to only list @new_urls_to_download. That way
        # download() only downloads the new URLs not the already downloaded ones
        # again.
        $download_path = [@new_urls_to_download];

        return 'New URLs Found.';
    } else {
        return;
    }
}


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
results of the C<html_treebuilder_callback> are still HTML::Element objects that
need to be converted to just string download urls. That is what the default
C<download_links_callback> does.

It receives a list of all of the download HTML::Elements that
C<html_treebuilder_callback> returned true on. It is called only once, and
should return a list of string download links for download later by HTML::Tiny
in download().

=head3 keep_destination_directory [OPTIONAL]

This optional option is a boolean true or false configuration option that
when true prevents HTMLPageSync from deleting your destination_directory when
you run fetchware uninstall.

Its default is false, so by defualt HTMLPageSync B<will> delete your files from
your C<destination_directory> unless you set this to true.

=cut


###BUGALERT### Actually implement croak or more likely confess() support!!!

=head1 ERRORS

As with the rest of App::Fetchware, App::Fetchware::Config does not return any
error codes; instead, all errors are die()'d if it's App::Fetchware::Config's
error, or croak()'d if its the caller's fault. These exceptions are simple
strings, and are listed in the L</DIAGNOSTICS> section below.

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
