package App::Fetchware::Config;
# ABSTRACT: Manages App::Fetchware's internal representation of Fetchwarefiles.
###BUGALERT### Uses die instead of croak. croak is the preferred way of throwing
#exceptions in modules. croak says that the caller was the one who caused the
#error not the specific code that actually threw the error.
use strict;
use warnings;

# Enable Perl 6 knockoffs.
use 5.010;


# Set up Exporter to bring App::Fetchware's API to everyone who use's it
# including fetchware's ability to let you rip into its guts, and customize it
# as you need.
use Exporter qw( import );
# By default fetchware exports its configuration file like subroutines and
# fetchware().
#

# These tags go with the override() subroutine, and together allow you to
# replace some or all of fetchware's default behavior to install unusual
# software.
our %EXPORT_TAGS = (
    CONFIG => [qw(
        config
        config_replace
        config_delete
        __clear_CONFIG
        debug_CONFIG
    )],
);
# *All* entries in @EXPORT_TAGS must also be in @EXPORT_OK.
our @EXPORT_OK = map {@{$_}} values %EXPORT_TAGS;


# Fetchware's internal representation of your Fetchwarefile.
my %CONFIG;


=head2 config()

    $config_sub_value = config($config_sub_name, $config_sub_value);

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



=head2 config_replace()

    config_replace($name, $value);

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



=head2 config_delete()

    config_delete($name);

delete's $name from %CONFIG.

=cut

sub config_delete {
    my $config_sub_name = shift;

    delete $CONFIG{$config_sub_name};
}


=head2 __clear_CONFIG()

    __clear_CONFIG();

Clears the %CONFIG variable that is shared between this subroutine and config().

=cut

sub __clear_CONFIG {
    %CONFIG = ();
}


=head2 debug_CONFIG()

    debug_CONFIG();

Data::Dumper::Dumper()'s %CONFIG and prints it.

=cut

sub debug_CONFIG {
    print Dumper(\%CONFIG);
}



1;
