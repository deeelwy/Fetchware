package App::Fetchware;
# ABSTRACT: App::Fetchware is Fetchware's API used to make extensions.
###BUGALERT### Uses die instead of croak. croak is the preferred way of throwing
#exceptions in modules. croak says that the caller was the one who caused the
#error not the specific code that actually threw the error.
use strict;
use warnings;

# CPAN modules making Fetchwarefile better.
use File::Spec::Functions qw(catfile splitpath splitdir file_name_is_absolute);
use Path::Class;
use Data::Dumper;
use File::Copy 'cp';
use HTML::TreeBuilder;
use Scalar::Util qw(blessed looks_like_number);
use Digest::SHA;
use Digest::MD5;
#use Crypt::OpenPGP::KeyRing;
#use Crypt::OpenPGP;
use Archive::Tar;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Cwd 'cwd';
use Sub::Mage;
use URI::Split qw(uri_split uri_join);

use App::Fetchware::Util ':UTIL';
use App::Fetchware::Config ':CONFIG';

# Enable Perl 6 knockoffs, and use 5.10.1, because smartmatching and other
# things in 5.10 were changed in 5.10.1+.
use 5.010001;

# Set up Exporter to bring App::Fetchware's API to everyone who use's it
# including fetchware's ability to let you rip into its guts, and customize it
# as you need.
use Exporter qw( import );
# By default fetchware exports its configuration file like subroutines.
#
# These days popular dogma considers it bad to import stuff without being asked
# to do so, but App::Fetchware is meant to be a configuration file that is both
# human readable, and most importantly flexible enough to allow customization.
# This is done by making the configuration file a perl source code file called a
# Fetchwarefile that fetchware simply executes with eval.
our @EXPORT = qw(
    program
    filter
    temp_dir
    fetchware_db_path
    user
    prefix
    configure_options
    make_options
    build_commands
    install_commands
    uninstall_commands
    lookup_url
    lookup_method
    gpg_keys_url
    gpg_sig_url
    sha1_url
    md5_url
    verify_method
    no_install
    verify_failure_ok
    user_keyring
    stay_root
    mirror
    config

    start
    lookup
    download
    verify
    unarchive
    build
    install
    end
    uninstall

    hook
);

# These tags allow you to replace some or all of fetchware's default behavior to
# install unusual software.
our %EXPORT_TAGS = (
    # No OVERRIDE_START OVERRIDE_END because start() does *not* use any helper
    # subs that could be beneficial to override()rs.
    OVERRIDE_LOOKUP => [qw(
        check_lookup_config
        get_directory_listing
        parse_directory_listing
        determine_download_path
        ftp_parse_filelist
        http_parse_filelist
        file_parse_filelist
        lookup_by_timestamp
        lookup_by_versionstring
        lookup_determine_downloadpath
    )],
    OVERRIDE_DOWNLOAD => [qw(
        determine_package_path
    )],
    OVERRIDE_VERIFY => [qw(
        gpg_verify
        sha1_verify
        md5_verify
        digest_verify
    )],
    OVERRIDE_UNARCHIVE => [qw(
        check_archive_files    
        list_files
        list_files_tar
        list_files_zip
        unarchive_package
        unarchive_tar
        unarchive_zip
    )],
    OVERRIDE_BUILD => [qw(
        run_star_commands
        run_configure
    )],
    OVERRIDE_INSTALL => [qw(
        chdir_unless_already_at_path
    )],
    OVERRIDE_UNINSTALL => [qw()],
);
# OVERRIDE_ALL is simply all other tags combined.
@{$EXPORT_TAGS{OVERRIDE_ALL}} = map {@{$_}} values %EXPORT_TAGS;
# *All* entries in @EXPORT_TAGS must also be in @EXPORT_OK.
our @EXPORT_OK = @{$EXPORT_TAGS{OVERRIDE_ALL}};




###BUGALERT### Add strict argument checking to App::Fetchware's API subroutines
#to check for not being called correctly to aid extension debugging.
=head1 FETCHWAREFILE API SUBROUTINES

The subroutines below B<are> Fetchwarefile's API subroutines or helper
subroutines for App::Fetchware's API subroutines. If you want information on
fetchware's configuration file syntax, then see the section
L<FETCHWAREFILE CONFIGURATION SYNTAX> for more information. For additional
information on how to keep or override these APi subroutines in a fetchware
extension see the section L<CREATING A FETCHWARE EXTENSION>

=cut


###BUGALERT### Recommend installing http://gpg4win.org if you use fetchware on
# Windows so you have gpg support. 






# _make_config_sub() is an internal subroutine that only App::Fetchware and
# App::Fetchware::CreateConfigOptions should use. Use
# App::Fetchware::CreateConfigOptions to create any configuration option
# subroutines that you want your fetchware extensions to have.
#=head2 _make_config_sub()
#
#    _make_config_sub($name, $one_or_many_values)
#
#A function factory that builds many functions that are the exact same, but have
#different names. It supports three types of functions determined by
#_make_config_sub()'s second parameter.  It's first parameter is the name of that
#function. This is the subroutine that builds all of Fetchwarefile's
#configuration subroutines such as lookupurl, mirror, fetchware, etc....
#
#=over
#=item LIMITATION
#
#_make_config_sub() creates subroutines that have prototypes, but in order for
#perl to honor those prototypes perl B<must> know about them at compile-time;
#therefore, that is why _make_config_sub() must be called inside a C<BEGIN> block.
#
#=back
#
#=over
#=item NOTE
#_make_config_sub() uses caller to determine the package that _make_config_sub()
#was called from. This package is then prepended to the string that is eval'd to
#create the designated subroutine in the caller's package. This is needed so that
#App::Fetchware "subclasses" can import this function, and enjoy its simple
#interface to create custom configuration subroutines.
#
#=back
#
#=over
#
#=item $one_or_many_values Supported Values
#
#=over
#
#=item * 'ONE'
#
#Generates a function with the name of _make_config_sub()'s first parameter that
#can B<only> be called one time per Fetchwarefile. If called more than one time
#will die with an error message.
#
#Function created with C<$CONFIG{$name} = $value;> inside the generated function that
#is named $name.
#
#=item * 'ONEARRREF'
#
#Generates a function with the name of _make_config_sub()'s first parameter that
#can B<only> be called one time per Fetchwarefile. And just like C<'ONE'> above
#if called more than once it will throw an exception. However, C<'ONEARRREF'> can
#be called with a list of values just like C<'MANY'> can, but it can still only
#be called once like C<'ONE'>.
#
#=item * 'MANY'
#
#Generates a function with the name of _make_config_sub()'s first parameter that
#can be called more than just once. This option is only used by fetchware's
#C<mirror()> API call.
#
#Function created with C<push @{$CONFIG{$name}}, $value;> inside the generated function that
#is named $name.
#
#=item * 'BOOLEAN'
#
#Generates a function with the name of _make_config_sub()'s first parameter that
#can be called only once just like 'ONE' can be, but it also only support true or
#false values.  What is true and false is the same as in perl, with the exception
#that /false/i and /off/i are also false.
#
#Function created the same way as 'ONE''s are, but with /false/i and /off/i
#mutated into a Perl accepted false value (they're turned into zeros.).
#
#=back
#
#=back
#
#All API subroutines fetchware provides to Fetchwarefile's are generated by
#_make_config_sub() except for fetchware() and override().
#
#=cut

    my @api_functions = (
        [ program => 'ONE' ],
        [ filter => 'ONE' ],
        [ temp_dir => 'ONE' ],
        [ fetchware_db_path => 'ONE' ],
        [ user => 'ONE' ],
        [ prefix => 'ONE' ],
        [ configure_options=> 'ONEARRREF' ],
        [ make_options => 'ONEARRREF' ],
        [ build_commands => 'ONEARRREF' ],
        [ install_commands => 'ONEARRREF' ],
        [ uninstall_commands => 'ONEARRREF' ],
        [ lookup_url => 'ONE' ],
        [ lookup_method => 'ONE' ],
        [ gpg_keys_url => 'ONE' ],
        [ gpg_sig_url => 'ONE' ],
        [ sha1_url => 'ONE' ],
        [ md5_url => 'ONE' ],
        [ verify_method => 'ONE' ],
        [ mirror => 'MANY' ],
        [ no_install => 'BOOLEAN' ],
        [ verify_failure_ok => 'BOOLEAN' ],
        [ stay_root => 'BOOLEAN' ],
        [ user_keyring => 'BOOLEAN' ],
    );


# Loop over the list of options needed by _make_config_sub() to generated the
# needed API functions for Fetchwarefile.
    for my $api_function (@api_functions) {
        _make_config_sub(@{$api_function});
    }


sub _make_config_sub {
    my ($name, $one_or_many_values, $callers_package) = @_;

    # Obtain caller's package name, so that the new configuration subroutine
    # can be created in the caller's package instead of our own. Use the
    # specifed $callers_package if the caller specified one. This allows
    # create_config_options() to reuse _make_config_sub() by passing in its
    # caller to _make_config_sub().
    my $package = $callers_package // caller;

    die <<EOD unless defined $name;
App-Fetchware: internal syntax error: _make_config_sub() was called without a
name. It must receive a name parameter as its first paramter. See perldoc
App::Fetchware.
EOD
    unless ($one_or_many_values eq 'ONE'
            or $one_or_many_values eq 'ONEARRREF',
            or $one_or_many_values eq 'MANY'
            or $one_or_many_values eq 'BOOLEAN') {
        die <<EOD;
App-Fetchware: internal syntax error: _make_config_sub() was called without a
one_or_many_values parameter as its second parameter. Or the parameter it was
called with was invalid. Only 'ONE', 'MANY', and 'BOOLEAN' are acceptable
values. See perldoc App::Fetchware.
EOD
    }

    given($one_or_many_values) {
        when('ONE') {
            my $eval = <<'EOE'; 
package $package;

sub $name (@) {
    my $value = shift;
    
    die <<EOD if defined config('$name');
App-Fetchware: internal syntax error: $name was called more than once in this
Fetchwarefile. Currently only mirror supports being used more than once in a
Fetchwarefile, but you have used $name more than once. Please remove all calls
to $name but one. See perldoc App::Fetchware.
EOD
    unless (@_) {
        config('$name', $value);
    } else {
        die <<EOD;
App-Fetchware: internal syntax error. $name was called with more than one
option. $name only supports just one option such as '$name 'option';'. It does
not support more than one option such as '$name 'option', 'another option';'.
Please chose one option not both, or combine both into one option. See perldoc
App::Fetchware.
EOD
    }
}
1; # return true from eval
EOE
            $eval =~ s/\$name/$name/g;
            $eval =~ s/\$package/$package/g;
            eval $eval or die <<EOD;
1App-Fetchware: internal operational error: _make_config_sub()'s internal eval()
call failed with the exception [$@]. See perldoc App::Fetchware.
EOD
        } when('ONEARRREF') {
            my $eval = <<'EOE'; 
package $package;

sub $name (@) {
    my $value = shift;
    
    die <<EOD if defined config('$name');
App-Fetchware: internal syntax error: $name was called more than once in this
Fetchwarefile. Currently only mirror supports being used more than once in a
Fetchwarefile, but you have used $name more than once. Please remove all calls
to $name but one. See perldoc App::Fetchware.
EOD
    unless (@_) {
        config('$name', $value);
    } else {
        config('$name', $value, @_);
    }
}
1; # return true from eval
EOE
            $eval =~ s/\$name/$name/g;
            $eval =~ s/\$package/$package/g;
            eval $eval or die <<EOD;
2App-Fetchware: internal operational error: _make_config_sub()'s internal eval()
call failed with the exception [$@]. See perldoc App::Fetchware.
EOD
        }
        when('MANY') {
            my $eval = <<'EOE';
package $package;

sub $name (@) {
    my $value = shift;

    # Support multiple arguments specified on the same line. like:
    # mirror 'http://djfjf.com/a', 'ftp://kdjfjkl.net/b';
    unless (@_) {
        config('$name', $value);
    } else {
        config('$name', $value, @_);
    }
}
1; # return true from eval
EOE
            $eval =~ s/\$name/$name/g;
            $eval =~ s/\$package/$package/g;
            eval $eval or die <<EOD;
3App-Fetchware: internal operational error: _make_config_sub()'s internal eval()
call failed with the exception [\$@]. See perldoc App::Fetchware.
EOD
        } when('BOOLEAN') {
            my $eval = <<'EOE';
package $package;

sub $name (@) {
    my $value = shift;

    die <<EOD if defined config('$name');
App-Fetchware: internal syntax error: $name was called more than once in this
Fetchwarefile. Currently only mirror supports being used more than once in a
Fetchwarefile, but you have used $name more than once. Please remove all calls
to $name but one. See perldoc App::Fetchware.
EOD
    # Make extra false values false (0). Not needed for true values, because
    # everything but 0, '', and undef are true values.
    given($value) {
        when(/false/i) {
            $value = 0;
        } when(/off/i) {
            $value = 0;
        }
    }

    unless (@_) {
        config('$name', $value);
    } else {
        die <<EOD;
App-Fetchware: internal syntax error. $name was called with more than one
option. $name only supports just one option such as '$name 'option';'. It does
not support more than one option such as '$name 'option', 'another option';'.
Please chose one option not both, or combine both into one option. See perldoc
App::Fetchware.
EOD
    }
}
1; # return true from eval
EOE
            $eval =~ s/\$name/$name/g;
            $eval =~ s/\$package/$package/g;
            eval $eval or die <<EOD;
4App-Fetchware: internal operational error: _make_config_sub()'s internal eval()
call failed with the exception [\$@]. See perldoc App::Fetchware.
EOD
        }
    }
}








=head2 start()

    my $temp_dir = start();

=over

=item Configuration subroutines used:

=over

=item temp_dir 

=back

=back

Creates a temp directory using File::Temp, and sets that directory up so that it
will be deleted by File::Temp when fetchware closes.

Returns the $temp_file that start() creates, so everything else has access to
the directory they should use for storing file operations.

=over

=item EXTENSION OVERRIDE NOTES

start() calls L<App::Fetchware::Util>'s create_tempdir() subroutine that cleans
up the temporary directory. If your fetchware extension overrides start() or
end(), you must call create_tempdir() or name your temproary directories in a
manner that fetchware clean won't find them, so something that does not start
with C<fetchware-*>.

If you fail to do this, and you use some other method to create temporary
directories that begin with C<fetchware-*>, then fetchware clean may delete your
temporary directories out from under your feet. To fix this problem:

=over

=item *

Use L<App::Fetchware::Util>'s create_tempdir() in your start() and
cleanup_tempdir() in your end().

=item *

Or, be sure not to name your temprorary directory that you create and manage
yourself to begin with C<fetchware-*>, which is the glob pattern fetchware clean
uses. I recommend using something like
C<App-FetchwareX-NameOfExtension-$$-XXXXXXXXXXXXXX> as the name you would use in
your File::Temp::temdir $pattern, with $$ being the special perlvar for the
curent processes id.

=back

=back

=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

start() is called in the parent with root privileges. This is done, so that when
the parent calls cleanup_tempdir() in its end() call, cleanup_tempdir() still
has a valid filehandle to the fetchware semaphore file, which is used to keep
C<fetchware clean> from deleting fetchware's temporary directories out from
under if you run a C<fetchware clean> while another process is running another
fetchware comand at the same time.

=back

=back

=back

=cut

    sub start {
        my %opts = @_;

        # Add temp_dir config sub to create_tempdir()'s arguments.
        if (config('temp_dir')) {
            $opts{TempDir} = config('temp_dir');
            vmsg "Using user specified temporary directory [$opts{TempDir}]";
        }

        # Add KeepTempDir option if no_install is set. That way user can still
        # access the build directory to do the install themselves.
        if (config('no_install')) {
            $opts{KeepTempDir} = 1;
            vmsg "no_install option enabled not deleting temporary directory.";
        }

        # Forward opts to create_tempdir(), which does the heavy lifting.
        my $temp_dir = create_tempdir(%opts);
        msg "Created fetchware temporary directory [$temp_dir]";

        return $temp_dir;
    }


=head2 lookup()

    my $download_path = lookup();

=over

=item Configuration subroutines used:

=over

=item lookup_url

=item lookup_method

=item filter

=back

=back

Accesses C<lookup_url> as a http/ftp directory listing, and uses C<lookup_method>
to determine what the newest version of the software is available. This is
combined with the path given in C<lookup_url>, and return as $download_path for
use by download().

=over

=item LIMITATIONS
C<lookup_url> is a web browser like URL such as C<http://host.com/a/b/c/path>,
and it B<must> be a directory listing B<not> a actual file. This directory
listing must be a listing of all of the available versions of the program this
Fetchwarefile belongs to.

Only ftp://, http://, and file:// URL scheme's are supported.

And the HTML directory listings Apache and other Web Server's return I<are>
exactly what lookup() uses to determine what the latest version available for
download is.

=back

=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

Under drop_privs() lookup() is executed in the child with reduced privileges.

=back

=back

C<lookup_method> can be either C<'timestamp'> or C<'versionstring'>, any other
values will result in fetchware throwing an exception.

=cut

sub lookup {
    msg "Looking up download url using lookup_url [@{[config('lookup_url')]}]";

    # die if lookup_url wasn't specified.
    # die if lookup_method was specified wrong.
    vmsg 'Checking that lookup has been configured properly.';
    check_lookup_config();
    # obtain directory listing for file, ftp, or http. (a sub for each.)
    vmsg 'Downloading a directory listing using your lookup_url';
    my $directory_listing = get_directory_listing();
    vmsg 'Obtained the following directory listing:';
    vmsg Dumper($directory_listing);
    # parse the directory listing's format based on ftp or http.
    vmsg 'Parse directory listing into internal format.';
    my $filename_listing = parse_directory_listing($directory_listing);
    vmsg 'Directory listing parsed as:';
    vmsg Dumper($filename_listing);
    # Run those listings through lookup_by_timestamp() and/or
        # lookup_by_versionstring() based on lookup_method, or first by timestamp,
        # and then by versionstring if timestamp can't figure out the latest
        # version (normally because everything in the directory listing has the
        # same timestamp.
    # return $download_url, which is lookup_url . <latest version archive>
    vmsg 'Using parsed directory listing to determine download url.';
    my $download_path = determine_download_path($filename_listing);

    vmsg "Download path determined to be [$download_path]";

    return $download_path;
}



=head2 lookup() API REFERENCE

The subroutines below are used by lookup() to provide the lookup functionality
for fetchware. If you have overridden the lookup() handler, you may want to use
some of these subroutines so that you don't have to copy and paste anything from
lookup.

App::Fetchware is B<not> object-oriented; therefore, you B<can not> subclass
App::Fetchware to extend it! 

=cut

=head3 check_lookup_config()

    check_lookup_config();

Verifies the configurations parameters lookup() uses are correct. These are
C<lookup_url> and C<lookup_method>. If they are wrong die() is called. If they
are right it does nothing, but return.

check_lookup_config() also currently checks if a program config option is given,
and throws an exception if it is not.

It also ensures that you specify at least one mirror, and how to verify your
program. If this is not done properly, and exception is thrown. For verification
to work properly, you must specify C<gpg_keys_url>, C<md5_url>, or C<sha1_url>.
B<Only> if there is no verification availabe from your program's author should
you use the C<verification_failure 'On';> option.

=cut

