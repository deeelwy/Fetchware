use strict;
use warnings;
package App::Fetchware;

# CPAN modules making Fetchwarefile better.
use File::Temp 'tempdir';
use File::Spec::Functions qw(catfile catdir splitpath updir splitdir
    file_name_is_absolute rel2abs);
use Path::Class;
use Data::Dumper;
use Net::FTP;
use HTTP::Tiny;
use File::Copy 'cp';
use HTML::TreeBuilder;
use Scalar::Util 'blessed';
###BUGALERT### Replace IPC::System::Simple with App::Cmd, because App::Cmd is one of
# Archive::Extract's dependencies, so I may as well use one of my dependencies'
# dependencies so App::Fetchware users have one fewer dependency to install.
use Digest::SHA;
use Digest::MD5;
#use Crypt::OpenPGP::KeyRing;
#use Crypt::OpenPGP;
use Archive::Extract;
use Archive::Tar;
use Sub::Override;
use Test::More 0.98; # some utility test subroutines need it.
use Perl::OSType 'is_os_type';
use Cwd;

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
    fetchware
    override
    config
);

# Forward declarations to make their prototypes work correctly.
sub msg (@);
sub vmsg (@);
sub run_prog ($;@);

# These tags go with the override() subroutine, and together allow you to
# replace some or all of fetchware's default behavior to install unusual
# software.
our %EXPORT_TAGS = (
    FETCHWARE => [qw(
        start
        lookup
        download
        verify
        unarchive
        build
        install
        end
        uninstall
    )],
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
        print_ok
        skip_all_unless_release_testing
        __clear_CONFIG
        debug_CONFIG
        config_replace
        config_delete
        make_clean
        make_test_dist
        md5sum_file
        start
        lookup
        download
        verify
        unarchive
        build
        install
        end
        uninstall
    )],
    UTIL => [qw(
        msg
        vmsg
        run_prog
        download_dirlist
        ftp_download_dirlist
        http_download_dirlist
        file_download_dirlist
        download_file
        download_ftp_url
        download_http_url
        download_file_url
        just_filename
    )],
);
# OVERRIDE_ALL is simply all other tags combined.
@{$EXPORT_TAGS{OVERRIDE_ALL}} = map {@{$_}} values %EXPORT_TAGS;
# *All* entries in @EXPORT_TAGS must also be in @EXPORT_OK.
our @EXPORT_OK = @{$EXPORT_TAGS{OVERRIDE_ALL}};



=head1 FETCHWAREFILE API SUBROUTINES

The subroutines below B<are> Fetchwarefile's API subroutines, but I<more
importantly> also Fetchwarefile's configuration file syntax See the SECTION
L<FETCHWAREFILE CONFIGURATION SYNTAX> for more information regarding using these
subroutines as Fetchwarefile configuration syntax.


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
subroutines fetchware itself uses to implement the lookup() step of
installation.  You can also use C<:OVERRIDE_ALL> to import all of the
subroutines fetchware uses to implement its behavior.  Feel free to specify a
list of the specifc subroutines that you need to avoid namespace polution, or
install and use L<Sub::Import> if you demand more control over imports.

=cut

=over

=item override LIST;

Used instead of C<fetchware;> to override fetchware's default behavior. This
should only be used if fetchware's configuration options do B<not> provide the
customization that your particular program may need.

The LIST your provide is a fake hash of steps you want to override as keys and
the coderefs to a replacement  those subroutines like:

=over
override lookup => \&overridden_lookup,
    download => sub { code refs work too; };
=back


=cut

sub override (@) {
    my %opts = @_;
    #diag("OVERRIDE");
    #$Data::Dumper::Deparse = 1; # Turn on deparsing coderefs.
    #diag explain \%opts;

    # override the parts that need overriden as specified in %opts.

    # Then execute just like fetchware; does, but exchanging the default steps
    # with the overriden ones.

    die <<EOD if keys %opts == 0;
App-Fetchware: syntax error: you called override with no options. It must be
called with a fake hash of name => value, pairs where the names are the names of
the Fetchwarefile steps you would like to override, and the values are a coderef
to a subroutine that implements that steps behavior. See perldoc App::Fetchware.
EOD


    my $override = Sub::Override->new();

    for my $sub (keys %opts) {
        die <<EOD unless grep { $_ eq $sub } @EXPORT_OK;
App-Fetchware: run-time error. override was called specifying a subroutine to
override that it is not allowed to override. override is only allowed to
override App::Fetchware's *own* routines as listed in [@EXPORT_OK].
See perldoc App::Fetchware.
EOD
        $override->replace("App::Fetchware::$sub", $opts{$sub});
    }
    #diag("Did I override them?");
    #diag explain $override;

    # Call fetchware after overriding what ever subs that need overridden.
    ###BUGALERT### Must rewrite ALL override() support!!!!!!!!!!!
    #fetchware;

    # When $override falls out of scope at the end of 

    # Return success.
    return 'overrode specified subs and executed them';
}

