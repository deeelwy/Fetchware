package App::Fetchware::ExportAPI;
# ABSTRACT: Used by fetchware extensions to export their API subroutines.
use strict;
use warnings;

# CPAN modules making Fetchwarefile better.
use Sub::Mage;

# ExportAPI takes advantage of CreateConfigOption's _create_config_options() and
# _add_export() to do its dirty work.
use App::Fetchware::CreateConfigOptions ();
# _create_config_options() clone()'s some of App::Fetchware's API subroutines
# when a fetchware extension "KEEP"s them, so I must load it, so I can access
# these subroutines.
use App::Fetchware ();

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

It's import() method is what does the heavy lifting of actually importing any
"inherited" Fetchware API subroutines from App::Fetchware, and also setting up
the caller's exports, so that the caller also exports all of Fetchware's API
subroutines.

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
It also imports L<Exporter>'s import() subroutine to the caller's package, so
that the caller has a proper import() subroutine that Perl will use when someone
uses your fetchware extension in their fetchware extension. Used by fetchware
extensions to easily add fetchware's API subroutines to your extension's package
exports.

This is how fetchware extensions I<inherit> whatever API subroutines that they
want to reuse from App::Fetchware.

Normally, you don't actually call import(); instead, you call it implicity by
simply use()ing it.

=over

=item WARNING

_export_api() also imports Exporter's import() method into its
$callers_package_name. This is absolutely required, because when a user's
Fetchwarefile is parsed it is the C<use App::Fetchware::[extensionname];> line
that imports fetchware's API subrotines into fetchware's namespace so its
internals can call the correct fetchware extension. This mechanism simply uses
Exporter's import() method for the heavy lifting, so _export_api() B<must> also
ensure that its caller gets a proper import() method.

If no import() method is in your fetchware extension, then fetchware will fail
to parse any Fetchwarefile's that use your fetchware extension, but this error
is caught with an appropriate error message.

=back

=cut

sub import {
    my ($class, @opts) = @_;

    # Just return success if user specified no options, because that just means
    # the user wanted to load the module, but not actually import() anything.
    return 'Success' if @opts == 0;

    my $caller = caller;

    # Forward call to _export_api(), which does all the work.
    _export_api($caller, @opts);
}


# Make _export_api() "invisible." users should only ever actually use import(),
# and technically they should never even use import; instead, they should just
# use ExportAPI, and Perl will call import() for them.
#=head2 _export_api()
#
#    # Keep App::Fetchware's start() and end() API subroutines, but override the
#    # other ones.
#    _export_api(KEEP => [qw(start end)],
#        OVERRIDE =>
#        [qw(lookup download verify unarchive build install uninstall)]
#    );
#
#    # YOu can specify NOIMPORT => 1 to avoid the creation of any "KEEP"
#    # App::Fetchware configuration options.
#    _export_api(KEEP => [qw(start end)],
#        0VERRIDE =
#            [qw(lookup download verify unarchive build install uninstall)]
#        NOIMPORT => 1;
#    );
#
#
#Adds fetchware's API subroutines (start(), lookup(), download(), verify(),
#unarchive(), build(), install(), and uninstall()) to the caller()'s  @EXPORT.
#Used by fetchware extensions to easily add fetchware's API subroutines to your
#extension's package exports.
#
#=over
#
#=item WARNING
#
#_export_api() also imports Exporter's import() method into its
#$callers_package_name. This is absolutely required, because when a user's
#Fetchwarefile is parsed it is the C<use App::Fetchware::[extensionname];> line
#that imports fetchware's API subrotines into fetchware's namespace so its
#internals can call the correct fetchware extension. This mechanism simply uses
#Exporter's import() method for the heavy lifting, so _export_api() B<must> also
#ensure that its caller gets a proper import() method.
#
#If no import() method is in your fetchware extension, then fetchware will fail
#to parse any Fetchwarefile's that use your fetchware extension, but this error
#is caught with an appropriate error message.
#
#=back
#
#=cut

sub _export_api {
    my ($callers_package_name, %opts) = @_;

    # clone() Exporter's import() into $callers_package_name, because
    # fetchware extensions use Exporter's import() when fetchware eval()'s
    # Fetchwarefile's that use that extension. Exporter's import() is what makes
    # the magic happen.
    clone(import => (from => 'Exporter', to => $callers_package_name));

    my %api_subs = (
        start => 0,
        lookup => 0,
        download => 0,
        verify => 0,
        unarchive => 0,
        build => 0,
        install => 0,
        uninstall => 0,
        end => 0
    );

    # Check %opts for correctness.
    for my $sub_type (@opts{qw(KEEP OVERRIDE)}) {
        # Skip KEEP or OVERRIDE if it does not exist.
        next unless defined $sub_type;
        for my $sub (@{$sub_type}) {
            if (exists $api_subs{$sub}) {
                $api_subs{$sub}++;
            }
        }
    }
use Test::More;
note("CALLER[$callers_package_name]");
note("APISUBS[");
note explain \%api_subs;
note("]");
    die <<EOD if (grep {$api_subs{$_} == 1} keys %api_subs) != 9;
App-Fetchware-Util: export_api() must be called with either or both of the KEEP
and OVERRIDE options, and you must supply the names of all of fetchware's API
subroutines to either one of these 2 options.
EOD

    # Import any KEEP subs from App::Fetchware.
    for my $sub (@{$opts{KEEP}}) {
        clone($sub => ( from => 'App::Fetchware', to => $callers_package_name));

    }

    # Also import any subroutines the fetchware extension developer wants to
    # keep unless the fetchware extension developer does not want them.
    App::Fetchware::CreateConfigOptions::_create_config_options(
        $callers_package_name,
        IMPORT => $opts{KEEP})
            unless $opts{NOIMPORT};

    ###LIMITATION###You may want _export_api() and import() and ExportAPI to
    #check if all of the required fetchware extension API subroutines have been
    #implemented by our caller using something like
    #"$callers_package_name"->can($sub), but this can't work, because ExportAPI
    #is run inside an implied BEGIN block, from the use(), That means that the
    #rest of the file has *not* been compiled yet, so any subroutines defined
    #later on in the same file have not actually been compiled yet, so any use
    #of can() to lookup if they exist yet will fail, because they don't actually
    #exist yet. But if they have been properly defined, they will properly
    #exist.
    #
    #Therefore, I have moved checking if all of the proper API subroutines have
    #been defined properly to bin/fetchware's parse_fetchwarefile(), because
    #after the Fetchwarefile has been eval()'s the API subroutines should be in
    #bin/fetchware's namespace, so it just uses Sub::Mage's sublist() to see if
    #they all exist.


    # _create_config_options() takes care of setting up KEEP's exports, but
    # I need to ensure OVERRIDE's exports are also set up.
    App::Fetchware::CreateConfigOptions::_add_export(
        $_, $callers_package_name)
            for @{$opts{OVERRIDE}};
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