sub check_lookup_config {
    if (not defined config('lookup_url')) {
        die <<EOD;
App-Fetchware: run-time syntax error: your Fetchwarefile did not specify a
lookup_url. lookup_url is a required configuration option, and must be
specified, because fetchware uses it to located new versions of your program to
download. See perldoc App::Fetchware
EOD
    }

    # Only test lookup_method if it has been defined.
    if (defined config('lookup_method')) {
        given (config('lookup_method')) {
            when ('timestamp') {
                # Do nothing
            } when ('versionstring') {
                # Do nothing
            } default {
                die <<EOD;
App-Fetchware: run-time syntax error: your Fetchwarefile specified a incorrect
option to lookup_method. lookup_method only supports the options 'timestamp' and
'versionstring'. All others are wrong. See man App::Fetchware.
EOD
            }
        }
    }

    ###BUGALERT### Should I add a syntax_check() API sub to App::Fetchware, so
    #other extensions can do this easier. Perhaps even create a helper function
    #where you can specify which config options must be specified???
    die <<EOD unless config('program');
App-Fetchware: You failed to specify a [program] configuration option. This
option is mandatory, and gives the program your Fetchwarefile manages a name.
Please add a [program 'your program's name here';] configuration option to your
Fetchwarefile.
EOD

    die <<EOD unless config('mirror');
App-Fetchware: You failed to specify a [mirror] configuration option. This
option is mandatory, and is used by fetchware to download a new version of your
program to install that is looked up using the [lookup_url]. Please add a
[mirror 'scheme://some.url';] configuration option to your Fetchwarefile.
EOD

    unless (config('gpg_keys_url')
            or config('gpg_sig_url')
            or config('md5_url')
            or config('sha1_url')
    ) {
        msg <<EOD unless config('verify_failure_ok');
App-Fetchware: You failed to specify a method of verifying downloaded archives
of your program. This is mandatory to ensure that the software that you download
is the same as the software the author actually uploaded. Please specify a
[gpg_keys_url] that points to the KEYS file that lists the author's gpg keys. If
the author does not maintain such a file, then specify a [sha1_url] that
specifies a directory where SHA-1 digests can be downloaded from. And if SHA-1
digests are not availabe, then fall back on MD5 digests using [md5_url]. If not
even MD5 digest verification is available from your software's author, you may
specify the [verification_failure 'On';] configuration option to force fetchware
to build and install your software even though it can not be verified. This
option should not be enabled lightly, because mirrors do sometimes get hacked,
and some times malware is injected.
EOD
    }
}


=head3 get_directory_listing()

    my $directory_listing = get_directory_listing();

Downloads a directory listing that lookup() uses to determine what the latest
version of your program is. It is returned.

=over
=item SIDE EFFECTS
get_directory_listing() returns a SCALAR REF of the output of HTTP::Tiny
or a ARRAY REF for Net::Ftp downloading that listing. Note: the output is
different for each download type. Type 'http' will have HTML crap in it, and
type 'ftp' will be the output of Net::Ftp's dir() method.

Type 'file' will just be a listing of files in the provided C<lookup_url>
directory.

=back

=cut

sub get_directory_listing {

    return download_dirlist(config('lookup_url'));
}


=head3 parse_directory_listing()

    my $file_listing = parse_directory_listing($directory_listing);

Based on URL scheme of C<'file'>, C<'http'>, or C<'ftp'>,
parse_directory_listing() will call file_parse_filelist(), ftp_parse_filelist(),
or http_parse_filelist(). Those subroutines do the heavy lifting, and the
results are returned.

=over
=item SIDE EFFECTS
parse_directory_listing() returns to a array of arrays of the filenames and
timestamps that make up the directory listing.

=back

=cut

sub parse_directory_listing {
    my ($directory_listing) = @_;

    given (config('lookup_url')) {
        when (m!^ftp://!) {
        ###BUGALERT### *_parse_filelist may not properly skip directories, so a
        #directory could exist that could wind up being the "latest version"
            return ftp_parse_filelist($directory_listing);
        } when (m!^http://!) {
            return http_parse_filelist($directory_listing);
        } when (m!^file://!) {
            return file_parse_filelist($directory_listing);
        }
    }
}


=head3 determine_download_path()

    my $download_path = determine_download_path($filename_listing);

Runs the C<lookup_method> to determine what the lastest filename is, and that
one is then concatenated with C<lookup_url> to determine the $download_path,
which is then returned to the caller.

=over
=item SIDE EFFECTS
determine_download_path(); returns $download_path the path that download() will
use to download the archive of your program.

=back

=cut

sub determine_download_path {
    my $filename_listing = shift;

    # Base lookup algorithm on lookup_method configuration sub if it was
    # specified.
    given (config('lookup_method')) {
        when ('timestamp') {
            return lookup_by_timestamp($filename_listing);
        } when ('versionstring') {
            return lookup_by_versionstring($filename_listing);
        # Default is to just use timestamp although timestamp will call
        # versionstring if it can't figure it out, because all of the timestamps
        # are the same.
        } default {
            return lookup_by_timestamp($filename_listing);
        }
    }
}


=head3 ftp_parse_filelist()

    $filename_listing = ftp_parse_filelist($ftp_listing);

Takes an array ref as its first parameter, and parses out the filenames and
timstamps of what is assumed to be C<Net::FTP->dir()> I<long> directory listing
output.

Returns a array of arrays of filenames and timestamps.

=cut


{ # Bare block for holding %month {ftp,http}_parse_filelist() need.
    my %month = (
        Jan => '01',
        Feb => '02',
        Mar => '03',
        Apr => '04',
        May => '05',
        Jun => '06',
        Jul => '07',
        Aug => '08',
        Sep => '09',
        Oct => '10',
        Nov => '11',
        Dec => '12',
    );

    my %num_month = (
         1 => '01',
         2 => '02',
         3 => '03',
         4 => '04',
         5 => '05',
         6 => '06',
         7 => '07',
         8 => '08',
         9 => '09',
        10 => '10',
        11 => '11',
        12 => '12',
    );


    sub  ftp_parse_filelist {
        my $ftp_listing = shift;

        my ($filename, $timestamp, @filename_listing);

        for my $listing (@$ftp_listing) {
            # Example Net::FTP->dir() output.
            #drwxrwsr-x   49 200      200          4096 Oct 05 14:27 patches
            my @fields = split /\s+/, $listing;
            # Test & try it???  Probaby won't work.
            #my ($month, $day, $year_or_time, $filename) = ( split /\s+/, $listing )[-4--1];
            $filename = $fields[-1];
            #month       #day        #year
            #"$fields[-4] $fields[-3] $fields[-2]";
            my $month = $fields[-4];
            my $day = $fields[-3];
            my $year_or_time = $fields[-2];

            # Normalize timestamp format.
            given ($year_or_time) {
                # It's a time.
                when (/\d\d:\d\d/) {
                    # the $month{} hash access replaces text months with numerical
                    # ones.
                    $year_or_time =~ s/://; # Make 12:00 1200 for numerical sort.
                    #DELME$fl->[1] = "9999$month{$timestamp[0]}$timestamp[1]$timestamp[2]";
                    $timestamp = "9999$month{$month}$day$year_or_time";
                    # It's a year.
                } when (/\d\d\d\d/) {
                    # the $month{} hash access replaces text months with numerical
                    # ones.
                    #DELME$fl->[1] = "$timestamp[2]$month{$timestamp[0]}$timestamp[1]0000";
                    $timestamp = "$year_or_time$month{$month}${day}0000";
                }
            }
            push @filename_listing, [$filename, $timestamp];
        }

        return \@filename_listing;
    }



=head3 http_parse_filelist()

    $filename_listing = http_parse_filelist($http_listing);

Takes an scalar of downloaded HTML output, and parses it using
HTML::Linkextractor to build and return an array of arrays of filenames and
timestamps.

=cut

    sub  http_parse_filelist {
        my $http_listing = shift;

        # Use HTML::TreeBuilder to parse the scalar of html into a tree of tags.
        my $tree = HTML::TreeBuilder->new_from_content($http_listing);

        my @filename_listing;
        my @matching_links = $tree->look_down(
            _tag => 'a',
            sub {
                my $h = shift;

                #parse out archive name.
                my $link = $h->as_text();
                # NOTE: The weird alternations adding .asc, .md5, and .sha.?,
                # and also a KEYS file are to allow fetchware new to also use
                # this subroutine to parse http file listings to analyze the
                # contents of the user's lookup_url. It does not make any sense
                # to copy and paste this function or even add a callback argument
                # allowing you to change the regex.
                if ($link =~
                    /(\.(tar\.(gz|bz2|xz)|(tgz|tbz2|txz))|(asc|md5|sha.?))|KEYS$/) {
                    # Should I strip out dirs just to be safe?
                    my $filename = $link;
                    # Obtain the tag to the right of the archive link to find the
                    # timestamp.
                    if (my $rh = $h->right()) {
                        my $listing_line;
                        if (blessed($rh)) {
                            $listing_line = $rh->as_text();
                        } else {
                            $listing_line = $rh;
                        }
                        my @fields = split ' ', $listing_line;
                        ###BUGALERT### Internationalization probably breaks this
                        #datetime parsing? Can a library do it?
                        # day-month-year   time
                        # $fields[0]      $fields[1]
                        # Normalize format for lookup algorithms .
                        my ($day, $month, $year) = split /-/, $fields[0];
                        # Ditch the ':' in the time.
                        $fields[1] =~ s/://;
                        # Some dirlistings use string months Aug, Jun, etc...
                        if (looks_like_number($month)) {
                            # Strip leading 0 if it exists by converting the
                            # string with the useless leading 0 into an integer.
                            # The %num_month hash lookup will add back a leading
                            # 0 if there was one. This stupid roundabout code is
                            # to ensure that there always is a leading 0 if the
                            # number is less than 10 to ensure that all of the
                            # numbers this hacky datetime parser outputs all
                            # have the same length so that the numbers can
                            # easily be compared with each other.
                            $month = sprintf("%u", $month);
                            push @filename_listing, [$filename,
                                "$year$num_month{$month}$day$fields[1]"];
                        # ...and some use numbers 8, 6, etc....
                        } else {
                            push @filename_listing, [$filename,
                                "$year$month{$month}$day$fields[1]"];
                        }
                    } else {
###BUGALERT### Add support for other http servers such as lighttpd, nginx,
#cherokee, starman?, AND use the Server: header to determine which algorithm to
#use.
                        die <<EOD;
App-Fetchware: run-time error. A hardcoded algorithm to parse HTML directory
listings has failed! Fetchware currently only supports parseing Apache HTML
directory listings. This is a huge limitation, but surprisingly pretty much
everyone who runs a mirror uses apache for http support. This is a bug so
please report it. Also, if you want to try a possible workaround, just use a ftp
mirror instead of a http one, because ftp directory listings are a easy to
parse. See perldoc App::Fetchware.
EOD
                    }
                }
            }
        );


        # Delete the $tree, so perl can garbage collect it.
        $tree = $tree->delete;

        return \@filename_listing;
    }


} # end bare block for %month.




=head3 file_parse_filelist()

    my $filename_listing = file_parse_filelist($file_listing);

Parses the provided filelist by C<stat>ing each file, and creating a properly
formatted timestamp to return in kdjfkdj format.

Returns an array of arrays of filenames and timestamps.

=cut

sub file_parse_filelist {
    my $file_listing = shift;

    for my $file (@$file_listing) {
        my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,
            $blksize,$blocks)
            = stat($file) or die <<EOD;
App-Fetchware: Fetchware failed to stat() the file [$file] while trying to parse
your local [file://] lookup_url. The OS error was [$!]. This should not happen,
and is either a bug in fetchware or some sort of race condition.
EOD

        # Replace scalar filename with a arrayref of the filename with its
        # assocated timestamp for later processing for lookup().
        # 
        # Use Path::Class's file() constructor & basename() method to strip out
        # all unneeded directory information leaving just the file's name.
        # Add all of the timestamp numbers together, so that only one numberical
        # sort is needed instead of a descending list of numerical sorts.
        $file = [file($file)->basename(), $mtime ];
    }

    return $file_listing;
}


=head3 lookup_by_timestamp()

    my $download_url = lookup_by_timestamp($filename_listing);

Implements the 'timestamp' lookup algorithm. It takes the timestamps placed in
its first argument, normalizes them into a standard descending format
(YYYYMMDDHHMM), and then cleverly uses sort to determine the latest
filename, which should be the latest version of your program.

=cut

sub  lookup_by_timestamp {
    my $file_listing = shift;
    
    # Sort the timstamps to determine the latest one. The one with the higher
    # numbers, and put $b before $a to put the "bigger", later versions before
    # the "lower" older versions.
    # Sort based on timestamp, which is $file_listing->[0..*][1][0..6].
    # Note: the crazy || ors are to make perl sort each timestamp array first by
    # year, then month, then day of the month, and so on.
    my @sorted_listing = sort { $b->[1] <=> $a->[1] } @$file_listing;

    # Manage duplicate timestamps apropriately including .md5, .asc, .txt files.
    # And support some hacks to make lookup() more robust.
    ###BUGALERT### Refactor this containing sub to call the sub below, and
    #another one called lookup_hacks() for example, or perhaps provide a
    #callback for this :)
    return lookup_determine_downloadpath(\@sorted_listing);
}


=head3 lookup_by_versionstring()

    my $download_url = lookup_by_versionstring($filename_listing);

Determines the $download_url used by download() by cleverly C<split>ing the
filenames on C</\D+/>, which will return a list of version numbers. Then
they're just sorted normally. And lookup_determine_downloadpath() is used to
take the sorted $file_listing, and determine the actual $download_url, which is
returned.

=cut

sub  lookup_by_versionstring {
    my $file_listing = shift;

    # Implement versionstring algorithm.
    for my $fl (@$file_listing) {
        # Split each filename on *non digits*
        ###BUGALERT### Add error checking for if the /D+ split fails to actually
        #split the string!!!
        my @split_fl = split /\D+/, $fl->[0];
        # Join each digit into one "super digit"
        $fl->[2] = join '', @split_fl;
        # And sort below sorts them into highest number first order.
    }

    # Sort $file_listing by the versionstring, and but $b in front of $a to get
    # a reverse sort, which will put the "bigger", later version numbers before
    # the "lower", older ones.
    @$file_listing = sort { $b->[2] <=> $a->[2] } @$file_listing;
    

    ###BUGALERT### This action at a distance crap should get its own high-level
    #subroutine at least vmsg determine_downloadurl inside lookup().
    # Manage duplicate timestamps apropriately including .md5, .asc, .txt files.
    # And support some hacks to make lookup() more robust.
    return lookup_determine_downloadpath($file_listing);
}



=head3 lookup_determine_downloadpath()

    my $download_path = lookup_determine_downloadpath($file_listing);

Given a $file_listing of files with the same timestamp or versionstring,
determine which one is a downloadable archive, a tarball or zip file. And
support some backs to make fetchware more robust. These are the C<filter>
configuration subroutine, ignoring "win32" on non-Windows systems, and
supporting Apache's CURRENT_IS_ver_num and Linux's LATEST_IS_ver_num helper
files.

=cut

sub lookup_determine_downloadpath {
    my $file_listing = shift;

    # First grep @$file_listing for $CONFIG{filter} if $CONFIG{filter} is defined.
    # This is done, because some distributions have multiple versions of the
    # same program in one directory, so sorting by version numbers or
    # timestamps, and then by filetype like below is not enough to determine,
    # which file to download, so filter was invented to fix this problem by
    # letting Fetchwarefile's specify which version of the software to download.
    if (defined config('filter')) {
        @$file_listing = grep { $_->[0] =~ /@{[config('filter')]}/ } @$file_listing;
    }

    # Skip any filenames with win32 in them on non-Windows systems.
    # Windows systems who may need to download the win32 version can just use
    # filter 'win32' for that or maybe 'win32|http-2.2' if they need the other
    # functionality of filter.
    if ($^O ne 'MSWin32') { # $^O is what os I'm on, MSWin32, Linux, darwin, etc
        @$file_listing = grep { $_->[0] !~ m/win32/i } @$file_listing;
    }

    # Support 'LATEST{_,-}IS' and 'CURRENT{_,-}IS', which indicate what the
    # latest version is.  These files come from each software distributions
    # mirror scripts, so they should be more accurate than either of my lookup
    # algorithms. Both Apache and the Linux kernel maintain these files.
    $_->[0] =~ /^(?:latest|current)[_-]is[_-](.*)$/i for @$file_listing;
    my $latest_version = $1;
    @$file_listing = grep { $_->[0] =~ /$latest_version/ } @$file_listing
        if defined $latest_version;

    # Determine the $download_url based on the sorted @$file_listing by
    # finding a downloadable file (a tarball or zip archive).
    # Furthermore, choose them based on best compression to worst to save some
    # bandwidth.
    for my $fl (@$file_listing) {
        given ($fl->[0]) {
            when (/\.tar\.xz$/) {
                my $path = ( uri_split(config('lookup_url')) )[2];
                return "$path/$fl->[0]";
            } when (/\.txz$/) {
                my $path = ( uri_split(config('lookup_url')) )[2];
                return "$path/$fl->[0]";
            } when (/\.tar\.bz2$/) {
                my $path = ( uri_split(config('lookup_url')) )[2];
                return "$path/$fl->[0]";
            } when (/\.tbz$/) {
                my $path = ( uri_split(config('lookup_url')) )[2];
                return "$path/$fl->[0]";
            } when (/\.tar\.gz$/) {
                my $path = ( uri_split(config('lookup_url')) )[2];
                return "$path/$fl->[0]";
            } when (/\.tgz$/) {
                my $path = ( uri_split(config('lookup_url')) )[2];
                return "$path/$fl->[0]";
            } when (/\.zip$/) {
                my $path = ( uri_split(config('lookup_url')) )[2];
                return "$path/$fl->[0]";
            } when (/\.fpkg$/) {
                my $path = ( uri_split(config('lookup_url')) )[2];
                return "$path/$fl->[0]";
            }
        }
##DELME##        if (config('lookup_url') =~ m!^file://!) {
##DELME##        # Must prepend scheme, so that download() knows how to retrieve this
##DELME##        # file with download_file(), which requires a URL that must begin
##DELME##        # with a scheme, and file:// is the scheme for local files.
##DELME##        $fl->[0] =~ s/"file://$fl->[0]";
    }
    die <<EOD;
App-Fetchware: run-time error. Fetchware failed to determine what URL it should
use to download your software. This URL is based on the lookup_url you
specified. See perldoc App::Fetchware.
EOD
}



=head2 download()

    my $package_path = download($temp_dir, $download_path);

=over

=item Configuration subroutines used:

=over

=item mirror

=back

=back

Downloads $download_path to C<tempdir 'whatever/you/specify';> or to
whatever File::Spec's tempdir() method tries. Supports ftp and http URLs as well
as local files specified like in browsers using C<file://>

Also, returns $package_path, which is used by unarchive() as the path to the
archive for unarchive() to untar or unzip.

=over

=item LIMITATIONS
Uses Net::FTP and HTTP::Tiny to download ftp and http files. No other types of
downloading are supported, and fetchware is stuck with whatever limitations or
bugs Net::FTP or HTTP::Tiny impose.

=back

=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

Under drop_privs() download() is executed in the child with reduced privileges.

=back

=back

=cut

sub download {
    my ($temp_dir, $download_path) = @_;

    # Ensure we're passed just a path, and *not* a full URL.
    die <<EOD if $download_path =~ m!(?:http|ftp|file)://!;
App-Fetchware: download() has been passed a full URL *not* only a path.
download() should only be called with a path never a full URL. The URL you
specified was [$download_path]
EOD

    vmsg <<EOM;
Using [$download_path] as basis for determined our download_url using the user
supplied mirrors.
EOM

    msg "Downloading from url [$download_path] to temp dir [$temp_dir]";

    my $downloaded_file_path = download_file(PATH => $download_path);
    vmsg "Downloaded file to [$downloaded_file_path]";

    my $package_path = determine_package_path($temp_dir, $downloaded_file_path);
    msg "Determined package path to be [$package_path]";

    return $package_path;
}



=head2 download() API REFERENCE

The subroutines below are used by download() to provide the download
functionality for fetchware. If you have overridden the download() handler, you
may want to use some of these subroutines so that you don't have to copy and
paste anything from download.

App::Fetchware is B<not> object-oriented; therefore, you B<can not> subclass
App::Fetchware to extend it! 

=cut


=head3 determine_package_path()

    my $package_path = determine_package_path($tempdir, $filename)

Determines what $package_path is based on the provided $tempdir and
$filename. $package_path is the path used by unarchive() to unarchive the
software distribution download() downloads.

$package_path is returned to caller.

=cut

sub determine_package_path {
    my ($tempdir, $filename) = @_;

    # return $package_path, which stores the full path of where the file
    # HTTP::Tiny downloaded.
    ###BUGALERT### $tempdir is no longer used, so remove it from
    #determine_package_path() and probably download() too.
    return catfile(cwd(), $filename)
}



=head2 verify()

    verify($download_path, $package_path)

=over

=item Configuration subroutines used:

=over

=item gpg_keys_url 'a.browser/like.url';

=item user_keyring 'On';

=item gpg_sig_url 'a.browser/like.url';

=item sha1_url 'a browser-like url';

=item md5_url 'a browser-like url';

=item verify_method 'md5,sha,gpg';

=item verify_failure_ok 'True/False';

=back

=back

Verifies the downloaded package stored in $package_path by downloading
$download_path.{asc,sha1,md5}> and comparing the two together. Uses the
helper subroutines C<{gpg,sha1,md5,digest}_verify()>.

=over

=item LIMITATIONS
Uses gpg command line, and the interface to gpg is a little brittle.
Crypt::OpenPGP is buggy and not currently maintainted again, so fetchware cannot
make use of it, so were stuck with using the command line gpg program.

=back

=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

Under drop_privs() verify() is executed in the child with reduced privileges.

=back

=back

=cut

sub verify {
    my ($download_path, $package_path) = @_;

    msg "Verifying the downloaded package [$package_path]";

    my $retval;
    given (config('verify_method')) {
        when (undef) {
            # if gpg fails try
            # sha and if it fails try
            # md5 and if it fails die
            msg 'Trying to use gpg to cyptographically verify downloaded package.';
            my ($gpg_err, $sha_err, $md5_err);
            eval {$retval = gpg_verify($download_path)};
            $gpg_err = $@;
            if ($gpg_err) {
                msg <<EOM;
Cyptographic verification using gpg failed!
GPG verification error [
$@
]
EOM
                warn $gpg_err;
            }
            if (! $retval or $gpg_err) {
                msg <<EOM;
Trying SHA1 verification of downloaded package.
EOM
                eval {$retval = sha1_verify($download_path, $package_path)};
                $sha_err = $@;
                if ($sha_err) {
                    msg <<EOM;
SHA1 verification failed!
SHA1 verificaton error [
$@
]
EOM
                    warn $sha_err;
                }
                if (! $retval or $sha_err) {
                    msg <<EOM;
Trying MD5 verification of downloaded package.
EOM
                    eval {$retval = md5_verify($download_path, $package_path)};
                    $md5_err = $@;
                    if ($md5_err) {
                        msg <<EOM;
MD5 verification failed!
MD5 verificaton error [
$@
]
EOM
                        warn $md5_err;
                    }
                }
                if (! $retval or $md5_err) {
                    die <<EOD unless config('verify_failure_ok');
App-Fetchware: run-time error. Fetchware failed to verify your downloaded
software package. You can rerun fetchware with the --force option or add
[verify_failure_ok 'True';] to your Fetchwarefile. See the section VERIFICATION
FAILED in perldoc fetchware.
EOD
                }
                if (config('verify_failure_ok')) {
                        warn <<EOW;
App-Fetchware: run-time warning. Fetchware failed to verify the integrity of you
downloaded file [$package_path]. This is ok, because you asked Fetchware to
ignore its errors when it tries to verify the integrity of your downloaded file.
You can also ignore the errors Fetchware printed out abover where it tried to
verify your downloaded file. See perldoc App::Fetchware.
EOW
                    vmsg <<EOM;
Verification Failed! But you asked to ignore verification failures, so this
failure is not fatal.
EOM
                    return 'warned due to verify_failure_ok'
                }
            }
        } when (/gpg/i) {
            vmsg <<EOM;
You selected gpg cryptographic verification. Verifying now.
EOM
            ###BUGALERT### Should trap the exception {gpg,sha1,md5}_verify()
            #throws, and then add that error to the one here, otherwise the
            #error message here is never seen.
            gpg_verify($download_path)
                or die <<EOD unless config('verify_failure_ok');
App-Fetchware: run-time error. You asked fetchware to only try to verify your
package with gpg or openpgp, but they both failed. See the warning above for
their error message. See perldoc App::Fetchware.
EOD
        } when (/sha1?/i) {
            vmsg <<EOM;
You selected SHA1 checksum verification. Verifying now.
EOM
            sha1_verify($download_path, $package_path)
                or die <<EOD unless config('verify_failure_ok');
App-Fetchware: run-time error. You asked fetchware to only try to verify your
package with sha, but it failed. See the warning above for their error message.
See perldoc App::Fetchware.
EOD
        } when (/md5/i) {
            vmsg <<EOM;
You selected MD5 checksum verification. Verifying now.
EOM
            md5_verify($download_path, $package_path)
                or die <<EOD unless config('verify_failure_ok');
App-Fetchware: run-time error. You asked fetchware to only try to verify your
package with md5, but it failed. See the warning above for their error message.
See perldoc App::Fetchware.
EOD
        } default {
            die <<EOD;
App-Fetchware: run-time error. Your fetchware file specified a wrong
verify_method option. The only supported types are 'gpg', 'sha', 'md5', but you
specified [@{[config('verify_method')]}]. See perldoc App::Fetchware.
EOD
        }
    }
    msg 'Verification succeeded.';
}



=head2 verify() API REFERENCE

The subroutines below are used by verify() to provide the verify
functionality for fetchware. If you have overridden the verify() handler, you
may want to use some of these subroutines so that you don't have to copy and
paste anything from verify().

App::Fetchware is B<not> object-oriented; therefore, you B<can not> subclass
App::Fetchware to extend it! 

=cut


=head3 gpg_verify()

    'Package Verified' = gpg_verify($download_path);

Uses the command-line program C<gpg> to cryptographically verify that the file
you download is the same as the file the author uploaded. It uses public-key
priviate-key cryptography. The author signs his software package using gpg or
some other OpenPGP compliant program creating a digital signature file with the
same filename as the software package, but usually with a C<.asc> file name
extension. gpg_verify() downloads the author's keys, imports them into
fetchware's own keyring unless the user sets C<user_keyring> to true in his
Fetchwarefile. Then Fetchware downloads a the digital signature that usually
ends in C<.asc>. Afterwards, fetchware uses the gpg command line program to
verify the digital signature. gpg_verify returns true if successful, and throws
an exception otherwise.

You can use C<gpg_keys_url> to specify the URL of a file where the author has
uploaded his keys. And the C<gpg_sig_url> can be used to setup an alternative
location of where the C<.asc> digital signature is stored.

=cut

sub gpg_verify {
    my $download_path = shift;


    # Determine @gpg_options for use when running gpg.
    my @gpg_options;
    push @gpg_options, '--homedir', '.' unless config('user_keyring');

    ## Attempt to download KEYS file in lookup_url's containing directory.
    ## If that fails, try gpg_keys_url if defined.
    ## Import downloaded KEYS file into a local gpg keyring using gpg command.
    ## Determine what URL to use to download the signature file *only* from
    ## lookup_url's host, so that we only download the signature from the
    ## project's main mirror.
    ## Download it.
    # gpg verify the sig using the downloaded and imported keys in our local
    # keyring.

    # Skip downloading and importing keys if we're called from inside a
    # fetchware package, which should already have a copy of our package's KEYS
    # file.
    unless (-e './pubring.gpg' and -e './secring.gpg') {
        # Obtain a KEYS file listing everyone's key that signs this distribution.
        my $keys_file;
        if (defined config('gpg_keys_url')) {
            $keys_file = no_mirror_download_file(config('gpg_keys_url'));
        } else {
            eval {
                $keys_file = no_mirror_download_file(config('lookup_url'). '/KEYS');
            }; 
                die <<EOD if $@;
App-Fetchware: Fetchware was unable to download the gpg_key_url you specified or
that fetchware tried appending asc, sig, or sign to [@{[config('lookup_url')]}].
It needs to download this file to properly verify you software package. This is
a fatal error, because failing to verify packages is a perferable default over
potentially installing compromised ones. If failing to verify your software
package is ok to you, then you may disable verification by adding
verify_failure_ok 'On'; to your Fetchwarefile. See perldoc App::Fetchware.
EOD
        }

        # Import downloaded KEYS file into a local gpg keyring using gpg command.
        eval {
            run_prog('gpg', @gpg_options, '--import', $keys_file);
            1;
        } or msg <<EOM;
App-Fetchware: Warning: gpg exits nonzero when importing large KEY files such as
Apache's. However, despite exiting nonzero gpg still manages to import most of
the keys into its keyring. It only exits nonzero, because some of the keys in
the KEYS file had errors, and these key's errors were enough to cause gpg to
exit nonzero, but not enough to cause it to completely fail importing the keys.
EOM
    }

    # Download Signature using lookup_url.
    my $sig_file;
    my (undef, undef, $path, undef, undef) = uri_split($download_path);
    my ($scheme, $auth, undef, undef, undef) = uri_split(config('lookup_url'));
    my $sig_url;
    for my $ext (qw(asc sig sign)) {
        eval {
            $sig_url = uri_join($scheme, $auth, "$path.$ext", undef, undef);
            $sig_file = no_mirror_download_file($sig_url);

        };
        # If the file was downloaded stop trying other extensions.
        last if defined $sig_file;
    }
    die <<EOD if not defined $sig_file;
App-Fetchware: Fetchware was unable to download the gpg_sig_url you specified or
that fetchware tried appending asc, sig, or sign to [$sig_url]. It needs
to download this file to properly verify you software package. This is a fatal
error, because failing to verify packages is a perferable default over
potentially installing compromised ones. If failing to verify your software
package is ok to you, then you may disable verification by adding
verify_failure_ok 'On'; to your Fetchwarefile. See perldoc App::Fetchware.
EOD


###BUGALERT###    # Use Crypt::OpenPGP if its installed.
###BUGALERT###    if (eval {use Crypt::OpenPGP}) {
##DOESNTWORK??        # Build a pubring needed for verify.
##DOESNTWORK??        my $pubring = Crypt::OpenPGP::KeyRing->new();
##DOESNTWORK??        my $secring = Crypt::OpenPGP::KeyRing->new();
##DOESNTWORK??
##DOESNTWORK??        # Turn on gpg compatibility just in case its needed.
##DOESNTWORK??        my $pgp = Crypt::OpenPGP->new(
##DOESNTWORK??            Compat     => 'GnuPG',
##DOESNTWORK??            PubRing => $pubring,
##DOESNTWORK??            SecRing => $secring,
##DOESNTWORK??            # Automatically download public keys as needed.
##DOESNTWORK??            AutoKeyRetrieve => 1,
##DOESNTWORK??            # Use this keyserver to download them from.
##DOESNTWORK??            KeyServer => 'pool.sks-keyservers.net',
##DOESNTWORK??        );
##DOESNTWORK??
##DOESNTWORK??        # Verify the downloaded file.
##DOESNTWORK??        my $retval = $pgp->verify(SigFile => $sig_file, Files => $CONFIG{PackagePath});
##DOESNTWORK??        if ($retval == 0) {
##DOESNTWORK??            warn "Crypt::OpenPGP failed due to invalid signature.";
##DOESNTWORK??            # return failure, because Fetchware failed to verify the downloaded
##DOESNTWORK??            # file.
##DOESNTWORK??            return undef;
##DOESNTWORK??        } elsif ($retval) {
##DOESNTWORK??            return 'Package verified';
##DOESNTWORK??        } else {
##DOESNTWORK??            # print warning about $pgp errstr message.
##DOESNTWORK??            my $errstr = $pgp->errstr();
##DOESNTWORK??            warn "Crypt::OpenPGP failed with message: [$errstr]";
##DOESNTWORK??            # return failure, because Fetchware failed to verify the downloaded
##DOESNTWORK??            # file.
##DOESNTWORK??            return undef;
##DOESNTWORK??        }
###BUGALERT###    } else {
###BUGALERT###        ###BUGALERT### eval the run_prog()'s below & add better error reporting in
###BUGALERT###        ###BUGALERT### if Crypt::OpenPGP works ok remove gpg support & this if &
        #IPC::System::Simple dependency.
        #my standard format.
        # Use automatic key retrieval & a cool pool of keyservers
        ###BUGALERT## Give Crypt::OpenPGP another try with
        #pool.sks-keyservers.net
        ###BUGALERT### Should I cache the files gpg puts in its "homedir"? They
        #are the public keys that verify this fetchware package. Or should they
        #always be downloaded on demand as they are now??? But if verify() can
        #have keys cached inside the fetchware package does that mean that I
        #should open up this as an API for fetchware extensions????? I don't
        #know. I'll have to think more about this issue.
        #run_prog('gpg', '--keyserver', 'pool.sks-keyservers.net',
        #    '--keyserver-options', 'auto-key-retrieve=1',
        #    '--homedir', '.',  "$sig_file");

        # Verify sig.
        run_prog('gpg', @gpg_options, '--verify', "$sig_file");
###BUGALERT###    }

    # Return true indicating the package was verified.
    return 'Package Verified';
}


=head3 sha1_verify()

    'Package verified' = sha1_verify($download_path, $package_path);
    undef = sha1_verify($download_path, $package_path);

Verifies the downloaded software archive's integrity using the SHA Digest
specified by the C<sha_url 'ftp://sha.url/package.sha'> config option. Returns
true for sucess dies on error.

=over
=item SECURITY NOTE
If an attacker cracks a mirror and modifies a software package, they can also
modify the MD5 sum of that software package on that B<same mirror>. Because of
this limitation MD5 sums can only tell you if the software package was corrupted
while downloading. This can actually happen as I've had it happen to me once.

If your stuck with using MD5 sum, because your software package does not provide
gpg signing, I recommend that you download your SHA1 sums (and MD5 sums) from
your software package's master mirror. For example, Apache provides MD5 and SHA1
sums, but it does not mirror them--you must download them directly from Apache's
servers. To do this specify a C<sha1_url 'master.mirror/package.sha1';> in your
Fetchwarefile.

=back

=cut 

sub sha1_verify {
    my ($download_path, $package_path) = @_;

    return digest_verify('SHA-1', $download_path, $package_path);
}


=head3 md5_verify()

    'Package verified' = md5_verify($download_path, $package_path);
    undef = md5_verify($download_path, $package_path);

Verifies the downloaded software archive's integrity using the MD5 Digest
specified by the C<md5_url 'ftp://sha.url/package.sha'> config option. Returns
true for sucess and dies on error.

=over
=item SECURITY NOTE
If an attacker cracks a mirror and modifies a software package, they can also
modify the MD5 sum of that software package on that B<same mirror>. Because of
this limitation MD5 sums can only tell you if the software package was corrupted
while downloading. This can actually happen as I've had it happen to me once.

If your stuck with using MD5 sum, because your software package does not provide
gpg signing, I recommend that you download your MD5 sums (and SHA1 sums) from
your software package's master mirror. For example, Apache provides MD5 and SHA1
sums, but it does not mirror them--you must download them directly from Apache's
servers. To do this specify a C<md5_url 'master.mirror/package.md5';> in your
Fetchwarefile.

=back

=cut 

sub md5_verify {
    my ($download_path, $package_path) = @_;

    return digest_verify('MD5', $download_path, $package_path);
}


=head3 digest_verify()

    'Package verified' = digest_verify($digest_type, $download_path, $package_path);
    undef = digest_verify($digest_type, $download_path, $package_path);

Verifies the downloaded software archive's integrity using the specified
$digest_type, which also determines the
C<"$digest_type_url" 'ftp://sha.url/package.sha'> config option. Returns
true for sucess and returns false for failure.

=over
=item OVERRIDE NOTE
If you need to override verify() in your Fetchwarefile to change the type of
digest used, you can do this easily, because digest_verify() uses L<Digest>,
which supports a number of Digest::* modules of different Digest algorithms.
Simply do this by override verify() to call 
C<digest_verify('Digest's name for your Digest::* algorithm');>

=back

=over
=item SECURITY NOTE
If an attacker cracks a mirror and modifies a software package, they can also
modify the $digest_type sum of that software package on that B<same mirror>.
Because of this limitation $digest_type sums can only tell you if the software
package was corrupted while downloading. This can actually happen as I've had
it happen to me once.

If your stuck with using $digest_type sum, because your software package does
not provide gpg signing, I recommend that you download your $digest_type sums
(and SHA1 sums) from your software package's master mirror. For example, Apache
provides MD5 and SHA1 sums, but it does not mirror them--you must download them
directly from Apache's servers. To do this specify a
C<$digest_type_url 'master.mirror/package.$digest_type';>' in your Fetchwarefile.

=back

=cut 

sub digest_verify {
    my ($digest_type, $download_path, $package_path) = @_;

    # Turn SHA-1 into sha1 & MD5 into md5.
    my $digest_ext = $digest_type;
    $digest_ext = lc $digest_type;
    $digest_ext =~ s/-//g;
##subify get_sha_sum()
    my $digest_file;
    # Obtain a sha sum file.
    if (defined config("${digest_ext}_url")) {
        # Save old lookup_url and restore later like Perl's crazy local does.
        my $old_lookup_url = config('lookup_url');
        config_replace(lookup_url => config("${digest_ext}_url"));
        ###BUGALERT### This is crap! Rip lookup()'s fetchware out, and have this
        #subroutine call a new library function instead!
        ###BUGALERT### the package fetchware; crap is not needed after the great
        #override refactor. Or is it???
        package fetchware; # Pretend to be bin/fetchware.
        my $lookuped_download_path = lookup();
        package App::Fetchware; # Switch back.
        # Should I implement config_local() :)
        config_replace(lookup_url => $old_lookup_url);
        my ($scheme, $auth, undef, undef, undef) =
            uri_split(config("${digest_ext}_url"));
        my $digest_url =
            uri_join($scheme, $auth, $lookuped_download_path, undef, undef);
        msg "Downloading $digest_ext digest using [$digest_url.$digest_ext]";
        $digest_file =
            no_mirror_download_file("$digest_url.$digest_ext");
    } else {
        eval {
            my (undef, undef, $path, undef, undef) = uri_split($download_path);
            my ($scheme, $auth, undef, undef, undef) =
                uri_split(config('lookup_url'));
            my $digest_url = uri_join($scheme, $auth, $path, undef, undef);
            msg "Downloading $digest_ext digest using [$digest_url.$digest_ext]";
            $digest_file = no_mirror_download_file("$digest_url.$digest_ext");
        };
        if ($@) {
            die <<EOD;
App-Fetchware: Fetchware was unable to download the $digest_type sum it needs to
download to properly verify you software package. This is a fatal error, because
failing to verify packages is a perferable default over potentially installin
compromised ones. If failing to verify your software package is ok to you, then
you may disable verification by adding verify_failure_ok 'On'; to your
Fetchwarefile. See perldoc App::Fetchware.
EOD
        }
    }
    
###BUGALERT###subify calc_sum()
    # Open the downloaded software archive for reading.
    my $package_fh = safe_open($package_path, <<EOD);
App-Fetchware: run-time error. Fetchware failed to open the file it downloaded
while trying to read it in order to check its MD5 sum. The file was
[$package_path]. See perldoc App::Fetchware.
EOD

    # Do Digest type checking myself, because until Digest.pm 1.17,
    # Digest->new() could run any Perl code you specify or a user does causing
    # the security hole. Instead of use Digest 1.17, just avoid it altogether.
    my $digest;
    if ($digest_type eq 'MD5') {
        $digest = Digest::MD5->new();
    } elsif ($digest_type eq 'SHA-1') {
        $digest = Digest::SHA->new();
    } else {
        die <<EOD;
EOD
    }

    # Digest requires the filehandle to have binmode set.
    binmode $package_fh;

    my $calculated_digest;
    eval {
        # Add the file for digesting.
        $digest->addfile($package_fh);
        # Actually digest it.
        $calculated_digest = $digest->hexdigest();
    };
    if ($@) {
        die <<EOD;
App-Fetchware: run-time error. Digest::$digest_type croak()ed an error [$@].
See perldoc App::Fetchware.
EOD
    }

    close $package_fh or die <<EOD;
App-Fetchware: run-time error Fetchware failed to close the file
[$package_path] after opening it for reading. See perldoc App::Fetchware.
EOD

###subify compare_sums();
    # Open the downloaded software archive for reading.
    my $digest_fh = safe_open($digest_file, <<EOD);
App-Fetchware: run-time error. Fetchware failed to open the $digest_type file it
downloaded while trying to read it in order to check its $digest_type sum. The file was
[$digest_file]. See perldoc App::Fetchware.
EOD
    # Will only check the first md5sum it finds.
    while (<$digest_fh>) {
        next if /^\s+$/; # skip whitespace only lines just in case.
        my @fields = split ' '; # Defaults to $_, which is filled in by <>

        if ($fields[0] eq $calculated_digest) {
            return 'Package verified';
        # Sometimes a = is appended to make it 32bits.
        } elsif ("$fields[0]=" eq $calculated_digest) {
            return 'Package verified';
        }
    }
    close $digest_fh;

    # Return failure, because fetchware failed to verify by md5sum
    return undef;
}



=head2 unarchive()

    my $build_path = unarchive($package_path)

=over

=item Configuration subroutines used:

=over

=item none

=back

=back

Uses L<Archive::Tar> or L<Archive::Zip> to turn .tar.{gz,bz2,xz} or .zip into a
directory. Is intelligent enough to warn if the archive being unarchived does
not contain B<all> of its files in a single directory like nearly all software
packages do. Uses $package_path as the archive to unarchive, and returns
$build_path.

=over

=item LIMITATIONS
Depends on Archive::Extract, so it is stuck with Archive::Extract's limitations.

Archive::Extract prevents fetchware from checking if there is an absolute path
in the archive, and throwing a fatal error, because Archive::Extract B<only>
extracts files it gives you B<zero> chance of listing them except after you
already extract them.

=back

=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

Under drop_privs() unarchive() is executed in the child with reduced privileges.

=back

=back

=cut

sub unarchive {
    my $package_path = shift;

    msg "Unarchiving the downloaded package [$package_path]";


    my ($format, $files) = list_files($package_path);
    
    { # Encloseing block for $", which prints a \n between each array element.
    local $" = "\n";
    vmsg <<EOM;
Files are: 
[
@$files
]
EOM
    } # Enclosing block for $"

    # Ensure no files starting with an absolute path get extracted
    # And determine $build_path.
    my $build_path = check_archive_files($files);

    vmsg "Unarchiving $format archive [$package_path].";
    unarchive_package($format, $package_path);
    
    msg "Determined build path to be [$build_path]";
    return $build_path;
}


=head2 unarchive() API REFERENCE

The subroutine below are used by unarchive() to provide the unarchive
functionality for fetchware. If you have overridden the unarchive() handler, you
may want to use some of these subroutines so that you don't have to copy and
paste anything from unarchive().

App::Fetchware is B<not> object-oriented; therefore, you B<can not> subclass
App::Fetchware to extend it! 

=cut



=head3 list_files()

    # Remember $files is a array ref not a regular old scalar.
    my $files = list_files($package_path;

list_files() takes $package_path as an argument to a tar'ed and compressed
package or to a zip package, and calls C<list_files_{tar,zip}()> accordingly.
C<list_files_{tar,zip}()> in turn uses either Archive::Tar or Archive::Zip to
list all of the files in the archive and return a arrayref to that list.

=cut

sub list_files {
    my $package_path = shift;

    # List files based on archive format.
    my @files;
    my $format;
    given ($package_path) {
        when(/\.(t(gz|bz|xz|Z))|(tar\.(gz|bz2|xz|Z))|.fpkg$/) {
            $format = 'tar';
            vmsg <<EOM;
Listing files in your tar format archive [$package_path].
EOM
            @files = list_files_tar($package_path); 
        } when (/\.zip$/) {
            $format = 'zip';
            vmsg <<EOM;
Listing files in your zip format archive [$package_path].
EOM
            @files = list_files_zip($package_path); 
        } default {
            die <<EOD;
App-Fetchware: Fetchware failed to determine what type of archive your
downloaded package is [$package_path]. Fetchware only supports zip and tar
format archives.
EOD
        }
    }

    # return a reference, because @files could perhaps be a few thousand
    # elements long.
    # unarchive_package() needs $format, so return that too.
    return $format, \@files;
}


=head3 list_files_tar()

    my $tar_file_listing = list_files_tar($path_to_tar_archive);

Returns a list of file names that are found in the given, $path_to_tar_archive,
tar file. Throws an exception if there is an error.

=cut

sub list_files_tar {
    my $path_to_tar_archive = shift;

    my $tar = Archive::Tar->new($path_to_tar_archive);
    die <<EOD unless $tar->isa('Archive::Tar');
App-Fetchware: fetchware failed to create a new Archive::Tar object, and read
the contents of your archive [$path_to_tar_archive] into memory. The
Archive::Tar error message was [@{[Archive::Tar->error()]}].
EOD

    # Use list_files() method to return a list of files.
    # Pass in the weird special case of the 'name' inside an array ref to tell
    # list_files() to return just a list of file names instead of a list of
    # hashrefs.
    return $tar->list_files(['name']);
}


{ # Begin %zip_error_codes hash.
my %zip_error_codes = (
    AZ_OK => 'Everything is fine.',
    AZ_STREAM_END => 
        'The read stream (or central directory) ended normally.',
    AZ_ERROR => 'There was some generic kind of error.',
    AZ_FORMAT_ERROR => 'There is a format error in a ZIP file being read.',
    AZ_IO_ERROR => 'There was an IO error'
);


=head3 list_files_zip()

    my $zip_file_listing = list_files_zip($path_to_zip_archive);

Returns a list of file names that are found in the given, $path_to_zip_archive,
zip file. Throws an exception if there is an error.

=cut

sub list_files_zip {
    my $path_to_zip_archive = shift;

    my $zip = Archive::Zip->new();

    my $zip_error;
    if(($zip_error = $zip->read($path_to_zip_archive)) ne AZ_OK) {
        die <<EOD;
App-Fetchware: Fetchware failed to read in the zip file [$path_to_zip_archive].
The zip error message was [$zip_error_codes{$zip_error}].
EOD
    }

    # List the zip files "members," which are annoying classes not just a list
    # of file names. I could use the memberNames() method, but that method
    # returns their "internal" names, but I want their external names, what
    # their names will be on your file system.
    my @members = $zip->members();

    my @external_filenames;
    for my $member (@members) {
        push @external_filenames, $member->fileName();
    }

    # Return list of "external" filenames.
    return @external_filenames;
}


=head3 unarchive_package()

    unarchive_package($format, $package_path)

unarchive_package() unarchive's the $package_path based on the type of $format
the package is. $format is determined and returned by list_archive(). The
currently supported types are C<tar> and C<zip>. Nothing is returned, but
C<unarchive_{tar,zip}()> is used to to use Archive::Tar or Archive::Zip to
unarchive the specified $package_path.

=cut

sub unarchive_package {
    my ($format, $package_path) = @_;

    unarchive_tar($package_path) if $format eq 'tar';
    unarchive_zip($package_path) if $format eq 'zip';
}


=head3 unarchive_tar()

    my @extracted_files = unarchive_tar($path_to_tar_archive);

Extracts the given $path_to_tar_archive. It must be a tar archive. Use
unarchive_zip() for zip archives. It returns a list of files that it
extracted.

=cut

sub unarchive_tar {
    my $path_to_tar_archive = shift;

    my @extracted_files = Archive::Tar->extract_archive($path_to_tar_archive);
    # extract_archive() returns false if the extraction failed, which will
    # create an array with one false element, so I have test if tha one element
    # is false not something like if (@extracted_files), because if
    # extract_archive() returns undef on failure not empty list.
    unless ($extracted_files[0]) {
        die <<EOD;
App-Fetchware: Fetchware failed to extract your archive [$path_to_tar_archive].
The error message from Archive::Tar was [@{[Archive::Tar->error()]}].
EOD
    } else {
        return @extracted_files;
    }
}


=head3 unarchive_zip()

    'Extraced files successfully.' = unarchive_zip($path_to_zip_archive);

Extraces the give $path_to_zip_archive. It must be a zip archive. Use
unarchive_tar() for tar archives. It I<only> returns true for success. It
I<does not> return a list of extracted files like unarchive_tar() does, because
Archive::Zip's extractTree() method does not.

=cut

sub unarchive_zip {
    my $path_to_zip_archive = shift;

    my $zip = Archive::Zip->new();

    my $zip_error;
    if(($zip_error = $zip->read($path_to_zip_archive)) ne AZ_OK) {
        die <<EOD;
App-Fetchware: Fetchware failed to read in the zip file [$path_to_zip_archive].
The zip error message was [$zip_error_codes{$zip_error}].
EOD
    }

    if (($zip_error = $zip->extractTree()) ne AZ_OK) {
        die <<EOD;
App-Fetchware: Fetchware failed to extract the zip file [$path_to_zip_archive].
The zip error message was [$zip_error_codes{$zip_error}].
EOD
    } else {
        return 'Extraced files successfully.';
    }
}

} # End %zip_error_codes



=head3 check_archive_files()

    my $build_path = check_archive_files($files);

Checks if all of the files in the archive are contained in one B<main>
directory, and spits out a warning if they are not. Also checks if
B<one or more> of the files is an absolute path, and if so it throws an
exception, because absolute paths could potentially overwrite important system
files messing up your computer.

=cut

sub check_archive_files {
    my $files = shift;


    # Determine if *all* files are in the same directory.
    my %dir;
    for my $path (@$files) {
        # Skip Fetchwarefiles.
        next if $path eq './Fetchwarefile';
        if (file_name_is_absolute($path)) {
            my $error = <<EOE;
App-Fetchware: run-time error. The archive you asked fetchware to download has
one or more files with an absolute path. Absolute paths in archives is
dangerous, because the files could potentially overwrite files anywhere in the
filesystem including important system files. That is why this is a fatal error
that cannot be ignored. See perldoc App::Fetchware.
Absolute path [$path].
EOE
            $error .= "[\n";
            $error .= join("\n", @$files);
            $error .= "\n]\n";
            
            die $error;
        }

        my ($volume,$directories,$file) = splitpath($path); 
        my @dirs = splitdir($directories);
        # Skip empty directories.
        next unless @dirs;

        $dir{$dirs[0]}++;
    }


    my $i = 0;
    for my $dir (keys %dir) {
        $i++;
        warn <<EOD if $i > 1;
App-Fetchware: run-time warning. The archive you asked Fetchware to download 
does *not* have *all* of its files in one and only one containing directory.
This is not a problem for fetchware, because it does all of its downloading,
unarchive, and building in a temporary directory that makes it easy to
automatically delete all of the files when fetchware is done with them. See
perldoc App::Fetchware.
EOD
    
        # Return $build_path
        my $build_path = $dir;
        return $build_path;
    }
}



=head2 build()

    'build succeeded' = build($build_path)

=over

=item Configuration subroutines used:

=over

=item prefix

=item configure_options

=item make_options

=item build_commands

=back

=back

Changes directory to $build_path, and then executes the default build
commands of C<'./configure', 'make', 'make install'> unless your Fetchwarefile
specifies some build options like C<build_commands 'exact, build, commands';>,
C<make_options '-j4';>, C<configure_options '--prefix=/usr/local';>, or
C<prefix '/usr/local'>.

=over

=item LIMITATIONS
build() like install() inteligently parses C<build_commands>, C<prefix>,
C<make_options>, and C<configure_options> by C<split()ing> on C</,\s+/>, and
then C<split()ing> again on C<' '>, and then execute them using fetchware's
built in run_prog() to properly support -q.

Also, simply executes the commands you specify or the default ones if you
specify none. Fetchware will check if the commands you specify exist and are
executable, but the kernel will do it for you and any errors will be in
fetchware's output.

=back

=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

Under drop_privs() build() is executed in the child with reduced privileges.

The $build_path it returns is very important, because the parent process will
need to know this path, which is in turn provided to install() as an argument,
and install will then chdir to $build_path.

=back

=back

=cut

sub build {
    my $build_path = shift;

    msg "Building your package in [$build_path]";

    use Cwd;
    vmsg "changing Directory to build path [$build_path]";
    chdir $build_path or die <<EOD;
App-Fetchware: run-time error. Failed to chdir to the directory fetchware
unarchived [$build_path]. See perldoc App::Fetchware.
EOD


    # If build_commands is set, then all other build config options are ignored.
    if (defined config('build_commands')) {
        vmsg 'Building your package using user specified build_commands.';
        run_star_commands(config('build_commands'));
    # Otherwise handle the other options properly.
    } elsif (
        defined config('configure_options')
        or defined config('prefix')
        or defined config('make_options')
    ) {

        # Set up configure_options and prefix, and then run ./configure.
        vmsg "Running configure with options [@{[config('configure_options')]}]";
        run_configure();

        # Next, make.
        if (defined config('make_options')) {
            vmsg 'Executing make to build your package';
            run_prog('make', config('make_options'))
        } else {
            vmsg 'Executing make to build your package';
            run_prog('make');
        }

    # Execute the default commands.
    } else {
        vmsg 'Running default build commands [./configure] and [make]';
        run_prog($_) for qw(./configure make);
    }
    
    # Return success.
    msg 'The build was successful.';
    return 'build succeeded';
}

###BUGALERT### Add a *() API REFERENCE section for each fetchware API
#subroutine, and subify the API subs that aren't yet.

=head2 build() API REFERENCE

Below are the subroutines that build() exports with its C<BUILD_OVERRIDE> export
tag. run_configure() runs C<./configure>, and is needed, because AutoTools uses
full paths in its configuration files, so if you move it to a different location
or a different machine, the paths won't match up, which will cause build and
install errors. Rerunning C<./configure> with the same options as before will
recreate the paths to get rid of the errors.  

=cut


=head3 run_star_commands()

    run_star_commands(config('*_commands'));

run_star_commands() exists to remove some crazy copy and pasting from build(),
install(), and uninstall(). They all loop over the list accessing a C<ONEARRREF>
configuration option such as C<config('build_commands')>, and then
determine what the individual star_commands are, and then run them with
run_prog().

The I<"star"> simply refers to shell globbing with the I<"star"> character C<*>
meaning "any."

=cut

sub run_star_commands {
    my @star_commands = @_;

    # Support multiple options like star_command './configure', 'make';
    # Should be called like run_star_commands(config'*_commands')), and
    # config('star_commands') returns a list of *all* star_commands.
    for my $star_command (@star_commands) {
        # If a /,\s+/ is present in a $star_command
        # To support: star_commands './configure, make';
        if ($star_command =~ /,\s*/) {
            # split on it, and run each resulting command.
            my @star_commands = split /,\s*/, $star_command;
            for my $split_star_command (@star_commands) {
                my ($cmd, @options) = split ' ', $split_star_command;
                run_prog($cmd, @options);
            }
        # Or just run the one command.
        } else {
            my ($cmd, @options) = split ' ', $star_command;
            run_prog($cmd, @options);
        }
    }
}


=head3 run_configure()

    run_configure();

Runs C<./configure> as part of build() or uninstall(), which also annoying needs
to run it.

=over
=item NOTE
run_configure() is a piece of build() that was chopped out, because uninstall()
needs to run C<./configure> too. The only reason uninstall() must do this is
because Autotools uses full paths in the Makefile it creates. Examples from
Apache are pasted below.

    top_srcdir   = /tmp/fetchware-5506-8ROnNQObhd/httpd-2.2.22
    top_builddir = /tmp/fetchware-5506-8ROnNQObhd/httpd-2.2.22
    srcdir       = /tmp/fetchware-5506-8ROnNQObhd/httpd-2.2.22
    builddir     = /tmp/fetchware-5506-8ROnNQObhd/httpd-2.2.22
    VPATH        = /tmp/fetchware-5506-8ROnNQObhd/httpd-2.2.22

Why arn't relative paths good enough for Autotools?

=back

=cut

###BUGALERT### Add an uninstall() option to instead edit the AutoTools paths
#into relative ones.

sub run_configure {
    my $configure = './configure';
    if (config('configure_options')) {
        # Support multiple options like configure_options '--prefix', '.';
        for my $configure_option (config('configure_options')) {
            $configure .= " $configure_option";
        }
    }
    
    if (config('prefix')) {
        if ($configure =~ /--prefix/) {
            die <<EOD;
App-Fetchware: run-time error. You specified both the --prefix option twice.
Once in 'prefix' and once in 'configure_options'. You may only specify prefix
once in either configure option. See perldoc App::Fetchware.
EOD
        } else {
            $configure .= " --prefix=@{[config('prefix')]}";
        }
    }
    
    # Now lets execute the modifed standard commands.
    # First ./configure.
    my ($cmd, @options) = split ' ', $configure;
    run_prog($cmd, @options);

    # Return success.
    return 'Configure successful'; 
}


=head2 install()

    'install succeeded' = install($build_path);

=over

=item Configuration subroutines used:

=over

=item install_commands

=item make_options

=item prefix

=back

=back

Executes C<make install>, which installs the specified software, or executes
whatever C<install_commands 'install, commands';> if its defined.

install() takes $build_path as its argument, because it must chdir() to this
path if fetchware drops privileges.

=over
=item LIMITATIONS
install() like build() inteligently parses C<install_commands> by C<split()ing>
on C</,\s+/>, and then C<split()ing> again on C<' '>, and then execute them
fetchware's built-in run_prog(), which supports -q.

Also, simply executes the commands you specify or the default ones if you
specify none. Fetchware will check if the commands you specify exist and are
executable, but the kernel will do it for you and any errors will be in
fetchware's output.

=back

=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

install() is run in the B<parent> process as root, because most server programs
must be installed as root. install() must be called with $build_path as its
argument, because it may need to chdir to $build_path, the same path that
build() built the package in, in order to be able to install the program.

=back

=back

=cut

sub install {
    my $build_path = shift;

    # Skip installation if the user requests it.
    if (config('no_install')) {
        msg <<EOM;
Installation skipped, because no_install is specified in your Fetchwarefile.
EOM
        return 'installation skipped!' ;
    }

    msg 'Installing your software package.';

    chdir_unless_already_at_path($build_path);

    if (defined config('install_commands')) {
        vmsg 'Installing your package using user specified commands.';
        run_star_commands(config('install_commands'));
    } else {
        if (defined config('make_options')) {
            vmsg <<EOM;
Installing package using default command [make] with user specified make options.
EOM
            run_prog('make', config('make_options'), 'install', );
        } else {
            vmsg <<EOM;
Installing package using default command [make].
EOM
            run_prog('make', 'install');
        }
    }

    msg 'Installation succeeded';
    # Return success.
    return 'install succeeded';
}


=head2 install() API REFERENCE

Below are the subroutines that install() exports with its C<INSTALL_OVERRIDE>
export tag. fillmein!!!!!!!!  

=cut


=head3 chdir_unless_already_at_path()

chdir_unless_already_at_path() takes a $path as its argument, and determines if
that path is currently part of the current processes current working directory.
If it is, then it does nothing. Buf if the given $path is not in the current
working directory, then it is chdir()'d to.

If the chdir() fails, an exception is thrown.

=cut

sub chdir_unless_already_at_path {
    my $path = shift;

    # chdir() to $path unless its already our cwd.
    # This is needed, because we'll inherit the "child's" chdir if stay_root is
    # turned on, because stay_root does *not* fork and drop privs, which
    # typicially causes the child's chdir to be "inherited" by the parent,
    # because there is no parent and there is no child due to *not* forking.
    unless ( dir(cwd())->dir_list(-1, 1) eq $path ) {
        chdir($path) or die <<EOD;
fetchware: fetchware failed to chdir to the build directory [$path]. It
needs to chdir() to this directory, so that it can finish your fetchware
command.
EOD
    vmsg "chdir()'d to the necessary path [$path].";
    }
}



=head2 uninstall()

    'uninstall succeeded' = uninstall($build_path)

=over
=item Configuration subroutines used:
=over
=item uninstall_commands

=back

=back

Cd's to $build_path, and then executes C<make uninstall>, which installs the
specified software, or executes whatever C<uninstall_commands 'uninstall, commands';>
if its defined.

=over
=item LIMITATIONS
uninstall() like install() inteligently parses C<install_commands> by C<split()ing>
on C</,\s+/>, and then C<split()ing> again on C<' '>, and then execute them
fetchware's built-in run_prog(), which supports -q.

Also, simply executes the commands you specify or the default ones if you
specify none. Fetchware will check if the commands you specify exist and are
executable, but the kernel will do it for you and any errors will be in
fetchware's output.

=back

=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

uninstall() is run in the B<parent> process as root, because most server
programs must be uninstalled as root. uninstall() must be called with
$build_path as its argument, because it may need to chdir to $build_path, the
same path that build() built the package in, in order to be able to uninstall
the program.

=back

=back

=cut



###BUGALERT### Is uninstall() calling API subs a bug??? Should it just use the
#lower level library functions of these tools. Have it do this after I subify
#the rest of the API subs like I've done to lookup and download.
###BUGALERT### NOT TESTED!!! There is no t/App-Fetchware-uninstall.t test
#file!!! cmd_uninstall(), which uses uninstall(), is tested, but not uninstall()
#directly!!!
sub uninstall {
    my $build_path = shift;

    msg "Uninstalling package unarchived at path [$build_path]";

    chdir_unless_already_at_path($build_path);

    if (defined config('uninstall_commands')) {
        vmsg 'Uninstalling using user specified uninstall commands.';
        run_star_commands(config('uninstall_commands'));
    } else {
        # Set up configure_options and prefix, and then run ./configure, because
        # Autotools uses full paths that ./configure sets up, and these paths
        # change from install time to uninstall time.
        vmsg q{Uninstalling using AutoTool's default of make uninstall};

        vmsg q{Running AutoTool's default ./configure};
        run_configure();
        if (defined config('make_options')) {
            vmsg <<EOM;
Running AutoTool's default make uninstall with user specified make options.
EOM
            run_prog('make', config('make_options'), 'uninstall');
        } else {
            vmsg <<EOM;
Running AutoTool's default make uninstall.
EOM
            run_prog('make', 'uninstall');
        }
    }


    msg <<EOM;
Package uninstalled from system, but still installed in Fetchware's database.
EOM
    # Return success.
    return 'uninstall succeeded';
}



=head2 end()

    end();

=over
=item Configuration subroutines used:
=over
=item none

=back

=back

end() is called after all of the other main fetchware subroutines such as
lookup() are called. It's job is to cleanup after everything else. It just calls
cleanup_tempdir(), which mostly just closes the C<fetchware.sem> fetchware
semaphore file used to lock each fetchware temporary directory so C<fetchware
clean> does not delete it.

It also calls the very internal only __clear_CONFIG() subroutine that clears
App::Fetchware's internal %CONFIG variable used to hold your parsed
Fetchwarefile. 

=over

=item EXTENSION OVERRIDE NOTES

end() calls L<App::Fetchware::Util>'s cleanup_tempdir() subroutine that cleans
up the temporary directory. If your fetchware extension overrides end() or
start(), you must call cleanup_tempdir() or name your temproary directories
in a manner that fetchware clean won't find them, so something that does not
start with C<fetchware-*>.

If you fail to do this, and you use some other method to create temporary
directories that begin with C<fetchware-*>, then fetchware clean may delete your
temporary directories out from under your feet. To fix this problem:

=over

=item *

Use L<App::Fetchware::Util>'s create_tempdir() in your start() and
cleanup_tempdir() in your end().

=item *

Or, be sure not to name your temprorary directory that you create and manage
yourself to begin with C<fetchware-*>, which is the glob pattern fetchware clean
uses.

=back

=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

end() runs in the parent process similar to start(). It needs to be able to
close the lockfile that start() created so that C<fetchware clean> cannot delete
fetchware's temporary directory out from under it.

=back

=back

=back

=cut

sub end {
    # Use cleanup_tempdir() to cleanup your tempdir for us.
    cleanup_tempdir();
}



1;



=head1 SYNOPSIS


    ### App::Fetchware's use inside a Fetchwarefile.
    ### See fetchware's new command for an easy way to create Fetchwarefiles.
    use App::Fetchware;

    # Only program, lookup_url, one or more mirrors, and some method of
    # verification are required.
    program 'Your program';
    lookup_url 'http://whatevermirror.your/program/is/on';
    gpg_keys_url 'http://whatevermirror.your/program/gpg/key/url.asc';
    mirror 'http://whatevermirror1.your/program/is/on';
    mirror 'http://whatevermirror2.your/program/is/on';
    mirror 'http://whatevermirror3.your/program/is/on';
    mirror 'http://whatevermirror4.your/program/is/on';
    mirror 'http://whatevermirror5.your/program/is/on';

    # Below are some popular options that may interest you.
    make_options '-j 4';
    filter 'version-2';

    ### This is how Fetchwarefile's can replace lookup()'s or any other
    ### App::Fetchware API subroutine's default behavior.
    ### Remember your coderef must take the same parameters and return the same
    ### value.
    hook lookup => sub {
        # Callback that replaces lookup()'s behavior.
        # Callback receives the same arguments as lookup(), and is must return
        # the same number and type of arguments that lookup() returns.
        return $download_path;
    };


    ### See EXTENDING App::Fetchware WITH A MODULE for details on how to extend
    ### fetchware with a module to install software that cannot be expressed
    ### using App::Fetchware's configuration file syntax.

=cut


=head1 DESCRIPTION

App::Fetchware represents fetchware's API. For ducumentation on how to use
App::Fetchware's fetchware command line interface see L<fetchware>.

It is the heart and soul of fetchware where all of fetchware's main behaviors
are kept. It is fetchware's API, which consists of the subroutines start(),
lookup(), download(), verify(), unarchive(), build(), install(), uninstall(),
and end().


App::Fetchware stores both details about C<fetchware>'s configuration file
syntax, documents how to create a fetchware extension, and documents the
internal workings of how App::Fetchware implements C<fetchware>'s package
management behavior:

=over

=item *

For details on App::Fetchware's configuration file syntax see the section L<CREATING A App::Fetchware FETCHWAREFILE> and the section L<MANUALLY CREATING A App::Fetchware FETCHWAREFILE> for more details, and how to create one in a text editor without C<fetchware new>'s help.

=item *

If the needs of your program overcome the capabilities of App::Fetchware's configuration options, then see the section
L<FURTHER CUSTOMIZTING YOUR FETCHWAREFILE> for details on how to overcome those
limitations.

=item * 

For instructions on how to create a fetchware extension see the section
L<CREATING A FETCHWARE EXTENSION>.

=item *

For details on App::Fetchware's API that is useful for those customizing their
Fetchwarefile's and to those who are implementing a fetchware extension please
see the section L<FETCHWAREFILE API SUBROUTINES>.

=back

=cut

=head1 CREATING A App::Fetchware FETCHWAREFILE

In order to create a new fetchware package, you need to create a new
Fetchwarefile. You can easily do this with the C<fetchware new> command, which
works as follows.

=over

=item 1. This command will ask you a few questions, and use the answers you provide to create a Fetchwarefile for you.

=item 2. After it does so, it gives you a chance to edit its autogenerated Fetchwarefile manually in an editor of your choice.

=item 3. Afterwards, it will ask you if you would like to go ahead and use your newly created Fetchwarefile to install your new program as a fetchware package.  If you answer yes, the default, it will install it, but if you anwer no; instead, it will simply print out the location to the Fetchwarefile that it created for you. You can then copy that file to a location of your choice, or use that path as an option to additional fetchware commands.

=back

You can also create your Fetchwarefile manually in a text editor if you want to.
See the section L</MANUALLY CREATING A App::Fetchware FETCHWAREFILE> for the
details. Some programs require greater customization of Fetchware's behavior
than is available in its configuration options in these cases see the section
L</FURTHER CUSTOMIZTING YOUR FETCHWAREFILE> for the specific details on how to
make fetchware do what it needs to do to manage your source code distributions.

=cut


=head1 MANUALLY CREATING A App::Fetchware FETCHWAREFILE

L<fetchware> provides a L<new|fetchware/new> command that allows you to easily
create a Fetchwarefile by simply answering a bunch of simple questions. This
C<new> command even will let you manually edit the Fetchwarefile it generates
for you, so you can later customize it however you want to. Then it will ask if
you want to install it. If you answer yes, then it will install it for you, if
you answer no, it will print out the path to the newly created Fetchwarefile it
created for you. Then you can call C<fetchware install path/to/Fetchwarefile> to
install it later on. Or you can follow the instructions below and manually
create a Fetchwarefile in your text editor of choice.

=over

=item B<1. Name it>

Use your text editor to create a file with a C<.Fetchwarefile> file extension.
Use of this convention is not required, but it makes it obvious what type of
file it is. Then, just copy and paste the example text below, and replace
C<[program]> with what you choose the name of your proram to be.
C<program> is simply a configuration option that simply names your
Fetchwarefile. It is not actually used for anything other than to name your
Fetchwarefile to document what program or behavior this Fetchwarefile manages.

    use App::Fetchware;

    # [program] - explain what [program] does.
    program '[program]';

Fetchwarefiles are actually small, well structured, Perl programs that can
contain arbitrary perl code to customize fetchware's behavior, or, in most
cases, simply specify a number of fetchware or a fetchware extension's
configuration options. Below is my filled in example App::Fetchware
fetchwarefile.

    use App::Fetchware;

    # apache 2.2 - Web Server.
    program 'apache-2.2';

Notice the C<use App::Fetchware;> line at the top. That line is
absolutely critical for this Fetchwarefile to work properly, because it is what
allows fetchware to use Perl's own syntax as a nice easy to use syntax for
Fetchwarefiles. If you do not use the matching C<use App::Fetchware;> line,
then fetchware will spit out crazy errors from Perl's own compiler listing all
of the syntax errors you have. If you ever receive that error, just ensure you
have the correct C<use App::Fetchware;> line at the top of your
Fetchwarefile.

=item B<2. Determine your lookup_url>

At the heart of App::Fetchware is its C<lookup_url>, which is
the URL to the FTP or HTTP mirror you want App::Fetchware to use to obtain a
directory listing to see if a new version of your program is available for
download. To figure this out just use your browser to find the the program you
want fetchware to manage for you's Web site. Skip over the download link, and
instead look for the gpg, sha1, or md5 verify links, and copy and paste on of
those between the single quotes above in the lookup_url. Then delete the file
portion--from right to left until you reach a C</>. This is necessary, because
fetchware uses the lookup_url as a basis to download your the gpg, sha1, or md5
digital signatures or checksums to ensure that the packages fetchware downloads
and installs are exactly the same as the ones the author uploads.

    lookup_url '';

And then after you copy the url.

    lookup_url 'http://some.url/something.html';

=item B<3. Determine your filter configuration option>

The C<filter> option specifies a L<perl regex|perlretut> that is matched against
the list of the files in the directory you specify in your C<lookup_url>. This
sorts through the directory to pick out which program or even which version of
the same program you want this Fetchwarefile to manage.

This is needed, because some programs such as L<Apache|http://httpd.apache.org>
have multiple versions available at the same time, so you would need to specify
which version of apache you want to download. So, you'd specify
C<filter 'httpd-2.2';> to make fetchware download and manage Apache 2.2, or you
could specify C<filter 'httpd-2.4';> to specify the newer 2.4 series version.

This option also exists to allow fetchware to pick out our program if you
specify a mirror directory that has more than one program in it. If you do this,
then fetchware can use C<filter> to pick out the program you want to download
and install from the crowd.

Just write your perl regex in between the single quotes C<'> below. You don't
need to master regular expressions to specify this option. Just specify the name
of the program and/or the main part of the version number. B<Do not> specify the
entire version number or fetchware will never update your program properly.

    filter '';

And then after you type in the text pattern.

    filter 'httpd-2.2';

=item B<4. Add mandatory verification settings>

Verification of software downloads is mandatory, because fetchware, in order to
install the software that is downloaded, must execute the build and installation
scripts on your computer sometimes even as the root administrator! Therefore,
fetchware will refuse to build and install any software package that cannot be
verified. This limitation can be bypassed by setting the C<verify_failure_ok>
configuration option to true, but his is B<not> recommended.

Instead, if standard verification fails, please set up one or more of the
configuration options below that may allow verification to fail if the author
has his download site set up differently then fetchware expects.

=over

=item gpg_keys_url - Should list a URL to a file most likely named C<KEYS> that
contains versions of the author's gpg verification keys that is suitable to be
imported into gpg using C<gpg --import [name of file]>. An example would be:

    gpg_keys_url 'http://www.apache.org/dist/httpd/KEYS';

=item users_keyring - Tells fetchware to use the user who calls fetchware's gpg
keyring instead of fetchware's own keyring. This is handy for when you want to
install a program, but the author has no easily accessible C<KEYS> file, but the
author has listed his gpg key on his Website. With this option, you can import
this key into your own keyring using C<gpg --import [name of file]>, and then
specify this option in your Fetchwarefile as shown below.

    users_keyring 'On';

=item gpg_sig_url - Should list a URL to a directory (not a file) that has files
with the same names as the software archives that contain your program, but with
a C<.asc>, C<.sig>, or C<.sign> file extension. An example would be:

    gpg_sig_url 'http://www.apache.org/dist/httpd/';

=item sha1_url - Should list a URL to a directory (not a file) that has files
with the same names as the software archives that contain your program, but with
a C<.sha> or C<.sha1> file extension. An example would be:

    sha1_url 'http://www.apache.org/dist/httpd/';

=item md5_url - Should list a URL to a directory (not a file) that has files
with the same names as the software archives that contain your program, but with
a C<.md5> file extension. An example would be:

    md5_url 'http://www.apache.org/dist/httpd/';

=item NOTICE: There is no configuration option to change what filename fetchware
uses. You're stuck with its default of what fetchware determines your
$download_path to be with the appropriate C<.asc>, C<sha1>, or C<.md5> added
to it.  

=back

Just copy and paste the example below replacing C<[new_directive]> with the name
of the new directive you would like to add, and fill in the space between the
single quotes C<'>.

    [new_directive] '';

After pasting it should look like.

    [new_directive] '~/wallpapers';

=item B<5. Specify at least one mirror>

Because fetchware's C<lookup_url> B<must> be the author's main mirror instead of
a 3rd party mirror for verification purposes, you must also add a mirror option
that specifies one 3rd party mirror. I recommend picking one near your physical
geographical location or at least in your own country or one close by.

C<mirror> can be specified more than once, you you can have more than one
mirror. An example is below.

    mirror 'http://apache.mesi.com.ar//httpd/';
    mirror 'http://apache.osuosl.org//httpd/';
    mirror 'ftp://apache.mirrors.pair.com//httpd/';
    mirror 'http://mirrors.sonic.net/apache//httpd/';
    mirror 'http://apache.mirrors.lucidnetworks.net//';

You can specify as many mirrors as you want to. You could perhaps include all
the mirrors your source code distribution has.

=item B<6. Specifiy other options>

That's all there is to it unless you need to further customize App::Fetchware's
behavior to modify how your program is installed.

At this point you can install your new Fetchwarefile as a fetchware package
with:

    fetchware install [path to your new fetchwarefile]

Or you can futher customize it as shown next.

=item B<7. Optionally add build and install settings>

If you want to specify further settings the first to choose from are the
build and install settings. These settings control how fetchware builds and
installs your software. They are briefly listed below. For further details see
the section L<App::Fetchware FETCHWAREFILE CONFIGURATION OPTIONS>.

=over

=item B<temp_dir> - Specifies the temporary directory fetchware will use to create its own working temporary directory where it downloads, unarchives, builds, and then installs your program from a directory inside this directory.

=item B<user> - (UNIX only) - Specifies a non-root user to drop privileges to when downloading, verifying, unarchive, and building your program. Root priveedges are kept in the parent process for install if needed.

=item B<prefix> - Specifies the --prefix option for AutoTools (./configure) based programs.

=item B<configure_options> - Specifies any additional options that fetchware should give to AutoTools when it runs ./configure to configure your program before it is built and installed.

=item B<make_options> - Specifies any command line options you would like to provide to make when make is run to build and install your software. C<-j 4> is quite popular to do a paralled make to build and install the program faster.

=item B<build_commands> - Specifies a list of commands that fetchware will use to build your program. You only need this option if your program uses a build system other than AutoTools such as C<cmake> or perhaps a custom one like Perl's C<Configure>

=item B<install_commands> - Specifies a list of commands that fetchware will use to install your program. You only need this option if your program uses a build system other than AutoTools such as C<cmake> or perhaps a custom one like Perl's C<Configure>

=item B<uninstall_commands> - Specifies a list of commands that fetchware will
use to I<uninstall> your program. You only need this option if your source code
distribution does not provide a C<make uninstall> target, which not every source
code distribution does.

=item B<no_install> - Specifies a boolean (true or false) value to turn off fetchware installing the software it has downloaded, verified, unarchvied, and built. If you specify a true argument (1 or 'True' or 'On'), then fetchware will C<not> install your program; instead, it will leave its temporary directory intact, and print out the path of this directory for you to inspect and install yourself. If you don't specify this argument, comment it out, or provide a false argument (0 or 'False' or 'Off'), then fetchware C<will> install your program.

=back

Just copy and paste the example below replacing C<[new_directive]> with the name
of the new directive you would like to add, and fill in the space between the
single quotes C<'>.

    [new_directive] '';

After pasting it should look like.

    [new_directive] '~/wallpapers';

=cut


=head1 USING YOUR App::Fetchware FETCHWAREFILE WITH FETCHWARE

After you have
L<created your Fetchwarefile|/"MANUALLY CREATING A App::Fetchware FETCHWAREFILE">
as shown above you need to actually use the fetchware command line program to
install, upgrade, or uninstall your App::Fetchware Fetchwarefile.

=over

=item B<install>

A C<fetchware install [path/to/Fetchwarefile]> while using a App::Fetchware
Fetchwarefile causes fetchware to install your fetchwarefile to your computer
as you have specified any build or install options.

=item B<upgrade>

A C<fetchware upgrade [installed program name]> while using a App::Fetchware
Fetchwarefile will simply run the same thing as install all over again, which 
ill upgrade your program if a new version is available.

=item B<uninstall>

A C<fetchware uninstall [installed program name]> will cause fetchware to run
the command C<make uninstall>, or run the commands specified by the
C<uninstall_commands> configuration option. C<make uninstall> is only available
from some programs that use AutoTools such as ctags, but apache, for example,
also uses AutoTools, but does not provide a uninstall make target. Apache for
example, therefore, cannot be uninstalled by fetchware automatically.

=item B<upgrade-all>

A C<fetchware upgrade-all> will cause fetchware to run C<fetchware upgrade> for
all installed packages that fetchware is tracking in its internal fetchware
database. This command can be used to have fetchware upgrade all currently
installed programs that fetchware installed.

=back

=cut


=head1 App::Fetchware'S FETCHWAREFILE CONFIGURATION OPTIONS

App::Fetchware has many configuration options. Most were briefly described in
the section L<MANUALLY CREATING A App::Fetchware FETCHWAREFILE>. All of them are
detailed below.

=head2 program 'Program Name';

C<program> simply gives this Fetchwarefile a name. It is availabe to fetchware
after parsing your Fetchwarefile, and is used to name your Fetchwarefile when
using C<fetchware new>. It is required just like C<lookup_url>, C<mirror>,
perhaps C<filter>, and some method to verify downloads are.

=head2 filter 'perl regex here';

Specifies a Perl regular expression that fetchware uses when it determines what
the latest version of a program is. It simply compares each file in the
directory listing specified in your C<lookup_url> to this regular expression,
and only matching files are allowed to pass through to the next part of
fetchware that looks for source code archives to download.

See L<perlretut> for details on how to use and create Perl regular expressions;
however, actual regex know how is not really needed just paste verbatim text
between the single quotes C<'>. For example, C<filter 'httpd-2.2';> will cause
fetchware to only download Apache 2.2 instead of the version for Windows or
whatever is in the weird httpd-deps-* package.

=head2 temp_dir '/tmp';

C<temp_dir> tells fetchware where to store fetchware's temporary working
directory that it uses to download, verify, unarchive, build, and install your
software. By default it uses your system temp directory, which is whatever
directory L<File::Temp's> tempdir() decides to use, which is whatever
L<File::Spec>'s tmpdir() decides to use.

=head2 fetchware_db_path '~/.fetchwaredb';

C<fetchware_db_path> tells fetchware to use a different directory other
than its default directory to store the installed fetchware package for the
particular fetchware package that this option is specified in your
Fetchwarefile. Fetchware's default is C</var/log/fetchware> on Unix when run as
root, and something like C</home/[username]/.local/share/Perl/dist/fetchware/>
when run nonroot.

This option is B<not> recommended unless you only want to change it for just one
fetchware package, because fetchware also consults the
C<FETCHWARE_DATABASE_PATH> environment variable that you should set in your
shell startup files if you want to change this globally for all of your
fetchware packages. For sh/bash like shells use:

    export FETCHWARE_DATABASE_PATH='/your/path/here'

=head2 user 'nobody';

Tells fetchware what user it should drop privileges to. The default is
C<nobody>, but you can specify a different username with this configuration
option if you would like to.

Dropping privileges allows fetchware to avoid downloading files and executing
anything inside the downloaded archive as root. Except of course the commands
needed to install the software, which will still need root to able to write
to system directories. This improves security, because the downloaded software
won't have sytem privileges until after it is verified, prooviing that what you
downloaded is exactly what the author uploaded.

Note this only works for unix like systems, and is not used on Windows and
other non-unix systems.

Also note, that if you are running fetchware on Unix even if you do not specify
the C<user> configuration option to configure what user you will drop privileges
to, fetchware will still drop privileges using the ubiquitous C<nobody> user.
If you do B<not> want to drop privileges, then you must use the C<stay_root>
configuration option as described below.

=head2 stay_root 'On';

Tells fetchware to B<not> drop privileges. Dropping privileges when run as root
is fetchware's default behavior. It improves security, and allows fetchware to
avoid exposing the root account by downloading files as root. Instead,
everything but the API functions install(), which installs your program, and
end(), which deletes fetchware's temporary directory, runs as C<nobody> or
whatever C<user> option you provide. 

Do B<not> use this feature unless you are absolutely sure you need it.

=over

=item SECURITY NOTICE

stay_root, when turned on, causes fetchware to not drop privileges when
fetchware looks up, downloads, verifies, and builds your program. Instead,
fetchware will stay root through the entire build cycle, which needlessly
exposes the root account when downloading files from the internet. These files
may come from trusted mirrors, but mirrors can, and do get cracked:

L<http://www.itworld.com/security/322169/piwik-software-installer-rigged-back-door-following-website-compromise?page=0,0>

L<http://www.networkworld.com/news/2012/092612-compromised-sourceforge-mirror-distributes-backdoored-262815.html>

L<http://www.csoonline.com/article/685037/wordpress-warns-server-admins-of-trojans>

L<http://www.computerworld.com/s/article/9233822/Hackers_break_into_two_FreeBSD_Project_servers_using_stolen_SSH_keys>

=back

=head2 lookup_url 'ftp://somedomain.com/some/path

This configuration option specifies a url of a FTP or HTTP or local (file://)
directory listing that fetchware can download, and use to determine what actual
file to download and perhaps also what version of that program to download if
more than one version is available as some mirrors delete old versions and only
keep the latest one.

This url is used for:

=over

=item 1. To determine what the actual download url is for the latest version of this program

=item 2. As the base url to also download a cryptographic signature (ends in .asc) or a SHA-1 or MD5 signature to verify the contents match what the SHA-1 or MD5 checksum is.

=back

You can use the C<mirror> configuration option to specify additional mirrors.
However, those mirrors will only be used to download the large software
archives. Only the lookup_url will be used to download directory listings to
check for new versions, and to download digital signatures or checksums to
verify downloads.

=head2 lookup_method 'timestamp';

Fetchware has two algorithms it uses to determine what version of your program
to download:

=over

=item timestamp

The timestamp algorithm simply uses the mtime (last modification time) that is
availabe in FTP and HTTP directory listings to determine what file in the
directory is the newest. C<timestamp> is also the default option, and is the one
used if C<lookup_method> is not specified.

=item versionstring

Versionstring parses out the version numbers that each downloadable program has,
and uses them to determine the downloadable archive with the highest version
number, which should also be the newest and best version of the archive to use.

=back

=head2 gpg_keys_url 'lookup_url.com/some/path';

Specifies a file not a directory URL for a C<KEYS> file that lists all of the
authors' gpg keys for fetchware to download and import before using them to
verify the downloaded software package. 

If you come accross a software package whoose author uses gpg to sign his
software packages, but he does not include it in the form of a file on his main
mirror, then you can specify the C<user_keyring> option. This option forces
fetchware to use the user who runs fetchware's keyring instead of fetchware's
own keyring. This way you can then import the author's key into your own
keyring, and have fetchware use that keyring that already has the author's key
in it to verify your downloads.

=head2 user_keyring 'On';

When enabled fetchware will use the user who runs fetchware's keyring instead of
fetchware's own keyring. Fetchware uses its own keyring to avoid adding cruft to
your own keyring.

This is needed when the author of a software package does not maintain a KEYS
file that can easily be downloaded and imported into gpg. This option allows you
to import the author's key manually into your own gpg keyring, and then
fetchware will use your own keyring instead of its own to verify your downloads.

=head2 gpg_sig_url 'mirror.com/some/path';

Specifies an alternate url to use to download the cryptographic signature that
goes with your program. This is usually a file with the same name as the
download url with a C<.asc> file extension added on. Fetchware will also append
the extensions C<sig> and C<sign> if C<.asc> is not found, because some pgp
programs and author use these extensions too.

=head2 sha1_url 'mastermirror.com/some/path';

Specifies an alternate url to download the SHA-1 checksum. This checksum is used
to verify the integrity of the archive that fetchware downloads.

You B<must> specify the master mirror site, which is your programs main mirror
site, because if you download it from a mirror, its possible that both the
archive and the checksum could have been tampered with.

=head2 md5_url 'mastermirror.com/some/path';

Specifies an alternate url to download the MD5 checksum. This checksum is used
to verify the integrity of the archive that fetchware downloads.

You B<must> specify the master mirror site, which is your programs main mirror
site, because if you download it from a mirror, its possible that both the
archive and the checksum could have been tampered with.

=head2 verify_method 'gpg';

Chooses a method to verify your program. The default is to try C<gpg>, then
C<sha1>, and finally C<md5>, and if all three fail, then the default is to exit
fetchware with an error message, because it is insecure to install archives that
cannot be verified. The availabel options are:

=over

=item gpg - Uses the gpg program to cryptographically verify that the program you downloaded is exactly the same as its author uploaded it.

=item sha1 - Uses the SHA-1 hash function to verify the integrity of the download. This is much less secure than gpg.

=item sha1 - Uses the MD5 hash function to verify the integrity of the download. This is much less secure than gpg.

=back

=head2 verify_failure_ok 'True';

Fetchware's default regarding failing to verify your downloaded Archive with
gpg, sha1, or md5 is to exit with an error message, because installing software
that cannot be cryptographically verified should never be done.


=over

=item SECURITY NOTICE


However, if the author of a program you want to use fetchware to manage for you
does not offer a gpg, sha1, or md5 file to verify its integrity, then you can
use this option to force Fetchware to install this program anyway. However, do
not enable this option lightly. Please scour the program's mirrors and homepage
to see which C<gpg_sig_url>, C<sha1_url>, or C<md5_url> you can use to ensure
that your archive is verified before it is compiled and installed. Even mirrors
from sites large and small get hacked regularly:

L<http://www.itworld.com/security/322169/piwik-software-installer-rigged-back-door-following-website-compromise?page=0,0>

L<http://www.networkworld.com/news/2012/092612-compromised-sourceforge-mirror-distributes-backdoored-262815.html>

L<http://www.csoonline.com/article/685037/wordpress-warns-server-admins-of-trojans>

L<http://www.computerworld.com/s/article/9233822/Hackers_break_into_two_FreeBSD_Project_servers_using_stolen_SSH_keys>

So, Please give searching for a C<gpg_sig_url>, C<sha1_url>, or C<md5_url> for
your program another change before simply enabling this option.

=back

=over

=item NOTICE

C<verify_failure_ok> is a boolean configuration option, which just means its
values are limited to either true or false. True values are C<'True'>, C<'On'>,
C<1>, and false values are C<'False'>, C<'Off'>, and C<0>. All other values are
syntax errors.

=back

=head2 prefix '/opt/';

Controls the AutoTools C<./configuration --prefix=...> option, which allows you
to change the base directory that most software (software that uses AutoTools)
uses as the base directory for when they install themselves.

For example, most programs copy binaries to C<prefix/bin>, documentation to
C<prefix/docs>, manpages to C<prefix/man>, and so on.

=over

=item WARNING: C<prefix> only supports source code distributions that use GNU
AutoTools. These can easily be determined by the presence of certain files in
the the distributions main directory such as C<configure>, C<configure.in>, and
C<acinclude.m4>, and others. So, if your program uses a different build system
just include that system's version of AutoTools' C<--prefix> option in your
C<build_commands> configuration option.

=back

=head2 configure_options '--datadir=/var/mysql';

Provides options to AutoTools C<./configure> program that configures the source
code for building. Most programs don't need this, but some like Apache and MySQL
need lots of options to configure them properly. In order to provide multiple
options do not separate them with spaces; instead, separate them with commas and
keep single quotes C<'> around them like in the example below.

    configure_options '--datadir=/var/mysql', '--mandir=/opt/man',
        '--enable-module=example';

This option is B<not> compatible with C<build_commands>. If you use
C<build_commands>, than this option will B<not> be used.

=over

=item WARNING: C<configure_options> only supports source code distributions that use GNU
AutoTools. These can easily be determined by the presence of certain files in
the the distributions main directory such as C<configure>, C<configure.in>, and
C<acinclude.m4>, and others. So, if your program uses a different build system
just include that system's version of AutoTools' C<./configure> program in your
C<build_commands> configuration option.

=back

=head2 make_options '-j4';

This option exists mostly just to enable parallel make using the C<-j> jobs
option. But any list of options make excepts will work here too. Separate them
using commas and surround each one with single quotes C<'> like in the example
above.

=head2 build_commands './configure', 'make';

Specifies what commands fetchware will use to build your program. Building your
program includes configuring the source code to be compiled, and then the actual
compiling too. It does B<not> include installing the compiled source code. Use
C<install_commands>, which is described below, for that. Specify multiple
options just like C<configure_options> does.

The default C<build_commands> is simply to run C<./configure> followed by
C<make>.

=head2 install_commands 'make install';

This single command or perhaps list of commands will be run in the order your
specifyto install your program. You can specify multiple options just like
C<configure_options> does.

The default C<install_commands> is simply to run C<make install>.

=head2 uninstall_commands 'make uninstall';

This command or list of commands will be run instead of fetchware's default of
C<make uninstall>. Many source code distributions do not provide a C<uninstall>
make target, so they can not easily be uninstalled by fetchware without such
support. In these cases, you could look into
L<paco|http://paco.sourceforge.net/>, L<src2pkg|http://www.src2pkg.net/>, or
L<fpm|https://github.com/jordansissel/fpm>. These all aid turning a source code
distribution into your operating system's package format, or somehow magically
monitoring C<make install> to track what files are installed where, and then
using this information to be able to uninstall them.

=head2 no_install

This boolean, see below, configuration option determines if fetchware should
install your software or not install your software, but instead prints out the
path of its build directory, so that you can QA test or review the software before
you install it.

=over

=item NOTICE

C<no_install> is a boolean configuration option, which just means its
values are limited to either true or false. True values are C<'True'>, C<'On'>,
C<1>, and false values are C<'False'>, C<'Off'>, and C<0>. All other values are
syntax errors.

=back

=head2 mirror 'somemirror0.com/some/optional/path';

Your Fetchwarefile needs to have at least one mirror specified. Although you can
specify as many as you want to.

This configuration option, unlike all the others, can be specified more than
once. So, for example you could put:

    mirror 'somemirror1.com';
    mirror 'somemirror2.com';
    mirror 'somemirror3.com';
    mirror 'somemirror4.com';
    mirror 'somemirror5.com';

When fetchware downloads files or directories it will try each one of these
mirrors in order, and only fail if all attempts at all mirrors fail.

If you specify a path in addition to just the hostname, then fetchware will try
to get whatever it wants to download at that alternate path as well.

    mirror 'somemirror6./com/alternate/path';

=cut


=head1 FURTHER CUSTOMIZING YOUR FETCHWAREFILE

Because fetchware's configuration files, its Fetchwarefiles, are little Perl
programs, you have the full power of Perl at your disposal to customize
fetchware's behavior to match what you need fetchware to do to install your
source code distributions.

Not only can you use arbitrary Perl code in your Fetchwarefile to customize
fetchware for programs that don't follow most FOSS mirroring's unwritten
standards or use a totally different build system, you can also create a
fetchware extension. Creating a fetchware extension even allows you to turn your
extension into a proper CPAN distribution, and upload it to CPAN to share it
with everybody else. See the section below,
L<CREATING A FETCHWARE EXTENSION>, for full details.


=head2 How Fetchware's configuration options are made

Each configuration option is created with L<App::Fetchware::CreateConfigOptions>
This package's import() is a simple code generator that generates configuration
subroutines.  These subroutines have the same names as fetchware's configuration
options, because that is exactly what they are. Perl's
L<Prototypes|perlsub/Prototypes> are used in the code that is generated, so
that you can remove the parentheses typically required around each configuration
subroutine. This turns what looks like a function call into what could
believably be considered a configuration file syntax.

These prototypes turn:

    lookup_url('http://somemirror.com/some/path');

Into:

    lookup_url 'http://somemirror.com/some/path';

Perl's prototypes are not perfect. The single quotes and semicolon are still
required, but the lack of parens instantly makes it look much more like a
configuration file syntax, then an actual programming language.

=head2 The magic of C<use App::Fetchware;>

The real magic power behind turning a Perl program into a configuration file
sytax comes from the C<use App::Fetchware;> line. This line is single handedly
responsible for making this work. This one line imports all of the configuration
subroutines that make up fetchware's configuration file syntax. And this
mechanism is also behind fetchware's extension mechanism. (To use a
App::Fetchware extension, you just C<use> it. Like
C<use App::FetchwareX::HTMLPageSync;>. That's all there is to it. This I<other>
App::Fetchware is responsible for exporting subroutines of the same names as
those that make up App::Fetchware's API. These subroutines are listed in the
section L<FETCHWAREFILE API SUBROUTINES> as well as their helper subroutines.
See the section below L<CREATING A FETCHWARE EXTENSION> for more information on
how to create App::Fetchware extensions.

=head2 So how do I add some custom Perl code to customize my Fetchwarefile?

You use hook() to override one of fetchware's API subroutines. Then when
fetchware goes to call that subroutine, your own subroutine is called in its
place. You can hook() as many of fetchware's API subroutines as you need to.

=over

Remember your replackement subroutine B<must> take the exact same arguments, and
return the same outputs that the standard fetchware API subroutines do!

All of the things these subroutines return are later used as parameters to later
API subroutines, so failing to return a correct value may cause fetchware to
fail.

=back

=cut

=head3 hook()

    # Inside a Fetchwarefile...
    hook lookup => sub {
        # Your own custom lookup handler goes here!
    };

hook() allows you to replace fetchware's API subroutines with whatever Perl
code reference you want to. But it B<must> take the same arguments that each API
subroutine takes, and provide the same return value. See the section
L<FETCHWAREFILE API SUBROUTINES> for the details of what the API subroutine's
parameters are, and what their return values should be.

hook() should be used sparingly, and only if you really know what you're doing,
because it directly changes fetchware's behavior. It exists for cases where you
have a software package that exceeds the abilities of fetchware's configuration
options, but creating a fetchware extension for it would be crazy overkill.

=cut

sub hook ($$) {
    my ($sub_to_hook, $callback) = @_;

    die <<EOD unless App::Fetchware->can($sub_to_hook);
App-Fetchware: The subroutine [$sub_to_hook] you attempted to override does
not exist in this package. Perhaps you misspelled it, or it does not exist in
the current package.
EOD

    override $sub_to_hook => $callback;

    # Overriding the subroutine is not enough, because it is overriding it
    # inside App::Fetchware, so I need to also override the subroutine inside
    # hook()'s caller as done below.
    {
        no warnings 'redefine';
        clone($sub_to_hook => (from => 'App::Fetchware', to => caller()));
    }
}

=pod

    hook lookup => sub {
        # Your replacement for lookup() goes here.
    };

However, that is not quite right, because some of App::Fetchware's API
subroutines take important arguments and return important arguments that are
then passed to other API subroutines later on. So, your I<replacement> lookup()
B<must> take the same arguments and B<must> return the same values that the
other App::Fetchware subroutines may expect to be passed to them. So, let's fix
lookup(). Just check lookup()'s documentation to see what its arguments are and
what it returns by checking out the section L<FETCHWAREFILE API SUBROUTINES>:

    hook lookup => sub {
        # lookup does not take any arguments.
        
        # Your replacement for lookup() goes here.
        
        # Must return the same thing that the original lookup() does, so
        # download() and everything else works the same way.
        return $download_url;
    };

Some App::Fetchware API subroutines take arguments, so be sure to account for
them:

    hook download => sub {
        # Take same args as App::Fetchware's download() does.
        my $download_url = shift;
        
        # Your replacement for download() goes here.
        
        # Must return the same things as App::Fetchware's download()
        return $package_path;
    };

If changing lookup()'s behavior or one of the other App::Fetchware
subroutines, and you only want to change part of its behavior, then consider
importing one of the C<:OVERRIDE_*> export tags. These tags exist for most of the
App::Fetchware API subroutines, and are listed below along with what helper
subroutines they import with them. To check their documentation see the section 
L<FETCHWAREFILE API SUBROUTINES>.

=over

=item L<OVERRIDE_LOOKUP|lookup() API REFERENCE> - L</check_lookup_config()>,
L</get_directory_listing()>, L</parse_directory_listing()>,
L</determine_download_path()>, L</ftp_parse_filelist()>, L</http_parse_filelist()>,
L</file_parse_filelist()>, L</lookup_by_timestamp()>,
L</lookup_by_versionstring()>, L</lookup_determine_downloadpath()>

=item L<OVERRIDE_DOWNLOAD|download() API REFERENCE> -
L</determine_package_path()>

=item L<OVERRIDE_VERIFY|verify() API REFERENCE> - L</gpg_verify()>,
L</sha1_verify()>, L</md5_verify()>, L</digest_verify()>

=item L<OVERRIDE_UNARCHIVE|unarchive() API REFERENCE> -
L</check_archive_files()>, L</list_files()>, L</list_files_tar()>,
L</list_files_zip()>, L</unarchive_package()>, L</unarchive_tar()>,
L</unarchive_zip()>

=item L<OVERRIDE_BUILD|build() API REFERENCE> - L</run_star_commands()> and
L</run_configure()>.

=item L<OVERRIDE_INSTALL|install() API REFERENCE> -
L</chdir_unless_already_at_path()>.

=item OVERRIDE_UNINSTALL - uninstall() uses build()'s and install()'s API's, but
does not add any subroutines of its own..

=back

An example:

    use App::Fetchware ':OVERRIDE_LOOKUP';

    ...

    hook lookup => sub {

        ...

        # ...Download a directory listing....

        # Use same lookup alorithms that lookup() uses.
        return lookup_by_versionstring($filename_listing);
        
        # Return what lookup() needs to return.
        return $download_url;
    };

Feel free to specify a list of the specifc subroutines that you need to avoid
namespace polution, or install and use L<Sub::Import> if you demand more control
over imports.

=head2 A real example

A short, simple example fetchware extension is included with App::Fetchware
called L<App::FetchwareX::HTMLPageSync>. It simply downloads an HTML page,
parses out the links you want to download based on configuration options, and
then downloads them to a directory of your choice. It is quite brief and
compact, and does something useful. For example, I use it to keep a directory
of wallpaper listed on a Web page up to date.  

=cut

###BUGALERT### Add an section of use cases. You know explaing why you'd use
#no_install, or why'd you'd use look, or why And so on.....


=head1 CREATING A FETCHWARE EXTENSION

Fetchware's main program C<fetchware> uses App::Fetchware's short and simple API
to implement fetchware's default behavior; however, other styles of source code
distributions exist on the internet that may not fit inside App::Fetchware's
capabilities. In addition to its flexible configuration file sytax, that is why
fetchware allows modules other than App::Fetchware to provide it with its
behavior.

=head2 How the API works

When fetchware installs or upgrades something it executes the API subroutines
start(), lookup(), download(), verify(), unarchive(), build(), install(), and
end() in that order. And when fetchware uninstalls an installed package it
executes the API subroutines start(), part of build(), uninstall(), and end().


=head2 Extending App::Fetchware

This API can be overridden inside a user created Fetchwarefile by using hook()
as L<explained above|/So how do I add some custom Perl code to customize my Fetchwarefile?>.
hook() simply takes a Perl code reference that takes the same parameters, and
returns the same results that the subroutine that you've hook()ed takes and
returns.

For more extensive changes you can create a App::Fetchware module that
I<"subclasses"> App::Fetchware. Now App::Fetchware is not an object-oriented
module, so you cannot use L<parent> or L<base> to add it to your program's
inheritance tree using C<@INC>. You can, however, import whatever subroutines
from App::Fetchware that you want to reuse such as start() and end(), and then
simply implement the remaining  subroutines that make up App::Fetchware's API.
Just like the C<CODEREF> extensions mentioned above, you must take the same
arguments and return the same values that fetchware expects or using your
App::Fetchware extension will blow up in your face.

This is described in much more detail below in L<CHANGING FETCHWARE'S BEHAVIOR>.


=head2 Essential Terminology

App::Fetchware manages to behave like an object oriented module would with
regards to its extension system without actually using perl's object-oriented
features especially using @INC for subclassing, which App::Fetchware does not
use.

The same terminology as used in OOP is also used here in App::Fetchware, because
the concepts are nearly the same they're simply implemented differently.

=head3 API subroutines

These are the subroutines that App::Fetchware implements, and that fetchware
uses to implement its desired behavior. They are start(), lookup(), download(),
verify(), unarchive(), build(), install(), uninstall(), and end(). All must be
implemented in a App::Fetchware L<subclass>.

=head3 override

Means the same thing it does in object-oriented programming. Changing the
definition of a method/subroutine without changing its name. In OOP this is
simply done by subclassing something, and then defining one of the methods that
are in the superclass in the subclass. In App::Fetchware extensions this is done
by simply defining a subroutine with the same name as one or more of the API
subroutines that are defined above. There is no method resolution order and
C<@INC> is not consulted.

=head3 subclass

Means the same thing it does in object-oriented programming. Taking one class
and replacing it with another class. Only since App::Fetchware is not
object-oriented, it is implemented differently. You simply import from
App::Fetchware the L<API subroutines> that you are B<not> going to override, and
then actually implement the remaining subroutines, so that your App::Fetchware
I<subclass> has the same interface that App::Fetchware does.
L<App::Fetchware::CreateConfigOptions> is a great helper package that takes care
of the heavy lifting and specifics for you.

To create a fetchware extension you must understand how they work:

=over

=item 1. First a Fetchwarefile is created, and what module implements App:Fetchware's API is declared with a C<use App::Fetchware...;> line. This line is C<use App::Fetchware> for default Fetchwarefiles that use App::Fetchware to provide C<fetchware> with the API it needs to work properly.

=item 2. To use a fetchware extension, you simply specify the fetchware
extension you want to use with a C<use App::Fetchware...;> instead of specifying
C<use App::Fetchware> line in your Fetchwarefile. You B<must> replace the
App::Fetchware import with the extension's. Both cannot be present. Fetchware
will exit with an error if you use more than one App::Fetchware line without
specifying specific subroutines in all but one of them.

=item 3. Then when C<fetchware> parses this Fetchwarefile when you use it to install, upgrade, or uninstall something, This C<use App::Fetchware...;> line is what imports App::Fetchware's API subroutines into C<fetchware>'s namespace.

=back

That's all there is to it. That simple C<use App::Fetchware...;> imports from
App::Fetchware or a App::Fetchware extension such as
App::FetchwareX::HTMLPageSync the API subroutines C<fetchware> needs to use to
install, upgarde, or uninstall whatever program your Fetchwarefile specifies.

After understanding how they work, simply follow the instructons and consider
the recommendations below. Obviously, knowing Perl is required. A great place to
start is chromatic's
L<Modern Perl|http://www.onyxneon.com/books/modern_perl/index.html>.

=head2 Develop your idea keeping in mind fetchware's package manager metaphor

Fetchware is a package manager like apt-get, yum, or slackpkg. It I<installs>,
I<upgrades>, or I<uninstalls> programs. Fetchware is not a Plack for command
line programs. It has a rather specific API meant to fit its package manager
metaphor. So, keep this in mind when developing your idea for a fetchware
extension.

=head2 Map your extension's behavior to App::Fetchware's API

App::Fetchware has a specific behavior consisting of just a few subroutines with
specific names that take specific arguments, and return specific values. This
API is how you connect your extension to fetchware.

Just consider the description's of App::Fetchware's API below, and perhaps
consult their full documentation in L<FETCHWAREFILE API SUBROUTINES>.

=over

=item B<my $temp_dir = start(KeepTempDir => 0 | 1)> - Gives your extension a chance to do anything needed before the rest of the API subroutines get called. App::Fetchware's C<start()> manages App::Fetchware's temporary directory creation. If you would like to also use a temporary directory, you can just import App::Fetchware's start() instead of implementing it yourself.

=item B<my $download_url = lookup()> - Determines and returns a download url that C<download()> receives and uses to download the archive for the program.o

=item B<my $package_path = download($tempd_dir, $download_url)> - Downloads its provided $download_url argument.

=item B<verify($download_url, $package_path)> - Verifies the integrity of your downloaded archive using gpg, sha1, or md5.

=item B<my $build_path = unarchive($package_path)> - Unpacks the downloaded archive.

=item B<build($build_path)> - Configures and compiles the downloaded archive.

=item B<install()> - Installs the compiled archive.

=item B<end()> - Cleans up the temporary directory that start() created. Can be overridden to do any other clean up tasks that your archive needs.

=item B<uninstall($build_path)> - Uninstalls an already installed program installed with the same App::Fetchware extension.

=back

Also, keep in mind the order in which these subroutines are called, what
arguments they receive, and what their expected return value is.

=over

=item B<install> - start(), lookup(), download(), verify(), unarchive(), build(), install(), and end().

=item B<upgrade> - Exactly the same as install.

=item B<uninstall> - You might think its just uninstall(), but its not.  uninstall() calls start(), download() (to copy the already installed fetchware package from the fetchware package database to the temporary directory), unarchive(), uninstall(), and end().

=back

Use the above overview of App::Fetchware's API to design what each API
subroutine keeping in mind its arguments and what its supposed to return.

=head2 Determine your fetchware extension's Fetchwarefile configuration options.

App::Fetchware has various configuration options such as C<temp_dir>, C<prefix>,
and so on. Chances are your fetchware extension will also need such
configuration options. These are easily created with
L<App::Fetchware::CreateConfigOptions>, which manufactures these to order for
your convenience. There are four different types of configuration options:

=over

=item ONE - Takes only one argument, and can only be used once.

=item ONEARRREF - Can only be called once, but can take multiple agruments at once.

=item MANY - Takes only one argument, but can be called more than once. The only example is mirror.

=item BOOLEAN - Takes only one arguement, and can only be called once just like
ONE. The difference is that BOOLEANs are limited to only I<boolean> true or
false values such as C<'On'> or C<'Off'>, C<'True'> or C<'False'>, or C<1> or
C<0>. App::Fetchware examples include C<no_install> and C<vefify_failure_ok>.

=back

Using the documentation above and perhaps also the documentation for
L<App::Fetchware::CreateConfigOptions>, determine the names of your
configuration options, and what type of configuraton options they will be.

=head2 Implement your fetchware extension.

Since you've designed your new fetchware extension, now it's time to code it up.
The easiest way to do so, is to just take an existing extension, and just copy
and paste it, and then delete its specifics to create a simple extension
skeleton. Then just follow the steps below to fill in this skeleton with the
specifics needed for you fetchware extension.

=cut

###BUGALERT### Create a fetchware command to do this for users perhaps even
#plugin it into Module::Starter???? If possible.
####BUGALERT## Even have so that you can specify which API subs you want to
#override or avoid overriding, and then it will create the skelton with stubs
#for those API sub already having some empty POD crap and the correct
#prototypes.

=pod

=over

=item 1. Set up proper exports and imports.

Because fetchware needs your fetchware extension to export all of the
subroutines that make up the fetchware's API, and any configuration
options (as Perl subroutines) your extension will use, fetchware uses the helper
packages L<App::Fetchware::ExportAPI> and L<App::Fetchware::CreateConfigOptions>
to easily manage setting all of this up for you.

First, use L<App::Fetchware::ExportAPI> to be sure to export all of fetchware's
API subroutines. This package is also capable of "inheriting" any of
App::Fetchware's API subroutines that you would like to keep. An example.

    # Use App::Fetchware::ExportAPI to set up proper exports this fetchware
    # extension.
    use App::Fetchware::ExportAPI KEEP => [qw(start end)],
        OVERRIDE => [qw(lookup download verify unarchive build install uninstall)]
    ;

Second, use L<App::Fetchware::CreateConfigOptions> to create all of the
configuration options (such as temp_dir, no_install, and so on.) you want your
fetchware extension to have.

There are four types of configuration options.

=over

=item C<ONE> - Take one an only ever one argument, and can only be
called once per Fetchwarefile.

I<Examples:> C<temp_file>, C<prefix>, and C<lookup_url>.

=item C<ONEARRREF> - Takes one or more arguments like C<MANY>, but unlike
C<MANY> can only be called once.

I<Examples:> C<configure_options>, C<make_options>, and C<build_commands>.

=item C<MANY> - Takes one or more arguments, and can be called more than once.
If called more than once, then second call's arguments are I<added> to the
existing list of arguments.

I<Examples:> C<mirror>.

=item C<BOOLEAN> - Just like C<ONE> except it will convert /off/i and /false/i
to 0 to support more than just Perl's 0 or undef being false.

I<Examples:> C<verify_failure_ok>, C<no_install>, and C<stay_root>.

=back

An example.

    use App::Fetchware::CreateConfigOptions
        IMPORT => [qw(temp_dir no_install)],
        ONE => [qw(repository directory)],
        ONEARRREF => [qw(build_options install_options)],
        BOOLEAN => [qw(delete_after_download)],
    ;

These 2 simple use()'s are all it takes to set up proper exports for your
fetchware extension.

=item 2. Code any App::Fetchware API subroutines that you won't be reusing from App::Fetchware.

Use their API documentation from the section L<FETCHWAREFILE API SUBROUTINES> to
ensure that you use the correct subroutine names, arguments and return the
correct value as well.

An example for overriding lookup() is below.

    =head2 lookup()

        my $download_url = lookup();

    # New lookup docs go here....

    =cut

    sub lookup {

        # New code for new lookup() goes here....

        # Return the required $download_url.
        return $download_url;
    }

=back

=head3 Use Fetchware's Own Libraries to Save Developement Time.

Fetchware includes many libraries to save development time. These libraries are
well tested by Fetchware's own test suite, so you too can use them to save
development time in your own App::Fetchware extensions.

These libraries are:

=over

=item L<App::Fetchware::Util>

Houses various logging subroutines, downloading subroutines, security
subroutines, and temporary directory managment subroutines that fetchware itself
uses, and you can also make use of them in your own fetchware extensions.

=over

=item * Logging subroutines - L<msg()|App::Fetchware::Util/msg()>, L<vmsg()|App::Fetchware::Util/vmsg()>, and L<run_prog()|App::Fetchware::Util/run_prog()>.

=over

=item * These subroutines support fetchware's command line options such as -v
(--verbose) and -q (--quiet).

=item * L<msg()|App::Fetchware::Util/msg()> should be used to print a message
to the screen that should always be printed, while
L<vmsg()|App::Fetchware::Util/vmsg()> should only be used to print messages
to the screen when the -v (--verbose) command line option is turned on.  

=item * L<run_prog()|App::Fetchware::Util/run_prog()> is a system() wrapper
that also supports -v and -q options, and should be used to run any external
commands that your App::Fetchware extension needs to run.

=back


=item * Downloading subroutines - L<download_file()|App::Fetchware::Util/download_file> and L<download_dirlist()|App::Fetchware::Util/download_dirlist()>.

=over

=item * L<download_file()|App::Fetchware::Util/download_file> should be used to
download files. It supports the following schemes ftp://, http://, or file://.
It simply downloads the file using Net::Ftp or HTTP::Tiny to the current working
directory.  

=item * L<download_dirlist()|App::Fetchware::Util/download_dirlist()> should be
used to download FTP, HTTP, or local directory listings. It is mostly just used
by lookup() to determine if a new version is available based on the information
it parses from the directory listing.

=back


=item * Security subroutines - L<safe_open()|App::Fetchware::Util/safe_open> and L<drop_privs()|App::Fetchware::Util/drop_privs()>.

=over

=item * L<safe_open()|App::Fetchware::Util/safe_open> opens the file and then
runs a bunch of file and directory tests to ensure that only the user running
fetchware or root can modify the file or any of that file's containing
directories to help prevent Fetchwarefiles from perhaps being tampered by other
users or programs.

=item * L<drop_privs()|App::Fetchware::Util/drop_privs()> forks and drops
privileges. It's used by fetchware to drop privs to avoid downloading and
compiling software as root. It most likely should not be called by
App::Fetchware extensions, because fetchware already calls it for you, but it is
there if you need it.  

=back


=item * Temporary Directory subroutines - L<create_tempdir()|App::Fetchware::Util/create_tempdir()>, L<original_cwd()|App::Fetchware::Util/original_cwd()>, and L<cleanup_tempdir()|App::Fetchware::Util/cleanup_tempdir()>.

=over

=item * L<create_tempdir()|App::Fetchware::Util/create_tempdir()> creates and
chdir()'s into a temporary directory using File::Temp's tempdir() function. It
also deals with creating a Fetchware semaphore file to keep C<fetchware clean>
from deleting any still needed temporary directories.

=item * L<original_cwd()|App::Fetchware::Util/original_cwd()> simply returns
what fetchware's current working directory was before create_tempdir() created
and chdir()'d into the temporary directory.

=item * L<cleanup_tempdir()|App::Fetchware::Util/cleanup_tempdir()> deals with
closing the fetchware semaphore file.

=back


=back


=item L<Test::Fetchware>

Test::Fetchware includes utility subroutines that fetchware itself uses to test
itself, and they are shared with extension writers through this module.

=over

=item * L<eval_ok()|Test::Fetchware/eval_ok()> - A poor man's Test::Exception
in one simple subroutine. Why require every user to install a dependency only
used for testing when one simple subroutine does the trick.

=item * L<print_ok()|Test::Fetchware/print_ok()> - A poor man's Test::Output in
one simple subroutine.

=item *
L<skip_all_unless_release_testing()|Test::Fetchware/skip_all_unless_release_testing()>
- Does just what it's name says. If fetchware's internal release/author only 
Environment variables are set, only then will any Test::More subtests that call
this subroutine skip the entire subtest. This is used to skip running tests that
install real programs on the testing computer's system. Many of Fetchware's
tests actually install a real program such as Apache, and I doubt any
Fetchware user would like to have Apache installed and uninstalled a
bagillion times when they install Fetchware.  Use this subroutine in your own
App::Fetchware extension's to keep that from happening.

=item * L<make_clean()|Test::Fetchware/make_clean()> - Just run_prog('make',
'clean') in the current working directory just as its name suggests.

=item * L<make_test_dist()|Test::Fetchware/make_test_dist()> - Use this
subroutine or craft your own similar subroutine, if you need more flexibility,
to test actually installing a program on user's systems that just happens to
execute all of the proper installation commands, but supplies installation
commands that don't actually install anything. It's used to test actually
installing software without actually installing any software.

=item * L<md5sum_file()|Test::Fetchware/md5sum_file()> - Used to provide a
md5sum file for make_test_dist() create software packages in order to pass
fetchware's verify checks.

=item * L<verbose_on()|Test::Fetchware/verbose_on()> - Make's all vmsg()'s
actually print to the screen even if -v or --verbose was not actually
provided on the command line. Used to aid debugging.

=back

=item L<App::Fetchware::Config>

App::Fetchware::Config stores and manages fetchware's parsed configuration file.
parse_fetchwarefile() from L<fetchware> does the actual parsing, but it stores
the configuration file inside App::Fetchware::Config. Use the subroutines below
to access any configuration file options that you create with
L<App::Fetchware::CreateConfigOptions> to customize your fetchware extension.
Also feel free to reuse any names of App::Fetchware configuration subroutines
such as C<temp_dir> or C<lookup_url>

=over

=item L<config()|App::Fetchware::Config/config()> - Sets and gets values from
the currently parsed fetchware configuration file. If there is one argument,
then it returns that configuration options value or undef if there is none.If
there are more than one argument, then the first argument is what configuration
option to use, and the rest of the arguments are what values to set that
configuration option to.

=item L<config_iter()|App::Fetchware::Config/config_iter()> - returns a
configuration I<iterator>. that when I<kicked> (called, like
C<$config_iter-E<gt>()>) will return one value from the specifed
configuration option. Can be kicked any number of times, but once the number of
configuration values is exhausted the iterator will return undef.

=item L<config_replace()|App::Fetchware::Config/config_replace()> - config() is
used to I<set> configuration options, and once set they I<cannot> be changed by
config(). This is meant to catch and reduce errors. But sometimes, mostly in
test suites, you need to change the value of a configuration option. That's
what config_replace() is for.

=item L<config_delete()|App::Fetchware::Config/config_delete()> - deletes the
specified configuration option. Mostly just used for testing.

=item L<__clear_CONFIG()|App::Fetchware::Config/__clear_CONFIG()> - An internal
only subroutine that should be only used when it is really really needed. It
I<clears> (deletes) the entire internal hash that the configuration options are
stored in. It really should only be used during testing to clear
App::Fetchware::Config's intenal state between tests.

=item L<debug_CONFIG()|App::Fetchware::Config/debug_CONFIG()> - prints
App::Fetchware::Congig's internal state directly to STDOUT. Meant for debugging
only in your test suite.

=back


=item L<App::Fetchware's OVERRIDE_* export tags.|FETCHWAREFILE API SUBROUTINES>

App::Fetchware's main API subroutines, especially the crazy complicated ones
such as lookup(), are created by calling and passing data among many component
subroutines. This is done to make testing much much easier, and to allow
App::Fetchware extensions to also used some or most of these component
subroutines when they override a App::Fetchware API subroutine.

=over

=item L<lookup()'s OVERRIDE_LOOKUP export tag.|lookup() API REFERENCE>

This export tag is the largest, and perhaps the most important, because it
implements fetchware's ability to determine if a new version of your software
package is available. Its default is just a clever use of HTTP and FTP directory
listings.

See the section L<lookup() API REFERENCE> for more details on how to use these
subroutines to determine if new versions of your software is available
automatically.

=item L<download()'s OVERRIDE_DOWNLOAD export tag.|download() API REFERENCE>

Only exports the subroutine determine_package_path(), which simply comcatenates
a $tempdir with a $filename to return a properl $package_path, which unarchive
later uses. This is mostly its own subroutine to better document how this is
done, and to allow easier code reuse.

=item L<verify()'s OVERRIDE_VERIFY export tag.|verify() API REFERENCE>

Exports a family of subroutines to verify via MD5, SHA1, or GPG the integrity of
your downloaded package. MD5 and SHA1 are supported for legacy reasons. All
software packages should be GPG signed for much much much better security. GPG
signatures when verified actually prove that the software package you downloaded
is exactly what the author of that software package created, whereas MD5 and
SHA1 sums just verify that you downloaded the bunch of bits in the same order
that they are stored on the server.

digest_verify() an be used to add support for any other Digest::* modules that
CPAN has a Digest based module for that correctly follow Digest's API.

=item L<unarchive()'s OVERRIDE_UNARCHIVE export tag.|unarchive() API REFERENCE>

Exports subroutines that will help you unarchive software packages in tar and
zip format. The most important part to remember is to use list_files() to list
the files in your archive, and pass that list to check_archive_files() ensure
that the archive will not overwrite any system files, and contains no absolute
paths that could cause havok on your system. unarchive_package() does the actual
unarchiveing of software packages.

=item L<build()'s OVERRIDE_BUILD export tag.|build() API REFERENCE>

Provides run_star_commands(), which is mean to execute common override commands
that fetchware provides with the C<build_commands>, C<install_commands>, and
C<uninstall_commands> configuration file directives. These directives are of
type C<ONEARRREF> where they can only be called once, but you can supply a comma
separated list of commands that fetchware will install instead of the standard
commands default AutoTools commands (build() => ./configure, make; install() =>
make install; uninstall() => ./configure, make uninstall). See its
L<documentation|run_star_commands(config('*_commands'));> for more details.

=item L<install()'s OVERRIDE_INSTALL export tag.|install() API REFERENCE>

install() only exports chdir_unless_already_at_path(), which is of limited use.
install() also uses build()'s run_star_commands().

=item uninstall()'s OVERRDIE_UNINSTALL export tag.

uninstall() actually has no exports of its own, but it does make use of
build() and install()'s exports.


=back

=back


=head2 Write your fetchware extension's documentation

Fill in all of the skeleton's missing POD to ensure that fetchware extension has
enough documentation to make it easy for user's to use your fetchware extension.
Be sure to document:

=over

=item * All of Perl's standard POD sections such as SYNOPSIS, DESCRIPTION, AUTHOR, and all of the others. See L<perlpodstyle> for more details.

=item * Give each subroutine its own chunk of POD before it explaining its arguments, any App::Fetchware configuration options it uses, and what its return value is.

=item * Be sure to document both its external interface, its Fetchwarefile, and its internal interface, what subroutines it has and uses.

=back

=head2 Write tests for your fetchware extension

Use perls veneralbe Test::More, and whatever other Perl TAP testing modules you
need to be sure your fetchware extension works as expected.

L<Test::Fetchware/> has a few testing subroutines that fetchware itself uses
in its test suite that you may find helpful. These include:

=over

=item B<eval_ok()> - A poor man's Test::Exception. Captures any exceptions that are thrown, and compares them to the provided exception text or regex.

=item B<print_ok()> - A poor man's Test::Output. Captures STDOUT, and compares it to the provided text.

=item B<skip_all_unless_release_testing()> - Fetchware is a package manager, but
who wants software installed on their computer just to test it? This subroutine
marks test files or subtests that should be skipped unless fetchware's extensive
FETCHWARE_RELEASE_TESTING environement variables are set. This funtionality is
described next.

=item B<make_clean()> - Just runs C<make clean> in the current directory.

=item B<make_test_dist()> - Creates a temporary distribution that is used for
testing. This temporary distribution contains a C<./configure> and a C<Makefile>
that create no files, but can still be executed in the standard AutoTools way.

###BUGALERT### Add an API hook for customizing make_test_dist().

=item B<md5sum_file()> - Just md5sum's a file so verify() can be tested.

=item B<expected_filename_listing()> - Returns a string of crazy Test::Deep
subroutines to test filename listings. Not quite as useful as the rest, but may
come in handy if you're only changing the front part of lookup().

=back

Your tests should make use of fetchware's own C<FETHWARE_RELEASE_TESTING>
environment variable that controls with the help of
skip_all_unless_release_testing() if and where software is actually installed.
This is done, because everyone who installs fetchware or your fetchware
extension is really gonna freak out if its test suite installs apache or ctags
just to test its package manager functionality. To use it:

=over

=item 1. Set up an automated way of enabling FETCHWARE_RELEASE_TESTING.

Just paste the frt() bash shell function below. Translating this to your favorit
shell should be pretty straight forward. Do not just copy and paste it. You'll
need to customize the specific C<FETCHWARE_*> environment variables to whatever
mirrors you want to use or whatever actual programs you want to test with. And
you'll have to point the local (file://) urls to directories that actually exist
ono your computer.

    # Sets FETCHWARE_RELEASE_TESTING env vars for fully testing fetchware.
    frt() {
        if [ -z "$FETCHWARE_RELEASE_TESTING" ]
        then
            echo -n 'Setting fetchware_release_testing environment variables...';
            export FETCHWARE_RELEASE_TESTING='***setting this will install software on your computer!!!!!!!***'
            export FETCHWARE_FTP_LOOKUP_URL='ftp://carroll.cac.psu.edu/pub/apache/httpd'
            export FETCHWARE_HTTP_LOOKUP_URL='http://www.apache.org/dist/httpd/'
            export FETCHWARE_FTP_MIRROR_URL='ftp://carroll.cac.psu.edu/pub/apache/httpd'
            export FETCHWARE_HTTP_MIRROR_URL='http://mirror.cc.columbia.edu/pub/software/apache//httpd/'
            export FETCHWARE_FTP_DOWNLOAD_URL='ftp://carroll.cac.psu.edu/pub/apache/httpd/httpd-2.2.24.tar.bz2'
            export FETCHWARE_HTTP_DOWNLOAD_URL='http://newverhost.com/pub//httpd/httpd-2.2.24.tar.bz2'
            export FETCHWARE_LOCAL_URL='file:///home/dly/software/httpd-2.2.22.tar.bz2'
            export FETCHWARE_LOCAL_ZIP_URL='file:///home/dly/software/ctags-zip/ctags58.zip'
            export FETCHWARE_LOCAL_BUILD_URL='/home/dly/software/ctags-5.8.tar.gz'
            export FETCHWARE_LOCAL_UPGRADE_URL='file:///home/dly/software/fetchware-upgrade'
            echo 'done.'
        else
            echo -n 'Deleting fetchware_release_testing environment variables...';
            unset FETCHWARE_RELEASE_TESTING
            unset FETCHWARE_FTP_LOOKUP_URL
            unset FETCHWARE_HTTP_LOOKUP_URL
            unset FETCHWARE_FTP_MIRROR_URL
            unset FETCHWARE_HTTP_MIRROR_URL
            unset FETCHWARE_FTP_DOWNLOAD_URL
            unset FETCHWARE_HTTP_DOWNLOAD_URL
            unset FETCHWARE_LOCAL_URL
            unset FETCHWARE_LOCAL_ZIP_URL
            unset FETCHWARE_LOCAL_BUILD_URL
            unset FETCHWARE_LOCAL_UPGRADE_URL
            echo 'done.'
        fi
    }


Just run C<frt> with no args to turn FETCHWARE_RELEASE_TESTING on, and run it
once more to turn it off. Don't forget to reload your shell's configuration
with:

    $ . ~/.bashrc # Or whatever file you added it to is named.

Then inside your test suite just import skip_all_unless_release_testing() from
Test::Fetchware:

    use Test::Fetchware ':TESTING';

=item 2. Call skip_all_unless_release_testing() as needed

In each subtest where you I<actually> install anything other than a test
distribution made with make_test_dist(), begin that subtest with a call to
skip_all_unless_release_testing(), which will skip the whole subtest if
FETCHWARE_RELEASE_TESTING is not setup properly.

    subtest 'test install() for real' => sub {
        # Only test if during release testing.
        skip_all_unless_release_testing();
        
        # Tests that actually install non-trivial distributions such as ones
        # made by make_test_dist() go here.

        ....
    };

If you dislike subtests, or otherwise don't want to use them, then put all of
the tests that I<actually> install something into a SKIP block after the other
tests that all users will run at the end of your test file.

=back

=head2 Share it on CPAN

Fetchware has no Web site or any other place to share fetchware extensions. But
fetchware is written in Perl, so fetchware can just use Perl's CPAN. To learn
how to create modules and upload them to CPAN please see Perl's own
documentation. L<perlnewmod> shows how to create new Perl modules, and how to
upload them to CPAN. See L<Module::Starter> for a simple way to create a
skeleton for a new Perl module, and L<dzil|http://dzil.org/index.html> is beyond
amazing, but has insane dependencies and a significant learning curve.

=cut


=head1 FAQ

=head2 Why doesn't fetchware and App::Fetchware use OO or Moose?

One of my goals for fetchware was that its guts be pragmatic. I wanted it to
consist of a bunch of subroutines that simply get executed in a specific order.
And these subroutines should be small and do one and only one thing to make
understanding them easier and to make testing them a breeze.

OO is awesome for massive systems that need to take advandtage of inheritance or
perhaps composition. But fetchware is small and simple, and I wanted its
implementation to also be small and simple. It is mostly just two three
thousand line programs with some smaller utility files. If it were OO there
would be half or even a whole dozen number of smaller files, and they would have
complicated relationships with each other. I did not want to bother with
needless abstration that would just make fetchware more complicated. It is a
simple command line program, so it should be written as one.

Moose was out, because I don't need any of its amazing features. I could use
those amazing features, but fetchware's simple nature does not demand them.
Also, unless Moose and its large chunk of dependencies are in your OS's file
system cache,  Moose based command line apps take a few seconds to start,
because perl has to do a bunch of IO on slow disks to read in Moose and its
dependencies. I don't want to waste those few seconds. Plus fetchware is a
program not intended for use by experienced Perl developers like dzil is, which
does use Moose, and has a few second start up overhead, which is acceptable to
its author and maintainer. I also use it, and I'm ok with it, but those few
seconds might be off putting to users who have no Perl or Moose knowledge.

=head2 What's up with the insane fetchware extension mechanism?

Extension systems are always insane. dzil, for example, uses a configuration
file where you list names of dzil plugins, and for each name dzil loads that
plugin, and figures out what dzil roles it does, then when dzil executes any
commands you give it, dzil executes all of those roles that the plugins
registered inside you configuration file.

I wanted a configuration file free of declaring what plugins you're using. I
wanted it to be easy to use. dzil is for Perl programmers, so it requiring some
knowledge of Perl and Moose is ok. But fetchware is for end users or perhaps
system administrators not Perl programmers, so something easier is needed.

The extension mechanism was design for ease of use by people who use your
fetchware extension. And it is. Just "use" whatever fetchware extension you want
in your Fetchwarefile, and then supply whatever configuration options you
need.

This extension mechanism is also very easy for Perl programmers, because you're
basically I<subclassing> App::Fetchware, only you do it using
L<App::Fetchware::ExportAPI> and L<App::Fetchware::CreateConfigOptions>. See
section L<Implement your fetchware extension.> for full details.

=head2 How do I fix the verification failed error.

Fetchware is designed to always attempt to verify the software archives it
downloads even if you failed to configure fetchware's verification settings. It
will try to guess what those setting should be using simple heuristics. First it
will try gpg verificaton, then sha1 verification, and finally md5 verification.
If all fail, then fetchware exit failure with an appropriate error message.

When you get this error message
L<read fetchware's documentation on how to set this up|/4. Add mandatory verification settings>.

=head2 How do I make fetchware log to a file instead of STDOUT?

You can't fetchware does not have any log file support. However, you can simply
redirect STDOUT to a file to make your shell redirect STDOUT to a file for you.

    fetchware install <some-program.Fetchwarefile> > fetchware.log

This would not prevent any error messages from STDERR being printed to your
screen for that:

    fetchware install <some-program.Fetchwarefile> 2>&1 fetchware.log

And to throw away all messages use:

    fetchware -q install <some-progra.Fetchwarefile>

or use the shell

    fetchware install <some-program.Fetchwarefile 2>&1 /dev/null

=head2 Why don't you use Crypt::OpenPGP instead of the gpg command line program?

I tried to use Crypt::OpenPGP, but I couldn't get it to work. And getting gpg to
work was a breeze after digging through its manpage to find the right command
line options that did what I need it to.

Also, unfortunately Crypt::OpenPGP is buggy, out-of-date, and seems to have
lost another maintainer. If it ever gets another maintainer, who fixes the newer
bugs, perhaps I'll add support for Crypt::OpenPGP again. Because of how
fetchware works it needs to use supported but not popular options of
Crypt::OpenPGP, which may be where the bugs preventing it from working reside.

Supporting Crypt::OpenPGP is still on my TODO list. It's just not very high on
that list. Patches are welcome to add support for it, and the old code is still
there commented out, but it needs updating if anyone is interested.

In the meantime if you're on Windows without simple access to a gpg command line
program, try installing gpg from the L<gpg4win project|http://gpg4win.org/>,
which packages up gpg and a bunch of other tools for easier use on Windows.

=head2 Does fetchware support Windows?

Yes and no. I intend to support Windows, but right now I'm running Linux, and my
Windows virtual machine is broken, so I can't easily test it on Windows. The
codebase makes heavy use of File::Spec and Path::Class, so all of its file
operations should work on Windows.

I currently have not tested fetchware on Windows. There are probably some test
failures on Windows, but Windows support should be just a few patches away.

So the real answer is no, but I intend to support Windows in a future release.

=head2 Anything else I think of....

=cut


=head1 SECURITY

App::Fetchware is inherently insecure, because its Fetchwarefile's are
executable Perl code that actually is executed by Perl. These Fetchwarefiles are
capable of doing everything someone can program Perl to do. This is why
App::Fetchware will refuse to execute any Fetchwarefile's that are writable by
anyone other than the owner who is executing them. It will also exit with a
fatal error if you try to use a Fetchwarefile that is not the same user as the
one who is running fetchware. These saftey measures help prevent fetchware being
abused to get unauthorized code executed on your computer.

App::Fetchware also features the C<user> configuration option that tells
fetchware what user you want fetchware to drop privileges to when it does
everything but install (install()) and clean up (end()). The configuration
option does B<not> tell fetchware to turn on the drop privelege code; that code
is B<always> on, but just uses the fairly ubuiquitous C<nobody> user by default.
This feature requires the OS to be some version of Unix, because Windows and
other OSes do not support the same fork()ing method of limiting what processes
can do. On non-Unix OSes, fetchware won't fork() or try to use some other way of
dropping privileges. It only does it on Unix. If you use some version of Unix,
and do not want fetchware to drop privileges, then specify the C<stay_root>
configuration option.

=cut


=head1 ERRORS

App::Fetchware does not return any error codes; instead, all errors are die()'d
if it's App::Fetchware::Config's error, or croak()'d if its the caller's fault.
These exceptions are short paragraphs that give full details about the error
instead of the vague one liner that perl's own errors give.
###BUGALERT### Actually implement croak or more likely confess() support!!!

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


=head1 CAVEATS



=cut


=head1 BUGS 



=cut


=head1 RESTRICTIONS 



=cut
