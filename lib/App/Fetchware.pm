use strict;
use warnings;
package App::Fetchware;

# CPAN modules making Fetchwarefile better.
use File::Temp 'tempdir';
use File::Spec::Functions qw(catfile splitpath updir splitdir file_name_is_absolute);
use Data::Dumper;
use Net::FTP;
use HTTP::Tiny;
use HTML::TreeBuilder;
use Scalar::Util 'blessed';
use IPC::System::Simple 'system'; # remove me later???
use Digest;
use Digest::SHA;
use Digest::MD5;
#use Crypt::OpenPGP::KeyRing;
#use Crypt::OpenPGP;
use Archive::Extract;
use Test::More 0.98; # some utility test subroutines need it.

# Enable Perl 6 knockoffs.
use 5.010;

# Set up Exporter to bring App::Fetchware's API to everyone who use's it
# including fetchware's ability to let you rip into its guts, and customize it
# as you need.
use Exporter qw( import );
# By default fetchware exports its configuration file like subroutines and
# fetchware().
#
# These days popular dogma considers it bad to import stuff without be asked to
# do so, but App::Fetchware is meant to be a configuration file that is both
# human readable, and most importantly flexible enough to allow customization.
# This is done by making the configuration file a perl source code file called a
# Fetchwarefile that fetchware simply executes. The magic is in the fetchware()
# and override() subroutines.
our @EXPORT = qw(
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
    fetchware
    override
);
# These tags go with the override() subroutine, and together allow you to
# replace some or all of fetchware's default behavior to install unusual
# software.
our %EXPORT_TAGS = (
    OVERRIDE_LOOKUP => [qw(
        check_lookup_config
        download_directory_listing
        parse_directory_listing
        determine_download_url
        ftp_parse_filelist
        http_parse_filelist
        lookup_by_timestamp
        lookup_by_versionstring
        lookup_determine_downloadurl
    )],
    # No OVERRIDE_START OVERRIDE_END because start() does *not* use any helper
    # subs that could be beneficial to override()rs.
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
    OVERRIDE_UNARCHIVE => [qw(
        check_archive_files    
    )],
    OVERRIDE_BUILD => [qw()],
    OVERRIDE_INSTALL => [qw()],
    # Testing also imports lookup(), download(), etc, so that test scripts don't
    # need to add them.
    TESTING => [qw(
        eval_ok
        skip_all_unless_release_testing
        clear_FW
        start
        lookup
        download
        verify
        unarchive
        build
        install
        end
    )],
    UTIL => [qw(
        download_dirlist
        ftp_download_dirlist
        http_download_dirlist
        download_file
        download_ftp_url
        download_http_url
        just_filename
    )],
);
# OVERRIDE_ALL is simply all other tags combined.
@{$EXPORT_TAGS{OVERRIDE_ALL}} = map {@{$_}} values %EXPORT_TAGS;
# *All* entries in @EXPORT_TAGS must also be in @EXPORT_OK.
our @EXPORT_OK = @{$EXPORT_TAGS{OVERRIDE_ALL}};



# Hash of configuration variables Fetchwarefiles may use to configure
# fetchware's default behavior using a simple obvious Moose-like declarative
# syntax such as configure_prefix '/usr/local'; to make Fetchwarefile's, which
# are straight up perl .pl files without the extension.
my %FW;
# Give fetchware's test suite access to an otherwise private variable. Note the
# double underscores, which make it *extra* private instead of just private.
# Note: this subroutine is *not* exported on purpose to make abusing it harder.
sub __FW {
    return \%FW;
}



=head1 FETCHWAREFILE API SUBROUTINES

The subroutines below B<are> Fetchwarefile's API subroutines, but I<more
importantly> also Fetchwarefile's configuration file syntax See the SECTION
L<FETCHWAREFILE CONFIGURATION SYNTAX> for more information regarding using these
subroutines as Fetchwarefile configuration syntax.

=cut


=over

=item 'ONE' Fetchwarefile API Subroutines.

=over
=item filter $value;
=item temp_dir $value;
=item user $value;
=item no_install $value;
=item prefix $value;
=item configure_options $value;
=item make_options $value;
=item build_commands $value;
=item install_commands $value;
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

=item fetchware;

C<fetchware> is the subroutine that actually causes the Fetchwarefile to
execute fetchware's B<default, bult-in functionality>. If it is left out, then
the Fetchwarefile is incomplete, and will not actually do anything. The only
time to leave C<fetchware> out of a Fetchwarefile is if you want to customize
fetchware's behavior using App::Fetchware's API.

To customize your fetchware file, if fetchware's defaults or its configuration
subroutines are not enough, then you can use override() to override any of the
subroutines that fetchware() would normally call. For example, you could
override the lookup() subroutine, or you could just override one of the
subroutines lookup() calls. It's very flexible and reusable. See
L<CUSTOMIZING YOUR FETCHWAREFILE> below for the details.

It's not fancy on purpose, because it is meant to be dead simple, and easy to
implement and pragmatic.  

=back

=cut




=head1 CUSTOMIZING YOUR FETCHWAREFILE

When fetchware's default behavior and configuration are B<not> enough you can
replace your call to C<fetchware;> with C<override;> that allows you to replace
each of the steps fetchware follows to install your software.

If you only want to replace the lookup() step with your own, then just replace
your call to C<fetchware;> with a call to C<override> specifing what steps you
would like to replace as explained below.

If you also would like to have access to the functions fetchware itself uses to
implement each step, then specify the :OVERRIDE_<STEPNAME> tag when C<use>ing
App::Fetchware like C<use App::Fetchware :OVERRIDE_LOOKUP> to import the
subroutines fetchware itself uses to import the lookup() step of installation.
You can also use C<:OVERRIDE_ALL> to import all of the subroutines fetchware uses
to implement its behavior.  Feel free to specify a list of the specifc
subroutines that you need to avoid namespace polution, or install and use
L<Sub::Exporter> if you demand more control over imports.

=cut

=over

=item override LIST;

Used instead of C<fetchware;> to override fetchware's default behavior. This
should only be used if fetchware's configuration options do B<not> provide the
customization that your particular program may need.

The LIST your provide is a fake hash of steps you want to override as keys and a
coderef to a replacement subroutine like:
C<override lookup => \&overridden_lookup;>