# End over CUSTOMIZING YOUR FETCHWAREFILE.

=back

=cut




BEGIN { # BEGIN BLOCK due to api subs needing prototypes.


{ # Containing bare block for %CONFIG
    my %CONFIG;
    
=item config($config_sub_name, $config_sub_value);

config() stores all of the configuration options that are parsed (actually
executed) in your Fetchwarefile. They are stored in the %CONFIG variable that is
lexically only shared with the private __clear_CONFIG() subroutine, which when
executed simply clears %CONFIG for the next run of App::Fetchware in
bin/fetchware's upgrade_all() subroutine, which is the only place multiple
Fetchwarefiles may be parsed in on execution of bin/fetchware.

If config() is given more than 2 args, then the second arg, and all of the other
arguments are stored in %CONFIG as an C<ARRAY> ref. Also storing a second
argument where there was a previously defined() argument will cause that
element of %CONFIG to be promoted to being an C<ARRAY> ref.

=cut

    sub config {
        my ($config_sub_name, $config_sub_value) = @_;

        ###BUGALERT### Does *not* support ONEARRREFs!!!!!! Which are actually
        #needed.
        # Only one argument just lookup and return it.
        if (@_ == 1) {
            ref $CONFIG{$config_sub_name} eq 'ARRAY'
            ? return @{$CONFIG{$config_sub_name}}
            : return $CONFIG{$config_sub_name};
        # More than one argument store the provided values in %CONFIG.
        # If more than one argument then the rest will be store in an ARRAY ref.
        } elsif (@_ > 1) {
            if (ref $CONFIG{$config_sub_name} eq 'ARRAY') {
                # If config() is provided with more than 2 args, then the second
                # arg ($config_sub_value) and the third to $#_ args are also
                # added to %CONFIG.
                if (@_ > 2) {
                    push @{$CONFIG{$config_sub_name}}, $config_sub_value, @_[2..$#_]
                } else {
                    push @{$CONFIG{$config_sub_name}}, $config_sub_value;
                }
            } else {
                # If there is already a value in that %CONFIG entry then turn it
                # into an ARRAY ref.
                if (defined($CONFIG{$config_sub_name})) {
                    $CONFIG{$config_sub_name}
                        =
                        [$CONFIG{$config_sub_name}, $config_sub_value];
                } else {
                    $CONFIG{$config_sub_name} = $config_sub_value;
                }
            }
        }
    }



=item config_replace($name, $value);

Replaces $name with $value. If C<scalar @_> > 2, then config_replace() will
replace $name with $value, and @_[2..$#_].

=cut

    sub config_replace {
        my ($config_sub_name, $config_sub_value) = @_;

        if (@_ == 1) {
            die <<EOD;
App::Fetchware: run-time error. config_replace() was called with only one
argument, but it requres two arguments. Please add the other option. Please see
perldoc App::Fetchware.
EOD
        } elsif (@_ == 2) {
            $CONFIG{$config_sub_name} = $config_sub_value;
        } elsif (@_ > 2) {
            $CONFIG{$config_sub_name} = [$config_sub_value, @_[2..$#_]];
        }
    }



=item config_delete($name);

delete's $name from %CONFIG.

=cut

    sub config_delete {
        my $config_sub_name = shift;

        delete $CONFIG{$config_sub_name};
    }


=item __clear_CONFIG();

Clears the %CONFIG variable that is shared between this subroutine and config().

=cut

    sub __clear_CONFIG {
        %CONFIG = ();
    }


=item debug_CONFIG();

Data::Dumper::Dumper()'s %CONFIG and prints it.

=cut

    sub debug_CONFIG {
        print Dumper(\%CONFIG);
    }

} # Ending bare block for %CONFIG


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
        ###BUGALERT### ONEARREF isn't documented, and may not be needed.
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
                eval $eval or die <<EOD;
1App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [$@]. See perldoc App::Fetchware.
EOD
###BUGALERT### *_commands actually need 'ONEARRREF' to support having multiple
#build commands on one line such as:
# build_commands './configure', 'make';
# The eval created below doesn't actually create them properly.
# Also, add config_* subs to access them easily such as config_push, config_pop,
# config_iter, or whatever makes sense.
# Then update build, install, and uninstall to use them properly when accessing
# *_commands config options.
            } when('ONEARRREF') {
                ###BUGALERT### the (@) sub prototype needed for ditching parens must
                #be seen at compile time. Is "eval time" considered compile time?
                my $eval = <<'EOE'; 
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
                eval $eval or die <<EOD;
2App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [$@]. See perldoc App::Fetchware.
EOD
            }
            when('MANY') {
                my $eval = <<'EOE';
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
                eval $eval or die <<EOD;
3App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [\$@]. See perldoc App::Fetchware.
EOD
            } when('BOOLEAN') {
                my $eval = <<'EOE';
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
                eval $eval or die <<EOD;
4App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [\$@]. See perldoc App::Fetchware.
EOD
            }
        }
    }


} # End BEGIN BLOCK.


# $original_cwd is a globalish lexical variable that stores fetchware's original
# working directory for later use if its needed.
my $original_cwd;

=item start()

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

sub start {
    my %opts = @_;

    msg 'Creating temp dir to use to install your package.';

    # Ask for better security.
    File::Temp->safe_level( File::Temp::HIGH );

    # Create the temp dir in the portable locations as returned by
    # File::Spec->tempdir() using the specified template (the weird $$ is this
    # processes process id), and cleaning up at program exit.
    my $exception;
    my $temp_dir;
    eval {
        unless (defined $opts{KeepTempDir}) {
            $temp_dir = tempdir("fetchware-$$-XXXXXXXXXX", TMPDIR => 1, CLEANUP => 1);

            vmsg "Created temp dir [$temp_dir] that will be deleted on exit";
        } else {
            $temp_dir = tempdir("fetchware-$$-XXXXXXXXXX", TMPDIR => 1);

            vmsg "Created temp dir [$temp_dir] that will be kept on exit";

        }

        # Must chown 700 so gpg's localized keyfiles are good.
        chown 0700, $temp_dir;

        use Test::More;
        diag("tempdir[$temp_dir]");
        $exception = $@;
        1; # return true unless an exception is thrown.
    } or die <<EOD;
App-Fetchware: run-time error. Fetchware tried to use File::Temp's tempdir()
subroutine to create a temporary file, but tempdir() threw an exception. That
exception was [$exception]. See perldoc App::Fetchware.
EOD

    vmsg "Saving original working directory as [$original_cwd]";
    $original_cwd = cwd();
    diag("cwd[@{[$original_cwd]}]");
    # Change directory to $CONFIG{TempDir} to make unarchiving and building happen
    # in a temporary directory, and to allow for multiple concurrent fetchware
    # runs at the same time.
    chdir $temp_dir or die <<EOD;
App-Fetchware: run-time error. Fetchware failed to change its directory to the
temporary directory that it successfully created. This just shouldn't happen,
and is weird, and may be a bug. See perldoc App::Fetchware.
EOD
    diag("cwd[@{[cwd()]}]");
    vmsg "Successfully changed working directory to [$temp_dir].";

    msg "Temporary directory created [$temp_dir]";
    return $temp_dir;
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

sub lookup {
    msg "Looking up download url using lookup_url [@{[config('lookup_url')]}]";

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


=item get_directory_listing()

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


=item parse_directory_listing($directory_listing);

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


=item determine_download_url($filename_listing)

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




=item file_parse_filelist

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


=item lookup_by_timestamp($filename_listing)

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


=item lookup_by_versionstring($filename_listing)

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



=item download($download_url)

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

sub download {
    my ($temp_dir, $download_url) = @_;

    msg "Downloading from url [$download_url] to temp dir [$temp_dir]";

    my $downloaded_file_path = download_file($download_url);
    vmsg "Downloaded file to [$downloaded_file_path]";

    my $package_path = determine_package_path($temp_dir, $downloaded_file_path);
    msg "Determined package path to be [$package_path]";

    return $package_path;
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



=item verify($download_url, $package_path)

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

sub verify {
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


=item gpg_verify($download_url);

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


=item sha1_verify($download_url, $package_path);

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


=item md5_verify($download_url, $package_path);

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


=item digest_verify($digest_type, $download_url, $package_path);

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
        my $lookuped_download_url = lookup();
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



=item unarchive($package_path)

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

sub unarchive {
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



=item build($build_path)

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

sub build {
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
        ###BUGALERT### May not actually work due to ONEARRREF not being
        #implemented.
        for my $build_command (config('build_commands')) {
            # Dequote build_commands they just get in the way.
            my $dequoted_commands = $build_command;
            $dequoted_commands =~ s/'|"//g;
            # split build_commands on ,\s+ and execute them.
            my @build_commands = split /,\s+/, $dequoted_commands;
            ###BUGALERT### Add vmsg()s after ONEARRREF is implemented.
            #vmsg '

            for my $build_command (@build_commands) {
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
            my @make_options;
            # Support multiple options like make_options '-j', '4';
            ###BUGALERT### Not actually implemented correctly!!!
            for my $make_option (config('make_options')) {
                push @make_options, $make_option;
            }
            vmsg 'Executing make to build your package';
            run_prog('make', @make_options)
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


=item run_configure()

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


=item install()

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

sub install {
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
        ###BUGALERT### Support ONEARRREF's!!!
        for my $install_command (config('install_commands')) {
            # Dequote install_commands they just get in the way.
            my $dequoted_commands = $install_command;
            $dequoted_commands =~ s/'|"//g;
            # split install_commands on /,\s+/ and execute them.
            my @install_commands = split /,\s+/, $dequoted_commands;

            for my $install_command (@install_commands) {
                ###BUGALERT### Add a vmsg() after ONEARRREF works.
                #vmsg '
                my ($cmd, @options) = split ' ', $install_command;
                run_prog($cmd, @options);
            }
        }
    } else {
        if (defined config('make_options')) {
            vmsg <<EOM;
Installing package using default command [make] with user specified make options.
EOM
            ###BUGALERT### Will with work with ONEARRREF????
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





=item uninstall($build_path)

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
sub uninstall {
    my $build_path = shift;

    msg "Uninstalling package unarchived at path [$build_path]";

    # chdir to $build_path so make will find the correct make file!.
    ###BUGALERT### Refactor our chdir to its own subroutine that cmd_install and
    #uninstall can share.
    chdir $build_path or die <<EOD;
fetchware: Failed to uninstall the specified package and specifically to change
working directory to [$build_path] before running make uninstall or the
uninstall_commands provided in this package's Fetchwarefile. Os error [$!].
EOD
    vmsg "chdir()d to build path [$build_path].";



    if (defined config('uninstall_commands')) {
        vmsg 'Uninstalling using user specified uninstall commands.';
        # Support multiple options like install_commands 'make', 'install';
        ###BUGALERT### Doesn't actually work yet!!!!! Implement ONEARRREF!!!
        for my $uninstall_command (config('uninstall_commands')) {
            # Dequote uninstall_commands they just get in the way.
            my $dequoted_commands = $uninstall_command;
            $dequoted_commands =~ s/'|"//g;
            # split uninstall_commands on /,\s+/ and execute them.
            my @uninstall_commands = split /,\s+/, $dequoted_commands;
            ###BUGALERT### Add proper vmsg() crap after you implement the
            #ONEARRREF support.

            for my $uninstall_command (@uninstall_commands) {
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
            ###BUGALERT### make_options should go befoer e install!!!
            vmsg <<EOM;
Running AutoTool's default make uninstall with user specified make options.
EOM
            run_prog('make', 'uninstall', config('make_options'));
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





# new hooks here!









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

It also calls the very internal only __clear_CONFIG() subroutine that clears
App::Fetchware's internal %CONFIG variable used to hold your parsed
Fetchwarefile. 

###BUGALERT### Just take %CONFIG OO!!! App::Fetchware::Config!!! Problem solved.

=cut

sub end {
    msg 'Cleaning up temporary directory temporary directory.';
    # chdir to $original_cwd directory, so File::Temp can delete the tempdir. This
    # is necessary, because operating systems do not allow you to delete a
    # directory that a running program has as its cwd.

    vmsg 'Changing directory to [$original_cwd].';
    chdir($original_cwd) or die <<EOD;
App-Fetchware: run-time error. Fetchware failed to chdir() to [$original_cwd]. See
perldoc App::Fetchware.
EOD

    # Call File::Temp's cleanup subrouttine to delete fetchware's temp
    # directory.
    ###BUGALERT### Below doesn't seem to work!!
    vmsg 'Cleaning up temporary directory.';
    File::Temp::cleanup();
    ###BUGALERT### Should end() clear %CONFIG for next invocation of App::Fetchware
    # Clear %CONFIG for next run of App::Fetchware.
    # Is this a design defect? It's a pretty lame hack! Does my() do this for
    # me?
    ###BUGALERT###YYYYYYEEEEEEEEEESSSSSSSSSSSS!!!! It probbly should. It would
    #remove many calls to __clear_CONFIG() from the test suite.
###BUGALERT### Just take %CONFIG OO!!! App::Fetchware::Config!!! Problem solved.
    vmsg 'Clearing internal %CONFIG variable that hold your parsed Fetchwarefile.';
    __clear_CONFIG();

    msg 'Cleaned up temporary directory.';
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


=item print_ok(\&printer, $expected, $test_name)

Tests if $expected is in the output that C<\&printer->()> produces on C<STDOUT>.

It passes $test_name along to the underlying L<Test::More> function that it uses
to do the test.

$expected can be a C<SCALAR>, C<Regexp>, or C<CODEREF> as returned by Perl's
L<ref()> function.

=over
=item * If $expected is a SCALAR according to ref()
=over
=item * Then Use eq to determine if the test passes.
=back
=item * If $expected is a Regexp according to ref()
=over
=item * Then use a regex comparision just like Test::More's like() function.
=back
=item * If $expected is a CODEREF according to ref()
=over
=item * Then execute the coderef and use the result of that expression to determine if the test passed or failed .
=back
=back

=over
NOTICE: C<print_ok()'s> manipuation of STDOUT only works for the current Perl
process. STDOUT may be inherited by forks, but for some reason my knowledge of
Perl and Unix lacks a better explanation other than that print_ok() does not
work for testing what C<fork()ed> and C<exec()ed> processes do such as those
executed with run_prog().

I also have not tested other possibilities, such as using IO::Handle to
manipulate STDOUT, or tie()ing STDOUT like Test::Output does. These methods
probably would not survive a fork() and an exec() though either.
=back

=cut

###BUGALERT### Some code like in t/bin-fetchware-upgrade(-all)?.t uses copy and
#pasted code that this function is based on. Replace that crap with print_ok().
####BUGALERT## Add tests for it!!!!!!!!!!!!!!!!
sub print_ok {
    my ($printer, $expected, $test_name) = @_;

    my $error;
    my $stdout;
    # Use eval to catch errors that $printer->() could possibly throw.
    eval {
        local *STDOUT;
        # Turn on Autoflush mode, so each time print is called it causes perl to
        # flush STDOUT's buffer. Otherwise a write could happen, that may not
        # actually get written before this eval closes, causing $stdout to stay
        # undef instead of getting whatever was written to STDOUT.
        $| = 1;
        open STDOUT, '>', \$stdout
            or $error = 'Can\'t open STDOUT to test cmd_upgrade using cmd_list';

        # Execute $printer
        $printer->();

        close STDOUT
            or $error = 'WTF! closing STDOUT actually failed! Huh?';
    };
    $error = $@ if $@;
    fail($error) if defined $error;

    if (ref($expected) eq undef) {
        is($stdout, $expected,
            $test_name);
    } elsif (ref($expected) eq 'Regexp') {
        like($stdout, $expected,
            $test_name);
    } elsif (ref($expected) eq 'CODEREF') {
        ok($expected->(),
            $test_name);
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


=item make_clean

Runs C<make clean> and then chdirs to the parent directory. This subroutine is
used in build() and install()'s test scripts to run make clean in between test
runs. If you override build() or install() you may wish to use make_clean to
automate this for you.

=cut

sub make_clean {
    system('make', 'clean');
    chdir(updir()) or fail(q{Can't chdir(updir())!});
}



=item make_test_dist($file_name, $ver_num, rel2abs($destination_directory));

Makes a C<$filename-$ver_num.fpkg> fetchware package that can be used for
testing fetchware's functionality without actually installing anything. All of
the tests in the t/ directory use this, while all of the tests in the xt/
directory use real programs like apache and ctags to test fetchware's
functionality.

Reuses start() to create a temp directory that is used to put the test-dist's
files in. Then an archive is created based on $original_cwd or
$destination_directory if provided, which is the current working directory
before you call make_test_dist(). After the archive is created in $original_cwd,
make_test_dist() deletes the $temp_dir using end().

If $destination_directory is not provided as an argument, then make_test_dist()
will just use cwd(), your current working directory.

Returns the full path to the created test-dist fetchwware package.

=cut

sub make_test_dist {
    my $file_name = shift;
    my $ver_num = shift;
    my $destination_directory;
    if ($destination_directory = shift) {
        $destination_directory = rel2abs($destination_directory);

    } else {
        $destination_directory = $original_cwd;
    }

    # Create a temp dir to create or test-dist-1.$ver_num directory in.
    my $temp_dir = start();

    # Append $ver_num to $file_name to complete the dist's name.
    my $dist_name = "$file_name-$ver_num";

diag("dist_name[$dist_name]");
    mkdir($dist_name) or die <<EOD;
fetchware: Run-time error. Fetchware failed to create the directory
[$dist_name] in the current directory of [$temp_dir]. The OS error was
[$!].
EOD
    my $configure_path = catfile($dist_name, 'configure');
    my %test_dist_files = (
        './Fetchwarefile' => <<EOF
# $file_name is a fake "test distribution" mean for testing fetchware's basic installing, upgrading, and
# so on functionality.
use App::Fetchware;

program '$file_name';

# Need to filter out the cruft.
filter '$file_name';

lookup_url 'file://t';
EOF
        ,

        $configure_path => <<EOF 
#!/bin/sh

# A Test ./configure file for testing Fetchware's install, upgrade, and so on
# functionality.

echo "fetchware: ./configure ran successfully!"
EOF
        ,
        catfile($dist_name, 'Makefile') => <<EOF 
# Makefile for test-dist, which is a "test distribution" for testing Fetchware's
# install, upgrade, and so on functionality.

all:
	sh -c 'echo "fetchware: make ran successfully!"'

install:
	sh -c 'echo "fetchware: make install ran successfully!"'

uninstall:
	sh -c 'echo "fetchware: make uninstall ran successfully!"'

build-package:
	sh -c 'echo "Build package and creating md5sum."'

	sh -c '(cd .. && tar --create --gzip --verbose --file test-dist-1.00.fpkg  ./Fetchwarefile test-dist-1.00)'

	sh -c '(cd .. && md5sum test-dist-1.00.fpkg > test-dist-1.00.fpkg.md5)'

	sh -c 'echo "Build package and creating md5sum for upgrade version."'

	sh -c 'cp -R ../test-dist-1.00 ../test-dist-1.01'

	sh -c '(cd .. && tar --create --gzip --verbose --file test-dist-1.00/test-dist-1.01.fpkg  ./Fetchwarefile test-dist-1.01)'

	sh -c 'rm -r ../test-dist-1.01'

	sh -c 'md5sum test-dist-1.01.fpkg > test-dist-1.01.fpkg.md5'
EOF
        ,
    );

    for my $file_to_create (keys %test_dist_files) {
        open(my $fh, '>', $file_to_create) or die <<EOD;
fetchware: Run-time error. Fetchware failed to open
[$file_to_create] for writing to create the Configure script that
test-dist needs to work properly. The OS error was [$!].
EOD
        print $fh $test_dist_files{$file_to_create};
        close $fh;
    }

    # chmod() ./configure, so it can be executed.
    chmod(0755, $configure_path) or die <<EOC;
fetchware: run-time error. fetchware failed to chmod [$configure_path] to add
execute permissions, which ./configure needs. Os error [$!].
EOC

    my $test_dist_filename = catfile($destination_directory, "$dist_name.fpkg");
diag("test_dist_filename[$test_dist_filename]");

    # Create a tar archive of all of the files needed for test-dist.
    Archive::Tar->create_archive($test_dist_filename, COMPRESS_GZIP,
        keys %test_dist_files) or die <<EOD;
fetchware: Run-time error. Fetchware failed to create the test-dist archive for
testing [$test_dist_filename] The error was [@{[Archive::Tar->error()]}].
EOD

    # Cd back to $original_cwd and delete $temp_dir.
    end();

    return rel2abs($test_dist_filename);
}

=item md5sum_file($archive_to_md5)

Uses Digest::MD5 to generate a md5sum just like the md5sum program does, and
instead of returning the output it returns the full path to a file containing
the md5sum called C<"$archive_to_md5.md5">.

=cut

sub md5sum_file {
    my $archive_to_md5 = shift;

    open(my $package_fh, '<', $archive_to_md5)
        or die <<EOD;
App-Fetchware: run-time error. Fetchware failed to open the file it downloaded
while trying to read it in order to check its MD5 sum. The file was
[$archive_to_md5]. See perldoc App::Fetchware.
EOD

    my $digest = Digest::MD5->new();

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
App-Fetchware: run-time error. Digest::MD5 croak()ed an error [$@].
See perldoc App::Fetchware.
EOD
    }

    close $package_fh or die <<EOD;
App-Fetchware: run-time error Fetchware failed to close the file
[$archive_to_md5] after opening it for reading. See perldoc App::Fetchware.
EOD
    
    my $md5sum_file = rel2abs($archive_to_md5);
    $md5sum_file = "$md5sum_file.md5";
    open(my $md5_fh, '>', $md5sum_file) or die <<EOD;
fetchware: run-time error. Failed to open [$md5sum_file] while calculating a
md5sum. Os error [$!].
EOD

    print $md5_fh "$calculated_digest  @{[file($archive_to_md5)->basename()]}";

    close $md5_fh or die <<EOD;
App-Fetchware: run-time error Fetchware failed to close the file
[$md5sum_file] after opening it for reading. See perldoc App::Fetchware.
EOD

    return $md5sum_file;
}

=item Standards for using msg() and vmsg()

msg() should be used to describe the main events that happen, while vmsg()
should be used to describe what all of the main subroutine calls do.

For example, cmd_uninstall() has a msg() at the beginning and at the end, and so
do the main App::Fetchware subroutines that it uses such as start(), download(),
unarchive(), end() and so on. They both use vmsg() to add more detailed messages
about the particular even "internal" things they do.

msg() and vmsg() are also used without parens due to their appropriate
prototypes. This makes them stand out from regular old subroutine calls more.

=cut

=item msg('message to print to STDOUT');

msg() simply takes a list of scalars, and it prints them to STDOUT according to
any verbose (-v), or quiet (-q) options that the user may have provided to
fetchware.

msg() will still print its arguments if the user provided a -v (verbose)
argument, but it will B<not> print its argument if the user provided a -q (quiet)
command line option.

=over
=item This subroutine makes use of prototypes, so that you can avoid using parentheses around its args to make it stand out more in code.
=back

=cut

sub msg (@) {

    # If fetchware was not run in quiet mode, -q.
    unless ($fetchware::quiet > 0) {
        # print are arguments. Use say if the last one doesn't end with a
        # newline. $#_ is the last subscript of the @_ variable.
        if ($_[$#_] =~ /\w*\n\w*\z/) {
            print @_;
        } else {
            say @_;
        }
    # Quiet mode is turned on.
    } else {
        # Don't print anything.
        return;
    }
}


=item vmsg('message to print to STDOUT');

vmsg() simply takes a list of scalars, and it prints them to STDOUT according to
any verbose (-v), or quiet (-q) options that the user may have provided to
fetchware.

vmsg() will B<only> print its arguments if the user provided a -v (verbose)
argument, but it will B<not> print its argument if the user provided a -q (quiet)
command line option.

=over
=item This subroutine makes use of prototypes, so that you can avoid using parentheses around its args to make it stand out more in code.
=back

=cut

sub vmsg (@) {

    # If fetchware was not run in quiet mode, -q.
    ###BUGALERT### Can I do something like:
    #eval "use constant quiet => 0;" so that the iffs below can be resolved at
    #run-time to make vmsg() and msg() faster???
    unless ($fetchware::quiet > 0) {
        # If verbose is also turned on.
        if ($fetchware::verbose > 0) {
            # print our arguments. Use say if the last one doesn't end with a
            # newline. $#_ is the last subscript of the @_ variable.
            if ($_[$#_] =~ /\w*\n\w*\z/) {
                print @_;
            } else {
                say @_;
            }
        }
    # Quiet mode is turned on.
    } else {
        # Don't print anything.
        return;
    }
}


=item run_prog($program, @args);

run_prog() uses L<system> to execute the program for you. Only the secure way of
avoiding the shell is used, so you can not use any shell redirection or any
shell builtins.

If the user ran fetchware with -v (verbose) then run_prog() changes none of its
behavior it still just executes the program. However, if the user runs the
program with -q (quiet) specified, then the the command is run using a piped
open to capture the output of the program. This captured output is then ignored,
because the user asked to never be bothered with the output. This piped open
uses the safer shell avoiding syntax on systems with L<fork>, and systems
without L<fork>, Windows,  the older less safe syntax is used. Backticks are
avoided, because they always use the shell.

=over
=item This subroutine makes use of prototypes, so that you can avoid using parentheses around its args to make it stand out more in code.
=back

=cut

###BUGALERT### Add support for dry-run functionality!!!!
sub run_prog ($;@) {
    my ($program, @args) = @_;

    # If fetchware is run without -q.
    unless ($fetchware::quiet > 0) {
        system($program, @args) == 0 or die <<EOD;
fetchware: run-time error. Fetchware failed to execute the specified program
[$program] with the arguments [@args]. The OS error was [$!], and the return
value was [@{[$? >> 8]}]. Please see perldoc App::Fetchware::Diagnostics.
EOD
    # If fetchware is run with -q.
    } else {
        # Use a piped open() to capture STDOUT, so that STDOUT is not printed to
        # the terminal like it usually is therby "quiet"ing it.
        # If not on Windows use safer open call that doesn't work on Windows.
        unless (is_os_type('Windows', $^O)) {
            open(my $fh, '-|', "$program", @args) or die <<EOD;
fetchware: run-time error. Fetchware failed to execute the specified program
while capturing its input to prevent it from being copied to the screen, because
you ran fetchware with it's --quite or -q option. The program was [$program],
and its arguments were [@args]. OS error [$!], and exit value [$?]. Please see
perldoc App::Fetchware::Diagnostics.
EOD
            # Close $fh, to cause perl to wait for the command to do its
            # outputing to STDOUT.
            close $fh;
        # We're on Windows.
        } else {
            open(my $fh, '-|', "$program @args") or die <<EOD;
fetchware: run-time error. Fetchware failed to execute the specified program
while capturing its input to prevent it from being copied to the screen, because
you ran fetchware with it's --quite or -q option. The program was [$program],
and its arguments were [@args]. OS error [$!], and exit value [$?]. Please see
perldoc App::Fetchware::Diagnostics.
EOD
            # Close $fh, to cause perl to wait for the command to do its
            # outputing to STDOUT.
            close $fh;
        }
    }
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
        } when (m!^file://.*$!) {
          $dirlist = file_download_dirlist($url);
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


=item file_download_dirlist($local_lookup_url)

Glob's provided $local_lookup_url, and builds a directory listing of all files
in the provided directory. Then list_file_dirlist() returns a list of all of the
files in the current directory.

=over
=item SIDE EFFECTS
Does what ls or dir do, but natively inside perl, so I don't have to worry about
what OS I'm running on.
=back

=cut

sub file_download_dirlist {
    my $local_lookup_url = shift;

diag "before[$local_lookup_url]";
    $local_lookup_url =~ s!^file://!!; # Strip scheme garbage.
diag "after[$local_lookup_url]";

    # Prepend $original_cwd if $local_lookup_url is a relative path.
    unless (file_name_is_absolute($local_lookup_url)) {
diag "origcwd[$original_cwd]";
        $local_lookup_url =  catdir($original_cwd, $local_lookup_url);
    }

    my @file_listing;
    for my $file (glob catfile($local_lookup_url, '*')) {
diag "lfdfile[$file]";
        push @file_listing, $file;
    }
diag "lfd file_listing";
diag explain \@file_listing;
diag "end lfd file_listing";
    return \@file_listing;
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
        when (m!^ftp://!) {
            $filename = download_ftp_url($url);
        } when (m!^http://!) {
            $filename = download_http_url($url);
        } when (m!^file://!) {
            $filename = download_file_url($url);   
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

    # The caller needs the $filename to determine the $package_path later.
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

    # The caller needs the $filename to determine the $package_path later.
    diag("httpFILE[$filename]");
    return $filename;
}



=item download_file_url($url);

Uses File::Copy to copy ("download") the local file to the current working
directory.

=cut

sub download_file_url {
    my $url = shift;

    $url =~ s!^file://!!; # Strip useless URL scheme.
    
    # Prepend $original_cwd only if the $url is *not* absolute, which will mess
    # it up.
    $url = catdir($original_cwd, $url) unless file_name_is_absolute($url);

    # Download the file:// URL to the current directory, which should already be
    # in $temp_dir, because of start()'s chdir().
    cp($url, cwd()) or die <<EOD;
App::Fetchware: run-time error. Fetchware failed to copy the download URL
[$url] to the working directory [@{[cwd()]}]. Os error [$!].
EOD

    # Return just file filename of the downloaded file.
    return file($url)->basename();
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
