package App::Fetchware::Util;
# ABSTRACT: Miscelaneous functions for App::Fetchware.
###BUGALERT### Uses die instead of croak. croak is the preferred way of throwing
#exceptions in modules. croak says that the caller was the one who caused the
#error not the specific code that actually threw the error.
use strict;
use warnings;

use File::Spec::Functions qw(catfile catdir splitpath file_name_is_absolute);
use Path::Class;
use Net::FTP;
use HTTP::Tiny;
use Perl::OSType 'is_os_type';
use Cwd;
use App::Fetchware::Util ':UTIL';
use App::Fetchware::Config ':CONFIG';
use File::Copy 'cp';
use File::Temp 'tempdir';

# Enable Perl 6 knockoffs.
use 5.010;

# Set up Exporter to bring App::Fetchware::Util's API to everyone who use's it.
use Exporter qw( import );

our %EXPORT_TAGS = (
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
        do_nothing
        create_tempdir
        original_cwd
        cleanup_tempdir
    )],
);

# *All* entries in @EXPORT_TAGS must also be in @EXPORT_OK.
our @EXPORT_OK = map {@{$_}} values %EXPORT_TAGS;



=head1 UTILITY SUBROUTINES

These subroutines provide utility functions for testing and downloading files
and dirlists that may also be helpful for anyone who's writing a custom
Fetchwarefile to provide easier testing.

=cut 


=head2 Standards for using msg() and vmsg()

msg() should be used to describe the main events that happen, while vmsg()
should be used to describe what all of the main subroutine calls do.

For example, cmd_uninstall() has a msg() at the beginning and at the end, and so
do the main App::Fetchware subroutines that it uses such as start(), download(),
unarchive(), end() and so on. They both use vmsg() to add more detailed messages
about the particular even "internal" things they do.

msg() and vmsg() are also used without parens due to their appropriate
prototypes. This makes them stand out from regular old subroutine calls more.

=cut

=head2 msg()

    msg 'message to print to STDOUT' ;
    msg('message to print to STDOUT');

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


=head2 vmsg()

    vmsg 'message to print to STDOUT' ;
    vmsg('message to print to STDOUT');

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


=head2 run_prog()

    run_prog($program, @args);

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




=head2 download_dirlist()

    my $dir_list = download_dirlist($ftp_or_http_url)

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


=head2 ftp_download_dirlist()

    my $dir_list = ftp_download_dirlist($ftp_url);

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


=head2 http_download_dirlist()

    my $dir_list = http_download_dirlist($http_url);

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


=head2 file_download_dirlist()

    my $file_listing = file_download_dirlist($local_lookup_url)

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

    # Prepend original_cwd() if $local_lookup_url is a relative path.
    unless (file_name_is_absolute($local_lookup_url)) {
diag "origcwd[@{[original_cwd()]}]";
        $local_lookup_url =  catdir(original_cwd(), $local_lookup_url);
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



=head2 download_file()

    my $filename = download_file($url)

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


=head2 download_ftp_url()

    my $filename = download_ftp_url($url);

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


=head2 download_http_url()

    my $filename = download_http_url($url);

Uses HTTP::Tiny to download the specified HTTP URL.

Supports adding extra arguments to HTTP::Tiny's new() constructor. These
arguments are B<not> checked for correctness; instead, they are simply forwarded
to HTTP::Tiny, which does not check them for correctness either. HTTP::Tiny
simply loops over its internal listing of what is arguments should be, and then
accesses the arguments if they exist.

This was really only implemented to allow App::Fetchware::HTMLPageSync to change
its user agent string to avoid being blocked or freaking out Web developers that
they're being screen scraped by some obnoxious bot as HTMLPageSync is wimply and
harmless, and only downloads one page. 

You would add an argument like this:
download_http_url($http_url, agent => 'Firefox');

See HTTP::Tiny's documentation for what these options are.

=cut

sub download_http_url {
    my $http_url = shift;

    # Forward any other options over to HTTP::Tiny. This is used mostly to
    # support changing user agent strings, but why not support them all.
    my %opts = @_ if @_ % 2 == 0;

    my $http = HTTP::Tiny->new(%opts);
    my $response = $http->get($http_url);

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
    # If $filename is empty string, then its probably a index directory listing.
    $filename ||= 'index.html';
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



=head2 download_file_url()

    my $filename = download_file_url($url);

Uses File::Copy to copy ("download") the local file to the current working
directory.

=cut

sub download_file_url {
    my $url = shift;

    $url =~ s!^file://!!; # Strip useless URL scheme.
    
    # Prepend original_cwd() only if the $url is *not* absolute, which will mess
    # it up.
    $url = catdir(original_cwd(), $url) unless file_name_is_absolute($url);

    # Download the file:// URL to the current directory, which should already be
    # in $temp_dir, because of start()'s chdir().
    cp($url, cwd()) or die <<EOD;
App::Fetchware: run-time error. Fetchware failed to copy the download URL
[$url] to the working directory [@{[cwd()]}]. Os error [$!].
EOD

    # Return just file filename of the downloaded file.
    return file($url)->basename();
}



=head2 just_filename()

    my $filename = just_filename($path);

Uses File::Spec::Functions splitpath() to chop off everything except the
filename of the provided $path. Does zero error checking, so it will return
whatever value splitpath() returns as its last return value.

=cut

sub just_filename {
    my $path = shift;
    my ($volume, $directories, $filename) = splitpath($path);

    return $filename;
}


=head2 do_nothing()

    do_nothing();

do_nothing() does nothing but return. It simply returns doing nothing. It is
meant to be used by App::Fetchware "subclasses" that "override" App::Fetchware's
API subroutines to make those API subroutines do nothing.

=cut

sub do_nothing {
    return;
}



{ # Begin scope block for $original_cwd.

    # $original_cwd is a scalar variable that stores fetchware's original
    # working directory for later use if its needed. It is access with
    # original_cwd() below.
    my $original_cwd;

=head2 create_tempdir()

    my $temp_dir = create_tempdir();

Creates a temporary directory, chmod 700's it, and chdir()'s into it.

Accepts the fake hash argument C<KeepTempDir => 1>, which tells create_tempdir()
to B<not> delete the temporary directory when the program exits.

=cut

sub create_tempdir {
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

    $original_cwd = cwd();
    diag("cwd[@{[$original_cwd]}]");
    vmsg "Saving original working directory as [$original_cwd]";

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


=head2 original_cwd()

    my $original_cwd = original_cwd();

original_cwd() simply returns the value of fetchware's $original_cwd that is
saved inside each start() call. A new call to start() will reset this value.

=cut

    sub original_cwd {
        return $original_cwd;
    }


} # End scope block for $original_cwd.


=head2 cleanup_tempdir()

    cleanup_tempdir();

Cleans up B<any> temporary files or directories that anything in this process used
File::Temp to create. You cannot only clean up one directory or another;
instead, you must just use this sparingly or in an END block although file::Temp
takes care of that for you unless you asked it not to.

=cut

sub cleanup_tempdir {
    msg 'Cleaning up temporary directory temporary directory.';
    # chdir to original_cwd() directory, so File::Temp can delete the tempdir. This
    # is necessary, because operating systems do not allow you to delete a
    # directory that a running program has as its cwd.

    vmsg 'Changing directory to [@{[original_cwd()]}].';
    chdir(original_cwd()) or die <<EOD;
App-Fetchware: run-time error. Fetchware failed to chdir() to
[@{[original_cwd()]}]. See perldoc App::Fetchware.
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


1;
