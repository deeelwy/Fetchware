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
use Scalar::Util 'blessed';
use Digest::SHA;
use Digest::MD5;
#use Crypt::OpenPGP::KeyRing;
#use Crypt::OpenPGP;
use Archive::Extract;
use Archive::Tar;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use Cwd;

use App::Fetchware::Util ':UTIL';
use App::Fetchware::Config ':CONFIG';

# Enable Perl 6 knockoffs.
use 5.010;

# Add prototypes for the subroutines that can be used in Fetchwarefiles that can
# take a coderef in packages other than fetchware, but if in fetchware will just
# take a normal arguments. 
#
# The semicolon means the options that follow it are optional. Perl's sucky
# prototypes can't specify two different versions of the same subroutine with
# different arguments, so instead all options are optional, and they can be a
# coderef and/or whatever scalars the subroutine would normally take.
sub start (;$$);
sub lookup (;$);
sub download ($;$);
sub verify ($;$);
sub unarchive ($);
sub build ($);
sub install (;$);
sub uninstall ($);
sub end (;$);

# Set up Exporter to bring App::Fetchware's API to everyone who use's it
# including fetchware's ability to let you rip into its guts, and customize it
# as you need.
use Exporter qw( import );
# By default fetchware exports its configuration file like subroutines and
# fetchware().
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
    user
    prefix
    configure_options
    make_options
    build_commands
    install_commands
    lookup_url
    lookup_method
    gpg_key_url
    sha1_url
    md5_url
    verify_method
    no_install
    verify_failure_ok
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

    make_config_sub
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
        determine_download_url
        ftp_parse_filelist
        http_parse_filelist
        file_parse_filelist
        lookup_by_timestamp
        lookup_by_versionstring
        lookup_determine_downloadurl
    )],
    OVERRIDE_DOWNLOAD => [qw(
        download_ftp_url
        download_http_url
        determine_package_path
    )],
    OVERRIDE_VERIFY => [qw(
        gpg_verify
        sha1_verify
        md5_verify
        digest_verify
    )],
###BUGALERT### Break these subs up into their component parts like the others.
    OVERRIDE_UNARCHIVE => [qw(
        check_archive_files    
    )],
    OVERRIDE_BUILD => [qw()],
    OVERRIDE_INSTALL => [qw()],
    OVERRIDE_UNINSTALL => [qw()],
);
# OVERRIDE_ALL is simply all other tags combined.
@{$EXPORT_TAGS{OVERRIDE_ALL}} = map {@{$_}} values %EXPORT_TAGS;
# *All* entries in @EXPORT_TAGS must also be in @EXPORT_OK.
our @EXPORT_OK = @{$EXPORT_TAGS{OVERRIDE_ALL}};



=head1 FETCHWAREFILE API SUBROUTINES

The subroutines below B<are> Fetchwarefile's API subroutines or helper
subroutines for App::Fetchware's API subroutines, but I<more importantly> also
Fetchwarefile's configuration file syntax See the section
L<FETCHWAREFILE CONFIGURATION SYNTAX> for more information regarding using these
subroutines as Fetchwarefile configuration syntax.
###BUGALERT### Link to sections on craxy Fetchwarefile stuff and extensions too.


=over

=item 'ONE' Fetchwarefile API Subroutines.

=over
=item program $value;
=item filter $value;
=item temp_dir $value;
=item user $value;
=item no_install $value;
=item prefix $value;
=item configure_options $value;
=item make_options $value;
=item build_commands $value;
=item install_commands $value;
=item uninstall_commands $value;
=item lookup_url $value;
=item lookup_method $value;
=item gpg_key_url $value;
=item verify_method $value;

=back

These Fetchwarefile API subroutines can B<only> be called just one time in each
Fetchwarefile. Only one time. Otherwise they will die() with an error message.

These subroutines are generated at compile time by make_config_sub().

=item 'MANY' Fetchwarefile API Subroutines.
=over
=item mirror $value;

=back

C<mirror> can be called many times with each one adding a mirror that fetchware
will try if the one included in lookup_url or gpg_key_url fails.

C<mirror> is the only 'MANY' API subroutine that can be called more than one
time.

=item 'BOOLEAN' Fetchware API Subroutines
=over
=item no_install;
=item verify_failure_ok;

=back

C<no_install> is a true/false, on/off, 1/0 directive. It supports only true or
false values.  True or false work the same way they work in perl with the
special case of /false/i and /off/i also being false.

If you set no_install to true, its default is false, then fetchware will only
skip the part where it installs your programs. Instead it will build a Fetchware
package ending in '.fpkg' that can be installed with 'fetchware install <package>'.
Do this to build your software as a user, and then install it as root system
wide later on. However, this is no longer necessary as fetchware will drop privs
does everything but install your software as a non-root user.

If you set verify_failure_ok to true, its default is false too, then fetchware
will print a warning if fetchware fails to verify the gpg signature instead of
die()ing printing an error message.

###BUGALERT### Add a --force option to fetchware to be able to do the above on
#the command line too.

=cut


###BUGALERT### Recommend installing http://gpg4win.org if you use fetchware on
# Windows so you have gpg support. 






=head2 make_config_sub()

    make_config_sub($name, $one_or_many_values)

A function factory that builds many functions that are the exact same, but have
different names. It supports three types of functions determined by
make_config_sub()'s second parameter.  It's first parameter is the name of that
function. This is the subroutine that builds all of Fetchwarefile's
configuration subroutines such as lookupurl, mirror, fetchware, etc....

=over
=item LIMITATION

make_config_sub() creates subroutines that have prototypes, but in order for
perl to honor those prototypes perl B<must> know about them at compile-time;
therefore, that is why make_config_sub() must be called inside a C<BEGIN> block.

=back

=over
=item NOTE
make_config_sub() uses caller to determine the package that make_config_sub()
was called from. This package is then prepended to the string that is eval'd to
create the designated subroutine in the caller's package. This is needed so that
App::Fetchware "subclasses" can import this function, and enjoy its simple
interface to create custom configuration subroutines.

=back

=over

=item $one_or_many_values Supported Values

=over

=item * 'ONE'

Generates a function with the name of make_config_sub()'s first parameter that
can B<only> be called one time per Fetchwarefile. If called more than one time
will die with an error message.

Function created with C<$CONFIG{$name} = $value;> inside the generated function that
is named $name.

=item * 'MANY'

Generates a function with the name of make_config_sub()'s first parameter that
can be called more than just once. This option is only used by fetchware's
C<mirror()> API call.

Function created with C<push @{$CONFIG{$name}}, $value;> inside the generated function that
is named $name.

=item * 'BOOLEAN'

Generates a function with the name of make_config_sub()'s first parameter that
can be called only once just like 'ONE' can be, but it also only support true or
false values.  What is true and false is the same as in perl, with the exception
that /false/i and /off/i are also false.

Function created the same way as 'ONE''s are, but with /false/i and /off/i
mutated into a Perl accepted false value (they're turned into zeros.).

=back

=back

All API subroutines fetchware provides to Fetchwarefile's are generated by
make_config_sub() except for fetchware() and override().

=cut

    my @api_functions = (
        [ program => 'ONE' ],
        [ filter => 'ONE' ],
        [ temp_dir => 'ONE' ],
        [ user => 'ONE' ],
        [ prefix => 'ONE' ],
        [ configure_options=> 'ONEARRREF' ],
        [ make_options => 'ONEARRREF' ],
        [ build_commands => 'ONEARRREF' ],
        [ install_commands => 'ONEARRREF' ],
        [ uninstall_commands => 'ONEARRREF' ],
        [ lookup_url => 'ONE' ],
        [ lookup_method => 'ONE' ],
        [ gpg_key_url => 'ONE' ],
        [ sha1_url => 'ONE' ],
        [ md5_url => 'ONE' ],
        [ verify_method => 'ONE' ],
        [ mirror => 'MANY' ],
        [ no_install => 'BOOLEAN' ],
        [ verify_failure_ok => 'BOOLEAN' ],
    );


# Loop over the list of options needed by make_config_sub() to generated the
# needed API functions for Fetchwarefile.
    for my $api_function (@api_functions) {
        make_config_sub(@{$api_function});
    }


sub make_config_sub {
    my ($name, $one_or_many_values) = @_;

    # Obtain caller's package name, so that the new configuration subroutine
    # can be created in the caller's package instead of our own.
    my $package = caller;

    die <<EOD unless defined $name;
App-Fetchware: internal syntax error: make_config_sub() was called without a
name. It must receive a name parameter as its first paramter. See perldoc
App::Fetchware.
EOD
    use Test::More;
    unless ($one_or_many_values eq 'ONE'
            or $one_or_many_values eq 'ONEARRREF',
            or $one_or_many_values eq 'MANY'
            or $one_or_many_values eq 'BOOLEAN') {
        die <<EOD;
App-Fetchware: internal syntax error: make_config_sub() was called without a
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
1App-Fetchware: internal operational error: make_config_sub()'s internal eval()
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
2App-Fetchware: internal operational error: make_config_sub()'s internal eval()
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
3App-Fetchware: internal operational error: make_config_sub()'s internal eval()
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
4App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [\$@]. See perldoc App::Fetchware.
EOD
        }
    }
}








=head2 start()

    my $temp_dir = start();
    start sub {
        # Callback that replaces start()'s behavior.
        # Callback receives the same arguments as start(), and is must return
        # the same number and type of arguments that start() returns.
    };

=over
=item Configuration subroutines used:
=over
=item none

=back

=back

Creates a temp directory using File::Temp, and sets that directory up so that it
will be deleted by File::Temp when fetchware closes.

Returns the $temp_file that start() creates, so everything else has access to
the directory they should use for storing file operations.

