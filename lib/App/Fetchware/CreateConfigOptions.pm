package App::Fetchware::CreateConfigOptions;
# ABSTRACT: Used by fetchware extensions to create their configuration options.
use strict;
use warnings;

# CPAN modules making Fetchwarefile better.
use Sub::Mage;

# App::Fetchware::CreateConfigOptions uses _make_config_sub() from
# App::Fetchware, so I must use() it, so I can use it.
use App::Fetchware;

# Enable Perl 6 knockoffs, and use 5.10.1, because smartmatching and other
# things in 5.10 were changed in 5.10.1+.
use 5.010001;

# Don't use Exporter's import; instead, provide your own. This is all ExportAPI
# does. Provide an import() method, so that it can set up correct exports, and
# ensure that your fetchware extension implementes all of fetchware's API
# subroutines at compile time.

=head1 EXPORTAPI'S API METHODS

App::Fetchware::ExportAPI (ExportAPI) has only one user-servicable part--it's
import() method. It works just like L<Exporter>'s import() method except it
takes arguments differently, and checks it's arguments more thuroughly.

=cut

=head2 import()

    # You don't actually call import() unless you're doing something weird.
    # Instead, use calls import for you.
    use App::Fetchware::ExportAPI KEEP => [qw(start end)],
        OVERRIDE =>
            [qw(lookup download verify unarchive build install uninstall)];

    # But if you really do need to run import() itself.
    BEGIN {
        require App::Fetchware::ExportAPI;
        App::Fetchware::ExportAPI->import(KEEP => [qw(start end)],
            OVERRIDE =>
                [qw(lookup download verify unarchive build install uninstall)]
        );
    }

Adds fetchware's API subroutines (start(), lookup(), download(), verify(),
unarchive(), build(), install(), and uninstall()) to the caller()'s  @EXPORT.
Used by fetchware extensions to easily add fetchware's API subroutines to your
extension's package exports.

=cut

sub import {
    my ($class, @opts) = @_;
use Test::More;
note("CLASS[$class]OPTS[");
note explain \@opts;
note("]");
note("CALLER!!!![@{[scalar caller()]}]");

    # Just return success if user specified no options, because that just means
    # the user wanted to load the module, but not actually import() anything.
    return 'Success' if @opts == 0;

    my $caller = caller;

    # Forward call to _export_api(), which does all the work.
    # Note how the caller of import() is forwarded on to
    # _create_config_options().
    _create_config_options($caller, @opts);
}


=head2 _create_config_options()

    # _create_config_options() *must* be called in a BEGIN block, because it
    # creates subroutines that have prototypes, and prototypes *must* be known
    # about at compile time not run time!
    BEGIN { 
        _create_config_options(
            $callers_package,
            ONE => [qw(
                page_name
                html_page_url
                user_agent
                html_treebuilder_callback
                download_links_callback
            )],
            BOOLEAN => [qw(
                keep_destination_directory
            )],
            IMPORT => [qw(
                temp_dir
            )],
        );
    }

Creates configuration options of the same types App::Fetchware uses. These
are:

=over

=item 1. ONE - Stores one and only ever one value. If the configuration option
is used more than once, an exception is thrown.

=item 2. ONEARRREF - Stores one or more values. But only stores a list when
provided a list when you call it such as
C<install_commands './configure', 'make', 'make install'> would create a
configuration option with three values. However, if a ONEARRREF is called more
than once, and exception is also thrown.

=item 3. MANY - Stores many values one at a time just like ONEARRREF, but can
also be called any number of times, and  values are appended to any already
existing ones.

=item 4. BOOLEAN - Stores true or false values such as C<stay_root 'On'> or
C<verify_failure_ok 1> or C<no_install 'True'>

=back

In addition to App::Fetchware's types, _create_config_options() features an
additional type:

=over

=item 5. IMPORT - This option is documented only for completness, because it is
recommended that you use export_api(), and any App::Fetchware API subroutines
that you C<'KEEP'> export_api() will automatically call _create_config_options()
for you to import any fetchware API subroutines that you want your fetchware
extension to reuse. See L<export_api() for details. You can specify the
C<NOIMPORT> option, C<_create_config_options(..., NOIMPORT =E<gt> 1);>, to avoid
the automatic importing of App::Fetchware configuration options.

=back

Note: you must prepend your options with the $callers_package, which is the
package that you want the specified subroutines to be created in.

Just use any of C<ONE>, C<ONEARRREF>, C<MANY>, or C<BOOLEAN> as faux hash keys
being sure to wrap their arguments in a array reference brackets C<[]>

_create_config_options() also takes the faux hash key C<IMPORT> this hash key
does not create new configuration options, but instead imports already defined
ones from App::Fetchware allowing you to reuse popular configuration options
like C<temp_dir> or C<no_install> in your fetchware extension.