=cut

sub override (@) {
    my %opts = @_;

    # override the parts that need overriden as specified in %opts.

    # Then execute just like fetchware; does, but exchanging the default steps
    # with the overriden ones.

    die <<EOD if %opts = ();
App-Fetchware: syntax error: you called override with no options. It must be
called with a fake hash of name value pairs where the names are the names of the
Fetchwarefile steps you would like to override, and the values are a coderef to
a subroutine that implements that steps behavior. See perldoc App::Fetchware.
EOD

    ###BUGALERT### update to support all of the subs that lookup() and etc...
    #call. Update pod above accordingly.
    defined $opts{lookup} ? $opts{lookup}->() : lookup();
    defined $opts{download} ? $opts{download}->() : download();
    defined $opts{verify} ? $opts{verify}->() : verify();
    defined $opts{unarchive} ? $opts{unarchive}->() : unarchive();
    defined $opts{build} ? $opts{build}->() : build();
    defined $opts{install} ? $opts{install}->() : install();

}

# End over CUSTOMIZING YOUR FETCHWAREFILE.

=back

=cut



=head1 App::Fetchware API SUBROUTINES

These subroutines constitute App::Fetchware's API that C<Fetchwarefile>'s may
use to customize fetchware's default behavior using C<override> instead of
C<fetchware>

Below is a API Reference, for instructions on how to customize your
Fetchwarefile beyond fetchware's configuration subroutines allow please see
L<CUSTOMIZING YOUR FETCHWAREFILE>.

=over

=item make_config_sub($name, $one_or_many_values)

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

=item $one_or_many_values Supported Values

=over

=item * 'ONE'

Generates a function with the name of make_config_sub()'s first parameter that
can B<only> be called one time per Fetchwarefile. If called more than one time
will die with an error message.

Function created with C<$FW{$name} = $value;> inside the generated function that
is named $name.

=item * 'MANY'

Generates a function with the name of make_config_sub()'s first parameter that
can be called more than just once. This option is only used by fetchware's
C<mirror()> API call.

Function created with C<push @{$FW{$name}}, $value;> inside the generated function that
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