=cut

    sub start (;$$) {
        # Based on what package we're called in, either accept a callback as an
        # argument and save it for later, or execute the already saved callback.
        state $callback; # A state variable to keep its value between calls.
        if (caller ne 'fetchware') {
            $callback = shift;
            die <<EOD if ref $callback ne 'CODE';
App-Fetchware: start() was called from a package other than 'fetchware', and with an
argument that was not a code reference. Outside of package 'fetchware' this
subroutine can only be called with a code reference as its one and only
argument.
EOD
            return 'Callback added.';
        # We *were* called in package fetchware.
        } else {
            # Only execute and return the specified $callback, if it has
            # previously been defined. If it has not, then execute the rest of
            # this subroutine normally.
            if (defined $callback and ref $callback eq 'CODE') {
                return $callback->(@_);
            }
        }


        my %opts = @_;

        # Forward opts to create_tempdir(), which does the heavy lifting.
        my $temp_dir = create_tempdir(%opts);

        return $temp_dir;
    }


=head2 lookup()

    my $download_url = lookup();
    lookup sub {
        # Callback that replaces lookup()'s behavior.
        # Callback receives the same arguments as lookup(), and is must return
        # the same number and type of arguments that lookup() returns.
    };

=over
=item Configuration subroutines used:
=over
=item lookup_url
=item lookup_method

=back

=back

Accesses C<lookup_url> as a http/ftp directory listing, and uses C<lookup_method>
to determine what the newest version of the software is available, which it
combines with the C<lookup_url> and returns it to caller for use as an argument
to download().

=over
=item LIMITATIONS
C<lookup_url> is a web browser like URL such as C<http://host.com/a/b/c/path>,
and it B<must> be a directory listing B<not> a actual file. This directory
listing must be a listing of all of the available versions of the program this
Fetchwarefile belongs to.

Only ftp://, http://, and file:// URL scheme's are supported.

=back

C<lookup_method> can be either C<'timestamp'> or C<'versionstring'>, any other
values will result in fetchware die()ing with an error message.

=cut

sub lookup (;$) {
    # Based on what package we're called in, either accept a callback as an
    # argument and save it for later, or execute the already saved callback.
    state $callback; # A state variable to keep its value between calls.
    if (caller ne 'fetchware') {
        $callback = shift;
        die <<EOD if ref $callback ne 'CODE';
App-Fetchware: start() was called from a package other than 'fetchware', and with an
argument that was not a code reference. Outside of package 'fetchware' this
subroutine can only be called with a code reference as its one and only
argument.
EOD
        return 'Callback added.';
    # We *were* called in package fetchware.
    } else {
        # Only execute and return the specified $callback, if it has previously
        # been defined. If it has not, then execute the rest of this subroutine
        # normally.
        if (defined $callback and ref $callback eq 'CODE') {
            return $callback->(@_);
        }
    }


    msg "Looking up download url using lookup_url [@{[config('lookup_url')]}]";

use Test::More;
diag "lookup_url[@{[config('lookup_url')]}]";
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
    my $download_url = determine_download_url($filename_listing);

    msg "Download url determined to be [$download_url]";
    return $download_url;
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
diag "pdl file listing";
diag explain $directory_listing;
diag "end pdl";
}


=head3 determine_download_url()

    my $download_url = determine_download_url($filename_listing);

Runs the C<lookup_method> to determine what the lastest filename is, and that
one is then concatenated with C<lookup_url> to determine the $download_url,
which is then returned to the caller.

=over
=item SIDE EFFECTS
determine_download_url(); returns $download_url to the URL that download() will
use to download the archive of your program.

=back

=cut

sub determine_download_url {
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
diag "ddurl file listing";
diag explain $filename_listing;
diag "end ddurl";
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
                if ($link =~ /\.(tar\.(gz|bz2|xz)|(tgz|tbz2|txz))$/) {
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
                        # day-month-year   time
                        # $fields[0]      $fields[1]
                        # Normalize format for lookup algorithms .
                        my ($day, $month, $year) = split /-/, $fields[0];
                        # Ditch the ':' in the time.
                        $fields[1] =~ s/://;
                        push @filename_listing, [$filename, "$year$month{$month}$day$fields[1]"];
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
            = stat($file);

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
diag "lbt file listing";
diag explain \@sorted_listing;
diag "end lbt";

    # Manage duplicate timestamps apropriately including .md5, .asc, .txt files.
    # And support some hacks to make lookup() more robust.
    ###BUGALERT### Refactor this containing sub to call the sub below, and
    #another one called lookup_hacks() for example, or perhaps provide a
    #callback for this :)
    return lookup_determine_downloadurl(\@sorted_listing);
}


=head3 lookup_by_versionstring()

    my $download_url = lookup_by_versionstring($filename_listing);

Determines the $download_url used by download() by cleverly C<split>ing the
filenames on C</\D+/>, which will return a list of version numbers. Then
they're just sorted normally. And lookup_determine_downloadurl() is used to
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
    return lookup_determine_downloadurl($file_listing);
}



=head3 lookup_determine_downloadurl()

    my $download_url = lookup_determine_downloadurl($file_listing);

Given a $file_listing of files with the same timestamp or versionstring,
determine which one is a downloadable archive, a tarball or zip file. And
support some backs to make fetchware more robust. These are the C<filter>
configuration subroutine, ignoring "win32" on non-Windows systems, and
supporting Apache's CURRENT_IS_ver_num and Linux's LATEST_IS_ver_num helper
files.

=cut