=over

=item LIMITATION

_create_config_options() creates subroutines that have prototypes, but in order
for perl to honor those prototypes perl B<must> know about them at compile-time;
therefore, that is why _create_config_options() must be called inside a C<BEGIN>
block.

=back

=cut

sub _create_config_options {
    my ($callers_package, %opts) = @_;

    # Delete any specified IMPORT config options if the user also specified the
    # NOIMPORT key.
    if (exists $opts{NOIMPORT} and defined $opts{NOIMPORT}) {
        # Also delete NOIMPORT, so it's not mistakenly looped through below.
        delete @opts{qw(IMPORT NOIMPORT)};
    }
use Test::More;
note explain \%opts;
    #if it works add error checking or c&p existing error checking!!!
    for my $value_key (keys %opts) {
        for my $sub_name (@{$opts{$value_key}}) {

use Test::More;
note("NAME[$sub_name]");
note("ONEORMANY[$value_key]");
note("CALLERSPACKAGE[$callers_package]");
        if ($value_key ne 'IMPORT') {
            App::Fetchware::_make_config_sub($sub_name, $value_key,
                $callers_package);
        } else {
            die <<EOD unless grep {$INC{$_} =~ /App.Fetchware/} keys %INC;
App-Fetchware-Util: App::Fetchware has not been loaded. How can you import a
subroutine from App::Fetchware if you have not yet loaded it yet? Please load
App::Fetchware [use App::Fetchware;] and try again.
EOD
            clone($sub_name => (from => 'App::Fetchware', to => $callers_package))
                or die <<EOD;
App-Fetchware-Util: Failed to clone the specified subroutine [$sub_name] from
App::Fetchware into your namespace [$callers_package]. You probably just need to
load fetchware [use App::Fetchware;] inside your fetchware extension.
EOD
        }

    # Be sure to @EXPORT the newly minted subroutine.
    _add_export($sub_name, $callers_package);



        }
    }
}


# Hide it's POD since it's an '_' hidden subroutine I don't want fetchware
# extensions to use.
#=head2 _add_export()
#
#    _add_export(start => caller);
#
#Adds the specified subroutine to the specified caller's @EXPORT variable, so
#that when the specified package is imported the specified subroutine is imported
#as well.
#
#=cut

sub _add_export {
    my ($sub_to_export, $caller) = @_;

    {
        no strict 'refs';

        # If the $caller has not declared @EXPORT for us, then we'll do it here
        # ourselves, so you don't need to declare a variable in your fetchware
        # extension that you never even use yourself.
        #
        #The crazy *{...} contraption looks up @$caller::EXPORT up in the stash,
        #and checks if it's defined in the stash, and if there's a stash entry,
        #then it has been defined, and if not, then the variable is undeclared,
        #so then delare it using the crazy eval.
        #
        #Also, note that use vars is used in favor of our, because our variables
        #are bizarrely lexically scoped, which is insane. Why would a global be
        #lexically scoped it's a global isn't it. But if you think that's
        #bizarre, check this out, use vars is file scoped. Again, how is a
        #global file scoped? Perhaps just the variable you declare with our or
        #use vars is lexical or file scoped, but the stash entry it creates
        #actually is global???
        unless (defined *{ $caller . '::EXPORT' }{ARRAY}) {
            my $eval = 'use vars @$caller::EXPORT; 1;';
            $eval =~ s/\$caller/$caller/;
            eval $eval or die <<EOD;
App-Fetchware-Util: Huh?!? For some reason fetchware failed to create the
necessary \@EXPORT variable in the specified caller's package [$caller]. This
just shouldn't happen, and is probably an internal bug in fetchware. Perhaps
the package specified in [$caller] has not been defined. Exception:
[$@]
EOD
        }
        
        # export *all* @api_subs.
        push @{"${caller}::EXPORT"}, $sub_to_export;
    }
}



1;
__END__

=head1 SYNOPSIS

    use App::Fetchware::ExportAPI KEEP => [qw(start end)],
        OVERRIDE =>
            [qw(lookup download verify unarchive build install uninstall)];

=cut

=head1 DESCRIPTION

App::Fetchware::ExportAPI is a utility helper class for fetchware extensions. It
makes it easy to ensure that your fetchware extension implements or imports all
of App::Fetchware's required API subroutines.

See section L<App::Fetchware/CREATING A FETCHWARE EXTENSION> in App::Fetchware's
documentation for more information on how to create your very own fetchware
extension.

=cut

=head1 ERRORS

As with the rest of App::Fetchware, App::Fetchware::ExportAPI does not return 
ny error codes; instead, all errors are die()'d if it's Test::Fetchware's error,
or croak()'d if its the caller's fault.

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
