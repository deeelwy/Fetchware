package App::Fetchware::Config;
# ABSTRACT: Manages App::Fetchware's internal representation of Fetchwarefiles.
###BUGALERT### Uses die instead of croak. croak is the preferred way of throwing
#exceptions in modules. croak says that the caller was the one who caused the
#error not the specific code that actually threw the error.
use strict;
use warnings;

# Enable Perl 6 knockoffs, and use 5.10.1, because smartmatching and other
# things in 5.10 were changed in 5.10.1+.
use 5.010001;

use Carp 'carp';
use Data::Dumper;


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
        config_iter
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


=head1 CONFIG SUBROUTINES


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
                push @{$CONFIG{$config_sub_name}}, $config_sub_value, @_[2..$#_];
            } else {
                push @{$CONFIG{$config_sub_name}}, $config_sub_value;
            }
        } else {
            # If there is already a value in that %CONFIG entry then turn it
            # into an ARRAY ref.
            if (defined($CONFIG{$config_sub_name})) {
                if (@_ > 2) {
                    $CONFIG{$config_sub_name}
                        =
                        [ $CONFIG{$config_sub_name}, @_[1..$#_] ];
                } else {
                    $CONFIG{$config_sub_name}
                        =
                        [$CONFIG{$config_sub_name}, $config_sub_value];
                }
            } else {
                if (@_ > 2) {
                    $CONFIG{$config_sub_name} = [ @_[1..$#_] ];
                } else {
                    $CONFIG{$config_sub_name} = $config_sub_value;
                }
            }
        }
    }
}


=head2 config_iter()

    # Create a config "iterator."
    my $mirror_iter = config_iter('mirror');

    # Use the iterator to return a new value of 'mirror' each time it is kicked,
    # called.
    my $mirror
    while (defined($mirror = $mirror_iter->())) {
        # Do something with this version of $mirror
        # Next iteration will "kick" the iterator again
    }

config_iter() returns an iterator. An iterator is simply a subroutine reference
that when called (ex: C<$mirror_iter-E<gt>()>) will return the next value. And
the coolest part is that the iterator will keep track of where it is in the list
of values that configuration option has itself, so you don't have to yourself.

Iterators returned from config_iter() will return one or more elements of the
configuration option that you specify has stored. After you exceed the length of
the internal array reference the iterator will return false (undef).

=cut

sub config_iter {
    my $config_sub_name = shift;

    my $iterator = 0;

    # Return the "iterator." Read MJD's kick ass HOP for more info about
    # iterators: http://hop.perl.plover.com/book/pdf/04Iterators.pdf
    return sub {

        if (ref $CONFIG{$config_sub_name} eq 'ARRAY') {
            # Return undef if $iterator is greater than the last element index
            # of the array ref.
            return if $iterator > $#{$CONFIG{$config_sub_name}};

            # Simply access whatever number the iterator is at now.
            my $retval = $CONFIG{$config_sub_name}->[$iterator];

            # Now increment $iterator so next call will access the next element
            # of the arrayref.
            $iterator++;

            # Return the $retval. This is done after $iterator is incremented,
            # so we access the current element instead of the next one.
            return $retval;

        # If $config_sub_name is not an ARRREF, then just return whatever its
        # one value is on the first call ($iterator == 0), and return undef for
        # every other call.
        } else {
            if ($iterator == 0) {
                $iterator++;
                return config($config_sub_name);
            } else {
                return;
            }
        }
    }
}


=head2 config_replace()

    config_replace($name, $value);

    # Supports multiple values and arrays too.
    config_replace($name, $val1, $val2, $val3);
    config_replace($name, @values);

Allows you to replace the $value of the specified ($name) existing element of
the %CONFIG internal hash. It supports multiple values and arrays, and will
store those multiple values or arrays with an arrayref.

=cut

sub config_replace {
    my ($config_sub_name, $config_sub_value) = @_;

    if (@_ < 2) {
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

Clears the %CONFIG globalish variable. Meant more for use in testing, then for
use in Fetchware itself, or in Fetchware extensions.

=cut

sub __clear_CONFIG {
    %CONFIG = ();
}


=head2 debug_CONFIG()

    debug_CONFIG();

Data::Dumper::Dumper()'s %CONFIG and prints it.

=cut

sub debug_CONFIG {
    ###BUGALERT### Should print be a note() to avoid polluting stdout when
    #testing??? But I don't really want to load Test::More, when I'm not
    #testing. So, I could move this to Test::Fetchware, but that does not have
    #access to %CONFIG.
    print Dumper(\%CONFIG);
}



1;
__END__

=head1 SYNOPSIS

    use App::Fetchware::Config ':CONFIG';

    my $some_config_sub_value = config('some_config_sub');
    $config_sub_value = config($config_sub_name, $config_sub_value);

    # You can also take advantage of config('config_sub_name') returning the
    # value if it exists or returning false if it does not to make ifs testing
    # if the value exists or not.
    if (config('config_sub_name')) {
        # config_sub_name exists in %CONFIG.
    } else {
        # config_sub_name does not exist in %CONFIG.
    }

    config_replace($name, $value);

    config_delete($name);

    __clear_CONFIG();

    debug_CONFIG();

=cut


=head1 DESCRIPTION

App::Fetchware::Config maintains an abstraction layer between fetchware and
fetchware's internal Fetchwarefile represenation, which is inside C<%CONFIG>
inside App::Fetchware::Config.

App::Fetchware::Config gives the user a small, flexible API for manipulating
fetchware's internal represenation of the user's Fetchwarefile. This API allows
the user to get (via config()), set (via config()), replace (via
config_replace()), delete (via config_delete()), delete all (via
__clear_CONFIG()), and even debug (via debug_CONFIG()) the internal
representation of the users Fetchwarefile.

=over

=item NOTICE
App::Fetchware::Config's represenation of your Fetchwarefile is per process. If
you parse a new Fetchwarefile it will conflict with the existing C<%CONFIG>, and
various exceptions may be thrown. 

C<%CONFIG> is a B<global> per process variable! You B<can not> try to maniuplate
more than one Fetchwarefile in memory at one time! It will not work! You can
however use __clear_CONFIG() to clear the global %CONFIG, so that you can use it
again. This is mostly just done in fetchware's test suite, so this design
limitation is not such a big deal.

=back

=cut


=head1 ERRORS

As with the rest of App::Fetchware, App::Fetchware::Config does not return any
error codes; instead, all errors are die()'d if it's App::Fetchware::Config's
error, or croak()'d if its the caller's fault.

=cut

###BUGALERT### Actually implement croak or more likely confess() support!!!


=head1 BUGS 

App::Fetchware::Config's represenation of your Fetchwarefile is per process. If
you parse a new Fetchwarefile it will conflict with the existing C<%CONFIG>, and
various exceptions may be thrown. 

C<%CONFIG> is a B<global> per process variable! You B<can not> try to maniuplate
more than one Fetchwarefile in memory at one time! It will not work! You can
however use __clear_CONFIG() to clear the global %CONFIG, so that you can use it
again. This is mostly just done in fetchware's test suite, so this design
limitation is not such a big deal.

=cut