sub lookup_determine_downloadurl {
    my $file_listing = shift;

use Test::More;
diag "file_listing";
diag explain $file_listing;
diag "endfilelisting";
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
    diag("latestver[$latest_version]");
    @$file_listing = grep { $_->[0] =~ /$latest_version/ } @$file_listing
        if defined $latest_version;

    # Determine the $download_url based on the sorted @$file_listing by
    # finding a downloadable file (a tarball or zip archive).
    # Furthermore, choose them based on best compression to worst to save some
    # bandwidth.
    for my $fl (@$file_listing) {
        use Test::More;
        diag explain $fl;
        given ($fl->[0]) {
            when (/\.tar\.xz$/) {
                return "@{[config('lookup_url')]}/$fl->[0]";
            } when (/\.txz$/) {
                return "@{[config('lookup_url')]}/$fl->[0]";
            } when (/\.tar\.bz2$/) {
                return "@{[config('lookup_url')]}/$fl->[0]";
            } when (/\.tbz$/) {
                return "@{[config('lookup_url')]}/$fl->[0]";
            } when (/\.tar\.gz$/) {
                return "@{[config('lookup_url')]}/$fl->[0]";
            } when (/\.tgz$/) {
                return "@{[config('lookup_url')]}/$fl->[0]";
            } when (/\.zip$/) {
                return "@{[config('lookup_url')]}/$fl->[0]";
            } when (/\.fpkg$/) {
                return "@{[config('lookup_url')]}/$fl->[0]";
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

    my $package_path = download($download_url);
    download sub {
        # Callback that replaces download()'s behavior.
        # Callback receives the same arguments as download(), and is must return
        # the same number and type of arguments that download() returns.
    };

=over
=item Configuration subroutines used:
=over
=item none

=back

=back

Downloads $download_url to C<tempdir 'whatever/you/specify';> or to
whatever File::Spec's tempdir() method tries. Supports ftp and http URLs.

Also, returns $package_path, which is used by unarchive() as the path to the
archive for unarchive() to untar or unzip.

=over
=item LIMITATIONS
Uses Net::FTP and HTTP::Tiny to download ftp and http files. No other types of
downloading are supported, and fetchware is stuck with whatever limitations or
bugs Net::FTP or HTTP::Tiny impose.

=back

=cut

sub download ($;$) {
    # Based on what package we're called in, either accept a callback as an
    # argument and save it for later, or execute the already saved callback.
    state $callback; # A state variable to keep its value between calls.
    if (caller ne 'fetchware') {
        $callback = shift;
        die <<EOD if ref $callback ne 'CODE';
App-Fetchware: download() was called from a package other than 'fetchware', and with an
argument that was not a code reference. Outside of package 'fetchware' this
subroutine can only be called with a code reference as its one and only
argument.
EOD
        return 'Callback added.';
    # We *were* called in package fetchware.
    } else {
        # Only execute and return the specified $callback, if it has previously
        # been defined. If it has not, then execute the rest of this subroutine
        # normally.
        if (defined $callback and ref $callback eq 'CODE') {
            return $callback->(@_);
        }
    }


    my ($temp_dir, $download_url) = @_;

    msg "Downloading from url [$download_url] to temp dir [$temp_dir]";

    my $downloaded_file_path = download_file($download_url);
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
    diag explain \@_;

    # return $package_path, which stores the full path of where the file
    # HTTP::Tiny downloaded.
    return catfile($tempdir, $filename)
}



=head2 verify()

    verify($download_url, $package_path)
    verify sub {
        # Callback that replaces verify()'s behavior.
        # Callback receives the same arguments as verify(), and is must return
        # the same number and type of arguments that verify() returns.
    };

=over
=item Configuration subroutines used:
=over
=item gpg_key_url 'a.browser/like.url';
=item gpg_sig_url 'a.browser/like.url';
=item sha1_url 'a browser-like url';
=item md5_url 'a browser-like url';
=item verify_method 'md5,sha,gpg';
=item verify_failure_ok 'True/False';

=back

=back

Verifies the downloaded package stored in $package_path by downloading
$download_url.{asc,sha1,md5}> and comparing the two together. Uses the
helper subroutines C<{gpg,sha1,md5,digest}_verify()>.

###BUGALERT### Update comment below regarding support status of Crypt::OpenPGP.
=over
=item LIMITATIONS
Uses gpg command line or Crypt::OpenPGP for Windows, and the interface to gpg is
a little brittle, while Crypt::OpenPGP is complex, poorly maintained, and bug
ridden, but still usable.

=back

=cut

sub verify ($;$) {
    # Based on what package we're called in, either accept a callback as an
    # argument and save it for later, or execute the already saved callback.
    state $callback; # A state variable to keep its value between calls.
    if (caller ne 'fetchware') {
        $callback = shift;
        die <<EOD if ref $callback ne 'CODE';
App-Fetchware: start() was called from a package other than 'fetchware', and with an
argument that was not a code reference. Outside of package 'fetchware' this
subroutine can only be called with a code reference as its one and only
argument.
EOD
        return 'Callback added.';
    # We *were* called in package fetchware.
    } else {
        # Only execute and return the specified $callback, if it has previously
        # been defined. If it has not, then execute the rest of this subroutine
        # normally.
        if (defined $callback and ref $callback eq 'CODE') {
            return $callback->(@_);
        }
    }


    my ($download_url, $package_path) = @_;

    msg "Verifying the downloaded package [$package_path]";

    my $retval;
    given (config('verify_method')) {
        when (undef) {
            # if gpg fails try
            # sha and if it fails try
            # md5 and if it fails die
            msg 'Trying to use gpg to cyptographically verify downloaded package.';
            my ($gpg_err, $sha_err, $md5_err);
            eval {$retval = gpg_verify($download_url)};
            $gpg_err = $@;
            diag("gpgrv[$retval]");
            if ($gpg_err) {
                msg <<EOM;
Cyptographic using gpg failed!
EOM
                warn $gpg_err;
            }
            if (! $retval or $gpg_err) {
                msg <<EOM;
Trying SHA1 verification of downloaded package.
EOM
                eval {$retval = sha1_verify($download_url, $package_path)};
                $sha_err = $@;
                diag("sharv[$retval]");
                if ($sha_err) {
                    msg <<EOM;
SHA1 verification failed!
EOM
                    warn $sha_err;
                }
                if (! $retval or $sha_err) {
                    diag("GOTTOMD5");
                    msg <<EOM;
Trying MD5 verification of downloaded package.
EOM
                    eval {$retval = md5_verify($download_url, $package_path)};
                    $md5_err = $@;
                    diag("md5rv[$retval]");
                    if ($md5_err) {
                        msg <<EOM;
MD5 verification failed!
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
            gpg_verify($download_url)
                or die <<EOD unless config('verify_failure_ok');
App-Fetchware: run-time error. You asked fetchware to only try to verify your
package with gpg or openpgp, but they both failed. See the warning above for
their error message. See perldoc App::Fetchware.
EOD
        } when (/sha1?/i) {
            vmsg <<EOM;
You selected SHA1 checksum verification. Verifying now.
EOM
            sha1_verify($download_url, $package_path)
                or die <<EOD unless config('verify_failure_ok');
App-Fetchware: run-time error. You asked fetchware to only try to verify your
package with sha, but it failed. See the warning above for their error message.
See perldoc App::Fetchware.
EOD
        } when (/md5/i) {
            vmsg <<EOM;
You selected MD5 checksum verification. Verifying now.
EOM
            md5_verify($download_url, $package_path)
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

    'Package Verified' = gpg_verify($download_url);

###BUGALERT### Update statement regarding use of Crypt::OpenPGP.
Verifies the downloaded source code distribution using the command line program
gpg or Crypt::OpenPGP on Windows or if gpg is not available.
=cut

sub gpg_verify {
    my $download_url = shift;

    my $keys_file;
    # Obtain a KEYS file listing everyone's key that signs this distribution.
##DELME##    if (defined $CONFIG{gpg_key_url}) {
##DELME##        $keys_file = download_file($CONFIG{gpg_key_url});
##DELME##    } else {
##DELME##        eval {
##DELME##            $keys_file = download_file("$CONFIG{lookup_url}/KEYS");
##DELME##        }; 
##DELME##        if ($@ and not defined $CONFIG{verify_failure_ok}) {
##DELME##            die <<EOD;
##DELME##App-Fetchware: Fetchware was unable to download the gpg_key_url you specified or
##DELME##that fetchware tried appending asc, sig, or sign to [$CONFIG{DownloadUrl}]. It needs
##DELME##to download this file to properly verify you software package. This is a fatal
##DELME##error, because failing to verify packages is a perferable default over
##DELME##potentially installing compromised ones. If failing to verify your software
##DELME##package is ok to you, then you may disable verification by adding
##DELME##verify_failure_ok 'On'; to your Fetchwarefile. See perldoc App::Fetchware.
##DELME##EOD
##DELME##        }
##DELME##    }

    # Download Signature using lookup_url.
    my $sig_file;
    ###BUGALERT### Should the eval{} be inside the for loop, so that the code
    #will actually try multiple times instead of exiting the loop on the first
    #failure, and not even trying the other two.
    eval {
        for my $ext (qw(asc sig sign)) {
            $sig_file = download_file("$download_url.$ext");

            # If the file was downloaded successfully stop trying other extensions.
            last if defined $sig_file;
        }
        1;
    } or die <<EOD;
App-Fetchware: Fetchware was unable to download the gpg_sig_url you specified or
that fetchware tried appending asc, sig, or sign to [$download_url]. It needs
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
        run_prog('gpg', '--keyserver', 'pool.sks-keyservers.net',
            '--keyserver-options', 'auto-key-retrieve=1',
            '--homedir', '.',  "$sig_file");

        # Verify sig.
#        run_prog('gpg', '--homedir', '.', '--verify', "$sig_file");
###BUGALERT###    }

    # Return true indicating the package was verified.
    return 'Package Verified';
}


=head3 sha1_verify()

    'Package verified' = sha1_verify($download_url, $package_path);
    undef = sha1_verify($download_url, $package_path);

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
    my ($download_url, $package_path) = @_;

    return digest_verify('SHA-1', $download_url, $package_path);
}


=head3 md5_verify()

    'Package verified' = md5_verify($download_url, $package_path);
    undef = md5_verify($download_url, $package_path);

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
    my ($download_url, $package_path) = @_;

    return digest_verify('MD5', $download_url, $package_path);
}


=head3 digest_verify()

    'Package verified' = digest_verify($digest_type, $download_url, $package_path);
    undef = digest_verify($digest_type, $download_url, $package_path);

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
    my ($digest_type, $download_url, $package_path) = @_;

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
        package fetchware; # Pretend to be bin/fetchware.
        my $lookuped_download_url = lookup();
        package App::Fetchware; # Switch back.
        # Should I implement config_local() :)
        config_replace(lookup_url => $old_lookup_url);
        $digest_file = download_file("$lookuped_download_url.$digest_ext");
    } else {
        eval {
            $digest_file = download_file("$download_url.$digest_ext");
            diag("digestfile[$digest_file]");
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
    
###subify calc_sum()
    # Open the downloaded software archive for reading.
    diag("PACKAGEPATH[$package_path");
    open(my $package_fh, '<', $package_path)
        or die <<EOD;
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
    diag("DIGESTFILE[$digest_file]");
    open(my $digest_fh, '<', $digest_file)
        or die <<EOD;
App-Fetchware: run-time error. Fetchware failed to open the $digest_type file it
downloaded while trying to read it in order to check its $digest_type sum. The file was
[$digest_file]. See perldoc App::Fetchware.
EOD
    # Will only check the first md5sum it finds.
    while (<$digest_fh>) {
        next if /^\s+$/; # skip whitespace only lines just in case.
        my @fields = split ' '; # Defaults to $_, which is filled in by <>
        diag("fields[@fields]");
        diag("filemd5[$fields[0]]calcmd5[$calculated_digest]");

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
    unarchive sub {
        # Callback that replaces unarchive()'s behavior.
        # Callback receives the same arguments as unarchive(), and is must return
        # the same number and type of arguments that unarchive() returns.
    };

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

=cut

sub unarchive ($) {
    # Based on what package we're called in, either accept a callback as an
    # argument and save it for later, or execute the already saved callback.
    state $callback; # A state variable to keep its value between calls.
    if (caller ne 'fetchware') {
        $callback = shift;
        die <<EOD if ref $callback ne 'CODE';
App-Fetchware: start() was called from a package other than 'fetchware', and with an
argument that was not a code reference. Outside of package 'fetchware' this
subroutine can only be called with a code reference as its one and only
argument.
EOD
        return 'Callback added.';
    # We *were* called in package fetchware.
    } else {
        # Only execute and return the specified $callback, if it has previously
        # been defined. If it has not, then execute the rest of this subroutine
        # normally.
        if (defined $callback and ref $callback eq 'CODE') {
            return $callback->(@_);
        }
    }


    my $package_path = shift;

    msg "Unarchiving the downloaded package [$package_path]";

    ###BUGALERT### fetchware needs Archive::Zip, which is *not* one of
    #Archive::Extract's dependencies.
    diag("PP[$package_path]");
    vmsg 'Creating Archive::Extract object.';
    my $ae;
    unless ($package_path =~ m!.fpkg$!) {
        $ae = Archive::Extract->new(archive => "$package_path") or die <<EOD;
App-Fetchware: internal error. Archive::Extract->new() as called by unarchive()
failed to create a new Archive::Extract object. This is a fatal error. The
archive in question was [$package_path].
EOD
    ###BUGALERT### Include a workaround for Archive::Extract's caveat that uses
    #the file's extension to determine how to unarchive it by manually telling
    #it that fpkg's are actually .tar.gz's.
    } else {
        $ae = Archive::Extract->new(archive => "$package_path",
            type => 'tgz') or die <<EOD;
App-Fetchware: internal error. Archive::Extract->new() as called by unarchive()
failed to create a new Archive::Extract object. This is a fatal error. The
archive in question was [$package_path].
EOD
    }

###BUGALERT### Files are listed *after* they're extracted, because
#Archive::Extract *only* extracts files and then lets you see what files were
#*already* extracted! This is a huge limitation that prevents me from checking
#if an archive has an absolute path in it.
    vmsg 'Using Archive::Extract to extract files.';
    $ae->extract() or die <<EOD;
App-Fetchware: run-time error. Fetchware failed to extract the archive it
downloaded [$package_path]. The error message is [@{[$ae->error()]}].
See perldoc App::Fetchware.
EOD

    # list files.
    vmsg 'Unarchived the files:';
    my $files = $ae->files();
    die <<EOD if not defined $files;
App-Fetchware: run-time error. Fetchware failed to list the files in  the
archive it downloaded [$package_path]. The error message is
[@{[$ae->error()]}].  See perldoc App::Fetchware.
EOD
    vmsg Dumper($files);

    # Return the $build_path
    vmsg 'Checking that the files extracted from the archive are acceptable.';
    my $build_path =  check_archive_files($files);

    msg "Determined build path to [$build_path]";
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



=head3 list_files_tar()

    my $tar_file_listing = list_files_tar($path_to_tar_archive);

=cut

sub list_files_tar {
    my $path_to_tar_archive = shift;

    # Use list_files() method to return a list of files.
    # Pass in the weird special case of the $name inside an array ref to tell
    # list_files() to return just a list of file names instead of a list of
    # hasherefs.
    return Archive::Tar->list_files([$path_to_tar_archive]);
}


=head3 list_files_zip()

    my $zip_file_listing = list_files_zip($path_to_zip_archive);

=cut


{ # Begin %zip_error_codes hash.
my %zip_error_codes = (
    AZ_OK => 'Everything is fine.',
    AZ_STREAM_END => 
        'The read stream (or central directory) ended normally.',
    AZ_ERROR => 'There was some generic kind of error.',
    AZ_FORMAT_ERROR => 'There is a format error in a ZIP file being read.',
    AZ_IO_ERROR => 'There was an IO error'
);

sub list_files_zip {
    my $path_to_zip_archive = shift;

    my $zip = Archive::Zip->new();

    my $zip_error;
    if(($zip_error = $zip->new($path_to_zip_archive)) ne AZ_OK) {
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
        push @external_filenames, $member->externalFileName();
    }

    # Return list of "external" filenames.
    return @external_filenames;
}


=head3 unarchive_tar()

    unarchive_tar($path_to_tar_archive);

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
    }
}


=head3 unarchive_zip()

    unarchive_zip($path_to_zip_archive);

=cut

sub unarchive_zip {
    my $path_to_zip_archive = shift;

    my $zip = Archive::Zip->new();

    my $zip_error;
    if(($zip_error = $zip->new($path_to_zip_archive)) ne AZ_OK) {
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
##TEST##diag("path[$path]");
        # Skip Fetchwarefiles.
        next if $path eq './Fetchwarefile';

###BUGALERT### Archive::Extract *only* extracts files! $ae->files() is an
#accessor method to an arrayref of files that it has *already* extracted! This
#extreme limitation may be circumvented in the future by using Archive::Tar and
#Archive::Zip to list files, but I'm not fixing it now.
        my $error = <<EOE;
App-Fetchware: run-time error. The archive you asked fetchware to download has
one or more files with an absolute path. Absolute paths in archives is
dangerous, because the files could potentially overwrite files anywhere in the
filesystem including important system files. That is why this is a fatal error
that cannot be ignored. See perldoc App::Fetchware.
Absolute path [$path].
NOTE: Due to limitations in Archive::Extract any absolute paths have *already*
been extracted! Bug they are listed below in case you would like to see which
ones they are.
EOE
        $error .= "[\n";
        $error .= join("\n", @$files);
        $error .= "\n]\n";
        die $error if file_name_is_absolute($path);

        my ($volume,$directories,$file) = splitpath($path); 
##TEST##diag("vol[$volume]dirs[$directories]file[$file]");
        my @dirs = splitdir($directories);
##TEST##diag("dirssss");
##TEST##diag explain \@dirs;
        # Skip empty directories.
        next unless @dirs;

        $dir{$dirs[0]}++;
    }

diag("dirhash");
diag explain \%dir;

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
        diag("BUILDPATH[$build_path]");
        return $build_path;
    }
}



=head2 build()

    'build succeeded' = build($build_path)
    build sub {
        # Callback that replaces build()'s behavior.
        # Callback receives the same arguments as build(), and is must return
        # the same number and type of arguments that build() returns.
    };

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
build() likeinstall() inteligently parses C<build_commands>, C<prefix>,
C<make_options>, and C<configure_options> by C<split()ing> on C</,\s+/>, and
then C<split()ing> again on C<' '>, and then execute them using fetchware's
built in run_prog() to properly support -q.

Also, simply executes the commands you specify or the default ones if you
specify none. Fetchware will check if the commands you specify exist and are
executable, but the kernel will do it for you and any errors will be in
fetchware's output.

=back

=cut

sub build ($) {
    # Based on what package we're called in, either accept a callback as an
    # argument and save it for later, or execute the already saved callback.
    state $callback; # A state variable to keep its value between calls.
    if (caller ne 'fetchware') {
        $callback = shift;
        die <<EOD if ref $callback ne 'CODE';
App-Fetchware: start() was called from a package other than 'fetchware', and with an
argument that was not a code reference. Outside of package 'fetchware' this
subroutine can only be called with a code reference as its one and only
argument.
EOD
        return 'Callback added.';
    # We *were* called in package fetchware.
    } else {
        # Only execute and return the specified $callback, if it has previously
        # been defined. If it has not, then execute the rest of this subroutine
        # normally.
        if (defined $callback and ref $callback eq 'CODE') {
            return $callback->(@_);
        }
    }


    my $build_path = shift;

    msg "Building your package in [$build_path]";

    use Cwd;
    diag("before[@{[cwd()]}]");
    vmsg "changing Directory to build path [$build_path]";
    chdir $build_path or die <<EOD;
App-Fetchware: run-time error. Failed to chdir to the directory fetchware
unarchived [$build_path]. See perldoc App::Fetchware.
EOD
    diag("after[@{[cwd()]}]");


    # If build_commands is set, then all other build config options are ignored.
    if (defined config('build_commands')) {
        vmsg 'Building your package using user specified build_commands.';
        # Support multiple options like build_command './configure', 'make';
        # config('build_commands') returns a list of *all* build_commands.
        for my $build_command (config('build_commands')) {
            # If a /,\s+/ is present in a $build_command
            # To support: build_commands './configure, make';
            if ($build_command =~ /,\s*/) {
                # split on it, and run each resulting command.
                my @build_commands = split /,\s*/, $build_command;
                for my $split_build_command (@build_commands) {
                    my ($cmd, @options) = split ' ', $split_build_command;
                    run_prog($cmd, @options);
                }
            # Or just run the one command.
            } else {
                my ($cmd, @options) = split ' ', $build_command;
                run_prog($cmd, @options);
            }
        }
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

sub run_configure {
    my $configure = './configure';
    if (config('configure_options')) {
        # Support multiple options like configure_options '--prefix', '.';
        for my $configure_option (config('configure_options')) {
            $configure .= " $configure_option";
            diag("configureopts[$configure]");
        }
    } elsif (config('prefix')) {
        if ($configure =~ /--prefix/) {
            die <<EOD;
App-Fetchware: run-time error. You specified both the --prefix option twice.
Once in 'prefix' and once in 'configure_options'. You may only specify prefix
once in either configure option. See perldoc App::Fetchware.
EOD
        } else {
            $configure .= " --prefix=@{[config('prefix')]}";
            diag("prefixaddingprefix[$configure]");
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

    'install succeeded' = install();
    install sub {
        # Callback that replaces install()'s behavior.
        # Callback receives the same arguments as install(), and is must return
        # the same number and type of arguments that install() returns.
    };

=over
=item Configuration subroutines used:
=over
=item install_commands

=back

=back

Executes C<make install>, which installs the specified software, or executes
whatever C<install_commands 'install, commands';> if its defined.

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

=cut

sub install (;$) {
    # Based on what package we're called in, either accept a callback as an
    # argument and save it for later, or execute the already saved callback.
    state $callback; # A state variable to keep its value between calls.
    if (caller ne 'fetchware') {
        $callback = shift;
        die <<EOD if ref $callback ne 'CODE';
App-Fetchware: start() was called from a package other than 'fetchware', and with an
argument that was not a code reference. Outside of package 'fetchware' this
subroutine can only be called with a code reference as its one and only
argument.
EOD
        return 'Callback added';
    # We *were* called in package fetchware.
    } else {
        # Only execute and return the specified $callback, if it has previously
        # been defined. If it has not, then execute the rest of this subroutine
        # normally.
        if (defined $callback and ref $callback eq 'CODE') {
            return $callback->(@_);
        }
    }


    # Skip installation if the user requests it.
    if (config('no_install')) {
        msg <<EOM;
Installation skipped, because no_install is specified in your Fetchwarefile.
EOM
        return 'installation skipped!' ;
    }

    msg 'Installing your package.';

    if (defined config('install_commands')) {
        vmsg 'Installing your package using user specified commands.';
        # Support multiple options like install_commands 'make', 'install';
        for my $install_command (config('install_commands')) {
            # If a /,\s+/ is present in a $install_command
            # To support: build_commands './configure, make';
            if ($install_command =~ /,\s*/) {
                # split on it, and run each resulting command.
                my @install_commands = split /,\s*/, $install_command;
                for my $split_install_command (@install_commands) {
                    my ($cmd, @options) = split ' ', $split_install_command;
                    run_prog($cmd, @options);
                }
            # Or just run the one command.
            } else {
                my ($cmd, @options) = split ' ', $install_command;
                run_prog($cmd, @options);
            }
        }
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



=head2 uninstall()

    'uninstall succeeded' = uninstall($build_path)
    uninstall sub {
        # Callback that replaces uninstall()'s behavior.
        # Callback receives the same arguments as uninstall(), and is must return
        # the same number and type of arguments that uninstall() returns.
    };

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

=cut

###BUGALERT### NOT TESTED!!! There is no t/App-Fetchware-uninstall.t test
#file!!! cmd_uninstall(), which uses uninstall(), is tested, but not uninstall()
#directly!!!
sub uninstall ($) {
    # Based on what package we're called in, either accept a callback as an
    # argument and save it for later, or execute the already saved callback.
    state $callback; # A state variable to keep its value between calls.
    if (caller ne 'fetchware') {
        $callback = shift;
        diag("callback[$callback]");
        die <<EOD if ref $callback ne 'CODE';
App-Fetchware: start() was called from a package other than 'fetchware', and with an
argument that was not a code reference. Outside of package 'fetchware' this
subroutine can only be called with a code reference as its one and only
argument.
EOD
        return 'Callback added.';
    # We *were* called in package fetchware.
    } else {
        # Only execute and return the specified $callback, if it has previously
        # been defined. If it has not, then execute the rest of this subroutine
        # normally.
        if (defined $callback and ref $callback eq 'CODE') {
            return $callback->(@_);
        }
    }


    my $build_path = shift;

    msg "Uninstalling package unarchived at path [$build_path]";

    # chdir to $build_path so make will find the correct make file!.
    ###BUGALERT### Refactor our chdir to its own subroutine that cmd_install and
    #uninstall can share.
    chdir $build_path or die <<EOD;
App-Fetchware: Failed to uninstall the specified package and specifically to change
working directory to [$build_path] before running make uninstall or the
uninstall_commands provided in this package's Fetchwarefile. Os error [$!].
EOD
    vmsg "chdir()d to build path [$build_path].";



    if (defined config('uninstall_commands')) {
        vmsg 'Uninstalling using user specified uninstall commands.';
        # Support multiple options like install_commands 'make', 'install';
        for my $uninstall_command (config('uninstall_commands')) {
            # If a /,\s+/ is present in a $uninstall_command
            # To support: build_commands './configure, make';
            if ($uninstall_command =~ /,\s*/) {
                # split on it, and run each resulting command.
                my @uninstall_commands = split /,\s*/, $uninstall_command;
                for my $split_uninstall_command (@uninstall_commands) {
                    my ($cmd, @options) = split ' ', $split_uninstall_command;
                    run_prog($cmd, @options);
                }
            # Or just run the one command.
            } else {
                my ($cmd, @options) = split ' ', $uninstall_command;
                run_prog($cmd, @options);
            }
        }
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
    end sub {
        # Callback that replaces end()'s behavior.
        # Callback receives the same arguments as end(), and is must return
        # the same number and type of arguments that end() returns.
    };

=over
=item Configuration subroutines used:
=over
=item none

=back

=back

end() is called after all of the other main fetchware subroutines such as
lookup() are called. It's job is to cleanup after everything else. It just
calls C<File::Temp>'s internalish File::Temp::cleanup() subroutine.

It also calls the very internal only __clear_CONFIG() subroutine that clears
App::Fetchware's internal %CONFIG variable used to hold your parsed
Fetchwarefile. 

=cut

sub end (;$) {
    # Based on what package we're called in, either accept a callback as an
    # argument and save it for later, or execute the already saved callback.
    state $callback; # A state variable to keep its value between calls.
    if (caller ne 'fetchware') {
        $callback = shift;
        diag("callback[$callback]");
        die <<EOD if ref $callback ne 'CODE';
App-Fetchware: end() was called from a package other than 'fetchware', and with an
argument that was not a code reference. Outside of package 'fetchware' this
subroutine can only be called with a code reference as its one and only
argument.
EOD
        return 'Callback added.';
    # We *were* called in package fetchware.
    } else {
        # Only execute and return the specified $callback, if it has previously
        # been defined. If it has not, then execute the rest of this subroutine
        # normally.
        if (defined $callback and ref $callback eq 'CODE') {
            return $callback->(@_);
        }
    }

    # Use cleanup_tempdir() to cleanup your tempdir for us.
    cleanup_tempdir();
}



1;

__END__


=head1 SYNOPSIS


    ### App::Fetchware's use inside a Fetchwarefile.
    ### See fetchware's new command for an easy way to create Fetchwarefiles.
    use App::Fetchware;

    # Only the App:Fetchware import and program and lookup_url config options
    # are mandatory, but this can change if you use a App::Fetchware extension.
    program 'Your program';
    filter 'version-2';
    temp_dir '/var/tmp';
    user 'me';
    prefix '/opt';
    configure_options '--docdir=/usr/share/doc';
    make_options '-j 4';
    build_commands './configure', 'make';
    install_commands 'make install';
    lookup_url 'http://whatevermirror.your/program/is/on';
    lookup_method 'versionstring';
    gpg_key_url 'http://whatevermirror.your/program/gpg/key/url.asc';
    sha1_url 'http://whatevermirror.your/program/sha1/url.sha1';
    md5_url 'http://whatevermirror.your/program/md5/url.md5';
    verify_method 'gpg';
    no_install 'True';
    verify_failure_ok 'False';
    mirror 'http://whatevermirror1.your/program/is/on';
    mirror 'http://whatevermirror2.your/program/is/on';
    mirror 'http://whatevermirror3.your/program/is/on';
    mirror 'http://whatevermirror4.your/program/is/on';
    mirror 'http://whatevermirror5.your/program/is/on';

    ### This is how Fetchwarefile's can replace lookup()'s or any other
    ### App::Fetchware API subroutine's default behavior.
    ### Remember your coderef must take the same parameters and return the same
    # value.
    lookup sub {
        # Callback that replaces lookup()'s behavior.
        # Callback receives the same arguments as lookup(), and is must return
        # the same number and type of arguments that lookup() returns.
        return $download_url;
    };


    # App::Fetchware's API
    # How fetchware calls App::Fetchware's API.
    use App::Fetchware;
  
    my $temp_dir = start();

    my $download_url = lookup();

    my $package_path = download($download_url);

    verify($download_url, $package_path)

    my $build_path = unarchive($package_path)

    'build succeeded' = build($build_path)

    'install succeeded' = install();

    'uninstall succeeded' = uninstall($build_path)

    end();

    ### See EXTENDING App::Fetchware WITH A MODULE for details on how to extend
    ### fetchware with a module to install software that App::Fetchware's
    ### configuration file syntax that's not flexible enough.

=cut


=head1 DESCRIPTION

App::Fetchware represents fetchware's API. For ducumentation on how to use
App::Fetchware's fetchware command line interface see L<fetchware>.

It is the heart and soul of fetchware where all of fetchware's main behaviors
are kept in its API, which consists of the subroutines start(), lookup(),
download(), verify(), unarchive(), build(), install(), uninstall(), and end().


App::Fetchware stores both details about C<fetchware>'s configuration file
syntax, documents how to create a fetchware extension, and documents the
internal workings of how App::Fetchware implements C<fetchware>'s package
management behavior:

=over

=item *

For details on App::Fetchware's configuration file syntax see the section L<CREATING A App::Fetchware FETCHWAREFILE> and the section L<MANUALLY CREATING A App::Fetchware FETCHWAREFILE> for more details, and how to create one in a text editor without C<fetchware new>'s help.

=item *

If the needs of your program how overcome the capabilities of App::Fetchware's
configuration options, then see the section
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

=item 3. Afterwards, it will ask you if you would like to go ahead and use your newly created Fetchwarefile to install your new program as a fetchware package.  If you answer yes, the default, it will install it, but if you anwer no; instead, it will simply print out the location to the Fetchwarefile that it created for you.

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
C<[program_name]> with what you choose your C<program_name> to be.
C<program_name> is simply a configuration option that simply names your
Fetchwarefile. It is not actually used for anything other than to name your
Fetchwarefile to document what program or behavior this Fetchwarefile manages.

    use App::Fetchware;

    # [program_name] - explain what [program_name] does.

    program_name '[program_name]';

Fetchwarefiles are actually small, well structured, Perl programs that can
contain arbitrary perl code to customize fetchware's behavior, or, in most
cases, simply specify a number of fetchware or a fetchware extension's
configuration options. Below is my filled in example App::Fetchware
fetchwarefile.

    use App::Fetchware::HTMLPageSync;

    # Cool Wallpapers - Downloads cool wall papers.

    program_name 'Cool Wallpapers';

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
want fetchware to manage for you's Web site. Then find the download link
section, and right click on this link, and select "copy url location" or
whatever your Brower says that means the same thing. After that paste this link
into your browser, and delete the last bit up to the right most slash. Finally
click enter, and this should take you to a FTP or HTTP directory listing for
your program. This is exactly what you want your C<lookup_url> to be, and
then copy and paste the url between the single quotes C<'> as shown in the
example below.

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

And then after you copy the url.

    filter 'http://some.url/something.html';

=item B<4. Specifiy other options>

That's all there is to it unless you need to further customize App::Fetchware's
behavior to modify how your program is installed.

At this point you can install your new Fetchwarefile as a fetchware package
with:

    fetchware install [path to your new fetchwarefile]

Or you can futher customize it as shown next.

=item B<5. Optionally add build and install settings>

If you want to specify further settings the first to choose from are the
L<build and install settings|/"WHEREEVERTHEYARE">. These settings control how
fetchware builds and installs your software. They are briefly listed below. For
further details see the section
L<App::Fetchware FETCHWAREFILE CONFIGURATION OPTIONS>.

=over

=item B<temp_dir> - Specifies the temporary directory fetchware will use to create its own working temporary directory where it downloads, unarchives, builds, and then installs your program from a directory inside this directory.

###BUGALERT### Not actually implemented yet!!!

=item B<user> - (UNIX only) - Specifies a non-root user to drop priveledges to when downloading, verifying, unarchive, and building your program. Root priveedges are kept in the parent process for install if needed.

=item B<prefix> - Specifies the --prefix option for AutoTools (./configure) based programs.

=item B<configure_options> - Specifies any additional options that fetchware should give to AutoTools when it runs ./configure to configure your program before it is built and installed.

=item B<make_options> - Specifies any command line options you would like to provide to make when make is run to build and install your software. C<-j 4> is quite popular to do a paralled make to build and install the program faster.

=item B<build_commands> - Specifies a list of commands that fetchware will use to build your program. You only need this option if your program uses a build system other than AutoTools such as C<cmake> or perhaps a custom one like Perl's C<Configure>

=item B<install_commands> - Specifies a list of commands that fetchware will use to install your program. You only need this option if your program uses a build system other than AutoTools such as C<cmake> or perhaps a custom one like Perl's C<Configure>

=item B<no_install> - Specifies a boolean (true or false) value to turn off fetchware installing the software it has downloaded, verified, unarchvied, and built. If you specify a true argument (1 or 'True' or 'On'), then fetchware will C<not> install your program; instead, it will leave its temporary directory intact, and print out the path of this directory for you to inspect and install yourself. If you don't specify this argument, comment it out, or provide a false argument (0 or 'False' or 'Off'), then fetchware C<will> install your program.

=back

Just copy and paste the example below replacing C<[new_directive]> with the name
of the new directive you would like to add, and fill in the space between the
single quotes C<'>.

    [new_directive] '';

After pasting it should look like.

    [new_directive] '~/wallpapers';


=item B<6. Optionally add verification settings>

You can also add verification settings that will gpg, sha1 or md5 verify the
software package that is downloaded. This is supported out of the box without
these settings by simply adding a C<.asc, .sig, .sha1, or .md5> to the download
url that fetchware determines. So out of the box all programs that upload a gpg
.asc file to cryptographically verify the package work wihout configuration.
Please see
L<verification settings|/"WHEREEVERTHEYARE">. These settings control how
fetchware verifies your downloaded software. They are briefly listed below. For
further details see the section
L<App::Fetchware FETCHWAREFILE CONFIGURATION OPTIONS>.

=over

=item B<gpg_key_url> - Specifies an alternate directory url to use to try to download a gpg signature file that usually has a C<.asc> or a C<.sig> file extension.

=item B<sha1_url> - Specifies a directory url to use to download a SHA1 checksum.  This should only specify the master download site not a mirror, because of security concerns.  

=item B<md5_url> - Specifies a directory url to use to download a MD5 checksum.  This should only specify the master download site not a mirror, because of security concerns.  

=back

=over

=item NOTICE: There is no configuration option to change what filename fetchware uses. You're stuck with its default of what fetchware determines your $download_url to be with the appropriate C<.asc>, C<sha1>, or C<.md5> added to it.

=back

Just copy and paste the example below replacing C<[new_directive]> with the name
of the new directive you would like to add, and fill in the space between the
single quotes C<'>.

    [new_directive] '';

After pasting it should look like.

    [new_directive] '~/wallpapers';

=item B<7. Optionally Specify additional mirrors>

###BUGALERT### mirrors are not actually implemented yet, so implement them.
Fetchware supports additional mirrrors. These additional mirrors are only used
if the main mirror specified by your C<lookup_url> or one of the verification
url's fails to download a directory listing or a file. The list is simply tried
in order from the first to the last, and it fails only if all of the mirrors
fail. Please see
L<mirror settings/"WHEREEVERTHEYARE"> for a longer explanation. It is briefly
listed below. For further details see the section
L<App::Fetchware FETCHWAREFILE CONFIGURATION OPTIONS>.

Fill in the space between the single quotes C<'> with the B<only> the server
portion of the mirror's address.

    mirror '';

After pasting it should look like.

    mirror 'mirror1.url';

However mirror is the I<only> fetchware configuration option that supports being
used more than once in a Fetchwarefile. You can take advantage of this to add
more that one mirror to your Fetchwarefile.

    mirror 'mirror2.url';
    mirror 'mirror3.url';
    mirror 'mirror4.url';
    mirror 'mirror5.url';
    mirror 'mirror6.url';

=back

=cut


=head1 USING YOUR App::Fetchware FETCHWAREFILE WITH FETCHWARE

After you have
L<created your Fetchwarefile|/"MANUALLY CREATING A App::Fetchware FETCHWAREFILE">
as shown above you need to actually use the fetchware command line program to
install, upgrade, and uninstall your App::Fetchware Fetchwarefile.

=over

=item B<install>

A C<fetchware install> while using a App::Fetchware Fetchwarefile causes
fetchware to install your fetchwarefile to your computer as you have specified
any build or install options.

=item B<upgrade>

A C<fetchware upgrade> while using a App::Fetchware Fetchwarefile will simply run
the same thing as install all over again, which will upgrade your program if a
new version is available.

=item B<uninstall>

###BUGALERT### Implement the uninstall_commands configuration option
A C<fetchware uninstall> will cause fetchware to run the command
C<make uninstall>, or run the commands specified by the C<uninstall_commands>
configuration option. C<make uninstall> is only available from some programs
that use AutoTools such as ctags, but apache, for example, also uses AutoTools,
but does not provide a uninstall make target. Apache for example, therefore,
cannot be uninstalled by fetchware automatically.

=back

=cut


=head1 App::Fetchware'S FETCHWAREFILE CONFIGURATTION OPTIONS

App::Fetchware has many configuration options. Most were briefly described in
the section L<MANUALLY CREATING A App::Fetchware FETCHWAREFILE>. All of them are
detailed below.

=head2 program 'Program Name';

C<program> simply gives this Fetchwarefile a name. It is availabe to fetchware
after parsing your Fetchwarefile, and is used to name your Fetchwarefile when
using C<fetchware new>. It is not strictly necessary like C<lookup_url> and
perhaps C<filter> are, and can be skipped, but using it is recommended.

=head2 filter 'perl regex here';

See L<perlretut> for details on how to use and create Perl regular expressions;
however, actual regex know how is not really needed just paste verbatim text
between the single quotes C<'>. For example, C<filter 'httpd-2.2';>.

=head2 temp_dir '/var/tmp'; #UNIMPLEMENTED!!!

C<temp_dir> tells fetchware where to store fetchware's temporary working
directory that it uses to download, verify, unarchive, build, and install your
software. By default it uses your system temp directory, which is whatever
directory L<File::Temp::tempdir> decides to use.

=head2 user 'nobody'; # UNIMPLEMENTED!!!

Tells fetchware what user it should drop priveledges to. The default is
C<nobody>, but you can specify a different username with this configuration
option if you would like to.

This option allows fetchware to avoid downloading files and executing
anything inside the downloaded archive as root. Except of course the commands
needed to install the software, which will still need root to able to write
to system directories. This improves security, because the downloaded software
won't have sytem priveldeges until after it is verified, prooviing that what you
downloaded is exactly what the author uploaded.

Note this only works for unix like systems, and is not used on Windows and
other non-unix systems.

=head2 lookup_url 'ftp://somedomain.com/some/path

This is the only B<required> configuration option. Every other necessary option
has a default or is not needed. This one is mandatory. This configuration option
specifies a url of a FTP or HTTP directory listing that fetchware can download,
and use to determine what actual file to download and perhaps also what version
of that program to download if more than one version is available as some
mirrors delete old versions and only keep the latest one.

This url is used for:

=over

=item 1. To determine what the actual download url is for the latest version of this program

=item 2. As the base url to also download a cryptographic signature (ends in .asc) or a SHA-1 or MD5 signature to verify the contents match what the SHA-1 or MD5 checksum is.

You can use the C<mirror> configuration option to specify additional mirrors.
However, those mirrors will only be tried if the main one in the C<lookup_url>
dow not work properly.

=head2 lookup_method 'timestamp';

Fetchware has two algorithms it uses to determine what the properl download_url
is:

=over

=item timestamp

The timestamp algorithm simply uses the mtime (last modification time) that is
availabe in FTP and HTTP directory listings to determine what file in the
directory is the newest.

=item versionstring

Versionstring parses out the version numbers that each downloadable program has,
and uses them to determine the downloadable archive with the highest version
number, which should also be the newest and best version of the archive to use.

=back

=head2 gpg_key_url 'mastermirror.com/some/path';

Specifies an alternate url to use to download the cryptographic signature that
goes with your program. This is usually a file with the same name as the
download url with a C<.asc> file extension added on.

Because this file is cryptographically signed you can safely download it from
any mirror.

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

However, if the author of a program you want to use fetchware to manage for you
does not offer a gpg, sha1, or md5 file to verify its integrity, then you can
use this option to force Fetchware to install this program anyway. However, do
not enable this option lightly. Please scour the program's mirrors and homepage
to see which C<gpg_key_url>, C<sha1_url>, or C<md5_url> you can use to ensure
that your archive is verified before it is compiled and installed.

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

=head2 configure_options '--datadir=/var/mysql';

Provides options to AutoTools C<./configure> program that configures the source
code for building. Most programs don't need this, but some like Apache and MySQL
need lots of options to configure them properly. In order to provide multiple
options do not separate them with spaces; instead, separate them with commas and
keep single quotes C<'> around them like in the example below.

    configure_options '--datadir=/var/mysql', '--mandir=/opt/man',
        '--enable-module=example';

This option is B<not> compatible with C<build_commands>. If you use
C<build_commands>, than this optio will B<not> be used.

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

=head2 no_install

This boolean, see below, configuration option determines if fetchware should
install your software or not install your software, but instead print out the
path of its build directory, so that you can test or review the software before
you install it.

=over

=item NOTICE

C<no_install> is a boolean configuration option, which just means its
values are limited to either true or false. True values are C<'True'>, C<'On'>,
C<1>, and false values are C<'False'>, C<'Off'>, and C<0>. All other values are
syntax errors.

=back

=head2 mirror 'somemirror0.com/some/path';

Allows you to specify additional mirrors to use in case the main one listed in
your C<lookup_url> fails. This configuration option, unlike all the others, can
be specified more than once. So, for example you could put:

    mirror 'somemirror1.com';
    mirror 'somemirror2.com';
    mirror 'somemirror3.com';
    mirror 'somemirror4.com';
    mirror 'somemirror5.com';

In your Fetchwarefile, and if fetchware fails to download the directory listing
in your C<lookup_url>, then fetchware will try these other hostnames in the
order they appear in your Fetchwarefile.

However, if you specify a path in addition to just the hostname, then fetchware
will try to get whatever it wants to download at that alternate path as well.

    mirror 'somemirror6./com/alternate/path';

###BUGALERT### mirror is *not* actually implemented yet.

###BUGALERT### Should the =head2's below be described here or in the fetchware
#extension section???

=head2 start
=head2 lookup
=head2 download
=head2 verify
=head2 unarchive
=head2 build
=head2 install
=head2 end
=head2 uninstall

=head2 config
=head2 make_config_sub

=cut


=head1 FURTHER CUSTOMIZING YOUR FETCHWAREFILE

Because fetchware's configuration files, its Fetchwarefiles, are little Perl
programs, you have the full power of Perl at your disposal to customize
fetchware's behavior to match what you need fetchware to do to install your
source code distributions.

Not only can you use arbitrary Perl code in your Fetchwarefile to customize
fetchware for programs that don't follow most FOSS mirroring unwritten standards
or use a totally different build system, you can also create a fetchware
extension. Creating a fetchware extension even allows you to turn your extension
into a proper CPAN distribution, and upload it to CPAN to share it with
everybody else. See the section below,
L<CREATING A FETCHWARE EXTENSION>, for full details.


=head2 How Fetchware's configuration options are made

Each configuration option is created with the make_config_sub() subroutine
L<make_config_sub()|/make_config_sub()> (Did <-- work????)
(see the section L<FETCHWAREFILE API SUBROUTINES> for its documentation). This
subroutine is a simple code generator that generates configuration subroutines.
These subroutines have the same names as fetchware's configuration options,
because that is exactly what they are. Perl's L<Prototypes|perlsub/Prototypes>
are used in the code that is generated, so that you can remove the parentheses
typically required around each configuration subroutine. This turns what looks
like a function call into what could believably be considered a configuration
file syntax.

These prototypes turn:

    lookup_url('http://somemirror.com/some/path');

Into:

    lookup_url 'http://somemirror.com/some/path';

Perl's prototypes are not perfect. The single quotes and semicolon are still
required, but the lack of parens instantly makes it look much more like a
configuration file syntax, then an actual programming language.

=head2 The magic of C<use App::Fetchware;>

The real magic power behind turning a Perl program into a configuration file
sytanx comes from the C<use App::Fetchware;> line. This line is single handedly
responsible for making this work. This one line imports all of the configuration
subroutines that make up fetchware's configuration file syntax. And this
mechanism is also behind fetchware's extension mechanism. (To use a
App::Fetchware extension, you just C<use> it. Like
C<use App::Fetchware::HTMLPageSync;>. That's all there is to it. This I<other>
App::Fetchware is responsible for exporting subroutines of the same names as
those that make up App::Fetchware's API. These subroutines are listed in the
section L<FETCHWAREFILE API SUBROUTINES> as well as their helper subroutines.
See the section below L<CREATING A FETCHWARE EXTENSION> for more information on
how to create App::Fetchware extensions.

=head2 So how do I add some custom Perl code to customize my Fetchwarefile?

Well, you can just put random perl code wherever you want in your Fetchwarefile,
but you must then connect that code back into App::Fetchware's API. To do that
use one of the configuration option hooks, which have the same name as
App::Fetchware's main API. These hooks are start(), lookup(), download(),
verify(), unarchive(), build(), install(), uninstall(), and end(). So to
completely replace App::Fetchare's lookup() subroutine, because perhaps your
program needs a totally different way of of checking if a new version is
available, you only need to use that hook as though it were a configuration
option:

    lookup sub {
        # Your replacement for lookup() goes here.
    };

However, that is not quite right, because some of App::Fetchware's API
subroutines take important arguments and return important arguments that are
then passed to other API subroutines later on. So, your I<replacement> lookup()
B<must> take the same arguments and B<must> return the same values that the
other App::Fetchware subroutines may expect to be passed to them. So, let's fix
lookup(). Just check lookup()'s documentation to see what its arguments are and
what it returns by checking out the section L<FETCHWAREFILE API SUBROUTINES>:

    lookup sub {
        # lookup does not take any arguments.
        
        # Your replacement for lookup() goes here.
        
        # Must return the same thing that the original lookup() does, so
        # download() and everything else works the same way.
        return $download_url;
    };

Some App::Fetchware API subroutines take arguments, so be sure to account for
them:

    download sub {
        # Take same args as App::Fetchware's download() does.
        my $download_url = shift;
        
        # Your replacement for download() goes here.
        
        # Must return the same things as App::Fetchware's download()
        return $package_path;
    };

If changing lookup()'s behavior or even one of the other App::Fetchware
subroutines, and you only want to change part of its behavior, then consider
using one of the C<:OVERRIDE_*> tags. These tags exist for most of the
App::Fetchware API subroutines, and are listed below along with what helper
subroutines they import with them. To check their documentation see the section 
L<FETCHWAREFILE API SUBROUTINES>.

=over

=item B<OVERRIDE_LOOKUP> - check_lookup_config, get_directory_listing, parse_directory_listing, determine_download_url, ftp_parse_filelist, http_parse_filelist, file_parse_filelist, lookup_by_timestamp, lookup_by_versionstring, lookup_determine_downloadurl

=item B<OVERRIDE_DOWNLOAD> - download_ftp_url, download_http_url, determine_package_path

=item B<OVERRIDE_VERIFY> - gpg_verify, sha1_verify, md5_verify, digest_verify

=item B<OVERRIDE_UNARCHIVE> - check_archive_files    

=item B<OVERRIDE_BUILD> -  none.

=item B<OVERRIDE_INSTALL> - none.

=item B<OVERRIDE_UNINSTALL> - none.

=back

An example:

    use App::Fetchware ':OVERRIDE_LOOKUP';

    ...

    lookup sub {

        ...

        # ...Download a directory listing....
        ###BUGALERT### improve this example.

        # Use same lookup alorithms that lookup() uses.
        return lookup_by_versionstring($filename_listing);
        
        # Return what lookup() needs to return.
        return $download_url;
    };

Feel free to specify a list of the specifc subroutines that you need to avoid
namespace polution, or install and use L<Sub::Import> if you demand more control
over imports.

=head2 A real example

    ###BUGALERT### Actually create a useful example!!!!!!

###BUGALERT### Add an section of use cases. You know explaing why you'd use
#no_install, or why'd you'd use look, or why And so on.....

=cut


=head1 CREATING A FETCHWARE EXTENSION

Fetchware's main program C<fetchware> uses App::Fetchware's short and simple API
to implement fetchware's default behavior; however, other styles of source code
distributions exist on the internet that may not fit inside App::Fetchware's
capabilities. In addition to its flexible configuration file sytax, that is why
fetchware allows modules other than App::Fetchware to provide it with its
behavior.

=head2 How the API works

When fetchware install or upgrades something it executes the API subroutines
start(), lookup(), download(), verify(), unarchive(), build(), install(), and
end() in that order. And when fetchware uninstalls and installed package it
executes the API subroutines start(), part of build(), uninstall(), and end().


=head2 Extending App::Fetchware

This API can be overridden inside a user created Fetchwarefile by supplying a
C<CODEREF> to any of the API subroutines that I mentioned above. This C<CODEREF>
simply replaces the default App::Fetchware API subroutine of that name's
behavior. This C<CODEREF>  is expected to take the same parameters, and return
the same thing th main API subroutine does.

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
implemnted in a App::Fetchware L<subclass>.

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
then actually implement the remaining subroutines, so that you App::Fetchware
I<subclass> has the same interface that App::Fetchware does.

To create a fetchware extension you must understand how they work:

=over

=item 1. First a Fetchwarefile is created, and what module implements App:Fetchware's API is declared with with a C<use App::Fetchware...;> line. This line is C<use App::Fetchware> for default Fetchwarefiles that use App::Fetchware to provide C<fetchware> with the API it needs to work properly.

=item 2. To use a fetchware extension, you simply specify the fetchware
extension you want to use with a C<use App::Fetchware...;> instead of specifying
C<use App::Fetchware> line in your Fetchwarefile. You B<must> replace the
App::Fetchware import with the extension's. Both cannot be present. Fetchware
will exit with an error if you use more than one App::Fetchware line without
specifying specific subroutines in all but one of them.

###BUGALERT### Write code to actualy check the use App::Fetchware crap in
#parse_fetchwarefile().

=item 3. Then when C<fetchware> parses this Fetchwarefile when you use it to install, upgrade, or uninstall something, This C<use App::Fetchware...;> line is what imports App::Fetchware's API subroutines into C<fetchware>'s namespace.

=back

That's all there is to it. That simple C<use App::Fetchware...;> imports from
App::Fetchware or a App::Fetchware extension such as
App::Fetchware::HTMLPageSync the API subroutines C<fetchware> needs to use to
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

###BUGALERT### Is uninstall() calling API subs a bug??? Should it just use the
#lower level library functions of these tools. Have it do this after I subify
#the rest of the API subs like I've done to lookup and download.

=back

Use the above overview of App::Fetchware's API to design what each API
subroutine keeping in mind its arguments and what its supposed to return.

###BUGALERT### Add strict argument checking to App::Fetchware's API subroutines
#to check for not being called correctly to aid extension debugging.

=head2 Determine your fetchware extension's Fetchwarefile configuration options.

App::Fetchware has various configuration options such as C<temp_dir>, C<prefix>,
and so on. Chances are your fetchware extension will also need such
configuration options. These are easily created with App::Fetchware's API
subroutine make_config_sub(), which manufactures these to order for your
convenience. There are four different types of configuration options:

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
C<make_config_sub> in the L<FETCHWAREFILE API SUBROUTINES> section, determine
the names of your configuration options, and what type of configuraton options
they will be.

=head2 Implement your fetchware extension.

Since you've designed your new fetchware extension, now it's time to code it up.
The easiest way to do so, is to just take an existing extension, and just copy
and paste it, and then delete its specifics to create a simple extension
skeleton. Then just follow the steps below to fill in this skeleton with the
specifics needed for you fetchware extension.

###BUGALERT### Create a fetchware command to do this for users perhaps even
#plugin it into Module::Starter???? If possible.
####BUGALERT## Even have so that you can specify which API subs you want to
#override or avoid overriding, and then it will create the skelton with stubs
#for those API sub already having some empty POD crap and the correct
#prototypes.

=over

=item 1. Code any App::Fetchware API subroutines that you won't be reusing from App::Fetchware.

Use their API documentation from the section L<FETCHWAREFILE API SUBROUTINES> to
ensure that you use the correct subroutine names, prototypes, arguments and
return the correct value as well.

###BUGALERT### Add the prototypes to the API docs.

An example for overriding lookup() is below.

    =head2 lookup()

        my $download_url = lookup();

    # New lookup docs go here....

    =cut

    sub lookup (;$) {

        # New code for new lookup() goes here....

        # Return the required $download_url.
        return $download_url;
    }

=item 2. Set up proper exports and imports.

You B<must> import from App::Fetchware any App::Fetchware API subroutines you
intend to reuse from App::Fetchware such as start() and end(), or perhaps all of
them but lookup(). So use something like:

    # Import reused API subroutines from App::Fetchware.
    use App::Fetchware qw(start end);

or

    # Import reused API subroutines from App::Fetchware.
    use App::Fetchware qw(start download verify unarchive build install end
        uninstall);

To include whatever subroutines you want to reuse from App::Fetchware.

And you B<must> also setup proper exports to export App::Fetchware's standard
API subroutines that you either imported from App::Fetchware or implemented
yourself and also whatever configuration subroutines that your fetchware
extension created with make_config_sub(). Just customize something like:

    # Setup proper exports of App::Fetchware API subroutines and any
    # configuration subroutines this fetchware extension uses.
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

        # Any configuration subroutines go here.

        # If you're reussing App::Fetchware's start() and end() perhaps you also
        # want to import from App::Fetchware temp_dir, and also export here so
        # users of your Fetchwarefile can change the temporary directory too.
        temp_dir
        ...

    );

=back

Then your fetchware extension has exported the App::Fetchware API subroutines
and any configuraton options that you want users of your fetchware extension to
be able to use to customize their Fetchwarefile.


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
This is done, because everyone who installs fetchware is really gonna freak out
if its test suite installs apache or ctags just to test its package manager
functionality. To use it:

=over

=item 1. Set up an automated way of enabling FETCHWARE_RELEASE_TESTING.

Just paste the frt() bash shell function below. Translating this to your favorit
shell should be pretty straight forward. Do not just copy and paste it. You'll
need to customize the specific C<FETCHWARE_*> environment variables to whatever
mirrors you want to use or whatever actual programs you want to test with. And
you'll have to point the local (file://) urls to directories that actually exist
ono your computer.

    frt() {
        if [ -z "$FETCHWARE_RELEASE_TESTING" ]
        then
            echo -n 'Setting fetchware_release_testing environment variables...';
            export FETCHWARE_RELEASE_TESTING='***setting this will install software on your computer!!!!!!!***'
            export FETCHWARE_FTP_LOOKUP_URL='ftp://carroll.cac.psu.edu/pub/apache/httpd'
            export FETCHWARE_HTTP_LOOKUP_URL='http://mirror.cc.columbia.edu/pub/software/apache//httpd/'
            export FETCHWARE_FTP_DOWNLOAD_URL='ftp://carroll.cac.psu.edu/pub/apache/httpd/httpd-2.2.22.tar.bz2'
            export FETCHWARE_HTTP_DOWNLOAD_URL='http://newverhost.com/pub//httpd/httpd-2.2.22.tar.bz2'
            export FETCHWARE_LOCAL_URL='file:///home/user/software/httpd-2.2.22.tar.bz2'
            export FETCHWARE_LOCAL_BUILD_URL='/home/user/software/ctags-5.8.tar.gz'
            export FETCHWARE_LOCAL_UPGRADE_URL='file:///home/user/software/fetchware-upgrade'
            echo 'done.'
        else
            echo -n 'Deleting fetchware_release_testing environment variables...';
            unset FETCHWARE_RELEASE_TESTING
            unset FETCHWARE_FTP_LOOKUP_URL
            unset FETCHWARE_HTTP_LOOKUP_URL
            unset FETCHWARE_FTP_DOWNLOAD_URL
            unset FETCHWARE_HTTP_DOWNLOAD_URL
            unset FETCHWARE_LOCAL_URL
            unset FETCHWARE_LOCAL_BUILD_URL
            unset FETCHWARE_LOCAL_UPGRADE_URL
            echo 'done.'
        fi
    }

Just run C<frt> with no args to turn FETCHWARE_RELEASE_TESTING on, and run it
once more to turn it off. Don't forget to reload your shells configuration with:

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

If you dislike subtests, or otherwise don't want to use them, then use a
separative file for these subtests.

=back

###BUGALERT### Fix this inflexibiltiy in skip_all_unless_release_testing().
###BUGALERT### skip_all_unless_release_testing() may be compatible if used in a
#SKIP: {...} block, so that's perhaps how it could be used outside of a subtest.

=head2 Share it on CPAN

Fetchware has no Web site or any other place to share fetchware extensions. But
fetchware is written in Perl, so fetchware can just use Perl's CPAN. To learn
how to create modules and upload them to CPAN please see Perl's own
documentation. L<perlnewmod> shows how to create new Perl modules, and howt to
upload them to CPAN. See L<Module::Starter> for a simple way to create a
skeleton for a new Perl module, and L<dzil|http://dzil.org/index.html> is beyond
amazing, but has insane dependencies.

=cut


=head1 FAQ

=head2 Why doesn't fetchware and App::Fetchware use OO or Moose?

One of my goals for fetchware was that its guts be pragmatic. I wanted it to
consist of a bunch of subroutines that simply get executed in a specific order.
And these subroutines should be small and do one an only one thing to make
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

The extension mechanism was design for ease of use for people who use you
fetchware extension. And it is. Just "use" whatever fetchware extension you want
in your Fetchwarefile, and then supplying whatever configuration options you
need.

This extension mechanism is also very easy to Perl programmers, because you're
basically I<subclassing> App::Fetchware, only you have to do it manually:

=over

=item 1. Instead of C<use parent 'App::Fetchware';>, you use
C<use App::Fetchware qw(the subroutines you want to "inherit");>

=item 2. Just like in a real subclass, whatever subroutines you want to "override", you implement in your subclass.

=item 3. Most importantly, Perl does not do any "subroutine resolution." Therefore, you B<must> do this manually by exporting App::Fetchware's API subroutines and whatever configuration options your subclass needs.

=back

###BUGALERT### Move above explanation to where it is explained above.

=head2 How do I fix the verification failed error.

###BUGALERT### Fill this section in!!!!!!!!!

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
capable of doing everything someone can program Perl can do. This is why
App::Fetchware will refuse to execute any Fetchwarefile's that are writable by
anyone other than the owner who is executing them. It will also exit with a
fatal error if you try to use a Fetchwarefile that is not the same user as the
one who is running fetchware. These saftey measures help prevent fetchware being
abused to get unauthorized code executed on your computer.

###BUGALERT### user does nothing and the drop priv code isn't written! Write
#it!!!!!! and test it!!!!!!!!!

App::Fetchware also features the C<user> configuration option that tells
fetchware what user you want fetchware to drop priveledges to when it does
everything but install (install()) and clean up (end()). The configuration
option does B<not> tell fetchware to turn on the drop privelege code; that code
is B<always> on, but just uses the fairly ubuiquitous C<nobody> user by default.
This feature requires the OS to be some version of Unix, because Windows and
other OSes do not support the same fork()ing method of limiting what processes
can do.

=cut


=head1 ERRORS

As with the rest of App::Fetchware, App::Fetchware::Config does not return any
error codes; instead, all errors are die()'d if it's App::Fetchware::Config's
error, or croak()'d if its the caller's fault. These exceptions are simple
strings, and are listed in the L</DIAGNOSTICS> section below.
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
