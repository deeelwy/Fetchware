use strict;
use warnings;
package App::Fetchware;

# Enable Perl 6 knockoffs.
use 5.010;

# Set up Exporter to bring App::Fetchware's API to everyone who use's it
# including fetchware's ability to let you rip into its guts, and customize it
# as you need.
use Exporter qw( import );
# By default fetchware exports its configuration file like subroutines and
# fetchware(). override() is exported only when one of the :OVERRIDE_* export
# tags is also specified.
#
# These days it's considered bad to import stuff without be asked to do so, but
# App::Fetchware is meant to be a configuration file that is both human
# readable, and most importantly flexible enough to allow customization. This is
# done by making the configuration file a perl source code file called a
# Fetchwarefile that fetchware simply executes. The magic is in the fetchware()
# and override() subroutines.
our @EXPORT = qw(
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
    verify_method
    no_install
    verify_failure_ok
    mirror
    fetchware
);
# *All* @EXPORT_TAGS must also be @EXPORT_OK, or else they can't be exported.
our @EXPORT_OK = qw(
    OVERRIDE_LOOKUP
    OVERRIDE_DOWNLOAD
    OVERRIDE_VERIFY
    OVERRIDE_UNARCHIVE
    OVERRIDE_BUILD
    OVERRIDE_INSTALL
    OVERRIDE_ALL
);
# These tags go with the override() subroutine, and together allow you to
# replace some or all of fetchware's default behavior to install unusual
# software.
our @EXPORT_TAGS = (
    OVERRIDE_LOOKUP => qw(),
    OVERRIDE_DOWNLOAD => qw(),
    OVERRIDE_VERIFY => qw(),
    OVERRIDE_UNARCHIVE => qw(),
    OVERRIDE_BUILD => qw(),
    OVERRIDE_INSTALL => qw(),
    OVERRIDE_ALL => qw(), # list *all* subs that are in any OVERRIDE_* tag.
);

###BUGALERT### I may need to forward declare the subs make_config_sub()'s
#generates.
#sub fetchware (@);

# Hash of configuration variables Fetchwarefiles may use to configure
# fetchware's default behavior using a simple obvious Moose-like declarative
# syntax such as configure_prefix '/usr/local'; to make Fetchwarefile's, which
# are straight up perl .pl files without the extension.
my %FW;
# Give fetchware's test suite access to an otherwise private variable. Note the
# double underscores, which make it *extra* private instead of just private.
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
skip the part where it installs your programs. At exit it will print out
information regarding where your programs are, so that you can install them
yourself.

If you set verify_failure_ok to true, its default is false too, then fetchware
will print a warning if fetchware fails to verify the gpg signature instead of
die()ing printing an error message.

=item fetchware;

C<fetchware> is the subroutine that actually causes the Fetchwarefile to
execute fetchware's B<default, bult-in functionality>. If it is left out, then
the Fetchwarefile is incomplete, and will not actually do anything. The only
time to leave C<fetchware> out of a Fetchwarefile is if you want to customize
fetchware's behavior using App::Fetchware's API.

This API isn't written yet, but will probably just be subroutines that you'll
have to ask to import like C<use App::Fetchware :customize;>, and the
customization subroutines will be imported.

It's not fancy on purpose, because it is meant to be dead simple, and easy to
implement and pragmatic.  

###BUGALERT### Actually implement App::Fetchware's API.  Design it!!!

See L<CUSTOMIZING YOUR FETCHWAREFILE> below for fetchware implementation
details, and how you can extend fetchware or change its behavior to suit unusual
program installations.

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

my @api_functions = (
    [ temp_dir => 'ONE' ],
    [ user => 'ONE' ],
    [ prefix => 'ONE' ],
    [ configure_options=> 'ONE' ],
    [ make_options => 'ONE' ],
    [ build_commands => 'ONE' ],
    [ install_commands => 'ONE' ],
    [ lookup_url => 'ONE' ],
    [ lookup_method => 'ONE' ],
    [ gpg_key_url => 'ONE' ],
    [ verify_method => 'ONE' ],
    [ mirror => 'MANY' ],
    [ no_install => 'BOOLEAN' ],
    [ verify_failure_ok => 'BOOLEAN' ],
);


# Loop over the list of options needed by make_config_sub() to generated the
# needed API functions for Fetchwarefile.
###BUGALERT### Does this need to be done in a BEGIN block?
for my $api_function (@api_functions) {
    make_config_sub(@{$api_function});
}


=head1 INTERNAL SUBROUTINES

=over

=item make_config_sub($name, $one_or_many_values)

A function factory that builds many functions that are the exact same, but have
different names. It supports two types of functions determined by
make_config_sub()'s second parameter.  It's first parameter is the function it
creates name.

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
make_config_sub() except for fetchware().

=cut

sub make_config_sub {
    my ($name, $one_or_many_values) = @_;

    die <<EOD unless defined $name;
App-Fetchware: internal syntax error: make_config_sub() was called without a
name. It must receive a name parameter as its first paramter. See perldoc
App::Fetchware.
EOD
    use Test::More;
    unless ($one_or_many_values eq 'ONE'
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
sub $name ($) {
###BUGALERT### DEBUG WEIRD BACKSLASH ESCAPTING!!!!!
    my $value = shift;
    
    die <<EOD if defined $FW{$name};
App-Fetchware: internal syntax error: $name was called more than once in this
Fetchwarefile. Currently only mirror supports being used more than once in a
Fetchwarefile, but you have used $name more than once. Please remove all calls
to $name but one. See perldoc App::Fetchware.
EOD
    $FW{$name} = $value;
}
1; # return true from eval
EOE
            $eval =~ s/\$name/$name/g;
            eval $eval or die <<EOD;
App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [$@]. See perldoc App::Fetchware.
EOD
        } when('MANY') {
            my $eval = <<'EOE';
sub $name ($) {
    my $value = shift;

    if (defined $FW{$name} and ref $FW{$name} ne 'ARRAY') {
        die <<EOD;
App-Fetchware: internal operation error!!! $FW{$name} is *not* undef or an array
ref!!! This simply should never happen, but it did somehow. This is most likely
a bug, so please report it. Thanks. See perldoc App::Fetchware.
EOD
    }

    push @{$FW{$name}}, $value;
}
1; # return true from eval
EOE
            $eval =~ s/\$name/$name/g;
            eval $eval or die <<EOD;
App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [\$@]. See perldoc App::Fetchware.
EOD
        } when('BOOLEAN') {
            my $eval = <<'EOE';
sub $name ($) {
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
    $FW{$name} = $value;
}
1; # return true from eval
EOE
            $eval =~ s/\$name/$name/g;
            eval $eval or die <<EOD;
App-Fetchware: internal operational error: make_config_sub()'s internal eval()
call failed with the exception [\$@]. See perldoc App::Fetchware.
EOD
        }
    }
}






1;