BEGIN { # BEGIN BLOCK due to api subs needing prototypes.
###BUGALERT### Replace BEGIN & eval's with AUTOLOAD???
    my @api_functions = (
        [ filter => 'ONE' ],
        [ temp_dir => 'ONE' ],
        [ user => 'ONE' ],
        [ prefix => 'ONEARRREF' ],
        [ configure_options=> 'ONEARRREF' ],
        [ make_options => 'ONEARRREF' ],
        [ build_commands => 'ONEARRREF' ],
        [ install_commands => 'ONEARRREF' ],
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
                ###BUGALERT### the ($) sub prototype needed for ditching parens must
                #be seen at compile time. Is "eval time" considered compile time?
                my $eval = <<'EOE'; 
sub $name (@) {
    my $value = shift;
    
    die <<EOD if defined $FW{$name};
App-Fetchware: internal syntax error: $name was called more than once in this
Fetchwarefile. Currently only mirror supports being used more than once in a
Fetchwarefile, but you have used $name more than once. Please remove all calls
to $name but one. See perldoc App::Fetchware.
EOD
    unless (@_) {
        $FW{$name} = $value;
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
                eval $eval or die <<EOD;
1App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [$@]. See perldoc App::Fetchware.
EOD
            } when('ONEARRREF') {
                ###BUGALERT### the (@) sub prototype needed for ditching parens must
                #be seen at compile time. Is "eval time" considered compile time?
                my $eval = <<'EOE'; 
sub $name (@) {
    my $value = shift;
    
    die <<EOD if defined $FW{$name};
App-Fetchware: internal syntax error: $name was called more than once in this
Fetchwarefile. Currently only mirror supports being used more than once in a
Fetchwarefile, but you have used $name more than once. Please remove all calls
to $name but one. See perldoc App::Fetchware.
EOD
    unless (@_) {
        $FW{$name} = $value;
    } else {
        $FW{$name} = [$value, @_];
    }
}
1; # return true from eval
EOE
                $eval =~ s/\$name/$name/g;
                eval $eval or die <<EOD;
2App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [$@]. See perldoc App::Fetchware.
EOD
            }
            when('MANY') {
                my $eval = <<'EOE';
sub $name (@) {
    my $value = shift;

    if (defined $FW{$name} and ref $FW{$name} ne 'ARRAY') {
        die <<EOD;
App-Fetchware: internal operation error!!! $FW{$name} is *not* undef or an array
ref!!! This simply should never happen, but it did somehow. This is most likely
a bug, so please report it. Thanks. See perldoc App::Fetchware.
EOD
    }

    push @{$FW{$name}}, $value;

    # Support multiple arguments specified on the same line. like:
    # mirror 'http://djfjf.com/a', 'ftp://kdjfjkl.net/b';
    push @{$FW{$name}}, @_ if @_;
}
1; # return true from eval
EOE
                $eval =~ s/\$name/$name/g;
                eval $eval or die <<EOD;
3App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [\$@]. See perldoc App::Fetchware.
EOD
            } when('BOOLEAN') {
                my $eval = <<'EOE';
sub $name (@) {
    my $value = shift;

    die <<EOD if defined $FW{$name};
App-Fetchware: internal syntax error: $name was called more than once in this
Fetchwarefile. Currently only mirror supports being used more than once in a
Fetchwarefile, but you have used $name more than once. Please remove all calls
to $name but one. See perldoc App::Fetchware.
EOD
    # Make extra false values false (0).
    given($value) {
        when(/false/i) {
            $value = 0;
        } when(/off/i) {
            $value = 0;
        }
    }

    unless (@_) {
        $FW{$name} = $value;
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
                eval $eval or die <<EOD;
4App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [\$@]. See perldoc App::Fetchware.
EOD
            }
        }
    }

} # End BEGIN BLOCK.

=item start()

=over
=item Configuration subroutines used:
=over
=item none
=back
=back

Creates a temp directory using File::Temp, and sets that directory up so that it
will be deleted by File::Temp when fetchware closes.

=cut

sub start {
    # Ask for better security.
    File::Temp->safe_level( File::Temp::HIGH );

    # Create the temp dir in the portable locations as returned by
    # File::Spec->tempdir() using the specified template (the weird $$ is this
    # processes process id), and cleaning up at program exit.
    ###BUGALERT### WTF is returned by tempdir???
    my $exception;
    eval {
        #$FW{TempDir} = tempdir("fetchware-$$-XXXXXXXXXX", TMPDIR => 1,);# CLEANUP => 1);
        $FW{TempDir} = tempdir("fetchware-$$-XXXXXXXXXX", TMPDIR => 1, CLEANUP => 1);

        # Must chown 700 so gpg's localized keyfiles are good.
        chown 0700, $FW{TempDir};

        use Test::More;
        diag("tempdir[$FW{TempDir}]");
        $exception = $@;
        1; # return true unless an exception is thrown.
    } or die <<EOD;
App-Fetchware: run-time error. Fetchware tried to use File::Temp's tempdir()
subroutine to create a temporary file, but tempdir() threw an exception. That
exception was [$exception]. See perldoc App::Fetchware.
EOD

    use Cwd;
    diag("cwd[@{[cwd()]}]");
    # Change directory to $FW{TempDir} to make unarchiving and building happen
    # in a temporary directory, and to allow for multiple concurrent fetchware
    # runs at the same time.
    chdir $FW{TempDir} or die <<EOD;
App-Fetchware: run-time error. Fetchware failed to change its directory to the
temporary directory that it successfully created. This just shouldn't happen,
and is weird, and may be a bug. See perldoc App::Fetchware.
EOD
    diag("cwd[@{[cwd()]}]");
}




=item lookup()

=over
=item Configuration subroutines used:
=over
=item lookup_url
=item lookup_method
=back
=back

Accesses C<lookup_url> as a http/ftp directory listing, and uses C<lookup_method>
to determine what the newest version of the software is available, which it
combines with the C<lookup_url> and stores in C<$FW{DownloadURL}>

=over
=item LIMITATIONS
C<lookup_url> is a web browser like URL such as C<http://host.com/a/b/c/path>,
and it B<must> be a directory listing B<not> a actual file. This directory
listing must be a listing of all of the available versions of the program this
Fetchwarefile belongs to.
=back

C<lookup_method> can be either C<'timestamp'> or C<'versionstring'>, any other
values will result in fetchware die()ing with an error message.

=cut

sub lookup {
    # die if lookup_url wasn't specified.
    # die if lookup_method was specified wrong.
    check_lookup_config();
    # obtain directory listing for ftp or http. (a sub for each.)
    download_directory_listing();
    # parse the directory listing's format based on ftp or http.
    # ftp: just use Net::Ftp's dir command to get a "long" listing.
    # http: use regex hackery or *html:linkextractor*.
    parse_directory_listing();
    # Run those listings through lookup_by_timestamp() and/or
        # lookup_by_versionstring() based on lookup_method, or first by timestamp,
        # and then by versionstring if timestamp can't figure out the latest
        # version (normally because everything in the directory listing has the
        # same timestamp.
    # Set $FW{DownloadURL} to lookup_url . <latest version archive>
    determine_download_url();
}



=head1 lookup() API REFERENCE

The subroutines below are used by lookup() to provide the lookup functionality
for fetchware. If you have overridden the lookup() handler, you may want to use
some of these subroutines so that you don't have to copy and paste anything from
lookup.

App::Fetchware is B<not> object-oriented; therefore, you B<can not> subclass
App::Fetchware to extend it! 

###BUGALERT### App::Fetchware *not* subclassable; how will I impl the web app
#support and wall paper support?!!?

=cut

=item check_lookup_config()

Verifies the configurations parameters lookup() uses are correct. These are
C<lookup_url> and C<lookup_method>. If they are wrong die() is called. If they
are right it does nothing, but return.

=cut

sub check_lookup_config {
    if (not defined $FW{lookup_url}) {
        die <<EOD;
App-Fetchware: run-time syntax error: your Fetchwarefile did not specify a
lookup_url. lookup_url is a required configuration option, and must be
specified, because fetchware uses it to located new versions of your program to
download. See perldoc App::Fetchware
EOD
    }

    # Only test lookup_method if it has been defined.
    if (defined $FW{lookup_method}) {
        given ($FW{lookup_method}) {
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


=item download_directory_listing()

Downloads a directory listing that lookup() uses to determine what the latest
version of your program is. It is B<not> returned, but instead placed in
C<$FW{DirectoryListing}>.

=over
=item SIDE EFFECTS
determine_directory_listing() sets $FW{DirectoryListing} to a SCALAR REF of the
output of HTTP::Tiny or a ARRAY REF for Net::Ftp downloading that listing.
Note: the output is different for each download type. Type 'http' will have HTML
crap in it, and type 'ftp' will be the output of Net::Ftp's dir() method.
=back

=cut

sub download_directory_listing {
    $FW{DirectoryListing} = download_dirlist($FW{lookup_url});
}


=item parse_directory_listing();

Based on C<$FW{DownloadType}> of C<'http'> or C<'ftp'>,
parse_directory_listing() will call either ftp_parse_filelist() or
http_parse_filelist(). Those subroutines do the heavy lifting, and the results
are stored by parse_directory_listing() in C<$FW{FilenameListing}>.

=over
=item SIDE EFFECTS
parse_directory_listing() sets $FW{FilenameListing} to a array of arrays of the
filenames  and timestamps that make up the directory listing.
=back

=cut

sub parse_directory_listing {
    given ($FW{lookup_url}) {
        when (m!^ftp://!) {
            my $filename_listing = ftp_parse_filelist($FW{DirectoryListing});
            $FW{FilenameListing} = $filename_listing;
        } when (m!^http://!) {
            my $filename_listing = http_parse_filelist($FW{DirectoryListing});
            $FW{FilenameListing} = $filename_listing;
        }
    }
}


=item determine_download_url()

Runs the C<lookup_method> to determine what the lastest filename is, and that
one is then concatenated with C<lookup_url> to determine and set the
C<FW{DownloadURL}>.

=over
=item SIDE EFFECTS
determine_download_url(); sets $FW{DownloadURL} to the URL that download() will
use to download the archive of your program.
=back

=cut

sub determine_download_url {
    # Base lookup algorithm on lookup_method configuration sub if it was
    # specified.
    given ($FW{lookup_method}) {
        when ('timestamp') {
            $FW{DownloadURL} =  lookup_by_timestamp($FW{FilenameListing});
        } when ('versionstring') {
            $FW{DownloadURL} =  lookup_by_versionstring($FW{FilenameListing});
        # Default is to just use timestamp although timestamp will call
        # versionstring if it can't figure it out, because all of the timestamps
        # are the same.
        } default {
            $FW{DownloadURL} = lookup_by_timestamp($FW{FilenameListing});
        }
    }
}


=item ftp_parse_filelist($ftp_listing)

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



=item http_parse_filelist

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


=item lookup_by_timestamp($FW{FileListing})

Implements the 'timestamp' lookup algorithm. It takes the timestamps placed in
C<@$FW{FileListing}>, normalizes them into a standard descending format
(YYYYMMDDHHMM), and then cleverly uses sort to determine the latest
filename.

=cut

sub  lookup_by_timestamp {
    my $file_listing = shift;
    
    # Sort the timstamps to determine the latest one. The one with the higher
    # numbers, and put $b before $a to put the "bigger", later versions before
    # the "lower" older versions.
    # Sort based on timestamp, which is $file_listing->[0..whatever][1].
    @$file_listing = sort { $b->[1] <=> $a->[1] } @$file_listing;

    # Manage duplicate timestamps apropriately including .md5, .asc, .txt files.
    # And support some hacks to make lookup() more robust.
    return lookup_determine_downloadurl($file_listing);
}


=item lookup_by_versionstring($FW{FileListing})

Determines the C<$FW{DownloadURL}> by cleverly C<split>ing the filenames on
C</\D+/>, which will return a list of version numbers. Then they're just sorted
normally. And lookup_determine_downloadurl() is used to take the sorted
$file_listing, and determine the actual C<$FW{DownloadURL}>.

=cut

sub  lookup_by_versionstring {
    my $file_listing = shift;

    # Implement versionstring algorithm.
    for my $fl (@$file_listing) {
        my @split_fl = split /\D+/, $fl->[0];
        $fl->[2] = join '', @split_fl;
    }

    # Sort $file_listing by the versionstring, and but $b in front of $a to get
    # a reverse sort, which will put the "bigger", later version numbers before
    # the "lower", older ones.
    @$file_listing = sort { $b->[2] <=> $a->[2] } @$file_listing;
    

    # Manage duplicate timestamps apropriately including .md5, .asc, .txt files.
    # And support some hacks to make lookup() more robust.
    return lookup_determine_downloadurl($file_listing);
}



=item lookup_determine_downloadurl($file_listing)

Given a $file_listing of files with the same timestamp or versionstring,
determine which one is a downloadable archive, a tarball or zip file. And
support some backs to make fetchware more robust. These are the C<filter>
configuration subroutine, ignoring "win32" on non-Windows systems, and
supporting Apache's CURRENT_IS_ver_num and Linux's LATEST_IS_ver_num helper
files.

=cut

sub lookup_determine_downloadurl {
    my $file_listing = shift;

    # First grep @$file_listing for $FW{filter} if $FW{filter} is defined.
    # This is done, because some distributions have multiple versions of the
    # same program in one directory, so sorting by version numbers or
    # timestamps, and then by filetype like below is not enough to determine,
    # which file to download, so filter was invented to fix this problem by
    # letting Fetchwarefile's specify which version of the software to download.
    if (defined $FW{filter}) {
        @$file_listing = grep { $_->[0] =~ /$FW{filter}/ } @$file_listing;
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
    $_->[0] =~ /^(:?latest|current)[_-]is(.*)$/i for @$file_listing;
    my $latest_version = $1;
    diag("latestver[$latest_version]");
    @$file_listing = grep { $_->[0] =~ /$latest_version/ } @$file_listing;

    # Determine the $FW{DownloadURL} based on the sorted @$file_listing by
    # finding a downloadable file (a tarball or zip archive).
    # Furthermore, choose them based on best compression to worst to save some
    # bandwidth.
    for my $fl (@$file_listing) {
        given ($fl->[0]) {
            when (/\.tar\.xz$/) {
                return catfile($FW{lookup_url}, $fl->[0]);
            } when (/\.txz$/) {
                return catfile($FW{lookup_url}, $fl->[0]);
            } when (/\.tar\.bz2$/) {
                return catfile($FW{lookup_url}, $fl->[0]);
            } when (/\.tbz$/) {
                return catfile($FW{lookup_url}, $fl->[0]);
            } when (/\.tar\.gz$/) {
                return catfile($FW{lookup_url}, $fl->[0]);
            } when (/\.tgz$/) {
                return catfile($FW{lookup_url}, $fl->[0]);
            } when (/\.zip$/) {
                return catfile($FW{lookup_url}, $fl->[0]);
            }
        }
    }
    die <<EOD;
App-Fetchware: run-time error. Fetchware failed to determine what URL it should
use to download your software. This URL is based on the lookup_url you
specified. See perldoc App::Fetchware.
EOD
}




=item download()

=over
=item Configuration subroutines used:
=over
=item none
=back
=back

Downloads C<$FW{DownloadURL}> to C<tempdir 'whatever/you/specify';> or to
whatever File::Spec's tempdir() method tries. Supports ftp and http URLs.

Also, sets C<$FW{PackagePath}>, which is used by unarchive() as the path to the
archive for unarchive() to untar or unzip.

=over
=item LIMITATIONS
Uses Net::FTP and HTTP::Tiny to download ftp and http files. No other types of
downloading ar supported, and fetchware is stuck with whatever limitations or
bugs Net::FTP or HTTP::Tiny impose.
=back

=cut

sub download {

    my $filename = download_file($FW{DownloadURL});

    $FW{PackagePath} = determine_package_path($FW{TempDir}, $filename);
}



=head1 download() API REFERENCE

The subroutines below are used by download() to provide the download
functionality for fetchware. If you have overridden the download() handler, you
may want to use some of these subroutines so that you don't have to copy and
paste anything from download.

App::Fetchware is B<not> object-oriented; therefore, you B<can not> subclass
App::Fetchware to extend it! 

###BUGALERT### App::Fetchware *not* subclassable; how will I impl the web app
#support and wall paper support?!!?

=cut


=item determine_package_path($tempdir, $filename)

Determines what C<$FW{PackagePath}> is based on the provided $tempdir and
$filename. C<$FW{PackagePath}> is the path used by unarchive() to unarchive the
software distribution download() downloads.

=cut

sub determine_package_path {
    my ($tempdir, $filename) = @_;

    # Save the $FW{PackagePath}, which stores the full path of where the file
    # HTTP::Tiny downloaded.
    return catfile($tempdir, $filename)
}




=item verify()

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

Verifies the downloaded package stored in $FW{PackagePath} by downloading
C<$FW{DownloadURL}.{asc,sha1,md5}> and comparing the two together. Uses the
helper subroutines C<{gpg,sha1,md5,digest}_verify()>.

=over
=item LIMITATIONS
Uses gpg command line or Crypt::OpenPGP for Windows, and the interface to gpg is
a little brittle, while Crypt::OpenPGP is complex, poorly maintained, and bug
ridden, but still usable.
=back

=cut

sub verify {
            my $retval;
    given ($FW{verify_method}) {
        when (undef) {
            # if gpg fails try
            # sha and if it fails try
            # md5 and if it fails die
            my ($gpg_err, $sha_err, $md5_err);
            eval {$retval = gpg_verify()};
            $gpg_err = $@;
            diag("gpgrv[$retval]");
            warn $gpg_err if $gpg_err;
            if (! $retval or $gpg_err) {
                eval {$retval = sha1_verify()};
                $sha_err = $@;
                diag("sharv[$retval]");
                warn $sha_err if $sha_err;
                if (! $retval or $sha_err) {
                    diag("GOTTOMD5");
                    eval {$retval = md5_verify()};
                    $md5_err = $@;
                    diag("md5rv[$retval]");
                    warn $md5_err if $md5_err;
                }
                if (! $retval or $md5_err) {
                    die <<EOD unless $FW{verify_failure_ok};
App-Fetchware: run-time error. Fetchware failed to verify your downloaded
software package. You can rerun fetchware with the --force option or add
[verify_failure_ok 'True';] to your Fetchwarefile. See perldoc App::Fetchware.
EOD
                }
                if ($FW{verify_failure_ok}) {
                        warn <<EOW;
App-Fetchware: run-time warning. Fetchware failed to verify the integrity of you
downloaded file [$FW{PackagePath}]. This is ok, because you asked Fetchware to
ignore its errors when it tries to verify the integrity of your downloaded file.
You can also ignore the errors Fetchware printed out abover where it tried to
verify your downloaded file. See perldoc App::Fetchware.
EOW
                    return 'warned due to verify_failure_ok'
                }
            }
        } when (/gpg/i) {
            gpg_verify()
                or die <<EOD unless $FW{verify_failure_ok};
App-Fetchware: run-time error. You asked fetchware to only try to verify your
package with gpg or openpgp, but they both failed. See the warning above for
their error message. See perldoc App::Fetchware.
EOD
        } when (/sha1?/i) {
            sha1_verify()
                or die <<EOD unless $FW{verify_failure_ok};
App-Fetchware: run-time error. You asked fetchware to only try to verify your
package with sha, but it failed. See the warning above for their error message.
See perldoc App::Fetchware.
EOD
        } when (/md5/i) {
            md5_verify()
                or die <<EOD unless $FW{verify_failure_ok};
App-Fetchware: run-time error. You asked fetchware to only try to verify your
package with md5, but it failed. See the warning above for their error message.
See perldoc App::Fetchware.
EOD
        } default {
            die <<EOD;
App-Fetchware: run-time error. Your fetchware file specified a wrong
verify_method option. The only supported types are 'gpg', 'sha', 'md5', but you
specified [$FW{verify_method}]. See perldoc App::Fetchware.
EOD
        }
    }
}



=head1 verify() API REFERENCE

The subroutines below are used by verify() to provide the verify
functionality for fetchware. If you have overridden the verify() handler, you
may want to use some of these subroutines so that you don't have to copy and
paste anything from verify().

App::Fetchware is B<not> object-oriented; therefore, you B<can not> subclass
App::Fetchware to extend it! 

###BUGALERT### App::Fetchware *not* subclassable; how will I impl the web app
#support and wall paper support?!!?

=cut


=item gpg_verify();

Verifies the downloaded source code distribution using the command line program
gpg or Crypt::OpenPGP on Windows or if gpg is not available.
=cut

sub gpg_verify {
    my $keys_file;
    # Obtain a KEYS file listing everyone's key that signs this distribution.
##DELME##    if (defined $FW{gpg_key_url}) {
##DELME##        $keys_file = download_file($FW{gpg_key_url});
##DELME##    } else {
##DELME##        eval {
##DELME##            $keys_file = download_file("$FW{lookup_url}/KEYS");
##DELME##        }; 
##DELME##        if ($@ and not defined $FW{verify_failure_ok}) {
##DELME##            die <<EOD;
##DELME##App-Fetchware: Fetchware was unable to download the gpg_key_url you specified or
##DELME##that fetchware tried appending asc, sig, or sign to [$FW{DownloadUrl}]. It needs
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
    eval {
        for my $ext (qw(asc sig sign)) {
            $sig_file = download_file("$FW{DownloadURL}.$ext");

            # If the file was downloaded successfully stop trying other extensions.
            last if defined $sig_file;
        }
        1;
    } or die <<EOD;
App-Fetchware: Fetchware was unable to download the gpg_sig_url you specified or
that fetchware tried appending asc, sig, or sign to [$FW{DownloadURL}]. It needs
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
##DOESNTWORK??        my $retval = $pgp->verify(SigFile => $sig_file, Files => $FW{PackagePath});
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
###BUGALERT###        ###BUGALERT### eval the system()'s below & add better error reporting in
###BUGALERT###        ###BUGALERT### if Crypt::OpenPGP works ok remove gpg support & this if &
        #IPC::System::Simple dependency.
        #my standard format.
        # Use automatic key retrieval & a cool pool of keyservers
        ###BUGALERT## Give Crypt::OpenPGP another try with
        #pool.sks-keyservers.net
        system('gpg', '--keyserver', 'pool.sks-keyservers.net',
            '--keyserver-options', 'auto-key-retrieve=1',
            '--homedir', '.',  "$sig_file");

        # Verify sig.
#        system('gpg', '--homedir', '.', '--verify', "$sig_file");
###BUGALERT###    }

    # Return true indicating the package was verified.
    return 'Package Verified';
}


=item sha1_verify();

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
    return digest_verify('SHA-1');
}


=item md5_verify();

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
    return digest_verify('MD5');
}


=item digest_verify($digest_type);

Verifies the downloaded software archive's integrity using the specified
$digest_type, which also determines the
C<"$digest_type_url" 'ftp://sha.url/package.sha'> config option. Returns
true for sucess and returns false for failure.

=over
=item OVERRIDE NOTE
If you need to override verify() in your Fetchwarefile to change the type of
digest used, you can do this easily, because digest_verify() uses L<Digest>,
which supporta a number of Digest::* modules of different Digest algorithms.
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
    my $digest_type = shift;

    # Turn SHA-1 into sha1 & MD5 into md5.
    my $digest_ext = $digest_type;
    $digest_ext = lc $digest_type;
    $digest_ext =~ s/-//g;
##subify get_sha_sum()
    my $digest_file;
    # Obtain a sha sum file.
    if (defined $FW{"${digest_type}_url"}) {
        $digest_file = download_file($FW{"${digest_type}_url"});
    } else {
        eval {
            $digest_file = download_file("$FW{DownloadURL}.$digest_ext");
            diag("digestfile[$digest_file]");
        };
        if ($@) {
            die <<EOD;
App-Fetchware: Fetchware was unable to download the $digest_type sum it needs to download
to properly verify you software package. This is a fatal error, because failing
to verify packages is a perferable default over potentially installing
compromised ones. If failing to verify your software package is ok to you, then
you may disable verification by adding verify_failure_ok 'On'; to your
Fetchwarefile. See perldoc App::Fetchware.
EOD
        }
    }
    
###subify calc_sum()
    # Open the downloaded software archive for reading.
    diag("PACKAGEPATH[$FW{PackagePath}");
    open(my $package_fh, '<', $FW{PackagePath})
        or die <<EOD;
App-Fetchware: run-time error. Fetchware failed to open the file it downloaded
while trying to read it in order to check its MD5 sum. The file was
[$FW{PackagePath}]. See perldoc App::Fetchware.
EOD

    my $digest;
    if ($digest_type eq 'MD5') {
        $digest = Digest::MD5->new();
    } elsif ($digest_type eq 'SHA-1') {
        $digest = Digest::SHA->new();
    } else {
        die <<EOD;
EOD
    }
    #my $digest = Digest->new($digest_type);
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
[$FW{PackagePath}] after opening it for reading. See perldoc App::Fetchware.
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

    # Return failure, because fetchware failed to verify by md5sum
    return undef;
}




=item unarchive()

=over
=item Configuration subroutines used:
=over
=item none
=back
=back

Uses L<Archive::Tar> or L<Archive::Zip> to turn .tar.{gz,bz2,xz} or .zip into a
directory. Is intelligent enough to warn if the archive being unarchived does
not contain B<all> of its files in a single directory like nearly all software
packages do. Uses C<$FW{PackagePath}> as the archive to unarchive, and sets
C<$FW{BuildPath}>

=over
=item LIMITATIONS
Depends on Archive::Extract, so it is stuck with Archive::Extract's limitations.

Archive::Extract prevents fetchware from checking if there is an absolute path
in the archive, and throwing a fatal error, because Archive::Extract B<only>
extracts files it gives you B<zero> chance of listing them except after you
already extract them.
=back

=cut

sub unarchive {
    ###BUGALERT### fetchware needs Archive::Zip, which is *not* one of
    #Archive::Extract's dependencies.
    diag("PP[$FW{PackagePath}]");
    my $ae = Archive::Extract->new(archive => "$FW{PackagePath}");

###BUGALERT### Files are listed *after* they're extracted, because
#Archive::Extract *only* extracts files and then lets you see what files were
#*already* extracted! This is a huge limitation that prevents me from checking
#if an archive has an absolute path in it.
    $ae->extract() or die <<EOD;
App-Fetchware: run-time error. Fetchware failed to extract the archive it
downloaded [$FW{PackagePath}]. The error message is [@{[$ae->error()]}].
See perldoc App::Fetchware.
EOD

    # list files.
    my $files = $ae->files();
    die <<EOD if not defined $files;
App-Fetchware: run-time error. Fetchware failed to list the files in  the
archive it downloaded [$FW{PackagePath}]. The error message is
[@{[$ae->error()]}].  See perldoc App::Fetchware.
EOD

    check_archive_files($files);
}


=head1 unarchive() API REFERENCE

The subroutine below are used by unarchive() to provide the unarchive
functionality for fetchware. If you have overridden the unarchive() handler, you
may want to use some of these subroutines so that you don't have to copy and
paste anything from unarchive().

App::Fetchware is B<not> object-oriented; therefore, you B<can not> subclass
App::Fetchware to extend it! 

###BUGALERT### App::Fetchware *not* subclassable; how will I impl the web app
#support and wall paper support?!!?

=cut

=item check_archive_files($files);

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
        my @dirs = splitdir($directories);

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
    
        # Set $FW{BuildPath}
        $FW{BuildPath} = $dir; #BuildPath should be a key not a value.
        diag("BUILDPATH[$FW{BuildPath}]");
    }

    return 'Files good';
}







# New hooks here!!!!!


=item end()

=over
=item Configuration subroutines used:
=over
=item none
=back
=back

end() is called after all of the other main fetchware subroutines such as
lookup() are called. It's job is to cleanup after everything else. It just
calls C<File::Temp>'s internalish File::Temp::cleanup() subroutine.

=cut

sub end {
    # chdir to our home directory, so File::Temp can delete the tempdir. This is
    # necessary, because operating systems do not allow you to delete a
    # directory that a running program has as its cwd.
    # Determines where to chdir() to so File::Temp can delete fetchware's temp
    # directior $FW{TempDir}.
    my $home = $ENV{HOME} // updir();

    my $error = <<EOS;
App-Fetchware: run-time error. Fetchware failed to chdir() to [$home]. See
perldoc App::Fetchware.
EOS

    chdir($home) or die $error;

    # Call File::Temp's cleanup subrouttine to delete fetchware's temp
    # directory.
    ###BUGALERT### Below doesn't seem to work!!
    File::Temp::cleanup();
    ###BUGALERT### Should end() clear %FW for next invocation of App::Fetchware
    # Clear %FW for next run of App::Fetchware.
    # Is this a design defect? It's a pretty lame hack! Does my() do this for
    # me?
    #%FW = ();
}



=head1 UTILITY SUBROUTINES

These subroutines provide utility functions for testing and downloading files
and dirlists that may also be helpful for anyone who's writing a custom
Fetchwarefile to provide easier testing.

=cut 

=over

=item eval_ok($code, $expected_exception_text_or_regex, $test_name)

Executes the $code coderef, and compares its thrown exception, C<$@>, to
$expected_exception_text_or_regex, and uses $test_name as the name for the test if
provided.

If $expected_exception_text_or_regex is a string then Test::More's is() is used,
and if $expected_exception_text_or_regex is a C<'Regexp'> according to ref(),
then like() is used, which will treat $expected_exception_text_or_regex as a
regex instead of as just a string.

=cut

sub eval_ok {
    my ($code, $expected_exception_text_or_regex, $test_name) = @_;
    eval {$code->()};
    # Test if an exception was actually thrown.
    if (not defined $@) {
        BAIL_OUT("[$test_name]'s provided code did not actually throw an exception");
    }
    
    # Support regexing the thrown exception's test if needed.
    if (ref $expected_exception_text_or_regex ne 'Regexp') {
        is($@, $expected_exception_text_or_regex, $test_name);
    } elsif (ref $expected_exception_text_or_regex eq 'Regexp') {
        like($@, qr/$expected_exception_text_or_regex/, $test_name);
    }

}

=item skip_all_unless_release_testing()

Skips all tests in your test file or subtest() if fetchware's testing
environment variable, C<FETCHWARE_RELEASE_TESTING>, is set to its proper value.

=cut

sub skip_all_unless_release_testing {
    plan skip_all => 'Not testing for release.'
        if $ENV{FETCHWARE_RELEASE_TESTING}
            ne '***setting this will install software on your computer!!!!!!!***';
}


=item clear_FW()

Clears App::Fetchware's internal %FW globalish (file scoped lexical) variable.
This subroutine should never actually be executed in a Fetchwarefile, because
its sole purpose is to clear %FW between tests being run in Fetchware's test
suite.

=cut

sub clear_FW {
    %FW = ();
}




=item download_dirlist($ftp_or_http_url)

Downloads a ftp or http url and assumes that it will be downloading a directory
listing instead of an actual file. To download an actual file use
L<download_file()>. download_dirlist returns the directory listing that it
obtained from the ftp or http server. ftp server will be an arrayref of C<ls -l>
like output, while the http output will be a scalar of the HTML dirlisting
provided by the http server.

=cut

sub download_dirlist {
    my $url = shift;

    my $dirlist;
    given ($url) {
        when (m!^ftp://.*$!) {
            $dirlist = ftp_download_dirlist($url);
        } when (m!^http://.*$!) {
            $dirlist = http_download_dirlist($url);
        } default {
            die <<EOD;
App-Fetchware: run-time syntax error: the url parameter your provided in
your call to download_dirlist() [$url] does not have a supported URL scheme (the
http:// or ftp:// part). The only supported download types, schemes, are FTP and
HTTP. See perldoc App::Fetchware.
EOD
        }
    }

    return $dirlist;
}


=item ftp_download_dirlist

Uses Net::Ftp's dir() method to obtain a I<long> directory listing. lookup()
needs it in I<long> format, so that the timestamp algorithm has access to each
file's timestamp.

Returns an array ref of the directory listing.

=cut

sub ftp_download_dirlist {
    my $ftp_url = shift;
    use Test::More;
    diag("ftp_url[$ftp_url]");
    $ftp_url =~ m!^ftp://([-a-z,A-Z,0-9,\.]+)(/.*)?!;
    my $site = $1;
    my $path = $2;
    use Test::More;
    diag("site[$site]path[$path]");

    # Add debugging later based on fetchware commandline args.
    # for debugging: $ftp = Net::FTP->new('$site','Debug' => 10);
    # open a connection and log in!
    my $ftp;
    $ftp = Net::FTP->new($site)
        or die <<EOD;
App-Fetchware: run-time error. fetchware failed to connect to the ftp server at
domain [$site]. The system error was [$@].
See man App::Fetchware.
EOD

    $ftp->login("anonymous",'-anonymous@')
        or die <<EOD;
App-Fetchware: run-time error. fetchware failed to log in to the ftp server at
domain [$site]. The ftp error was [@{[$ftp->message]}]. See man App::Fetchware.
EOD


    my @dir_listing = $ftp->dir($path)
        or die <<EOD;
App-Fetchware: run-time error. fetchware failed to get a long directory listing
of [$path] on server [$site]. The ftp error was [@{[$ftp->message]}]. See man App::Fetchware.
EOD

    $ftp->quit();

    return \@dir_listing;
}


=item http_download_dirlist

Uses HTTP::Tiny to download a HTML directory listing from a HTTP Web server.

Returns an scalar of the HTML ladden directory listing.

=cut

sub http_download_dirlist {
    my $http_url = shift;

    my $response = HTTP::Tiny->new->get($http_url);

    die <<EOD unless $response->{success};
App-Fetchware: run-time error. HTTP::Tiny failed to download a directory listing
of your provided lookup_url. HTTP status code [$response->{status} $response->{reason}]
HTTP headers [@{[Data::Dumper::Dumper($response->{headers})]}].
See man App::Fetchware.
EOD

    use Test::More;
    diag("$response->{status} $response->{reason}\n");

    while (my ($k, $v) = each %{$response->{headers}}) {
        for (ref $v eq 'ARRAY' ? @$v : $v) {
            diag("$k: $_\n");
        }
    }

    diag($response->{content}) if length $response->{content};
    die <<EOD unless length $response->{content};
App-Fetchware: run-time error. The lookup_url you provided downloaded nothing.
HTTP status code [$response->{status} $response->{reason}]
HTTP headers [@{[Data::Dumper::Dumper($response)]}].
See man App::Fetchware.
EOD
    diag explain $response;
    return $response->{content};
}



=item download_file($url)

Downloads a $url and assumes it is a file that will be downloaded instead of a
file listing that will be returned. download_file() returns the file name of the
file it downloads.

=cut

sub download_file {
    my $url = shift;

    my $filename;
    given ($url) {
        when (m!^ftp://.*$!) {
            $filename = download_ftp_url($url);
        } when (m!^http://.*$!) {
            $filename = download_http_url($url);
        } default {
            die <<EOD;
App-Fetchware: run-time syntax error: the url parameter your provided in
your call to download_file() [$url] does not have a supported URL scheme (the
http:// or ftp:// part). The only supported download types, schemes, are FTP and
HTTP. See perldoc App::Fetchware.
EOD
        }
    }

    return $filename;
}


=item download_ftp_url($url);

Uses Net::FTP to download the specified FTP URL using binary mode.

=cut

sub download_ftp_url {
    my $ftp_url = shift;

    use Test::More;
    diag("ftp_url[$ftp_url]");
    $ftp_url =~ m!^ftp://([-a-z,A-Z,0-9,\.]+)(/.*)?!;
    my $site = $1;
    my $path = $2;
    use Test::More;
    diag("FIRSTpath[$path]");
    my ($volume, $directories, $file) = splitpath($path);
    diag("site[$site]path[$path]dirs[$directories]file[$file]");

    # for debugging: $ftp = Net::FTP->new('site','Debug',10);
    # open a connection and log in!

    my $ftp = Net::FTP->new($site)
        or die <<EOD;
App-Fetchware: run-time error. fetchware failed to connect to the ftp server at
domain [$site]. The system error was [$@].
See man App::Fetchware.
EOD
    
    $ftp->login("anonymous",'-anonymous@')
        or die <<EOD;
App-Fetchware: run-time error. fetchware failed to log in to the ftp server at
domain [$site]. The ftp error was [@{[$ftp->message]}]. See man App::Fetchware.
EOD

    # set transfer mode to binary
    $ftp->binary()
        or die <<EOD;
App-Fetchware: run-time error. fetchware failed to swtich to binary mode while
trying to download a the file [$path] from site [$site]. The ftp error was
[@{[$ftp->message]}]. See perldoc App::Fetchware.
EOD

    # change the directory on the ftp site
    $ftp->cwd($directories)
        or die <<EOD;
App-Fetchware: run-time error. fetchware failed to cwd() to [$path] on site
[$site]. The ftp error was [@{[$ftp->message]}]. See perldoc App::Fetchware.
EOD


    # Download the file to the current directory. The start() subroutine should
    # have cd()d to a tempdir for fetchware to use.
    $ftp->get($file)
        or die <<EOD;
App-Fetchware: run-time error. fetchware failed to download the file [$file]
from path [$path] on server [$site]. The ftp error message was
[@{[$ftp->message]}]. See perldoc App::Fetchware.
EOD

    # ftp done!
    $ftp->quit;

    # The caller needs the $filename to determine the $FW{PackagePath} later.
    diag("FILE[$file]");
    return $file;
}


=item download_http_url($url);

Uses HTTP::Tiny to download the specified HTTP URL.

=cut

sub download_http_url {
    my $http_url = shift;

    my $response = HTTP::Tiny->new->get($http_url);

    die <<EOD unless $response->{success};
App-Fetchware: run-time error. HTTP::Tiny failed to download a directory listing
of your provided lookup_url. HTTP status code [$response->{status} $response->{reason}]
HTTP headers [@{[Data::Dumper::Dumper($response->{headers})]}].
See man App::Fetchware.
EOD

    use Test::More;
    diag("$response->{status} $response->{reason}\n");

    while (my ($k, $v) = each %{$response->{headers}}) {
        for (ref $v eq 'ARRAY' ? @$v : $v) {
            diag("$k: $_\n");
        }
    }

    # In this case the content is binary, so it will mess up your terminal.
    #diag($response->{content}) if length $response->{content};
    die <<EOD unless length $response->{content};
App-Fetchware: run-time error. The lookup_url you provided downloaded nothing.
HTTP status code [$response->{status} $response->{reason}]
HTTP headers [@{[Data::Dumper::Dumper($response)]}].
See man App::Fetchware.
EOD
    # Contains $response->{content}, which may be binary terminal killing
    # garbage.
    #diag explain $response;

    # Must convert the worthless $response->{content} variable into a real file
    # on the filesystem. Note: start() should have cd()d us into a suitable
    # tempdir.
    my $path = $http_url;
    $path =~ s!^http://!!;
    diag("path[$path]");
    # Determine filename from the $path.
    my ($volume, $directories, $filename) = splitpath($path);
    diag("filename[$filename]");
    ###BUGALERT### Need binmode() on Windows???
    open(my $fh, '>', $filename) or die <<EOD;
App-Fetchware: run-time error. Fetchware failed to open a file necessary for
fetchware to store HTTP::Tiny's output. Os error [$!]. See perldoc
App::Fetchware.
EOD
    # Write HTTP::Tiny's downloaded file to a real file on the filesystem.
    print $fh $response->{content};
    close $fh
        or die <<EOS;
App-Fetchware: run-time error. Fetchware failed to close the file it created to
save the content it downloaded from HTTP::Tiny. This file was [$filename]. OS
error [$!]. See perldoc App::Fetchware.
EOS

    # The caller needs the $filename to determine the $FW{PackagePath} later.
    diag("httpFILE[$filename]");
    return $filename;
}



=item just_filename($path);

Uses File::Spec::Functions splitpath() to chop off everything except the
filename of the provided $path. Does zero error checking, so it will return
whatever value splitpath() returns as its last return value.

=cut

sub just_filename {
    my $path = shift;
    my ($volume, $directories, $filename) = splitpath($path);

    return $filename;
}


# End UTILITY SUBROUTINES =over.
=back

=cut


1;
