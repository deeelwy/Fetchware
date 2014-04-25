package App::Fetchware::Fetchwarefile;
# ABSTRACT: Helps Fetchware extensions create Fetchwarefiles.
###BUGALERT### Uses die instead of croak. croak is the preferred way of throwing
#exceptions in modules. croak says that the caller was the one who caused the
#error not the specific code that actually threw the error.
use strict;
use warnings;

# Enable Perl 6 knockoffs, and use 5.10.1, because smartmatching and other
# things in 5.10 were changed in 5.10.1+.
use 5.010001;

use App::Fetchware::Util 'singleton';
use Text::Wrap 'wrap';

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
    FETCHWAREFILE => [qw(
        fetchwarefile_header
        fetchwarefile_config_options
        append_options_to_fetchwarefile
        fetchwarefile
    )],
);
# *All* entries in @EXPORT_TAGS must also be in @EXPORT_OK.
our @EXPORT_OK = (
    map {@{$_}} values %EXPORT_TAGS,
    # Don't forget about the debugging only subroutines that should *not* be in
    # the FETCHWAREFILE, because they're meant for testing.
    qw(__debug_fetchware_descriptions
        __set_fetchwarefile
        __clear_fetchwarefile_config_options)
);


# Fetchware's internal representation of your Fetchwarefile.
# Keys are options, but values are always an arrayref of values to easily
# support ONEARRREF, and MANY options without making them too "special" and
# annoying.
my %FETCHWAREFILE;


=head1 FETCHWAREFILE SUBROUTINES


=head2 fetchwarefile_header()

    fetchwarefile_header(<<EOF);
    use App::Fetchware;
    # Auto generated @{[localtime()]} by fetchware's new command.
    # However, feel free to edit this file if fetchware's new command's
    # autoconfiguration is not enough.
    # 
    # Please look up fetchware's documentation of its configuration file syntax at
    # perldoc App::Fetchware, and only if its configuration file syntax is not
    # malleable enough for your application should you resort to customizing
    # fetchware's behavior. For extra flexible customization see perldoc
    # App::Fetchware.
    EOF

Sets the opening paragraph or two of text that is displayed in the generated
Fetchwarefile. This chunk of text should describe what this type of
Fetchwarefile does, and perhaps also mention what specific Fetchwarefile options
are mandatory. Above is an example from L<App::Fetchware> itself.

=cut

singleton('fetchwarefile_header');


=head2 fetchwarefile_config_options()

    fetchwarefile_config_options({
        program => <<EOD,
    program simply names the program the Fetchwarefile is responsible for
    downloading, building, and installing.
    <<EOD
        temp_dir => <<EOD,
    temp_dir specifies what temporary directory fetchware will use to download and
    build this program.
    <<EOD
        
        ...
        
    });

Sets the short paragraph of commented text each configuration option has before
them as shown below.

    ...


    # program simply names the program the Fetchwarefile is responsible for
    # downloading, building, and installing.
    program 'my program';


    # temp_dir specifies what temporary directory fetchware will use to download and
    # build this program.
    temp_dir '/var/tmp';

    ...

Besure to notice the braces inside the call to fetchwarefile_config_options(), because
fetchwarefile_config_options() requires its argument to be a hashref not a list that is
later on turned into a hash.


=cut


# Stores the descriptions for your fetchwarefile's options.
my %FETCHWAREFILE_CONFIG_OPTIONS;

sub fetchwarefile_config_options {
    %FETCHWAREFILE_CONFIG_OPTIONS //= @_;

    if (@_ == 0) {
        return %FETCHWAREFILE_CONFIG_OPTIONS;
    } else {
        if (defined %FETCHWAREFILE_CONFIG_OPTIONS) {
            croak <<EOD;
fetchwarefile_config_options() must only be called once! Please determine where it is
being called a second time, and combine that call with the first one.
EOD
        } else {
            %FETCHWAREFILE_CONFIG_OPTIONS = @_;
        }
    }
}


=head2 append_options_to_fetchwarefile()

=cut

sub append_options_to_fetchwarefile {
    my %options = @_;

    for my $option (keys %options) {
        ###BUGALERT### Should fetchwarefile_config_options() include if the option is
        #MANY, ONE, ONEARRREF, and so that fetchwarefile() can avoid creating
        #syntactially wrong Fetchwarefiles?
        #NOTATTHISTIME, because the
        push %{$FETCHWAREFILE{$option}}, $options{$option};        
    }
}



=head2 fetchwarefile()

    my $fetchwarefile = fetchwarefile();

    print fetchwarefile();

=cut

sub fetchwarefile {

    # Stores the Fetchwarefile that we're generating for our caller.
    my $fetchwarefile;

    # Tracks how many times each Fetchwarefile configuration option is used, so
    # that each options description is only put in the Fetchwarefile only once.
    my %description_seen;
    for my $option_key (keys %$FETCHWAREFILE) {
        # %FETCHWAREFILE stores the configuration options using the option name
        # as key and the value is always an arrayref of options mostly just one,
        # but there can be more than one because of 'MANY' and 'ONEARRREF'
        # configuration option types.
        for my $option_value (@{$FETCHWAREFILE->{$option_key}}) {
            if (defined $FETCHWAREFILE_CONFIG_OPTIONS{$option_key}) {
                # If the description has not been written to the $fetchwarefile yet,
                # then include it.
                unless (exists $description_seen{$option_key}
                    and defined $description_seen{$option_key}
                    and $description_seen{$option_key} > 0 
                ) {
                    _append_to_fetchwarefile(\$fetchwarefile, $option_key,
                        $option_value,
                        $FETCHWAREFILE_CONFIG_OPTIONS{$option_key});
                # Otherwise avoid duplicating the description.
                } else {
                    _append_to_fetchwarefile(\$fetchwarefile, $option_key,
                        $option_value);
                }
                vmsg <<EOM;
Appended [$option_key] configuration option [$option_value] to Fetchwarefile.
EOM
            } else {
                die <<EOD;
fetchware: fetchwarefile() was called to generate the Fetchwarefile you have
created using append_options_to_fetchwarefile(), but it has options in it that
do not have a description to add to the Fetchwarefile. Please add a description
to your call to fetchwarefile_config_options() for the option [$option_key].
EOD
            }
        }
        # Increment this for each time each $option_key is written to the
        # $fetchwarefile to ensure that only on the very first time the
        # $option_key is written to the $fetchwarefile that its
        # description is also written.
        $description_seen{$option_key}++;
    }



}


