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
use Text::ParseWords 'quotewords';
use File::Temp 'tempfile';
use Term::ReadLine;
use Term::UI;

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
    user_agent
    verify_method
    no_install
    verify_failure_ok
    user_keyring
    stay_root
    mirror
    config

    new
    new_install
    check_syntax
    start
    lookup
    download
    verify
    unarchive
    build
    install
    end
    uninstall
    upgrade

    hook
);

# These tags allow you to replace some or all of fetchware's default behavior to
# install unusual software.
our %EXPORT_TAGS = (
    # No OVERRIDE_START OVERRIDE_END because start() does *not* use any helper
    # subs that could be beneficial to override()rs.
    OVERRIDE_NEW => [qw(
        extension_name
        name_program
        opening_message
        get_lookup_url
        download_lookup_url
        get_mirrors
        get_verification
        get_filter_option
        append_to_fetchwarefile
        prompt_for_other_options
        append_options_to_fetchwarefile
        edit_manually
    )],
    OVERRIDE_NEW_INSTALL => [qw(
        ask_to_install_now_to_test_fetchwarefile
    )],
    OVERRIDE_CHECK_SYNTAX => [qw(
        check_config_options
    )],
    OVERRIDE_LOOKUP => [qw(
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
    OVERRIDE_UPGRADE => [qw()],
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
information on how to keep or override these API subroutines in a fetchware
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
        [ user_agent => 'ONE' ],
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

    if ($one_or_many_values eq 'ONE') {
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
    } elsif ($one_or_many_values eq 'ONEARRREF') {
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
    } elsif ($one_or_many_values eq 'MANY') {
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
    } elsif ($one_or_many_values eq 'BOOLEAN') {
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
    if ($value =~ /false/i) {
        $value = 0;
    } elsif ($value =~ /off/i) {
        $value = 0;
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





=head2 new()

    my ($program_name, $fetchwarefile) = new($term, $program_name);

    # Or in an extension, you can return whatever list of variables you want,
    # and then cmd_new() will provide them as arguments to new_install() except
    # a $term Term::ReadLine object will precede the others.
    my ($term, $program_name, $fetchwarefile, $custom_argument1, $custom_argument2)
        = new($term, $program_name);

new() is App::Fetchware's API subroutine that implements fetchware's new
command. new() calls a bunch of helper subroutines that implement
the algorithm fetchware uses to build new Fetchwarefiles automagically for the
user. The algorithm is dead stupid:

=over

=item 1. Ask for lookup_url & download it.

=item 2. Analyze the contents of the output from the lookup_url.

=item 3. Build the Fetchwarefile according to the output.

=item 4. Ask other questions as needed.

=back

new() uses Term::UI, which in turn uses Term::ReadLine to implement the
character based question and anwser wizard interface. A Term::ReadLine/Term::UI
object is passed to new() as its first argument.

new()'s argument is the program name that the user has specified on the command
line. It will be undef if the user did not specify one on the command line.

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

This API subroutine is run as root, so be mindful of what you do with it.

=item *

When fetchware is run as a regular user, it is run as whoever has run the
fetchware program that calls it. If run as root, it runs as the user
drop_privs() drops privileges to, which is C<nobody> or whatever you have set
the C<user> configuration option to.

=back

=back

=cut

sub new {
    my ($term, $program_name) = @_;

    # Instantiate a new Fetchwarefile object for managing and generating a
    # Fetchwarefile, which we'll write to a file for the user or use to
    # build a associated Fetchware package.
    my $now = localtime;
    my $fetchwarefile = App::Fetchware::Fetchwarefile->new(
        header => <<EOF,
use App::Fetchware;
# Auto generated $now by fetchware's new command.
# However, feel free to edit this file if fetchware's new command's
# autoconfiguration is not enough.
# 
# Please look up fetchware's documentation of its configuration file syntax at
# perldoc App::Fetchware, and only if its configuration file syntax is not
# malleable enough for your application should you resort to customizing
# fetchware's behavior. For extra flexible customization see perldoc
# App::Fetchware.
EOF
        descriptions => {

            program => <<EOA,
program simply names the program the Fetchwarefile is responsible for
downloading, building, and installing.
EOA
            filter => <<EOA,
filter specifies a program name and/or version number that tells fetchware
which program and or which version of a program you want fetchware to install.
This is *only* needed in cases where there are multiple programs and or
multiple versions of the same program in the directory lookup_url specifies.
EOA
            temp_dir => <<EOA,
temp_dir specifies what temporary directory fetchware will use to download and
build this program.
EOA
            user => <<EOA,
user specifes a user that fetchware will drop priviledges to when fetchware
downloads and builds your software. It will then switch back to root privs, if
run as root, and install your software system wide. This does not work on
Windows.
EOA
            fetchware_database_path => <<EOA,
fetchware_database_path specifies an alternate path for fetchware to use to
store the fetchware package that 'fetchware install' creates, and that
'fetchware upgrade' uses to upgrade this fetchware package.
EOA
            prefix => <<EOA,
prefix specifies what base path your software will be installed under. This
only works for software that uses GNU AutoTools to configure itself, it uses
./configure.
EOA
            configure_options => <<EOA,
configure_options specifes what options fetchware should pass to ./configure
when it configures your software. This option only works for software that
uses GNU AutoTools.
EOA
            make_options => <<EOA,
make_options specifes what options fetchware should pass to make when make is
run to build and install your software.
EOA
            build_commands => <<EOA,
build_commands specifies what commands fetchware should execute to build your
software.
EOA
            install_commands => <<EOA,
install_commands specifies what commands fetchware should execute to install
your software.
EOA
            uninstall_commands => <<EOA,
uninstall_commands specifies what commands fetchware should execute to uninstall
your software.
EOA
            lookup_url => <<EOA,
lookup_url specifes the url that fetchware uses to determine what what
versions of your program are available. It should point to a directory listing
instead of a specific file.
EOA
            lookup_method => <<EOA,
lookup_method specifies how fetchware determines what version of your program
to install. The default is the 'timestamp' algorithm, and then to try the
'versionstring' algorithm if 'timestamp' fails. lookup_method specifies which
one you would like to use. Only the strings 'timestamp' and 'versionstring'
are allowed options.
EOA
            gpg_keys_url => <<EOA,
gpg_keys_url specifies the url that fetchware will use to download the author's
KEYS file that it uses for gpg verification.
EOA
            gpg_sig_url => <<EOA,
gpg_sig_url specifies the url that fetchware uses to download digital
signatures of this program. They're files that usually end .asc.
EOA
            sha1_url => <<EOA,
sha1_url specfies the url that fetchware uses to download sha1sum files of
this program. This url should be the program's main download site instead of a
mirror, because a hacked mirror could alter the sha1sum on that mirror.
EOA
            md5_url => <<EOA,
md5_url specfies the url that fetchware uses to download md5sum files of
this program. This url should be the program's main download site instead of a
mirror, because a hacked mirror could alter the md5sum on that mirror.
EOA
            verify_method => <<EOA,
verify_method specifes a specific method that fetchware should use to verify
your program. This method can be 'gpg', 'sha1', or 'md5'.
EOA
            no_install => <<EOA,
no_install specifies that this software should not be installed. Instead, the
install step is skipped, and fetchware prints to STDOUT where it downloaded,
verified, and built your program. no_install must be a true or false value.
EOA
            verify_failure_ok => <<EOA,
verify_failure_ok specifies that fetchware should not stop installing your
software and terminate with an error message if fetchware fails to verify your
software. You should never set this to true. Doing so could cause fetchware to
install software that may have been compromised, or had malware inserted into
it. Never use this option unless the author or maintainer of this program does
not gpg sign or checksum his software.
EOA
            user_keyring => <<EOA,
users_keyring if enabled causes fetchware to use the user's own gpg keyring
instead of fetchware's own keyring.
EOA
            mirror => <<EOA
The mirror configuration option provides fetchware with alternate servers to
try to download this program from. This option is used when the server
specified in the url options in this file is unavailable or times out.
EOA
        }
    );
    ###INSANEFEATUREENHANCEMENT### Prompt for name of program, and do a fuzzy 
    #search on CPAN for that program under
    #App::Fetchware::FetchwarefileX::UpCasedProgName. Consider using the meta
    #CPAN API. And if it exists ask user if they wanna use that one instead of
    #autogening one.
    #
    #Perhaps create a 'fetchwarefile' command to download and look at
    #fetchwarefiles from CPAN, and then install them, and/or perhaps upload
    #them pausing to ask for the user's PAUSE credentials!!!!!!!!!


    extension_name(__PACKAGE__);


    my $opening_message = <<EOM;
Fetchware's new command is reasonably sophisticated, and is smart enough to
determine based on the lookup_url you provide if it can autogenerate a
Fetchwarefile for you. If Fetchware cannot, then it will ask you more
questions regarding the information it requires to be able to build a
installable fetchware package for you. After that, fetchware will ask you if
you would like to edit the Fetchwarefile, fetchware has created for you in an
editor. If you say yes, fetchware will open a editor for you, but if you say
no, fetchware will skip the custom editing. Next, fetchware will create a test
Fetchwarefile for you, and ask you if you would like to test it by trying to
install it now. If you say yes, fetchware will install it, and if you say no,
then fetchware will print the location of the Fetchwarefile it created for
you to later use to install your application.
EOM

    opening_message($opening_message);

    # Ask user for name of program unless the user provided one at command
    # line such as fetchware new <programname>.
    $program_name //= name_program($term);
    vmsg "Determined name of your program to be [$program_name]";

    $fetchwarefile->config_options(program => $program_name);
    vmsg "Appended program [$program_name] configuration option to Fetchwarefile";

    my $lookup_url = get_lookup_url($term);
    vmsg "Asked user for lookup_url [$lookup_url] from user.";

    $fetchwarefile->config_options(lookup_url => $lookup_url);
    vmsg "Appended lookup_url [$lookup_url] configuration option to Fetchwarefile";

    vmsg "Downloaded lookup_url [$lookup_url]";
    my $filename_listing = download_lookup_url($term, $lookup_url);
    vmsg "Downloaded lookup_url's directory listing";
    vmsg Dumper($filename_listing);

    my $mirrors_hashref = get_mirrors($term, $filename_listing);
    vmsg "Added mirrors to your Fetchwarefile.";
    vmsg Dumper($mirrors_hashref);

    my $verify_hashref = get_verification($term, $filename_listing, $lookup_url);
    vmsg "Added verification settings to Fetchwarefile.";
    vmsg Dumper($verify_hashref);

    my $filter_hashref = get_filter_option($term, $filename_listing);
    vmsg "Added [$filter_hashref->{filter}] filter setting to Fetchwarefile.";

    $fetchwarefile->config_options(
        %$mirrors_hashref,
        %$verify_hashref,
        %$filter_hashref
    );

    ###BUGALERT### Ask to parrallelize make with make_options???
    ###BUGALERT### Verify prefix is writable by current user, who will
    #presumably be the user who will install the package now and later.
    ###BUGALERT### Ask user for a prefix if their running nonroot???
    vmsg 'Prompting for other options that may be needed.';
    my $other_options_hashref = prompt_for_other_options($term,
        temp_dir => {
            prompt => <<EOP,
What temp_dir configuration option would you like? 
EOP
            print_me => <<EOP
temp_dir is the directory where fetchware creates a temporary directory that
stores all of the temporary files it creates while it is building your software.
The default directory is /tmp on Unix systems and C:\\temp on Windows systems.
EOP
        },
        user => {
            prompt => <<EOP,
What user configuration option would you like? 
EOP
            print_me => <<EOP
user specifies what user fetchware will drop priveleges to on Unix systems
capable of doing so. This allows fetchware to download files from the internet
with user priveleges, and not do anything as the administrative root user until
after the downloaded software package has been verified as exactly the same as
the author of the package intended it to be. If you use this option, the only
thing that is run as root is 'make install' or whatever this package's
install_commands configuratio option is.
EOP
        },
        prefix => {
            prompt => <<EOP,
What prefix configuration option would you like? 
EOP
            print_me => <<EOP
prefix specifies the base path that will be used to install this software. The
default is /usr/local, which is acceptable for most unix users. Please note that
this difective only works for software packages that use GNU AutoTools, software
that uses ./configure --prefix=<your prefix will go here> to change the prefix.
EOP
        },
        configure_options => {
            prompt => <<EOP,
What configure_options configuration option would you like? 
EOP
            print_me => <<EOP
configure_options specifies what options fetchware should add when it configures
this software package for you. A list of possible options can be obtained by
running unarchiving the software package that corresponds to this Fetchwarefile,
and running the command './configure --help'. These options vary from software
package to software package. Please note that this option only works for GNU
AutoTools based software distributions, ones that use ./configure to configure
the software.
EOP
        },
        make_options => {
            prompt => <<EOP,
What make_options configuration option would you like? 
EOP
            print_me => <<EOP
make_options specifies what options fetchware will pass to make when make is run
to compile, perhaps test, and install your software package. They are simpley
added after make is called. An example is '-j 4', which will cause make to
execute 4 jobs simultaneously. A reasonable rule of thumb is to set make's -j
argument to two times as many cpu cores your computer has as compiling programs
is sometimes IO bound instead of CPU bound, so you can get away with running
more jobs then you have cores.
EOP
        },
###BUGALERT### Create a config sub called build_system that takes args like
#AutoTools, cmake, MakeMaker, Module::Build, and so on that will use the default
#build commands of whatever system this option specifies.
        build_commands => {
            prompt => <<EOP,
What build_commands configuration option would you like? 
EOP
            print_me => <<EOP
build_commands specifies what commands fetchware will run to compile your
software package. Fetchware's default is simply 'make', which is good for most
programs. If you're software package uses something other than fetchware's
default of GNU AutoTools, then you may need to change this configuration option
to specify what you would like instead. Specify multiple build commands in
single quotes with a comma between them:
'./configure', 'make'
EOP
        },
        install_commands => {
            prompt => <<EOP,
What install_commands configuration option would you like? 
EOP
            print_me => <<EOP
install_commands specifies what commands fetchware will run to install your
software package. Fetchware's default is simply 'make install', which is good
for most programs. If you're software package uses something other than
fetchware's default of GNU AutoTools, then you may need to change this
configuration option to specify what you would like instead. Specify multiple
build commands in single quotes with a comma between them:
'make test', 'make install'
EOP
        },
        uninstall_commands => {
            prompt => <<EOP,
What uninstall_commands configuration option would you like?
EOP
            print_me => <<EOP,
uninstall_commands specifes what commands fetchware will run to uninstall your
software pacakge. The default is 'make uninstall,' which works for some GNU
AutoTools packages, but not all. If your software package does not have a 'make
uninstall' make target, but it has some other command that can uninstall it,
then please specify it using uninstall_commands so fetchware can uninstall it. 
EOP

        },
        lookup_method => {
            prompt => <<EOP,
What lookup_method configuration option would you like? 
EOP
            print_me => <<EOP
lookup_method specifies what how fetchware determines if a new version of your
software package is available. The available algorithms are 'timstamp' and
'versionstring'. 'timestamp' uses the timestamp listed in the FTP or HTTP
listing, and uses the software package that is the newest by filesystem
timestamp. The 'versionstring' algorithm uses the filename of the files in the
FTP or HTTP listing. It parses out the version information, sorts it highest to
lowest, and then picks the highest version of your software package. The default
is try 'timestamp' and if that doesn't work, then try 'versionstring'.
EOP
        },
        gpg_keys_url => {
            prompt => <<EOP,
What gpg_keys_url configuration option would you like? 
EOP
            print_me => <<EOP
gpg_keys_url specifies a url similar to lookup_url in that it should specify a
directory instead a specific file. It is used to download KEYS files, which
contain your program author's gpg keys to import into gpg.
EOP
        },
        gpg_sig_url => {
            prompt => <<EOP,
What gpg_sig_url configuration option would you like? 
EOP
            print_me => <<EOP
gpg_sig_url specifies a url similar to lookup_url in that it should specify a
directory instead a specific file. It is used to download gpg signatures to
verify your software package.
EOP
        },
        sha1_url => {
            prompt => <<EOP,
What sha1_url configuration option would you like? 
EOP
            print_me => <<EOP
sha1_url specifies a url similar to lookup_url in that it should specify a
directory instead of a specific file. It is separate from lookup_url, because
you should download software from mirrors, but checksums from the original
vendor's server, because checksums are easily replaced on a mirror by a hacker
if the mirror gets hacked.
EOP
        },
        md5_url => {
            prompt => <<EOP,
What md5_url configuration option would you like? 
EOP
            print_me => <<EOP,
md5_url specifies a url similar to lookup_url in that it should specify a
directory instead of a specific file. It is separate from lookup_url, because
you should download software from mirrors, but checksums from the original
vendor's server, because checksums are easily replaced on a mirror by a hacker
if  the mirror gets hacked.
EOP
        },
        verify_method => {
            prompt => <<EOP,
What verify_method configuration option would you like? 
EOP
            print_me => <<EOP,
verify_method specifies what method of verification fetchware should use to
ensure the software you have downloaded has not been tampered with. The default
is to try gpg verification, then sha1, and then finally md5, and if they all
fail an error message is printed and fetchware exits, because if your software
package cannot be verified, then it should not be installed. This configuration
option allows you to remove the warnings by specifying a specific way of
verifying your software has not been tampered with. To disable verification set
the 'verify_failure_ok' configuration option to true.
EOP
        },
###BUGALERT### replace no_install config su with a command line option that
#would be the opposite of --force???
# Nah! Leave it! Just create a command line option for it too!
        no_install => {
            prompt => <<EOP,
Would you like to enable the no_install configuration option? 
EOP
            ###BUGALERT### no_install is not currently implemented properly!!!
            print_me => <<EOP
no_install is a true or false option, whoose acceptable values include 1
or 0, true or falue, On or Off. It's default value is false, but if you enable
it, then fetchware will not install your software package, and instead it will
simply download, verify, and build it. And then it will print out the full path
of the directory it built your software package in.
EOP
            ###BUGALERT### Add support for a check regex, so that I can ensure
            #that what the user enters will be either true or false!!!
        },
        verify_failure_ok => {
            prompt => <<EOP,
Would you like to enable the verify_failure_ok configuration option? 
EOP
            print_me => <<EOP
verify_failure_ok is a true or false option, whoose acceptable values include 1
or 0, true or falue, On or Off. It's default value is false, but if you enable
it, then fetchware will not print an error message and exit if verification
fails for your software package. Please note that you should never use this
option, because it makes it possible for fetchware to install source code that
may have been tampered with.
EOP
        },
        users_keyring => {
            prompt => <<EOP,
Would you like to enable users_keyring configuration option? 
EOP
            print_me => <<EOP
users_keyring when enabled causes fetchware to use the user who calls
fetchware's gpg keyring instead of fetchware's own gpg keyring. Useful for
source code distributions that do not provide an easily accessible KEYS file.
Just remember to import the author's keys into your gpg keyring with gpg
--import.
EOP
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
    if (blessed($edited_fetchwarefile)
        and
    $edited_fetchwarefile->isa('App::Fetchware::Fetchwarefile')) {
        # If edit_manually() did not modify the Fetchwarefile, then generate
        # it.
        $fetchwarefile = $fetchwarefile->generate(); 
    } else {
        # If edit_manually() modified the Fetchwarefile, then do not
        # generate it, and replace the Fetchwarefile object with the new
        # string that represents the user's edited Fetchwarefile.
        $fetchwarefile = $edited_fetchwarefile;
    }

    # Whatever variables the new() API subroutine returns are written via a pipe
    # back to the parent, and then the parent reads the variables back, and
    # makes then available to new_install(), back in the parent, as arguments.
    return $program_name, $fetchwarefile;
}



=head2 new() API REFERENCE

Below are the API routines that new() uses to create the question and answer
interface for helping to build new Fetchwarefiles and fetchware packages.

=cut


=head3 extension_name();

    my $extension_name = extension_name('App::FetchwareX::ExtensionName');

    # Or just...
    
    extension_name(__PACKAGE__);

    # Inside your extension whose package is 'App::FetchwareX::ExtensioNName'.

This subroutine sets the name of the extension that this implementation of new()
wants to be called by. It should be C<App::FetchwareX::ExtensionName> the full
name of your extension to make looking it up in documentaiton easier.

All of new()'s API subroutines (everything in App::Fetchware's OVERRIDE_NEW
export tag) use extension_name() to deterime what the this extension should be
called. This is really only used in error messages and occasionally in some of
the questions that new's API subroutines will ask the user. But this subroutine
is important, because it allows extension authors to change all of the
C<App::Fetchware> references in the error messages to their own fetchware
extensions name.

extension_name() is a singleton, and can only be set once. After being set only
once any attempts to set it again will result in an exception being thrown.
Furthermore, any calls to it without arguments will result in it returning the
one scalar argument that was set the first time it was called.

=cut

sub extension_name {
    # Use a state variable to keep $extension_name's value between calls.
    state $extension_name;

    # If $extension_name has never been touch and is still undef, then allow it
    # to be set.
    if (not defined $extension_name) {
        $extension_name = shift;
    # If $extension_name *is* set, and extension_name() was called with an
    # argument, which is what defined shift does (shift shifts the first value
    # off of @_ (the subroutine argument array), while defined checks to see if
    # one was actually defined and provided by the caller.)
    } elsif (defined $extension_name and defined shift) {
        die <<EOD;
App-Fetchware: extension_name() was called more than once. It is a singleton,
and therefore can only be called once. Please only call it once to set its
value, and then call it repeatedly wherever you need that value. see perldoc
App::Fetchware for more details.
EOD
    }

    # Return the singleton $extension_name.
    return $extension_name;
}


=head3 name_program();

    my $program_name = name_program($term);

Asks the user to provide a name for the program that will that corresponds to
Fetchwarefile's C<program> configuration subroutine. This directive is currently
not used for much, but might one day become a default C<filter> option, or might
be used in msg() output to the user for logging.

=cut

sub name_program {
    my $term = shift;
    my $what_a_program_is = <<EOM;
A program configuration directive simply names your program.

In the future it may access existing repositories to see if a Fetchwarefile
has already been created for that program, and use that one instead of creating
a new one, but for now it only names your program, so you can easily tell what
program the Fetchwarefile is supposed to download and install.
EOM

    my $program_name = $term->get_reply(
        prompt => q{What name is your program called? },
        print_me => $what_a_program_is,
    );

    return $program_name;
}


=head3 opening_message();

    opending_message($opening_message);

opening_message() takes the specified $opening_message and just prints it to
C<STDOUT>. This subroutine may seem useless, you could just use print, but using
it instead of print helps document that what you're doing is printing the
opening message to the user.

=cut

sub opening_message {
    my $opening_message = shift;

    # Just print the opening message.
    print $opening_message;
}


=head3 get_lookup_url()

    my $lookup_url = get_lookup_url($term);

Uses $term argument as a L<Term::ReadLine>/L<Term::UI> object to interactively
explain what a lookup_url is, and to ask the user to provide one and press
enter.

=cut

sub get_lookup_url {
    my $term = shift;


    # prompt for lookup_url.
    my $lookup_url = $term->get_reply(
        print_me => <<EOP,
Fetchware's heart and soul is its lookup_url. This is the configuration option
that tells fetchware where to check what the latest version of your program is.
This version number is then parsed out of the HTTP/FTP/local directory listing,
and compared against the latest installed version to determine when a new
version of your program has been released.

How to determine your application's lookup_url:
    1. Go to your application's Web site.
    2. Determine the download link for the latest version and copy it with
       CTRL-C or right-click it and select "copy".
    3. Paste the download link into your browser's URL Location Bar.
    4. Delete the filename from the location by starting at the end and deleting
       everything to the left until you reach a slash '/'.
       * ftp://a.url/downloads/program.tar.gz -> ftp://a.url/downloads/
    5. Press enter to access the directory listing on your Application's mirror
       site.
    6. If the directory listing in either FTP or HTTP format is displayed in
       your browser, then Fetchware's default, built-in lookup fuctionality will
       probably work properly. Copy and paste this URL into the prompt below, and
       Fetchware will download and analyze your lookup_url to see if it will work
       properly. If you do not end up with a browser directory listing, then
       please see Fetchware's documentation using perldoc App::Fetchware.
EOP
        prompt => q{What is your application's lookup_url? },
        allow => qr!(ftp|http|file)://!);

    return $lookup_url;
}


=head3 download_lookup_url()

    my $filename_listing = download_lookup_url($term, $lookup_url);

Attempts to download the lookup_url the user provides. Returns it after parsing
it using parse_directory_listing() from L<App::Fetchware> that lookup() itself
uses.

=cut

sub download_lookup_url {
    my $term = shift;
    my $lookup_url = shift;

    my $filename_listing;
    eval {
        # Use no_mirror_download_dirlist(), because the regular one uses
        # config(qw(lookup_url mirror)), which is not known yet.
        my $directory_listing = no_mirror_download_dirlist($lookup_url);

        # Create a fake lookup_url, because parse_directory_listing() uses it to
        # determine the type of *_filename_listing() subroutine to call.
        config(lookup_url => $lookup_url);

        $filename_listing = parse_directory_listing($directory_listing);

        __clear_CONFIG();

        # Fix the most annoying bug that ever existed in perl.
        # http://blog.twoshortplanks.com/2011/06/06/unexceptional-exceptions-in-perl-5-14/
        1;
    } or do {
        my $lookup_url_failed_try_again = <<EOF;
fetchware: the lookup_url you provided failed because of :
[$@]
Please try again. Try the steps outlined above to determine what your program's
lookup_url should be. If you cannot figure out what it should be please see
perldoc @{[extension_name()]} for additional hints on how to choose a lookup_url.
EOF
        $lookup_url = get_lookup_url($term, $lookup_url_failed_try_again);

        eval {
            # Use no_mirror_download_dirlist(), because the regular one uses
            # config(qw(lookup_url mirror)), which is not known yet.
            my $dir_list = no_mirror_download_dirlist($lookup_url);

            # Create a fake lookup_url, because parse_directory_listing() uses
            # it to determine the type of *_filename_listing() subroutine to
            # call.
            config(lookup_url => $lookup_url);

            $filename_listing = parse_directory_listing($dir_list);

            __clear_CONFIG();
        # Fix the most annoying bug that ever existed in perl.
        # http://blog.twoshortplanks.com/2011/06/06/unexceptional-exceptions-in-perl-5-14/
        1;
        } or do {
            die <<EOD;
fetchware: run-time error. The lookup_url you provided [$lookup_url] is not a
usable lookup_url because of the error below:
[$@]
Please see perldoc @{[extension_name()]} for troubleshooting tips and rerun
fetchware new.
EOD
        };
    };

    return $filename_listing;
}


=head3 get_mirrors()

    my $mirrors_hashref = get_mirrors($term, $filename_listing);

    # $mirrors_hashref = (
    #   mirrors => [
    #       'ftp://some.mirror/mirror',
    #       'http://some.mirror/mirror',
    #       'file://some.mirror/mirror',
    #   ],
    # );

Asks the user to specify at least one mirror to use to download their archives.
It also reiterates to the user that the C<lookup_url> should point to the
author's original download site, and B<not> a 3rd party mirror, because md5sums,
sha1sums, and gpg signatures should B<only> be downloaded from the author's
download site to avoid them being modified by a hacked 3rd party mirror. While
C<mirror> should be configured to point to a 3rd party mirror to lessen the load
on the author's offical download site.

After the user enters at least one mirror, get_mirrors() asks the user if they
would like to add any additional mirrors, and it adds them if the user specifies
them.

The list of the mirrors the user specified is returned as a hash with only one
key C<mirror>, and a value that is an arrayref of mirrors that the user has
specified. The caller, then should call append_options_to_fetchwarefile() to add
this list of mirrors to the user's Fetchwarefile.

=cut

###BUGALERT### Use the $filename_listing argument to search for a MIRRORS file
#that specifies this open source distribution's official listing of mirrors,
#parse it, and add them to the returned hash or mirrors. But, it'll probably
#need configuration. Use GeoIP? No options are avalable. Parse the list, and
#present it to the user, and ask him to pick some:)
sub get_mirrors {
    my ($term, $filename_listing) = @_;

    my @mirrors;

    my $mirror = $term->get_reply(
        print_me => <<EOP,
Fetchware requires you to please provide a mirror. This mirror is required,
because most software authors prefer users download their software packages from
a mirror instead of from the authors main download site, which your lookup_url
should point to.

The mirror should be a URL in standard browser format such as [ftp://a.mirror/].
FTP, HTTP, and local file:// mirrors are supported. All other formats are not
supported.
EOP
        prompt => 'Please enter the URL of your mirror: ',
        allow => qr!^(ftp|http|file)://!,
    );

    # Append mirror to $fetchwarefile.
    push @mirrors, $mirror;

    if (
        $term->ask_yn(
        print_me => <<EOP,
In addition to the one required mirror that you must define in order for
fetchware to function properly, you may specify additonal mirros that fetchware
will use if the mirror you've already specified is unreachable or download
attempts using that mirror fail.
EOP
        prompt => 'Would you like to add any additional mirrors? ',
        default => 'n',
        )
    ) {
        # Prompt for first mirror outside loop, because if you just hit enter or
        # type done, then the above text will be appended to your fetchwarefile,
        # but you'll be able to skip actually adding a mirror.
        my $first_mirror = $term->get_reply(
                prompt => 'Type in URL of mirror or done to continue: ',
                allow => qr!^(ftp|http|file)://!,
            );
            # Append $first_mirror to $fetchwarefile.
            push @mirrors, $first_mirror;

        while (1) {
            my $mirror_or_done = $term->get_reply(
                prompt => 'Type in URL of mirror or done to continue: ',
                default => 'done',
                allow => qr!(^(ftp|http|file)://)|done!,
            );
            if ($mirror_or_done eq 'done') {
                last;
            } else {
                # Append $mirror_or_done to $fetchwarefile.
                push @mirrors, $mirror_or_done;
            }
        }
    }

    return {mirror => \@mirrors};
}


=head3 get_verification()

    my $verification_hashref = get_verification($term, $filename_listing, $lookup_url);

    # $verification_hashref = (
    #   gpg_keys_url => 'http://main.mirror/distdir',
    #   verification_method => 'gpg',
    # );

Parses $filename_listing to determine what type of verification is available.
Prefering gpg, but falling back on sha1, and then md5 if gpg is not available.

If the type is gpg, then get_verification() will ask the user to specify a
C<gpg_keys_url>, which is required for gpg, because fetchware needs to be able
to import the needed keys to be able to use those keys to verify package
downloads. If this URL is not provided by the author, then get_verification()
will ask the user if they would like to import the author's key into their own
gpg public keyring. If they would, then get_verification() will use the
C<user_keyring> C<'On'> option to use the user's public keyring instead of
fetchware's own keyring. And if the user does not want to use their own gpg
public keyring, then get_verification will fall back to sha1 or md5 setting
C<verify_method> to sha1 or md5 as needed.

Also, adds a gpg_keys_url option if a C<KEYS> file is found in
$filename_listing.

If no verification methods are available, fetchware will print a big nasty
warning message, and offer to use C<verify_failure_ok> to make such a failure
cause fetchware to continue installing your software.

Returns a hashref of options for the user's Fetchwarefile. You're responsible
for calling append_options_to_fetchwarefile() to add them to the user's
Fetchwarefile, or perhaps the caller could analyze them in some way, before
adding them if needed. The keys are the names of the configuration options, and
the values are their values.

=cut

sub get_verification {
    my ($term, $filename_listing, $lookup_url) = @_;

    my %options;

    my %available_verify_methods;
    # Determine what types of verification are available.
    for my $file_and_timestamp (@$filename_listing) {
        if ($file_and_timestamp->[0] =~ /\.(asc|sig|sign)$/) {
            $available_verify_methods{gpg}++;
        } elsif ($file_and_timestamp->[0] =~ /\.sha1?$/) {
            $available_verify_methods{sha1}++;
        } elsif ($file_and_timestamp->[0] =~ /\.md5$/) {
            $available_verify_methods{md5}++;
        }
    }

    my $verify_configed_flag = 0;
    #If gpg is available prefer it over the others.
    if (exists $available_verify_methods{gpg}
            and defined $available_verify_methods{gpg}
            and $available_verify_methods{gpg} > 0
    ) {
        msg <<EOM;
gpg digital signatures found. Using gpg verification.
EOM
        $options{verify_method} = 'gpg';

        # Search for a KEYS file to use to import the author's keys.
        if (grep {$_->[0] eq 'KEYS'} @$filename_listing) {
            msg <<EOM;
KEYS file found using lookup_url. Adding gpg_keys_url to your Fetchwarefile.
EOM
            # Add 'KEYS' or '/KEYS' to $lookup_url's path.
            my ($scheme, $auth, $path, $query, $fragment) =
                uri_split($lookup_url);
            $path = catfile($path, 'KEYS');
            $lookup_url = uri_join($scheme, $auth, $path, $query, $fragment);

            $options{gpg_keys_url} = $lookup_url;
            $verify_configed_flag++;
        } else {
            msg <<EOM;
KEYS file *not* found!
EOM
            # Since autoconfiguration of KEYS failed, try asking the user if
            # they would like to import the author's key themselves into their
            # own keyring and have fetchware use that.
            if (
                $term->ask_yn(prompt =>
q{Would you like to import the author's key yourself after fetchware completes? },
                    default => 'n',
                    print_me => <<EOP,
Automatic KEYS file discovery failed. Fetchware needs the author's keys to
download and import into its own keyring, or you may specify the option
user_keyring, which if true will cause fetchware to use the user who runs
fetchware's keyring instead of fetchware's own keyring. But you, the user, needs
to import the author's keys into your own gpg keyring. You can do this now in a
separate shell, or after you finish configuring this Fetchwarefile. Just run the
command [gpg --import <name of file>].
EOP
                )
            ) {
                $options{user_keyring} = 'On';

                $verify_configed_flag++;
            }

            # And if the user does not want to, then fallback to sha1 and/or md5
            # if they're defined, which is done below.
        }
    }
    
    
    # Only try sha1 and md5 if gpg failed.
    unless ($verify_configed_flag == 1) {
        if (exists $available_verify_methods{sha1}
                and defined $available_verify_methods{sha1}
                and $available_verify_methods{sha1} > 0
        ) {
            msg <<EOM;
SHA1 checksums found. Using SHA1 verification.
EOM
            $options{verify_method} = 'sha1';
        } elsif (exists $available_verify_methods{md5}
                and defined $available_verify_methods{md5}
                and $available_verify_methods{md5} > 0
        ) {
            msg <<EOM;
MD5 checksums found. Using MD5 verification.
EOM
            $options{verify_method} = 'md5';
        } else {
            # Print a huge long nasty warning even include links to news stories
            # of mirrors actually getting hacked and serving malware, which
            # would be detected and prevented with proper verification enabled.

            # Ask user if they would like to continue installing fetchware even if
            # verification fails, and then enable the verify_failure_ok option.
            if (
                $term->ask_yn(prompt => <<EOP,
Would you like fetchware to ignore the fact that it is unable to verify the
authenticity of any downloads it makes? Are you ok with possibly downloading
viruses, worms, rootkits, or any other malware, and installing it possibly even
as root? 
EOP
                    default => 'n',
                    print_me => <<EOP,
Automatic verification of your fetchware package has failed! Fetchware is
capable of ignoring the error, and installing software packages anyway using its
verify_failure_ok configuration option. However, installing software packages
without verifying that they have not been tampered with could allow hackers to
potentially install malware onto your computer. Don't think this is *not*
possible or do you think its extremely unlikely? Well, it's actually
surprisingly common:
    1.  http://arstechnica.com/security/2012/09/questions-abound-as-malicious-phpmyadmin-backdoor-found-on-sourceforge-site/
    Discusses how a mirror for sourceforge was hacked, and the phpMyAdmin
    software package on that mirror was modified to spread malware.
    2.  http://www.geek.com/news/major-open-source-code-repository-hacked-for-months-says-fsf-551344/
    Discusses how FSF's gnu.org ftp download site was hacked.
    3.  http://arstechnica.com/security/2012/11/malicious-code-added-to-open-source-piwik-following-website-compromise/
    Discusses how Piwiki's wordpress software was hacked, and downloads of
    Piwiki had malicious code inserted into them.
    4. http://www.theregister.co.uk/2011/03/21/php_server_hacked/
    Discusses how php's wiki.php.org server was hacked yielding credentials to
    php's source code repository.
Download mirrors *do* get hacked. Do not make the mistake, and think that it is
not possible. It is possible, and it does happen, so please properly configure
your Fetchwarefile to enable fetchware to verify that the downloaded software is
the same what the author uploaded.
EOP
                )
            ) {
                # If the user is ok with not properly verifying downloads, then
                # ignore the failure, and install anyway.
                $options{verify_failure_ok} = 'On';
            } else {
                # Otherwise, throw an exception.
                die <<EOD;
fetchware: Fetchware *must* be able to verify any software packages that it
downloads. The Fetchwarefile that you were creating could not do this, because
you failed to specify how fetchware can verify its downloads. Please rerun
fetchware new again, and this time be sure to specify a gpg_keys_url, specify
user_keyring to use your own gpg keyring, or answer yes to the question
regarding adding verify_failure_ok to your Fetchwarefile to make failing
verificaton acceptable to fetchware.
EOD
            }
        }
    }

    return \%options;
}


=head3 get_filter_option()

    $filter_hashref = get_filter_option($term, $filename_listing);

    # $filter_hashref = (
    #   filter => 'user specfied filter option',
    # );

Analyzes $filename_listing and asks the user whatever questions are needed by
fetchware to determine if a C<filter> configuration option is needed, and if it
is what it should be. C<filter> is simply a perl regex that the list of files
that fetchware downloads is checked against, and only files that match this
regex will fetchware consider to be the latest version of the software package
that you want to install. The C<filter> option is needed, because some mirrors
will have multiple software packages in the same directory or multitple
different versions of one piece of software in the same directory. An example
would be Apache, which has Apache versions 2.0, 2.2, and 2.4 all in the same
directory. The C<filter> option is how you differentiate between them.

If a filter was provided by the user than it is returned as a hashref with
C<filter> as the key for use with append_options_to_fetchwarefile(), or for
further analysis by extension authors.

=cut

sub get_filter_option {
    my $term = shift;
    # $filename_listing is an array of [$filename, $timestamp] arrays.
    my $filename_listing = shift;
    msg <<EOS;
Analyzing the lookup_url you provided to determine if fetchware can use it to
successfully determine when new versions of your software are released.
EOS

    my $filter;
    if (grep {$_->[0] =~ /^(CURRENT|LATEST)[_-]IS[_-].+/} @$filename_listing) {
        # There is only one version in the lookup_url directory listing, so
        # I do not need a filter option.
        msg <<EOS;
* The lookup_url you gave fetchware includes a CURRENT_IS or a LATEST_IS file
that tells fetchware and regular users what the latest version is. Because of
this we can be reasonable sure that a filter option is not needed, so I'll skip
asking for one. You can provide one later if you need to provide one, when
fetchware prompts you for any custom options you may want to use.
EOS
    } else {
        # There is a CURRENT_IS_<ver_num> or LATEST_IS_<ver_num> file that tells
        # you what the latest version is.
###BUGALERT### Why is this line in both sections of the if statement??? Inside
#this else block means that a CURRENT_IS or LATEST-IS was *not* found??? Fix
#this!!!!!!
        msg <<EOS;
* The directory listing of your lookup_url has a CURRENT_IS_<ver_num> or
LATEST_IS_<ver_num> file that specifies the latest version, which means that
your program's corresponding Fetchwarefile does not need a filter option. If you
still would like to provide one, you can do so later on, when fetchware allows
you to define any additional configuration options.
EOS
        my $what_a_filter_is = <<EOA;
Fetchware needs you to provide a filter option, which is a pattern that fetchware
compares each file in the directory listing of your lookup_url to to determine
which version of your program to install.

Directories will have other junk files in them or even completely different
programs that could confuse fetchware, and even potentially cause it to install
a different program. Therefore, you should also add the program name to the
begining of your filter. For example if you program is apache, then your filter
should include the name of apache on mirror sites, which is actually:
httpd

For example, Apache's lookup_url has three versions in the same lookup_url
directory listing. These are 2.4, 2.2, and 2.0. Without the filter option
fetchware would choose the highest, which would be 2.4, which is the latest
version. However, you may want to stick with the older and perhaps more stable
2.2 version of apache. Therefore, you'll need to tell fetchware this by using
by adding the version number to your filter:
httpd-2.2
will result in fetchware filtering the results of its lookup check through your
filter of httpd-2.2 causing fetchware to choose the latest version from the 2.2
stable branch instead of the higher version numbered 2.4 or 2.0 legacy releases.
Note the use of the dash, which is used in the filename to separate the 'httpd'
name part from the '2.2' version part.

Note: fetchware accepts any valid perl regular expresion as an acceptable
filter option, but that should only be needed for advanced users. See perldoc
fetchware.
EOA
        # Prompt for the needed filter option.
        $filter = $term->get_reply(
            prompt => <<EOP,
[Just press enter or return to skip adding a filter option]
What does fetchware need your filter option to be? 
EOP
            print_me => $what_a_filter_is,
        );
        ###BUGALERT### Consider Adding a loop around checking the filter option
        #that runs determine_lookup_url() using the provided filter option, and
        #then asking the user if that is indeed the correct filter option, and
        #if not ask again and try it again unit it succeeds or user presses
        #ctrl-c|z.
    }

    return {filter => $filter};
}


=head3 prompt_for_other_options()

    prompt_for_other_options($term,
        temp_dir => {
            prompt => <<EOP,
    What temp_dir configuration option would you like? 
    EOP
            print_me => <<EOP
    temp_dir is the directory where fetchware creates a temporary directory that
    stores all of the temporary files it creates while it is building your software.
    The default directory is /tmp on Unix systems and C:\\temp on Windows systems.
    EOP
        },
            ...
    );

Accepts a Term::Readline/Term::UI object as an argument to use to ask the user
questions, and a gigantic hash of hashes in list form. The hash of hashes,
%option_description, argument incluedes the C<prompt> and C<print_me> options
that are then passed through to Term::UI to ask the user what argument they want
for each specified option in the %option_description hash.

The user's answers are tallied up an returned as a hash reference.
=cut

sub prompt_for_other_options {
    my $term = shift;

    my %option_description = @_;

    my %answered_option;

    if (
        $term->ask_yn(prompt =>
        q{Would you like to add extra configuration options to your fetchwarefile?},
        default => 'n',
        print_me => <<EOP,
Fetchware has many different configuration options that allow you to control its
behavior, and even change its behavior if needed to customize fetchware for any
possible source code distribution.

If you think you need to add configuration options please check out perldoc
fetchware for more details on fetchware and its Fetchwarefile configuration
options.

If this is your first package your creating with Fetchware or you're creating a
package for a new program for the first time, you should skip messing with
fetchware's more flexible options, and just give the defaults a chance.
EOP
        )
    ) {
        my @options = keys %option_description;
        my @config_file_options_to_provide = $term->get_reply(
            print_me => <<EOP,
Below is a listing of Fetchware's available configuration options.
EOP
            prompt => <<EOP,
Please answer with a space seperated list of the number before the configuration
file options that you would like to add to your configuration file? 
EOP
            choices => \@options,
            multi => 1,
        );


        for my $config_file_option (@config_file_options_to_provide) {
            $answered_option{$config_file_option} = $term->get_reply(
                print_me => $option_description{$config_file_option}->{print_me},
                prompt => $option_description{$config_file_option}->{prompt},
            );
        }
    }
    return \%answered_option;
}


=head3 edit_manually()

    $fetchwarefile = edit_manually($term, $fetchwarefile);

edit_manually() asks the user if they would like to edit the specified
$fetchwarefile manually. If the user answers no, then nothing is done. But if
the user answers yes, then fetchware will open their favorit editor either using
the C<$ENV{EDITOR}> environment variable, or fetchware will ask the user what
editor they would like to use. Then this editor, and a temporary fetchwarefile
are opened, and the user can edit their Fetchwarefile as they please. If they
are not satisfied with their edits, and wan to undo them, they can delete the
entire file, and write a size 0 file, which will cause fetchware to ignore the
file they edited. If the write a file with a size greater than 0, then the file
the user wrote, will be used as their Fetchwarefile.

=cut

sub edit_manually {
    my ($term, $fetchwarefile) = @_;

    if (
        $term->ask_yn(
        print_me => <<EOP,
Fetchware has now asked you all of the needed questions to determine what it
thinks your new program's Fetchwarefile should look like. But it's not perfect,
and perhaps you would like to tweak it manually. If you would like to edit it
manually in your favorite editor, answer 'yes', and if you want to skip this just
answer 'no', or just press <Enter>.

If you would like to cancel any edits you have made, and use the automagically
generated Fetchwarefile, just delete the entire contents of the file, and save
an empty file.
EOP
            prompt => q{Would you like to edit your automagically generated Fetchwarefile manually? },
        default => 'n',
        )
    ) {
        my ($fh, $fetchwarefile_filename) =
            tempfile('Fetchwarefile-XXXXXXXXX', TMPDIR => 1);
        print $fh $fetchwarefile->generate();

        close $fh;

        # Ask what editor to use if EDITOR environment variable is not set.
        my $editor = $ENV{EDITOR} || do {
            $term->get_reply(prompt => <<EOP,
What text editor would you like to use? 
EOP
                print_me => <<EOP
The Environment variable EDITOR is not set. This is used by fetchware and other
programs to determine what program fetchware should use to edit your
Fetchwarefile. Please enter what text editor you would like to use. Examples
include: vim, emacs, nano, pico, or notepad.exe (on Windows).
EOP
            );
        };

        run_prog($editor, $fetchwarefile_filename);
        # NOTE: fetchware will "block" during the above call to run_prog(), and
        # wait for the user to close the editor program.

        # If the edited Fetchwarefile does not have a file size of zero.
        if (not -z $fetchwarefile_filename) {
            my $fh = safe_open($fetchwarefile_filename, <<EOD);
fetchware: run-time error. fetchware can't open the fetchwarefile you edited
with your editor after you edited it. This just shouldn't happen. Possible race
condition or weird bug. See perldoc fetchware.
EOD
            # Since the generated Fetchwarefile has been edited, because its
            # size is nonzero, then replace the App::Fetchware::Fetchwarefile
            # object with whatever text can be slurped from the file the user
            # edited. Since it is now a scalar instead of an object, that is how
            # Fetchware will tell if the user changed it or not.
            $fetchwarefile = do { local $/; <$fh> }; # slurp fetchwarefile
        } else {
            msg <<EOM;
You canceled any custom editing of your fetchwarefile by writing an empty file
to disk.
EOM
        }
    }
    return $fetchwarefile;
}




=head2 new_install()

    my $fetchware_package_path = new_install($program_name, $fetchwarefile);

=over

=item Configuration subroutines used:

=over

=item All of them, because it calls bin/fetchware's cmd_install(),
which in turn calls all of the API subroutines that fetchware's install command
does.

=back

=back

Exists separate from new(), because new() drops privileges like most other
fetchware commands do. But the new command includes the ability to ask the user
if they want to install the associated program from their newly created
Fetchwarefile, which requires root privileges. Therefore, we must also have a
API subroutine that runs in the root privileged parent to that the install
commands will run with proper permissions when fetchware is run as root.

=over

=item drop_privs() NOTES

This section notes whatever problems you might come accross implementing and
debugging your Fetchware extension due to fetchware's drop_privs mechanism.

See L<Util's drop_privs() subroutine for more info|App::Fetchware::Util/drop_privs()>.

=over

=item *

When fetchware is run as root, new_install() is called in the parent process
with root permissions so that you can call the 
ask_to_install_now_to_test_fetchwarefile() helper subroutine. I suppose you
could do something else in your extension if it makes sense, but that's what
this API sub is intended for. The ask_to_install_now_to_test_fetchwarefile()
helper subroutine needs root permissions (Unless the Fetchwarefile has been
setup so that the user running it has access.), because it will call fetchware's
cmd_install() to directly cause fetchware to go ahead and install the previoulsy
generated Fetchwarefile.

=back

=back

=cut

sub new_install {
    my ($term, $program_name, $fetchwarefile) = @_;

    my $fetchware_package_path =
        ask_to_install_now_to_test_fetchwarefile($term, \$fetchwarefile,
            $program_name);

    return $fetchware_package_path;

}



=head2 new_install() API REFERENCE

The subroutines below are used by new_install() to provide the new_install functionality
for fetchware. If you have overridden the new_install() handler, you may want to use
some of these subroutines so that you don't have to copy and paste anything from
new_install.

App::Fetchware is B<not> object-oriented; therefore, you B<can not> subclass
App::Fetchware to extend it! 

=cut


=head3 ask_to_install_now_to_test_fetchwarefile()

    my $fetchware_package_path = ask_to_install_now_to_test_fetchwarefile($term, \$fetchwarefile, $program_name);
    my $fetchwarefile_filename = ask_to_install_now_to_test_fetchwarefile($term, \$fetchwarefile, $program_name);

This subroutine asks the user if they want to install the Fetchwarefile that
this subroutine has been called with. If they say yes, then the Fetchwarefile is
passed on to cmd_install() to do all of the installation stuff. If they say no,
then fetchware saves the file to C<"$program_name.Fetchwarefile"> or
ask_to_install_now_to_test_fetchwarefile() will ask the user where to save the
file until the user picks a filename that does not exist.

=over
NOTE: ask_to_install_now_to_test_fetchwarefile() has an infinite loop in it! It
asks the user forever until they provide a filename that doesn't exist. Should a
limit be placed on this? Should it only ask just once?

=back

If you answer yes to install your Fetchwarefile, then
ask_to_install_now_to_test_fetchwarefile() will return the full path to the
fetchware package that has been installed.

=cut

sub ask_to_install_now_to_test_fetchwarefile {
    my ($term, $fetchwarefile, $program_name) = @_;


    vmsg <<EOM;
Determining if user wants to install now or just save their Fetchwarefile.
EOM

    # If the user wants to install their new Fetchwarefile.
    if (
        $term->ask_yn(
        print_me => <<EOP,
It is recommended that fetchware go ahead and install the package based on the
Fetchwarefile that fetchware has created for you. If you don't want to install
it now, then enter 'no', but if you want to test your Fetchwarefile now, and
install it, then please enter 'yes' or just press <Enter>.
EOP
        prompt => q{Would you like to install the package you just created a Fetchwarefile for? },
        default => 'y',
        )
    ) {

        # Create a temp Fetchwarefile to store the autogenerated configuration.
        my ($fh, $fetchwarefile_filename)
            =
            tempfile("fetchware-$$-XXXXXXXXXXXXXX", TMPDIR => 1, UNLINK => 1);
        print $fh $$fetchwarefile;
        # Close the temp file to ensure everything that was written to it gets
        # flushed from caches and actually makes it to disk.
        close $fh;

        vmsg <<EOM;
Saved Fetchwarefile temporarily to [$fetchwarefile_filename].
EOM

        # Reach up bin/fetchware's skirt, and call cmd_install directly, because
        # if I use system() and call fetchware again in a separate process using
        # the install command, it will return a useless number indicating
        # success instead of the $fetchware_package_path I want. I could parse
        # the output, but that's a head ache I want to avoid. Instead, I'll just
        # be a little frisky.
        my $fetchware_package_path = fetchware::cmd_install($fetchwarefile_filename);
        ###BUGALERT### Call cmd_install() inside an eval that will catch any
        #problems that come up, and suggest how to fix them???
        #Is that really doable???
        vmsg <<EOM;
Copied Fetchwarefile package to fetchware database [$fetchware_package_path].
EOM
        msg 'Installed Fetchware package to fetchware database.';
        return $fetchware_package_path;
    # Else the user just wants to save the Fetchwarefile somewhere.
    } else {
        my $fetchwarefile_filename = $program_name . '.Fetchwarefile';

        # Get a name for the Fetchwarefile that does not already exist.
        if (-e $fetchwarefile_filename) {
            while (1) {
                $fetchwarefile_filename = $term->get_reply(
                    prompt => <<EOP,
What would you like your new Fetchwarefile's filename to be?
EOP
                    print_me => <<EOP
Fetchware by default uses the program name you specified at the beginning of
running fetchware new plus a '.Fetchwarefile' extension to name your
Fetchwarefile. But his file already exists, so you'll have to pick a new
filename that does not currently exist.
EOP
                );
                last unless -e $fetchwarefile_filename;
            }
        }
        vmsg <<EOM;
Determine Fetchwarefile name to be [$fetchwarefile_filename].
EOM

    ###BUGALERT### Replace >, create or delete whole file and replace it with
    #what I write now, with >> for append to file if it already exists????
    ###BUGALERT### Should safe_open() be moved into the loop above, and instead
    #of checking for existence, open the file using safeopen as needed, but
    #don't write to it just yet, and then test the open file handle if it's
    #empty, and therefore presumable a new file, or an old file that no one
    #cares about anymore, because it's empty?
        my $fh = safe_open($fetchwarefile_filename, <<EOD, MODE => '>');
fetchware: failed to open your new fetchwarefile because of os error
[$!]. This really shouldn't happen in this case. Probably a bug, or a weird race
condition.
EOD
        print $fh $$fetchwarefile;

        close $fh;

        msg "Saved Fetchwarefile to [$fetchwarefile_filename].";
        return $fetchwarefile_filename;
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

=item user_agent

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

    if (config('lookup_url') =~ m!^ftp://!) {
    ###BUGALERT### *_parse_filelist may not properly skip directories, so a
    #directory could exist that could wind up being the "latest version"
        return ftp_parse_filelist($directory_listing);
    } elsif (config('lookup_url') =~ m!^http://!) {
        return http_parse_filelist($directory_listing);
    } elsif (config('lookup_url') =~ m!^file://!) {
        return file_parse_filelist($directory_listing);
    }
}


=head3 determine_download_path()

    my $download_path = determine_download_path($filename_listing);

Runs the C<lookup_method> to determine what the lastest filename is, and that
one is then concatenated with C<lookup_url> to determine the $download_path,
which is then returned to the caller.

Also calls lookup_determine_downloadpath() to determine the actual download path
from the $sorted_filename_listing returned by C<lookup_by_*()>.

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
    my $sorted_filename_listing;
    if (defined config('lookup_method')
        and config('lookup_method') eq 'timestamp'
    ) {
        $sorted_filename_listing = lookup_by_timestamp($filename_listing);
    } elsif (defined config('lookup_method')
        and config('lookup_method') eq 'versionstring'
    ) {
        $sorted_filename_listing = lookup_by_versionstring($filename_listing);
    # Default is to just use timestamp although timestamp will call
    # versionstring if it can't figure it out, because all of the timestamps
    # are the same.
    } else {
        $sorted_filename_listing = lookup_by_timestamp($filename_listing);
    }

    # Manage duplicate timestamps apropriately including .md5, .asc, .txt files.
    # And support some hacks to make lookup() more robust.
    return lookup_determine_downloadpath($sorted_filename_listing);
}


=head3 ftp_parse_filelist()

    $filename_listing = ftp_parse_filelist($ftp_listing);

Takes an array ref as its first parameter, and parses out the filenames and
timstamps of what is assumed to be C<Net::FTP->dir()> I<long> directory listing
output.

Returns an array of arrays of filenames and timestamps.

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
            #     0       1  2         3             4   5  6    7     8
            my @fields = split /\s+/, $listing;
            # Test & try it???  Probaby won't work.
            #my ($month, $day, $year_or_time, $filename) = ( split /\s+/, $listing )[-4--1];
            $filename = $fields[-1];
            #month       #day        #year
            #"$fields[6] $fields[7] $fields[8]";
            my $month = $fields[5];
            my $day = $fields[6];
            my $year_or_time = $fields[7];

            # Normalize timestamp format.
            # It's a time.
            if ($year_or_time =~ /\d\d:\d\d/) {
                # the $month{} hash access replaces text months with numerical
                # ones.
                $year_or_time =~ s/://; # Make 12:00 1200 for numerical sort.
                $timestamp = "9999$month{$month}$day$year_or_time";
                # It's a year.
            } elsif ($year_or_time =~ /\d\d\d\d/) {
                # the $month{} hash access replaces text months with numerical
                # ones.
                $timestamp = "$year_or_time$month{$month}${day}0000";
            }
            push @filename_listing, [$filename, $timestamp];
        }

        return \@filename_listing;
    }


=head3 http_parse_filelist()

    $filename_listing = http_parse_filelist($http_listing);

Takes an scalar of downloaded HTML output, and parses it using
HTML::TreeBuilder to build and return an array of arrays of filenames and
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
formatted timestamp to return.

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

    return \@sorted_listing;
}


=head3 lookup_by_versionstring()

    my $sorted_filename_listing = lookup_by_versionstring($filename_listing);

Determines the $sorted_filename_listing used by determine_download_path() by
cleverly C<split>ing the filenames (the first value of the array of arrays
input, $filename_listing) on C</\D+/>, which will return a list of version
numbers. Then, the cleverly splitted filename is pushed on to the input array,
and then the array is sorted based on this new value using a custom sort block.

lookup_by_versionstring() also discards any entries from $filename_listing that
do not have a version number in them, because without version numbers that entry
can not be sorted properly. And if it is left in, it could confuse fetchware
into figuring out the correct download path.

Also note, that both $filename_listing and lookup_by_versionstring()'s return
value, $sorted_filename_listing, B<must> both be arrayrefs of arrays. That is a
scallar pointing to an array of arrays.

=cut

sub  lookup_by_versionstring {
    my $file_listing = shift;

    # Implement versionstring algorithm.
    my @versionstrings;
    for (my $i = 0; $i <= $#{$file_listing}; $i++) {
        # Split the filename on "Not a numbers", so remove all "not
        # numbers", but keep a list of things that actually are numbers.
        my @iversionstring = split(/\D+/, $file_listing->[$i][0]);

        # Use grep to strip leading empty strings (eg: '').
        @iversionstring = grep {$_ ne ''} @iversionstring;

        if (@iversionstring == 0) {
            # Let the usr know we're skipping this filename, but only if they
            # really want to know (They turned on verbose output.).
            vmsg <<EOM;
File [$file_listing->[$i][0]] has no version number in it. Ignoring.
EOM
            # And also skip adding this @iversionstring to @versionstrings,
            # because this @iversionstring is empty, and how do I sort an empty
            # array? Return undef--nope causes "value undef in sort fatal errors
            # and warnings." Return 0--nope causes a file with no version number
            # at beginning of listing to stay at listing, and cause fetchware to
            # fail picking the right version. Return -1--nope, because that's
            # hackish and lame. Instead, just not include them in the lookup
            # listing, and if that means that the lookup listing is empty throw
            # an exception.
            next;
        }
        # Add $i's version string to @versionstrings.
        push @versionstrings, [$i, @iversionstring];

        # And the sort below sorts them into highest number first order.
    }

   die <<EOD if @versionstrings == 0;
App-Fetchware: The lookup_url your provided [@{[config('lookup_url')]}] does not
have any filenames with detectable version numbers in them. Fetchware's
'versionstring' lookup algorithm depends on files having version numbers in them
such as [httpd-2.2.22.tar.gz] notice the [2.2.22] version number. Fetchware
failed to find any of those in the lookup_url you provided. Consider a different
lookup_url or try switching to the default 'timestamp' lookup algorithm adding
the "lookup_method" configuration option to your Fetchwarefile.
EOD

   # LIMITATION: The sort block below can not have any undef values in its
   # input. If there are any, then perl will give a warning about a value being
   # undef in a sort, if you are not lucky, then it will actually trigger a
   # fatal error. There are CPAN Testers reports with this problem, so it really
   # can happen. But you do not have to worry about this, because the for loop
   # above that creates @versionstrings 
    @versionstrings = sort {
        # Figure out whoose ($b or $a) is larger and set $last_index to it.
        my $last_index;
        if ($#{$b} > $#{$a}) {
            $last_index = $#{$b};
        } else {
            $last_index = $#{$a};
        }

        # Loop over the indexes of both $b and $a at the same time comparing
        # them one by one with <=>...
        # ...and be sure to start at index 1, because index 0 is the index of
        # $file_listing that this entry in @versionstrings belongs to...
        for my $x (1..$last_index) {
            # If one of $b or $a has more numbers in it ($#{$a_or_b} is smaller than
            # $x), then if it's $b we should return -1, because $b is smaller
            # than $a, and if it's $a, we should return 1, because $b is bigger
            # than $a.
            return -1 if $x > $#{$b};
            return 1 if $x > $#{$a};

            my $spaceship_result = $b->[$x] <=> $a->[$x];

            # ...and as soon as they no longer equal each other return whatever
            # result (-1 or 1) <=> gives.
            return $spaceship_result if $spaceship_result != 0;
        }

        # Return 0 for equal, because if the two versions were not equal, then
        # the for loop above would have caught it, and returned the appropriate
        # -1 or 1.
        return 0;
    } @versionstrings;

    # Now, "sort" $file_listing into the order @versionstrings was sorted into
    # using the copy @sorted_file_listing.
    my @sorted_file_listing;
    for my $versionstring_arrayref (@versionstrings) {
        push @sorted_file_listing,
            # The $versionstring_arrayref->[0] part refers to the index that was
            # saved first when @versionstrings was created.
            $file_listing->[$versionstring_arrayref->[0]];
    }

    # Return the sorted $file_listing, @sorted_filename_listing.
    return \@sorted_file_listing;
}



=head3 lookup_determine_downloadpath()

    my $download_path = lookup_determine_downloadpath($file_listing);

Given a $file_listing of files with the same timestamp or versionstring,
determine which one is a downloadable archive, a tarball or zip file. And
support some hacks to make fetchware more robust. These are the C<filter>
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
        if ($fl->[0] =~ /\.tar\.xz$/) {
            my $path = ( uri_split(config('lookup_url')) )[2];
            return "$path/$fl->[0]";
        } elsif ($fl->[0] =~ /\.txz$/) {
            my $path = ( uri_split(config('lookup_url')) )[2];
            return "$path/$fl->[0]";
        } elsif ($fl->[0] =~ /\.tar\.bz2$/) {
            my $path = ( uri_split(config('lookup_url')) )[2];
            return "$path/$fl->[0]";
        } elsif ($fl->[0] =~ /\.tbz$/) {
            my $path = ( uri_split(config('lookup_url')) )[2];
            return "$path/$fl->[0]";
        } elsif ($fl->[0] =~ /\.tar\.gz$/) {
            my $path = ( uri_split(config('lookup_url')) )[2];
            return "$path/$fl->[0]";
        } elsif ($fl->[0] =~ /\.tgz$/) {
            my $path = ( uri_split(config('lookup_url')) )[2];
            return "$path/$fl->[0]";
        } elsif ($fl->[0] =~ /\.zip$/) {
            my $path = ( uri_split(config('lookup_url')) )[2];
            return "$path/$fl->[0]";
        } elsif ($fl->[0] =~ /\.fpkg$/) {
            my $path = ( uri_split(config('lookup_url')) )[2];
            return "$path/$fl->[0]";
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

=item user_agent

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

=item gpg_keys_url

=item user_keyring

=item gpg_sig_url

=item sha1_url

=item md5_url

=item verify_method

=item verify_failure_ok

=item user_agent

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
    unless (defined(config('verify_method'))) {
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
    } elsif (config('verify_method') =~ /gpg/i) {
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
    } elsif (config('verify_method') =~ /sha1?/i) {
        vmsg <<EOM;
You selected SHA1 checksum verification. Verifying now.
EOM
        sha1_verify($download_path, $package_path)
            or die <<EOD unless config('verify_failure_ok');
App-Fetchware: run-time error. You asked fetchware to only try to verify your
package with sha, but it failed. See the warning above for their error message.
See perldoc App::Fetchware.
EOD
    } elsif (config('verify_method') =~ /md5/i) {
        vmsg <<EOM;
You selected MD5 checksum verification. Verifying now.
EOM
        md5_verify($download_path, $package_path)
            or die <<EOD unless config('verify_failure_ok');
App-Fetchware: run-time error. You asked fetchware to only try to verify your
package with md5, but it failed. See the warning above for their error message.
See perldoc App::Fetchware.
EOD
    } else {
        die <<EOD;
App-Fetchware: run-time error. Your fetchware file specified a wrong
verify_method option. The only supported types are 'gpg', 'sha', 'md5', but you
specified [@{[config('verify_method')]}]. See perldoc App::Fetchware.
EOD
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
Fetchwarefile. Then Fetchware downloads a digital signature that usually
ends in C<.asc>. Afterwards, fetchware uses the gpg command line program to
verify the digital signature. gpg_verify returns true if successful, and throws
an exception otherwise.

You can use C<gpg_keys_url> to specify the URL of a file where the author has
uploaded his keys. And the C<gpg_sig_url> can be used to setup an alternative
location of where the C<.asc> digital signature is stored.

=cut

sub gpg_verify {
    my $download_path = shift;

    my $keys_file;
    # Attempt to download KEYS file in lookup_url's containing directory.
    # If that fails, try gpg_keys_url if defined.
    # Import downloaded KEYS file into a local gpg keyring using gpg command.
    # Determine what URL to use to download the signature file *only* from
    # lookup_url's host, so that we only download the signature from the
    # project's main mirror.
    # Download it.
    # gpg verify the sig using the downloaded and imported keys in our local
    # keyring.

    # Skip downloading and importing keys if we're called from inside a
    # fetchware package, which should already have a copy of our package's
    # KEYS file.
    unless (config('user_keyring')
        or (-e './pubring.gpg' and -e './secring.gpg')) {
        # Obtain a KEYS file listing everyone's key that signs this distribution.
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

        # Import downloaded KEYS file into a local gpg keyring using gpg
        # command.
        eval {
            # Add --homedir option if needed.
            if (config('user_keyring')) {
                run_prog('gpg', '--import', $keys_file);
            } else {
                run_prog('gpg', '--homedir', '.', '--import', $keys_file);
            }
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
###BUGALERT###    }
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
        # Add --homedir option if needed.
        if (config('user_keyring')) {
            run_prog('gpg', '--verify', $sig_file);
        } else {
            run_prog('gpg', '--homedir', '.', '--verify', $sig_file);
        }

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
        my (undef, undef, $path, undef, undef) = uri_split($download_path);
        my ($scheme, $auth, undef, undef, undef) =
            uri_split(config("${digest_ext}_url"));
        my $digest_url = uri_join($scheme, $auth, $path, undef, undef);
        msg "Downloading $digest_ext digest using [$digest_url.$digest_ext]";
        $digest_file = no_mirror_download_file("$digest_url.$digest_ext");
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
    # Will only check the first checksum it finds.
    while (<$digest_fh>) {
        next if /^\s+$/; # skip whitespace only lines just in case.
        my @fields = split ' '; # Defaults to $_, which is filled in by <>

        # Search the @fields for a regex that is either 32 hex for md5 or 40 hex
        # for sha1.
        my ($checksum) = grep /^[0-9a-f]{32}(?:[0-9a-f]{8})?$/i, @fields;

        # Skip trying to verify the $checksum if we failed to find it in this
        # line, and instead skip to the next line in the checksum file to try to
        # find a $checksum.
        next unless defined $checksum;

        if ($checksum eq $calculated_digest) {
            return 'Package verified';
        # Sometimes a = is appended to make it 32bits.
        } elsif ("$checksum=" eq $calculated_digest) {
            return 'Package verified';
        }
    }
    close $digest_fh;

    # Return failure, because fetchware failed to verify by checksum
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
    my $files;
    my $format;
    if ($package_path =~ /\.(t(gz|bz|xz|Z))|(tar\.(gz|bz2|xz|Z))|.fpkg$/) {
        $format = 'tar';
        vmsg <<EOM;
Listing files in your tar format archive [$package_path].
EOM
        $files = list_files_tar($package_path); 
    } elsif ($package_path =~ /\.zip$/) {
        $format = 'zip';
        vmsg <<EOM;
Listing files in your zip format archive [$package_path].
EOM
        $files = list_files_zip($package_path); 
    } else {
        die <<EOD;
App-Fetchware: Fetchware failed to determine what type of archive your
downloaded package is [$package_path]. Fetchware only supports zip and tar
format archives.
EOD
    }

    # unarchive_package() needs $format, so return that too.
    return $format, $files;
}


=head3 list_files_tar()

    my $tar_file_listing = list_files_tar($path_to_tar_archive);

Returns a arrayref of file names that are found in the given, $path_to_tar_archive,
tar file. Throws an exception if there is an error.

It uses C<Archive::Tar-E<gt>iter()> to avoid reading the entire tar archive
into memory.

=cut

sub list_files_tar {
    my $path_to_tar_archive = shift;

    my $tar_iter = Archive::Tar->iter($path_to_tar_archive, 1, );
    die <<EOD unless defined $tar_iter;
App-Fetchware: fetchware failed to create a new Archive::Tar iterator. The
Archive::Tar error message was [@{[Archive::Tar->error()]}].
EOD

    # Iterate over the the archive one file at a time to save memory on big
    # archives suchs a say MariaDB or the Linux kernel.
    my @files;
    while (my $file = $tar_iter->() ) {
        push @files, $file->full_path();
    }

    return \@files;
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

Returns a arrayref of file names that are found in the given, $path_to_zip_archive,
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
    return \@external_filenames;
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

You can only specify C<build_commands> or any of the other three build options.
You cannot combine C<build_commands> with any of the other build options.

=over

=item LIMITATIONS
build() like install() inteligently parses C<build_commands>, C<prefix>,
C<make_options>, and C<configure_options> by just using Test::Parsewords to
parse out the string considering quotes, and then execute them using fetchware's
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

    vmsg "changing Directory to build path [$build_path]";
    chdir $build_path or die <<EOD;
App-Fetchware: run-time error. Failed to chdir to the directory fetchware
unarchived [$build_path]. OS error [$!].
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
                run_prog($split_star_command);
            }
        # Or just run the one command.
        } else {
            run_prog($star_command);
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
            ###BUGALERT## At least under AutoTools, --prefix needs to be a full
            #path. Should I check for this here? Ignore this possible error, and
            #just let ./configure check its own arguments. Or add syntax
            #checking to configuration subroutines???
            $configure .= " --prefix=@{[config('prefix')]}";
        }
    }
    
    # Finally run ./configure.
    run_prog($configure);

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

Uses its two arguments ($download_path and $fetchware_package_path) to determine
if the new version of your program that has been downloaded (from
$download_path) is newer than the currently installed version (from
$fetchware_package_path).

Returns true if $download_path is newer than $fetchware_package_path.

Returns false if $download_path is not newer than $fetchware_package_path.

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
    my ($download_path, $fetchware_package_path) = @_;

    # I only need the basename.
    my $download_path_basename = file($download_path)->basename();
    my $upgrade_name_basename =
        file( $fetchware_package_path)->basename();
    vmsg <<EOM;
Shortened the new download url [$download_path_basename] and the installed
package's [$upgrade_name_basename] into just their basenames.
EOM

    # Strip trailing garbage to normalize their names, so that they can be
    # compared to each other.
    ###BUGALERT### This comparision is quite fragile. Figure out a better way to
    #do this!!!
    $upgrade_name_basename =~ s/\.fpkg$//;
    $download_path_basename
        =~ s/(\.(?:zip|tgz|tbz|txz|fpkg)|(?:\.tar\.(gz|bz2|xz|Z)?))$//;
    vmsg <<EOM;
Striped the new download url [$download_path_basename] and the installed
package's [$upgrade_name_basename] of their file extensions.
EOM

    # Check if $upgrade_name_basename and $download_path_basename are eq, and if
    # they are return false indicating that this program should not be upgraded,
    # because the version available for upgrading is the same as the currently
    # installed version.
    return if $upgrade_name_basename eq $download_path_basename;

        # Transform both competing filenames into a string of version numbers.

    # Use lookup_by_versionstring() to determine which version of the same
    # program is "newer."
    my $sorted_file_names = lookup_by_versionstring(
        [
            [$upgrade_name_basename, 'placeholder'],
            [$download_path_basename, 'placeholder'],
        ]
    );

    if ($sorted_file_names->[0][0] eq $download_path_basename
        # Make sure cmd_upgrade() does not upgrade when the latest version is
        # the same as the currently installed version ($upgrade_name_basename).
        and $sorted_file_names->[0][0] ne $upgrade_name_basename) {
        # The latest version we can download ($download_path_basename) is newer
        # than the currently installed version ($upgrade_name_basename), so we
        # should upgrade.
        return 1;
    } else {
        # Currenlty installed version ($upgrade_name_basename) is equal to the
        # latest version available for download ($download_path_basename), so
        # return false indicating that we sould not upgrade.
        return;
    }
}



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
Fetchwarefile for "higher level" syntax errors. Syntax errors that are
B<Fetchware> syntax errors instead of just Perl syntax errors.

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

=item * program, lookup_url, and mirror are required for all Fetchwarefiles.

=back

=item * Conflicting configuration options

=over

=item * build_commands conflicts with any of prefix, configure_options, and
make_options.

=back

=item * Ensures some options have only allowable options specified.

=over

=item * lookup_method can only have 'timestamp' or 'versionstring'. as options.

=item * And verify_method can only have 'gpg', 'sha1', or 'md5' specified.

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
    my $fetchwarefile = shift;

    # Use check_config_options() to run config() a bunch of times to check the
    # already parsed Fetchwarefile.
    return check_config_options(
        BothAreDefined => [ [qw(build_commands)],
            [qw(prefix configure_options make_options)] ],
        Mandatory => [ 'program', <<EOM ],
App-Fetchware: Your Fetchwarefile must specify a program configuration
option. Please add one, and try again.
EOM
        Mandatory => [ 'mirror', <<EOM ],
App-Fetchware: Your Fetchwarefile must specify a mirror configuration
option. Please add one, and try again.
EOM
        Mandatory => [ 'lookup_url', <<EOM ],
App-Fetchware: Your Fetchwarefile must specify a lookup_url configuration
option. Please add one, and try again.
EOM
        ConfigOptionEnum => ['lookup_method', [qw(timestamp versionstring)] ],
        ConfigOptionEnum => ['verify_method', [qw(gpg sha1 md5)] ],
    );
}


=head2 check_syntax() API REFERENCE

check_syntax() uses check_config_options() to do the heavy lifting of Set Theory
to check that you do not use some configuration options that are not compatible
with other ones that you have used.

=cut


=head3 check_config_options()

    check_config_options(
        BothAreDefined => [ [qw(build_commands)],
            [qw(prefix configure_options make_options)] ],
        Mandatory => [ 'program', <<EOM ],
    App-Fetchware: Your Fetchwarefile must specify a program configuration
    option. Please add one, and try again.
    EOM
        Mandatory => [ 'mirror', <<EOM ],
    App-Fetchware: Your Fetchwarefile must specify a mirror configuration
    option. Please add one, and try again.
    EOM
        Mandatory => [ 'lookup_url', <<EOM ],
    App-Fetchware: Your Fetchwarefile must specify a lookup_url configuration
    option. Please add one, and try again.
    EOM
        ConfigOptionEnum => ['lookup_method', [qw(timestamp versionstring)] ],
        ConfigOptionEnum => ['verify_method', [qw(gpg sha1 md5)] ],
    );

Uses config() to test that no configuration options that clash with each other
are used.

It's parameters are specified in a list with an even number of parameters. Each
group of 2 parameters specifies a type of test that check_config_options() will
test for. There are three types of tests. Also, note that the parameters are
specified as a list not as a hash, because multiple "keys" are allowed, and hash
keys must be unique; therefore, the parameters are a list instead of a hash.

=over

=item BothAreDefined

Is used to test if one or more elements from both provided arrayrefs are defined
at the same time. This is needed, because if you specify C<build_commands> any
value you specify for C<prefix>, C<configure_options>, C<make_options> will be
ignored, which may not be what you expect or want, so BothAreDefined is used to
check for this.

Also, unlike C<Mandatory> and C<ConfigOptionEnum> this syntax checker does not
take a string argument that specifies an error message, because it takes the two
other values that you specifiy, and uses them to fill in its own error message.

=item Mandatory

Is used to check for mandatory options, which just means that these options
absolutely must be specified in user's Fetchwarefiles, and if they are not, then
the provided error message is thrown as an exception.

=item ConfigOptionEnum

Tests that enumerations are valid. For example, C<lookup_method> can only take
two values C<timestamp> or C<versionstring>, and ConfigOptionEnum is used to
test for this.

=back

=cut

sub check_config_options {
    my @args = @_;

    my @both_are_defined;
    my @mandatory;
    my @config_option_enum;

    # Process arguments, and check that they were specified correctly.
    # Loop over @args 2 at a time hence the $i += 2 instead of $i++.
    for( my $i = 0; $i < @args; $i += 2 ) {
        my( $type, $AnB ) = @args[ $i, $i+1 ];
        die <<EOD unless ref $AnB eq 'ARRAY';
App-Fetchware: check_config_options()'s even arguments must be an array
reference. Please correct your arguments, and try again.
EOD
        die <<EOD unless @$AnB == 2;
App-Fetchware: check_config_options()'s even arguments must be an array
reference with exactly two elements in it. Please correct and try again.
EOD

        if ($type eq 'BothAreDefined') {
            push @both_are_defined, $AnB;
        } elsif ($type eq 'Mandatory') {
            push @mandatory, $AnB;
        } elsif ($type eq 'ConfigOptionEnum') {
            push @config_option_enum, $AnB;
        } else {
            die <<EOD;
App-Fetchware: check_config_options() only supports types 'BothAreDefined',
'Mandatory', and 'ConfigOptionEnum.' Please specify one of these, and try again.
EOD
        }
    }

    # Process @both_are_defined by checking if both of the elements in the
    # provided arrayrefs are "both defined", and if they are "both defined"
    # throw an exception.
    for my $AnB (@both_are_defined) {
        my ($A, $B) = @$AnB;

        my @A_defined;
        my @B_defined;

        # Check which ones are defined in both $A and $B
        {
            # the config() call will call the specified strings of which many
            # are expected to be uninitialized. Because we expect them to be
            # uninitialized, we use that behavior to determine if they have been
            # specified in the users Fetchwarefile, and if an option was not
            # specified, then undef is returned by config(). Since, we expect
            # lots of undef warnings, we'll disable them.
            no warnings 'uninitialized';
            @A_defined = grep {config($_)} @$A;
            @B_defined = grep {config($_)} @$B;
        }

        if (@A_defined > 0 and @B_defined > 0) {
            die <<EOD;
App-Fetchware: Your Fetchwarefile has incompatible configuration options.
You specified configuration options [@$A] and [@$B], but these options are not
compatible with each other. Please specifiy either [@$A] or [@$B] not both.
EOD
        }
    }


    # Process @mandatory options by checking if they're defined, and if not
    # throwing the specified exception.
    for my $AnB (@mandatory) {
        my ($option, $error_message) = @$AnB;

        die $error_message if not defined config($option);
    }


    # Process @config_option_enum.
    for my $AnB (@config_option_enum) {
        my ($option, $enumerations) = @$AnB;

        # Ditch uninitialized warnings, because I'm using undef to mean
        # unspecified, so undef is not something unexpected to bother warning
        # about, but something that will happen all the time.
        {
            no warnings 'uninitialized';
        
            # Only test the @enumerations if $option was specified in the
            # Fetchwarefile.
            if (config($option)) {

                # Only one @enumerations should equal $option not more than one, hence
                # the == 1 part.
                die <<EOD unless (grep {config($option) eq $_} @$enumerations) == 1;
App-Fetchware: You specified the option [$option], but failed to specify only
one of its acceptable values [@$enumerations]. Please change the value you
specified [@{[config($option)]}] to one of the acceptable ones listed above, and try again.
EOD
            }

        }
    }
    
    return 'Syntax Ok';
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

    # filter is not required, but is often needed to tell fetchware which
    # program in the lookup_url directory or what specific version you would
    # want to install. For example, Apache maintains 3 versions 2.0, 2.2, and
    # 2.4. filter is what allows you to select which version you want fetchware
    # to use.
    filter 'version-2.0';

    # Below are some popular options that may interest you.
    make_options '-j 4';

    ### This is how Fetchwarefile's can replace lookup()'s or any other
    ### App::Fetchware API subroutine's default behavior.
    ### Remember your coderef must take the same parameters and return the same
    ### values.
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

=head2 Fetchware's Fetchwarefile's configuration option syntax

The syntax for setting configuration options is easy. It's just the name of the
configuration option you want to specify like so:

    program

And then you add a space, and then whatever value you want it to have in quotes.

    program 'Apache';

And don't forget the semicolon C<;> on then end. The semicolon is required

You can use comments as needed to help document you Fetchwarefile like so:

    # Fetchwarefile for Apache.
    program 'Apache';

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
download. To figure this out just use your browser to find the program you
want fetchware to manage for you's Web site. Skip over the download link, and
instead look for the gpg, sha1, or md5 verify links, and copy and paste one of
those between the single quotes above in the lookup_url. Then delete the file
portion--from right to left until you reach a C</>. This is necessary, because
fetchware uses the lookup_url as a basis to download your the gpg, sha1, or md5
digital signatures or checksums to ensure that the packages fetchware downloads
and installs are exactly the same as the ones the author uploads.

    lookup_url '';

And then after you copy the url.

    lookup_url 'http://www.apache.org/dist/httpd/';

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

Just copy and paste the example above replacing the example between the single
quotes C<'> with the actual value you need.

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
the mirrors your source code distribution has. And the mirrors are tried in the
order they are specified in your Fetchwarefile.

=item B<6. Specifiy other options>

That's all there is to it unless you need to further customize App::Fetchware's
behavior to modify how your program is installed.

If your Fetchwarefile is now finished, you can install your new Fetchwarefile
as a fetchware package with:

    fetchware install [path to your new fetchwarefile]

Or you can futher customize it further as shown next if needed.

=item B<7. Optionally add build and install settings>

If you want to specify additional settings the first to choose from are the
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

=back

=cut


=head1 USING YOUR App::Fetchware FETCHWAREFILE WITH FETCHWARE

After you have
L<created your Fetchwarefile|/"MANUALLY CREATING A App::Fetchware FETCHWAREFILE">
as shown above you need to actually use the fetchware command line program to
install, upgrade, or uninstall your App::Fetchware Fetchwarefile.

=over

=item B<install>

A C<fetchware install [path/to/Fetchwarefile]> while using a App::Fetchware
Fetchwarefile causes fetchware to install the program specified in your
fetchwarefile to your computer as you have specified any build or install
options.

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

If you would like C<fetchware upgrade-all> to be run every night automatically
by cron, then just create a file say fetchware with the contents below in it,
and add it to /etc/cron.daily.

    #!/bin/sh
    # Update all already installed fetchware packages.
    fetchware upgrade-all

And if you don't want to run it system wide as root, you can add it to your user
crontab by pasting the snippet below in to your crontab by executing C<crontab -e>.

    # Check for updates using fetchware every night at 2:30AM.
    # Minute   Hour   Day of Month     Month          Day of Week     Command    
    # (0-59)  (0-23)     (1-31)  (1-12 or Jan-Dec) (0-6 or Sun-Sat)
        30      2          *              *               *           fetchware upgrade-all

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
won't have sytem privileges until after it is verified, providing that what you
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
avoid exposing the root account by downloading files as root.

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

=over

=item LIMITAITON

C<user_keyring> when set to true requires that the user that fetchware is
running under have a real gpg keyring with keys that have been imported into it.
This is not the case B<unless> the C<user> option has been specified with a user
account with a proper home directory and gpg keyring for gpg to use. Because of
this limitation if you need to specify C<user_keyring> be sure to also specify
the C<user> option to specify a I<real> user account instead of the default fake
one C<nobody>.

Typically you would import the keys into your own user accounts gpg keyring, and
then you would specify your own username with the C<user> option to tell
fetchware to drop privs to your own user account to have access to your own gpg
keys.

=back

=head2 gpg_sig_url 'mirror.com/some/path';

Specifies an alternate url to use to download the cryptographic signature that
goes with your program. This is usually a file with the same name as the
download url with a C<.asc> file extension added on. Fetchware will also append
the extensions C<sig> and C<sign> if C<.asc> is not found, because some pgp
programs and authors use these extensions too.

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

=head2 user_agent 'Mozilla/5.0 (X11; Linux x86_64; rv:24.0) Gecko/20100101 Firefox/24.0'

Specifies what C<user_agent> you would like fetchware to pretend to be when
downloading files using the HTTP protocol. Some sites annoying prevent some
user agents from working while allowing others. This allows you to pretend to
be a real browser such as Firefox if you need to.

=head2 verify_method 'gpg';

Chooses a method to verify your program. The default is to try C<gpg>, then
C<sha1>, and finally C<md5>, and if all three fail, then the default is to exit
fetchware with an error message, because it is insecure to install archives that
cannot be verified. The availabel options are:

=over

=item gpg - Uses the gpg program to cryptographically verify that the program you downloaded is exactly the same as its author uploaded it.

=item sha1 - Uses the SHA-1 hash function to verify the integrity of the download. This is much less secure than gpg.

=item md5 - Uses the MD5 hash function to verify the integrity of the download. This is much less secure than gpg.

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
to see which C<gpg_keys_url>, C<gpg_sig_url>, C<sha1_url>, C<md5_url>, or
C<user_keyring> you can use to ensure that your archive is verified before it is
compiled and installed. Even mirrors from sites large and small get hacked
regularly:

L<http://www.itworld.com/security/322169/piwik-software-installer-rigged-back-door-following-website-compromise?page=0,0>

L<http://www.networkworld.com/news/2012/092612-compromised-sourceforge-mirror-distributes-backdoored-262815.html>

L<http://www.csoonline.com/article/685037/wordpress-warns-server-admins-of-trojans>

L<http://www.computerworld.com/s/article/9233822/Hackers_break_into_two_FreeBSD_Project_servers_using_stolen_SSH_keys>

So, Please give searching for a C<gpg_keys_url>, C<gpg_sig_url>, C<sha1_url>,
C<md5_url>, or C<user_keyring> for your program another try before simply
enabling this option.

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
option. But any list of options make accepts will work here too. Separate them
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

=head2 no_install 'On';

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
        return $download_path;
    };

Some App::Fetchware API subroutines take arguments, so be sure to account for
them:

    hook download => sub {
        # Take same args as App::Fetchware's download() does.
        my $download_path = shift;
        
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

=item WARNING

If you specify a C<OVERRIDE_*> export tag to C<App::Fetchware> be sure to add
the C<:DEFAULT> export tag to B<also> export C<App::Fetchware>'s default
exports, which must be properly exported for fetchware to work properly.

=back

=over

=item L<OVERRIDE_LOOKUP|lookup() API REFERENCE> - 
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
        return $download_path;
    };

Feel free to specify a list of the specifc subroutines that you need to avoid
namespace polution, or install and use L<Sub::Import> if you demand more control
over imports.

=head2 A real example

See the section L<EXAMPLE FETCHWAREFILES> for real examples of using hook() to
change fetchware's behavior enough to make it work properly with different
source code distributions that are popular.

=cut

###BUGALERT### Add an section of use cases. You know explaing why you'd use
#no_install, or why'd you'd use look, or why And so on.....

=head1 EXAMPLE FETCHWAREFILES

Below are example Fetchwarefiles. They use a range of features to show you what
Fetchware can do, and how it's Fetchwarefile can be manipulated to work with any
source-code distribution.

=head2 Apache Web Server

This Apache Fetchwarefile includes a few extra mirrors just in case one is down.
The fairly common C<-j 4> C<make_option> to make the build go faster, and a
gigantic C<configure_options> telling C<./configure> excatly how I want my
Apache built and configured. It also uses a heredoc to make its
C<configure_options> configuration option much more legible.

=over

    use App::Fetchware;

    program 'Apache';
    lookup_url 'http://www.apache.org/dist/httpd/';
    filter 'httpd-2.2';
    mirror 'http://apache.mirrors.pair.com/httpd/';
    mirror 'http://mirrors.ibiblio.org/apache/httpd/';
    mirror 'ftp://apache.cs.utah.edu/apache.org/httpd/';

    verify_method 'gpg';
    gpg_keys_url 'http://www.apache.org/dist/httpd/KEYS';

    make_options '-j 4';
    prefix '/home/dly/software/apache2.2';
    # You can use heredocs to make gigantic options like this one more legible.
    configure_options <<EOO;
    --with-mpm=prefork
    --enable-modules="access alias auth autoindex cgi logio log_config status vhost_alias userdir rewrite ssl"
    --enable-so
    EOO

=back


=head2 NGINX Web Server

nginx has its distribution set up differently than Apache, so some changes are
needed. First, nginx does not seem to use any mirrors at all, which means
nginx's Fetchwarefile is going to look kind of stupid with the same exact URL
being used for both the C<lookup_url> and the C<mirror>, but such a
configuration is supported. Next, nginx does not have a KEYS file, but it does
list it's developer's keys on its Website. So, they have to be imported manually
into your keyring, and then specify the C<user_keyring> option to switch
fetchware from usings its own keyring to using your own keyring. Also, note the
comment regarding having to use the C<user> option to specify a real user
account. This is needed, because the verify step is done by fetchware's child
after that child drops its root privileges. Th default user is nobody, and
nobody has no real home, and therefore no keyring, so gpg won't be able to read
the keys you ask it to by using the C<user_keyring> option; therefore, C<user>
must be specified to change it to a real user, whoose keyring has had these keys
imported into it. Also, worth noting that this nginx configuration does not use
a C<filter> option. This is not actually needed, because the only source-code
packages availabe at the C<lookup_url> are the nginx software packages
themselves, but it might be a good idea to include one, because the nginx
developers could always change how their download server is structured. So,
including it is always a good idea.

=over

    use App::Fetchware;
    
    program 'nginx';
    
    # lookup_url and mirror are the same thing, because nginx does not seem to have
    # mirrors. Fetchware, however, requires one, so the same URL is simply
    # duplicated.
    lookup_url 'http://nginx.org/download/';
    mirror 'http://nginx.org/download/';
    
    
    # Must add the developers public keys to my own keyring. These keys are
    # availabe from http://nginx.org/en/pgp_keys.html Do this with:
    # gpg \
    # --fetch-keys http://nginx.org/keys/aalexeev.key\
    # --fetch-keys http://nginx.org/keys/is.key\
    # --fetch-keys http://nginx.org/keys/mdounin.key\
    # --fetch-keys http://nginx.org/keys/maxim.key\
    # --fetch-keys http://nginx.org/keys/sb.key\
    # --fetch-keys http://nginx.org/keys/glebius.key\
    # --fetch-keys http://nginx.org/keys/nginx_signing.key
    # You might think you could just set gpg_keys_url to the nginx-signing.key key,
    # but that won't work, because like apache different releases are signed by
    # different people. Perhaps I could change gpg_keys_url to be like mirror where
    # you can specify more than one option?
    user_keyring 'On';
    # user_keyring specifies to use the user's own keyring instead of fetchware's.
    # But fetchware drops privileges by default using he user 'nobody.' nobody is
    # nobody, so that user account does not have a home directory for gpg to read a
    # keyring from. Therefore, I'm using my own account instead.
    user 'dly';
    # The other option, which is commented out below, is to use root's own keyring,
    # and the no_install option to ensure that root uses its own keyring instead of
    # nobody's.
    # noinstall 'On';
    verify_method 'gpg';

=back


=head2 PHP Programming Language

PHP annoyingly uses a custom Web application on each of its mirror sites to
serve HTTP downloads. No simple directory listing is available. Therefore, to
use php with fetchware, custom C<lookup>, C<download>, and C<verify> hooks are
needed that override fetchware's internal behavior to customize fetchware as
needed so that it can work with how PHP's site is up.

The C<lookup> hook downloads and parses the L<http://www.php.net/downloads.php>
page, which lists files availabe for download. This file is parsed using
L<HTML::TreeBuilder> to determine the latest version. The MD5 sum is also parsed
out to verify the downloaded file as well.

The C<download> hook is only needed, because http_download_file() presumes that
the last part of the path is the filename you're downloading. And this is
annoyingly not the case with the way PHP has its downloading system set up.

The C<verify> hook just uses L<Digest::MD5> to calculate the md5sum of the
downloaded file, and compares it with the one C<lookup> parses out.

=over

    use App::Fetchware qw(
        :OVERRIDE_LOOKUP
        :OVERRIDE_DOWNLOAD
        :OVERRIDE_VERIFY
        :DEFAULT
    );
    use App::Fetchware::Util ':UTIL';
    use HTML::TreeBuilder;
    use URI::Split qw(uri_split uri_join);
    use Data::Dumper;
    use HTTP::Tiny;
    
    program 'php';
    
    lookup_url 'http://us1.php.net/downloads.php';
    mirror 'http://us1.php.net';
    mirror 'http://us2.php.net';
    mirror 'http://www.php.net';
    
    # php does *not* use a standard http or ftp mirrors for downloads. Instead, it
    # uses its Web site, and some sort of application to download files using URLs
    # such as: http://us1.php.net/get/php-5.5.3.tar.bz2/from/this/mirror
    #
    # Bizarrely a URL like
    # http://us1.php.net/get/php-5.5.3.tar.bz2/from/us2.php.net/mirror
    # gets you the same page, but on a different mirror. Weirdly, these are direct
    # downloads without any HTTP redirects using 300 codes, but direct downloads.
    # 
    # This is why using fetchware with php you needs a custom lookup handler.
    # The files you download are resolved to a [http://us1.php.net/distributions/...]
    # directory, but trying to access a apache styple auto index at that url fails
    # with a rediret back to downloads.php.
    my $md5sum;
    hook lookup => sub {
        die <<EOD unless config('lookup_url') =~ m!^http://!;
    php.Fetchwarefile: Only http:// lookup_url's and mirrors are supported. Please
    only specify a http lookup_url or mirror.
    EOD
    
        msg "Downloading lookup_url [@{[config('lookup_url')]}].";
        my $dir_list = download_dirlist(config('lookup_url'));
    
        vmsg "Parsing HTML page listing php releases.";
        my $tree = HTML::TreeBuilder->new_from_content($dir_list);
    
        # This parsing code assumes that the latest version of php is the first one
        # we find, which seems like a dependency that's unlikely to change.
        my $download_path;
        $tree->look_down(
            _tag => 'a',
            sub {
                my $h = shift;
                
                my $link = $h->as_text();
    
                # Is the link a php download link or something to ignore.
                if ($link =~ /tar\.(gz|bz2|xz)|(tgz|tbz2|txz)/) {
    
                    # Set $download_path to this tags href, which should be
                    # something like: /get/php-5.5.3.tar.bz2/from/a/mirror
                    if (exists $h->{href} and defined $h->{href}) {
                        $download_path = $h->{href};
                    } else {
                        die <<EOD;
    php.Fetchwarefile: A path should be found in this link [$link], but there is no
    path it in. No href [$h->{href}].
    EOD
                    }
    
                    # Find and save the $md5sum for the verify hook below.
                    # It should be 3 elements over, so it should be the third index
                    # in the @right array below (remember to start counting 2 0.).
                    my @right = $h->right();
                    my $md5_span_tag = $right[2];
                    $md5sum = $md5_span_tag->as_text();
                    $md5sum =~ s/md5:\s+//; # Ditch md5 header.
                }
            }
        );
    
        # Delete the $tree, so perl can garbage collect it.
        $tree = $tree->delete;
    
        # Determine and return a proper $download_path.
        # Switch it from [/from/a/mirror] to [/from/this/mirror], so the mirror will
        # actually return the file to download.
        $download_path =~ s!/a/!/this/!;
    
        vmsg "Determined download path to be [$download_path]";
        return $download_path;
    };
    
    
    # I also must hook download(), because fetchware presumes that the filename of
    # the downloaded file is the last part of the $path, but that is not the case
    # with the path php uses for file downloads, because it ends in mirror, which is
    # *not* the name of the file; therefore, I must  hook download() to fix this
    # problem.
    hook download => sub {
        my ($temp_dir, $download_path) = @_;
    
        my $http = HTTP::Tiny->new();
        my $response;
        for my $mirror (config('mirror')) {
            my ($scheme, $auth, $path, $query, $fragment) = uri_split($mirror);
            my $url = uri_join($scheme, $auth, $download_path, undef, undef);
            msg <<EOM;
    Downloading path [$download_path] using mirror [$mirror].
    EOM
            $response = $http->get($url);
            
            # Only download it once.
            last if $response->{success};
        }
    
        die <<EOD unless $response->{success};
    php.Fetchwarefile: Failed to download the download path [$download_path] using
    the mirrors [@{[config('mirror')]}]. The response was:
    [@{[Dumper($response->{headers})]}].
    EOD
        die <<EOD unless length $response->{content};
    php.Fetchwarefile: Didn't actually download anything. The length of what was
    downloaded is zero. status [$response->{status}] reason [$response->{reason}]
    HTTP headers [@{[Dumper($response->{headers})]}].
    EOD
    
        msg 'File downloaded successfully.';
    
        # Determine $filename from $download_path
        my @paths = split('/', $download_path);
        my ($filename) = grep /php/, @paths;
    
        vmsg "Filename determined to be [$filename]";
    
        open(my $fh, '>', $filename) or die <<EOD;
    php.Fetchwarefile: Failed to open [$filename] for writing. OS error [$!].
    EOD
    
        print $fh $response->{content};
        close $fh or die <<EOD;
    php.Fetchwarefile: Huh close($filename) failed! OS error [$!].
    EOD
    
        my $package_path = determine_package_path($temp_dir, $filename);
    
        vmsg "Package path determined to be [$package_path].";
    
        return $package_path
    };
    
    
    # The above lookup hook parses out the md5sum on the php downloads.php web
    # site, and stores it in $md5sum, which is used in the the verify hook below.
    hook verify => sub {
        # Don't need the $download_path, because lookup above did that work for us.
        # $package_path is the actual php file that we need to ensure its md5
        # matches the one lookup determined.
        my ($download_path, $package_path) = @_;
    
        msg "Verifying [$package_path] using md5.";
    
        dir <<EOD if not defined $md5sum;
    php.Fetchwarefile: lookup failed to figure out the md5sum for verify to use to
    verify that the php version [$package_path] matches the proper md5sum.
    The md5sum was [$md5sum].
    EOD
    
        my $package_fh = safe_open($package_path, <<EOD);
    php.Fetchwarefile: Can not open the php package [$package_path]. The OS error
    was [$!].
    EOD
    
        # Calculate the downloaded php file's md5sum.
        my $digest = Digest::MD5->new();
        $digest->addfile($package_fh);
        my $calculated_digest = $digest->hexdigest();
    
        die <<EOD unless $md5sum eq $calculated_digest;
    php.Fetchwarefile: MD5sum comparison failed. The calculated md5sum
    [$calculated_digest] does not match the one parsed of php.net's Web site
    [$md5sum]! Do not trust this downloaded file! Perhaps there's a bug somewhere,
    or perhaps the php mirror you downloaded this php package from has been hacked.
    Mirrors do get hacked occasionally, so it is very much possible.
    EOD
    
        msg "ms5sums [$md5sum] [$calculated_digest] match.";
    
        return 'Package Verified';
    };

=back


=head2 PHP Programming Language using its git VCS instead of download mirrors.

PHP like most open source software you can easily download off the internet uses
a version control system to track changes to its source code. This source code
repository is basically the same thing as a normal source code distribution
would be except VCS commands like C<git pull> are used to update it instead of
checking a mirror for a new version. The Fetchwarefile below for php customizes
Fetchware to work with php's VCS instead of the traditional downloading of
actual source code archives.

It overrides lookup() to use a local git repo stored in the $git_repo_dir
variable. To create a repo just clone php's git repo (see
http://us1.php.net/git.php for details.). It runs git pull to update the repo,
and then it runs git tags, and ditches some older junk tags, and finds only the
tags used for new versions of php. These are sorted using the C<versonstring>
lookup() algorithm, and the latest one is returned.

download() uses C<git checkout [latesttag]> to "download" php by simply changing
the working directory to the latest tag. verify() uses git's cool C<verify-tag>
command to verify the gpg signature. unarchive() is updated to do nothing since
there is no archive to unarchive. However, because we reuse build(), archive()
must return a $build_path that build() will change its directory to. start() and
end() are also overridden, because managing a temporary directory is not needed,
so, instead, they just do a C<git checkout master> to switch from whatever the
latest tag is back to master, because git pull bases what it does on what branch
you're in, so we must actually be a real branch to update git.

=over

    # php-using-git.Fetchwarefile: example fetchwarefile using php's git repo
    # for lookup(), download(), and verify() functionality.
    use App::Fetchware qw(:DEFAULT :OVERRIDE_LOOKUP);
    use App::Fetchware::Util ':UTIL';
    use Cwd 'cwd';
    
    # The directory where the php source code's local git repo is.
    my $git_repo_dir = '/home/dly/Desktop/Code/php-src';
    
    # By default Fetchware drops privs, and since the source code repo is stored in
    # the user dly's home directory, I should drop privs to dly, so that I have
    # permission to access it.
    user 'dly';
    
    # Determine latest version by using the tags developers create to determine the
    # latest version.
    hook lookup => sub {
        # chdir to git repo.
        chdir $git_repo_dir or die <<EOD;
    php.Fetchwarefile: Failed to chdir to git repo at
    [$git_repo_dir].
    OS error [$!].
    EOD
    
        # Pull latest changes from php git repo.
        run_prog('git pull');
    
        # First determine latest version that is *not* a development version.
        # And chomp off their newlines.
        chomp(my @tags = `git tag`);
    
        # Now sort @tags for only ones that begin with 'php-'.
        @tags = grep /^php-/, @tags;
    
        # Ditch release canidates (RC, alphas and betas.
        @tags = grep { $_ !~ /(RC\d+|beta\d+|alpha\d+)$/ } @tags;
    
        # Sort the tags to find the latest one.
        # This is quite brittle, but it works nicely.
        @tags = sort { $b cmp $a } @tags;
    
        # Return $download_path, which is only just the latest tag, because that's
        # all I need to know to download it using git by checking out the tag.
        my $download_path = $tags[0];
    
        return $download_path;
    };
    
    
    # Just checkout the latest tag to "download" it.
    hook download => sub {
        my ($temp_dir, $download_path) = @_;
    
        # The latest tag is the download path see lookup.
        my $latest_tag = $download_path;
    
        # checkout the $latest_tag to download it.
        run_prog('git checkout', "$latest_tag");
    
        my $package_path = cwd();
        return $package_path;
    };
    
    
    # You must manually add php's developer's gpg keys to your gpg keyring. Do
    # this by  going to the page: http://us1.php.net/downloads.php . At the
    # bottom the gpg key "names are listed such as "7267B52D" or "5DA04B5D."
    # These are their key "names." Use gpg to download them and import them into
    # your keyring using: gpg --keyserver pgp.mit.edu --recv-keys [key id]
    hook verify => sub {
        my ($download_path, $package_path) = @_;
    
        # the latest tag is the download path see lookup.
        my $latest_tag = $download_path;
    
        # Run git verify-tag to verify the latest tag
        my $success = eval { run_prog('git verify-tag', "$latest_tag"); 1;};
    
        # If the git verify-tag fails, *and* verify_failure_ok has been turned on,
        # then ignore the thrown exception, but print an annoying message.
        unless (defined $success and $success) {
            unless (config('verify_failure_ok')) {
                msg <<EOM;
    Verification failure ok, becuase you've configured fetchware to continue even
    if it cannot verify its downloads. Please reconsider, because mirror and source
    code repos do get hacked. The exception that was caught was:
    [$@]
    EOM
            }
        }
    };
    
    
    hook unarchive => sub {
        # there is nothing to archive due to use of git.
        do_nothing(); # But return the $build_path, which is the cwd().
        my $build_path = $git_repo_dir;
        return $build_path;
    };
    
    # It's a git tag, so it lacks an already generated ./configure, so I must use
    # ./buildconf to generate one. But it won't work on php releases, so I have to
    # force it with --force to convince ./buildconf to run autoconf to generate the
    # ./configure program to configure php for building.
    build_commands './buildconf --force', './configure', 'make';

    # Add any custom configure options that you may want to add to customize
    # your build of php, or control what php extensions get built.
    #configure_options '--whatever you --need ok';
    
    # start() creates a tempdir in most cases this is exactly what you want, but
    # because this Fetchwarefile is using git instead. I don't need to bother with
    # creating a temporary directory.
    hook start => sub {
        # But checkout master anyway that way the repo can be in a known good state
        # so lookup()'s git pull can succeed.
        run_prog('git checkout master');
    };
    
    
    # Switch the local php repo back to the master branch to make using it less
    # crazy. Furthermore, when using git pull to update the repo git uses what
    # branch your on, and if I've checked out a tag, I'm not actually on a branch
    # anymore; therefore, I must switch back to master, so that the git pull when
    # this fetchwarefile is run again will still work.
    hook end => sub {
        run_prog('git checkout master');
    };

=back


=head2 MariaDB Database

This example MariaDB Fetchwarefile parses the MariaDB download page to determine
what the latest version is based on what C<filter> option you set up. Once this
is determined, the download path is created based on the weird path that MariaDB
uses on its mirrors.

Like PHP MariaDB uses some annoying software on their Web site to presumably
track downloads. This software makes use of AJAX, which is vastly beyone the
capabilities of HTML::TreeBuilder to parse, because it needs a working
JavaScript environment. Therefore, the example Fetchwarefile below has no way of
verifying the MySQL downloads. This could be fixed by using a Perl Web scraping
module that can deal with JavaScript.

=over

    use App::Fetchware;
    
    program 'MariaDB';
    
    # MariaDB uses ccache, which wants to create a ~/.ccache cache, which it can't
    # do when it's running as nobody, so use a real user account to ensure ccache
    # has a cache directory it can write to.
    user 'dly';
    
    lookup_url 'https://downloads.mariadb.org/';
    
    # Below are the two USA mirrors where I live. Customize them as you need based
    # on the mirrors listed on the download page (https://downloads.mariadb.org/ and
    # then click on which version you want, and then click on the various mirrors
    # by country. All you need is the scheme (ftp:// or http:// part) and the
    # hostname without a slash (ftp.osuosl.org or mirror.jmu.edu). Not the full path
    # for each mirror.
    mirror 'http://ftp.osuosl.org';
    mirror 'http://mirror.jmu.edu';
    
    # The filter option is key to the custom lookup hook working correctly. It must
    # represent the text that corresponds to the latest GA release of MariaDB
    # available. It should be 'Download 5.5' for 5.5 or 'Download 10.0' for the
    # newver but not GA 10.0 version of MariaDB.
    filter 'Download 5.5';
    
    hook lookup => sub {
        vmsg "Downloading HTML download page listing MariaDB releases.";
        my $dir_list = http_download_dirlist(config('lookup_url'));
    
        vmsg "Parsing HTML page listing MariaDB releases.";
        my $tree = HTML::TreeBuilder->new_from_content($dir_list);
    
        # This parsing code assumes that the latest version of php is the first one
        # we find, which seems like a dependency that's unlikely to change.
        my @version_number;
        $tree->look_down(
            _tag => 'a',
            sub {
                my $h = shift;
                
                my $link = $h->as_text();
    
                # Find the filter which should be "Download\s[LATESTVERSION]"
                my $filter = config('filter');
                if ($link =~ /$filter/) {
                    # Parse out the version number.
                    # It's just the second space separated field.
                    push @version_number, (split ' ', $link)[1];
                }
            }
        );
    
        # Delete the $tree, so perl can garbage collect it.
        $tree = $tree->delete;
    
        # Only one version should be found.
        die <<EOD if @version_number > 1;
    mariaDB.Fetchwarefile: multiple version numbers detected. You should probably
    refine your filter option and try again. Filter [@{[config('filter')]}].
    Versions found [@version_number].
    EOD
    
        # Construct a download path using $version_number[0].
        my $filename = 'mariadb-' . $version_number[0] . '.tar.gz';
    
        # Return a proper $download_path, so That I do not have to hook download(),
        # but can reuse Fetchware's download() subroutine.
        my $weird_prefix = '/mariadb-' . $version_number[0] . '/kvm-tarbake-jaunty-x86/';
        my $download_path = '/pub/mariadb' . $weird_prefix .$filename;
        return $download_path;
    };
    
    # Make verify() failing to verify MariaDB ok, because parsing out the MD5 sum
    # would require a Web scraper that supports javascript, which HTML::TreeBuilder
    # obviously does not.
    verify_failure_ok 'On';
    
    # Use build_commands to configure fetchware to use MariaDB's BUILD script to
    # build it. See https://mariadb.com/kb/en/generic-build-instructions/ for
    # instructions on the different BUILD  cmake scripts that are available.
    build_commands 'BUILD/compile-pentium64-max';
    
    # Use install_commands to tell fetchware how to install it. I could leave this
    # out, but it nicely documents what command is needed to install MariaDB
    # properly.
    install_commands 'make install';

=back


=head2 PostgreSQL Database

Below is a example Fetchwarefile that overrides lookup() to determine the latest
version, but manages to avoid overriding anything else. It uses the same style
as the rest downloading an HTML page that lists the version numbers on it
somewhere. Then it parses the HTML with HTML::TreeBuilder. It populates an
array, and then uses L<App::Fetchware>'s lookup_by_versionstring() to determine
which version is the latest one. This is then concatenated with a bunch of other
stuff to determine the $download_path.

MD5 verification is supported by simply specifying a C<md5_url> option, because
by default fetchware uses the C<lookup_url> to determine where to download the
md5sum from, but that won't work with PostgreSQL, because it's download system
has the md5sum on the download C<mirror> instead of the C<lookup_url>.

=over

    use App::Fetchware qw(:DEFAULT :OVERRIDE_LOOKUP);
    use App::Fetchware::Util ':UTIL';
    
    use HTML::TreeBuilder;
    
    program 'postgres';
    
    # The Postgres file browser URL lists the available versions of Postgres.
    lookup_url 'http://www.postgresql.org/ftp/source/';
    
    # Mirror URL where the file browser links to download them from.
    my $mirror = 'http://ftp.postgresql.org';
    mirror $mirror;
    
    # The Postgres file browser URL that is used for the lookup_url lists version
    # numbers of Postgres like v9.3.0. this lookup hook parses out the list of
    # theses numbers, determines the latest one, and constructs a $download_path to
    # return for download to use to download based on what I set my mirror to.
    hook lookup => sub {
        my $dir_list = no_mirror_download_dirlist(config('lookup_url'));
    
        my $tree = HTML::TreeBuilder->new_from_content($dir_list);
    
        # Parse out version number directories.
        my @ver_nums;
        my @list_context = $tree->look_down(
            _tag => 'a',
            sub {
                my $h = shift;
    
                my $link = $h->as_text();
    
                # Is this link a version number or something to ignore?
                if ($link =~ /^v\d+\.\d+(.\d+)?$/) {
                    # skip version numbers that are beta's, alpha's or release
                    # candidates (rc).
                    return if $link =~ /beta|alpha|rc/i;
                    # Strip useless "v" that just gets in the way later when I
                    # create the $download_path.
                    $link =~ s/^v//;
                    push @ver_nums, $link;
                }
            }
        );
    
        # Turn @ver_num into the array of arrays that lookup_by_versionstring()
        # needs its arguments to be in.
        my $directory_listing = do {
            my $arrayref_of_arrays_directory_listing = [];
            for my $ver_num (@ver_nums) {
                push @$arrayref_of_arrays_directory_listing,
                    [$ver_num];
            }
            $arrayref_of_arrays_directory_listing;
        };
        # Find latest version.
        my $latest_ver = lookup_by_versionstring($directory_listing);
    
        # Return $download_path.
        my $download_path = '/pub/source/'. "v$latest_ver->[0][0]" .
            "/postgresql-$latest_ver->[0][0].tar.bz2";
        return $download_path;
    };
    
    # MD5sums are stored on the download site, so use them to verify the package.
    verify_method 'md5';
    # But they are *not* stored on the original "lookup_url" site, so I must provide
    # a md5_url pointing to the download site.
    md5_url $mirror;

=back

=cut


=head1 CREATING A FETCHWARE EXTENSION

=over

=item WARNING

Currently, fetchware's extension system is B<ALPHA>, and is subject to change at
any time. This, however, is unlikely, but it could happen. Most likely, some new
API subroutines will just be introducted such as check_syntax() to check syntax
for extensions, and new(), which will allow fetchware extensions to customize
the C<fetchware new> command.

=back

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
inheritance tree using C<@INC>. You can, however, use
L<App::Fetchware::ExportAPI> to import whatever subroutines from App::Fetchware
that you want to reuse such as start() and end(), and then simply implement the
remaining  subroutines that make up App::Fetchware's API.  Just like the
C<CODEREF> extensions mentioned above, you must take the same arguments and
return the same values that fetchware expects or using your App::Fetchware
extension will blow up in your face.

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
object-oriented, it is implemented differently. You simply use
L<App::Fetchware::ExportAPI> to specify the L<API subroutines> that you are
B<not> going to override, and then actually implement the remaining subroutines,
so that your App::Fetchware I<subclass> has the same interface that
App::Fetchware does.

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
App::FetchwareX::HTMLPageSync the API subroutines (such as start(), lookup(),
..., install(), and uninstall()) C<fetchware> needs to use to install, upgrade,
or uninstall whatever program your Fetchwarefile specifies.

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

=item B<my $temp_dir = start(KeepTempDir => 0 | 1)> - Gives your extension a chance to do anything needed before the rest of the API subroutines get called.  App::Fetchware's C<start()> manages App::Fetchware's temporary directory creation. If you would like to also use a temporary directory, you can just use L<App::Fetchware::ExportAPI> to "inherit" App::Fetchware's start() instead of implementing it yourself.

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
App::Fetchware::Config's internal state directly to STDOUT. Meant for debugging
only in your test suite.

=back


=item L<App::Fetchware's OVERRIDE_* export tags.|FETCHWAREFILE API SUBROUTINES>

App::Fetchware's main API subroutines, especially the crazy complicated ones
such as lookup(), are created by calling and passing data among many component
subroutines. This is done to make testing much much easier, and to allow
App::Fetchware extensions to also use some or most of these component
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
the files in your archive, and pass that list to check_archive_files() to ensure
that the archive will not overwrite any system files, and contains no absolute
paths that could cause havok on your system. unarchive_package() does the actual
unarchiving of software packages.

=item L<build()'s OVERRIDE_BUILD export tag.|build() API REFERENCE>

Provides run_star_commands(), which is meant to execute common override commands
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

=item L<Test::Fetchware/eval_ok()> - A poor man's Test::Exception. Captures any
exceptions that are thrown, and compares them to the provided exception text or
regex.

=item L<Test::Fetchware/print_ok()> - A poor man's Test::Output. Captures
STDOUT, and compares it to the provided text.

=item L<Test::Fetchware/skip_all_unless_release_testing()> - Fetchware is a
package manager, but who wants software installed on their computer just to test
it? This subroutine marks test files or subtests that should be skipped unless
fetchware's extensive FETCHWARE_RELEASE_TESTING environement variables are set.
This funtionality is described next.

=item L<Test::Fetchware/make_clean()> - Just runs C<make clean> in the current
directory.

=item L<Test::Fetchware/make_test_dist()> - Creates a temporary distribution
that is used for testing. This temporary distribution contains a C<./configure>
and a C<Makefile> that create no files, but can still be executed in the
standard AutoTools way.

=item L<Test::Fetchware/md5sum_file()> - Just md5sum's a file so verify() can be
tested.

=item L<Test::Fetchware/expected_filename_listing()> - Returns a string of crazy
Test::Deep subroutines to test filename listings. Not quite as useful as the
rest, but may come in handy if you're only changing the front part of lookup().

=back

Your tests should make use of fetchware's own C<FETHWARE_RELEASE_TESTING>
environment variable that controls with the help of
skip_all_unless_release_testing() if and where software is actually installed.
This is done, because everyone who installs fetchware or your fetchware
extension is really gonna freak out if its test suite installs apache or ctags
just to test its package manager functionality. To use it:

=over

=item 1. Set up an automated way of enabling FETCHWARE_RELEASE_TESTING.

Just paste the frt() bash shell function below. Translating this to your
favorite shell should be pretty straight forward. Do not just copy and paste it.
You'll need to customize the specific C<FETCHWARE_*> environment variables to
whatever mirrors you want to use or whatever actual programs you want to test
with. And you'll have to point the local (file://) urls to directories that
actually exist on your computer.

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
            export FETCHWARE_FTP_DOWNLOAD_URL='ftp://carroll.cac.psu.edu/pub/apache/httpd/httpd-2.2.26.tar.bz2'
            export FETCHWARE_HTTP_DOWNLOAD_URL='http://mirrors.ibiblio.org/apache//httpd/httpd-2.2.26.tar.bz2'
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
implementation to also be small and simple. It is mostly just two four
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

=head2 How do I configure a HTTP proxy for use with Fetchware?

Fetchware uses Perl's L<HTTP::Tiny> module to download files over HTTP. So, all
you need to do is configure HTTP::Tiny for use with proxies. This is done with
environment variables that can easily be set from your shell.

Set C<http_proxy> in the format C<http://host:port>. You can do this permanantly
for this session with:

    export http_proxy='http://example.com:8080'

Or once just for this invocation of fetchware:

    http_proxy='http://example.com:8080 fetchware new

See your OS's shell for more details regarding using and exporting environment
variables.

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

=cut

###BUGALERT### Actually implement croak or more likely confess() support!!!

##TODO##=head1 DIAGNOSTICS
##TODO##
##TODO##App::Fetchware throws many exceptions. These exceptions are not listed below,
##TODO##because I have not yet added additional information explaining them. This is
##TODO##because fetchware throws very verbose error messages that don't need extra
##TODO##explanation. This section is reserved for when I have to actually add further
##TODO##information regarding one of these exceptions.
##TODO##
##TODO##=cut


=head1 BUGS 

The official bug tracker for fetchware is its 
L<github issues page.|https://github.com/deeelwy/Fetchware/issues>

=cut


=head1 RESTRICTIONS 



=cut