# It's an "_" internal subroutine, so don't publish its POD.
#=head3 _append_to_fetchwarefile()
#
#    _append_to_fetchwarefile(\$fetchwarefile, $config_file_option, $config_file_value, $description)
#
#Turns $description into a comment as described below, and then appends it to the
#$fetchwarefile. Then $config_file_option and $config_file_value are also
#appended inside proper Fetchwarefile syntax.
#
#$description is split into strings 78 characters long, and printed with C<# >
#prepended to make it a proper comment so fetchware skips parsing it.
#
#$description is optional. If you do not include it when you call
#_append_to_fetchwarefile(), then _append_to_fetchwarefile() will not add the
#provided description.
#
#=over
#
#=item NOTE
#Notice the backslash infront of the $fetchwarefile argument above. It is there,
#because the argument $fetchwarefile must be a reference to a scalar.
#
#=back
#
#=cut

sub __append_to_fetchwarefile {
    my ($fetchwarefile,
        $config_file_option,
        $config_file_value,
        $description) = @_;

    die <<EOD if ref($fetchwarefile) ne 'SCALAR';
fetchware: run-time error. You called _append_to_fetchwarefile() with a
fetchwarefile argument that is not a scalar reference. Please add the need
backslash reference operator to your call to _append_to_fetchwarefile() and try
again.
EOD


    # Only add a $description if we were called with one.
    if (defined $description) {
        # Append a double newline for easier reading, but only when we print a
        # new $description, which implies we're switching to a new configuration
        # option.
        $$fetchwarefile .= "\n\n";

        # Append a newline to $description if it doesn't have one already.
        $description .= "\n" unless $description =~ /\n$/;
        # Change wrap() to wrap at 80 columns instead of 76.
        local $Text::Wrap::columns = 81;
        # Use Text::Wrap's wrap() to split $description up
        $$fetchwarefile .= wrap('# ', '# ', $description);
    }

    # This simple chunk of regexes provide trivial and buggy support for
    # ONEARRREFs. This support simply causes fetchware to avoid adding any
    # characters that are needed for proper Perl syntax if the user has provided
    # those characters for us.
    if ($config_file_value =~ /('|")/) {
        $$fetchwarefile .= "$config_file_option $config_file_value";

        if ($config_file_value =~ /[^;]$/) {
            $$fetchwarefile .= ";"; 
        } elsif ($config_file_value =~ /[^\n]$/) {
            $$fetchwarefile .= "\n";
        }
    } else { 
        $$fetchwarefile .= "$config_file_option '$config_file_value';\n";
    }
}



=head1 DEBUGGING SUBROUTINES

These subroutines are intended only for use during testing and debugging. Please
do not use them for production code, but use them as needed while testing and
debugging.


=head2 __debug_fetchware_descriptions()

    use Test::More;
    diag explain __debug_fetchware_descriptions;

__debug_fetchware_descriptions() returns a reference to the internal variable
that App::Fetchware::Fetchwarefile uses to store each option's descriptions.
Please use this only for testing, and not for messing with Fetchware's internals
too much causing bugs and uncertainty if it will work properly or not.

=cut


=head2 __clear_fetchwarefile_config_options() 
    
    __clear_fetchwarefile_config_options();

Clears fetchwarefile_config_options()'s internal hash that stores the list of
Fetchwarefile options and their descriptions your Fetchwarefile may have.
Intended mostly just for testing.

=cut

sub __clear_fetchwarefile_config_options {
    %FETCHWAREFILE_CONFIG_OPTIONS = ();
} 


sub __debug_fetchware_descriptions {
    return \$FETCHWAREFILE_CONFIG_OPTIONS;
}


=head2 __set_fetchwarefile()

    __set_fetchwarefile(
        temp_dir => '/tmp',
        program => 'Some Program',
        ...
        make_options => '-j 4',
    );

Directly sets App::Fetchware::Fetchwarefile's internal variable. Only intended
for testing. Please do not abuse in extensions.

=cut

sub __set_fetchwarefile {
    %FETCHWAREFILE = @_;
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
error, or croak()'d if its the caller's fault. These exceptions are simple
strings, and are listed in the L</DIAGNOSTICS> section below.

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

App::Fetchware::Config's represenation of your Fetchwarefile is per process. If
you parse a new Fetchwarefile it will conflict with the existing C<%CONFIG>, and
various exceptions may be thrown. 

C<%CONFIG> is a B<global> per process variable! You B<can not> try to maniuplate
more than one Fetchwarefile in memory at one time! It will not work! You can
however use __clear_CONFIG() to clear the global %CONFIG, so that you can use it
again. This is mostly just done in fetchware's test suite, so this design
limitation is not such a big deal.

=cut
