package Test::Fetchware;
# ABSTRACT: Provides testing subroutines for App::Fetchware.
use strict;
use warnings;

# CPAN modules making Fetchwarefile better.
use File::Temp 'tempdir';
use File::Spec::Functions qw(catfile rel2abs updir tmpdir);
use Test::More 0.98; # some utility test subroutines need it.
use Cwd;
use Archive::Tar;
use Path::Class;
use Digest::MD5;

use App::Fetchware::Util ':UTIL';
use App::Fetchware::Config '__clear_CONFIG';

# Enable Perl 6 knockoffs, and use 5.10.1, because smartmatching and other
# things in 5.10 were changed in 5.10.1+.
use 5.010001;


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
    TESTING => [qw(
        eval_ok
        print_ok
        skip_all_unless_release_testing
        make_clean
        make_test_dist
        md5sum_file
        expected_filename_listing
        verbose_on
    )],
);
# *All* entries in @EXPORT_TAGS must also be in @EXPORT_OK.
our @EXPORT_OK = map {@{$_}} values %EXPORT_TAGS;


=head1 TESTING SUBROUTINES


=head2 eval_ok()

    eval_ok($code, $expected_exception_text_or_regex, $test_name);

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


=head2 print_ok()

    print_ok(\&printer, $expected, $test_name);

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
=item * Then execute the coderef with a copy of the $printer's STDOUT and use the result of that expression to determine if the test passed or failed .

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

    if (ref($expected) eq '') {
        is($stdout, $expected,
            $test_name);
    } elsif (ref($expected) eq 'Regexp') {
        like($stdout, $expected,
            $test_name);
    } elsif (ref($expected) eq 'CODE') {
        # Call the provided callback with what $printer->() printed.
        ok($expected->($stdout),
            $test_name);
    }
}


=head2 skip_all_unless_release_testing()

    subtest 'some subtest that tests fetchware' => sub {
        skip_all_unless_release_testing();

        # ... Your tests go here that will be skipped unless
        # FETCHWARE_RELEASE_TESTING among other env vars are set properly.
    };

Skips all tests in your test file or subtest() if fetchware's testing
environment variable, C<FETCHWARE_RELEASE_TESTING>, is not set to its proper
value. Furthermore, other C<FETCHWARE_*> environment variables must also be set
for C<FETCHWARE_RELEASE_TESTING> to work properly. See L<Where ever that will be
when I write it>


###BUGALERT## Expand with how to actually use this.

=cut

sub skip_all_unless_release_testing {
    if ($ENV{FETCHWARE_RELEASE_TESTING}
        ne '***setting this will install software on your computer!!!!!!!***'
        # Enforce having *all* other FETCHWARE_* env vars set too to make it
        # even harder to easily enable FETCHWARE_RELEASE_TESTING. This is
        # because FETCHWARE_RELEASE_TESTING *installs* software on your
        # computer.
        #
        # Furthermore, the env vars below are required for
        # FETCHWARE_RELEASE_TESTING to work properly, so without them being set,
        # then FETCHWARE_RELEASE_TESTING will not work properly, because these
        # env vars will be undef; therefore, check to see if they're enabled.
        and
        defined $ENV{FETCHWARE_FTP_LOOKUP_URL}
        and
        defined $ENV{FETCHWARE_HTTP_LOOKUP_URL}
        and
        defined $ENV{FETCHWARE_FTP_DOWNLOAD_URL}
        and
        defined $ENV{FETCHWARE_HTTP_DOWNLOAD_URL}
        and
        defined $ENV{FETCHWARE_LOCAL_URL}
        and
        defined $ENV{FETCHWARE_LOCAL_BUILD_URL}
        and
        defined $ENV{FETCHWARE_LOCAL_UPGRADE_URL}
    ) {
        plan skip_all => 'Not testing for release.'
    }
}


=head2 make_clean()

    make_clean();

Runs C<make clean> and then chdirs to the parent directory. This subroutine is
used in build() and install()'s test scripts to run make clean in between test
runs. If you override build() or install() you may wish to use make_clean to
automate this for you.

=cut

sub make_clean {
    system('make', 'clean');
    chdir(updir()) or fail(q{Can't chdir(updir())!});
}


=head2 make_test_dist()

    my $test_dist_path = make_test_dist($file_name, $ver_num, rel2abs($destination_directory));

Makes a C<$filename-$ver_num.fpkg> fetchware package that can be used for
testing fetchware's functionality without actually installing anything.

Reuses create_tempdir() to create a temp directory that is used to put the
test-dist's files in. Then an archive is created based on original_cwd() or
$destination_directory if provided, which is the current working directory
before you call make_test_dist(). After the archive is created in original_cwd(),
make_test_dist() deletes the $temp_dir using cleanup_tempdir().

If $destination_directory is not provided as an argument, then make_test_dist()
will just use tmpdir(), File::Spec's location for your system's temporary
directory.

Returns the full path to the created test-dist fetchwware package.

=cut

sub make_test_dist {
    my $file_name = shift;
    my $ver_num = shift;


    # Set optional 3 argument to be the destination directory.
    # If that option was not provided set the destination directory to be a
    # a new temporary directory.
    my $destination_directory = shift
        || tempdir("fetchware-$$-XXXXXXXXXXX", TMPDIR => 1, UNLINK => 1);

    # Append $ver_num to $file_name to complete the dist's name.
    my $dist_name = "$file_name-$ver_num";
diag("dist_name[$dist_name]");

    $destination_directory = rel2abs($destination_directory);
diag("destination_directory[$destination_directory]");

    my $test_dist_filename = catfile($destination_directory, "$dist_name.fpkg");
diag("test_dist_filename[$test_dist_filename]");



    my $configure_path = catfile($dist_name, 'configure');
    my %test_dist_files = (
        './Fetchwarefile' => <<EOF
# $file_name is a fake "test distribution" mean for testing fetchware's basic installing, upgrading, and
# so on functionality.
use App::Fetchware;

# Delme!!!!!!!!!!!!!!
stay_root 'On';

program '$file_name';

# Need to filter out the cruft.
filter '$file_name';

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

    # Append the lookup_url customized based the the $destination_directory for
    # this generated test dist.
    $test_dist_files{'./Fetchwarefile'}
        .= 
        "lookup_url 'file://$destination_directory';";

    # Create a temp dir to create or test-dist-1.$ver_num directory in.
    # Must be done before original_cwd() is used to set $destination_directory,
    # because original_cwd() is undef until create_tempdir() sets it.
    my $temp_dir = create_tempdir();

    mkdir($dist_name) or die <<EOD;
fetchware: Run-time error. Fetchware failed to create the directory
[$dist_name] in the current directory of [$temp_dir]. The OS error was
[$!].
EOD

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

    # Create a tar archive of all of the files needed for test-dist.
    Archive::Tar->create_archive("$test_dist_filename", COMPRESS_GZIP,
        keys %test_dist_files) or die <<EOD;
fetchware: Run-time error. Fetchware failed to create the test-dist archive for
testing [$test_dist_filename] The error was [@{[Archive::Tar->error()]}].
EOD

    # Cd back to original_cwd() and delete $temp_dir.
    cleanup_tempdir();

    return rel2abs($test_dist_filename);
}


=head2 md5sum_file()

    my $md5sum_fil_path = md5sum_file($archive_to_md5);

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
[$archive_to_md5]. OS error [$!]. See perldoc App::Fetchware.
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


=head2 expected_filename_listing()

    my $expected_filename_listing = expected_filename_listing()

Returns a crazy string meant for use with Test::Deep for testing that Apache
directory listings have been parsed correctly by lookup().

=cut

sub expected_filename_listing {
    my $expected_filename_listing = <<'EOC';
        array_each(
            array_each(any(
                re(qr/Announcement2.\d.(html|txt)/),
                re(qr/CHANGES_2\.\d(\.\d+)?/),
                re(qr/CURRENT(-|_)IS(-|_)\d\.\d+?\.\d+/),
                re(qr/
                    HEADER.html
                    |
                    KEYS
                    |
                    README.html
                    |
                    binaries
                    |
                    docs
                    |
                    flood
                /x),
                re(qr/httpd-2\.\d\.\d+?-win32-src\.zip(\.asc)?/),
                re(qr/httpd-2\.\d\.\d+?\.tar\.(bz2|gz)(\.asc)?/),
                re(qr/httpd-2\.\d\.\d+?-deps\.tar\.(bz2|gz)(\.asc)?/),
                re(qr/
                    libapreq
                    |
                    mod_fcgid
                    |
                    mod_ftp
                    |
                    patches
                /x),
                re(qr/\d{12}/)
                ) # end any
            )
        );
EOC

    return $expected_filename_listing;
}


=head2 verbose_on()

    verbose_on();

Just turns C<$fetchware::vebose> on, by setting it to 1. It does no do anything
else. There is no corresponding verbose_off(). Just an vebose_on().

Meant to be used in test suites, so that you can see any vmsg()s that print
during testing.

=cut

sub verbose_on {
    # Turn on verbose functionality.
    $fetchware::verbose = 1;
}


###BUGALERT### Create a frt() subroutine to mirror my frt bash function that
#will work like Util's config() does, but access %ENV instead of %CONFIG, and if
#the requested env var does not exist it will print a failure mesage using
#fail().  I could also use this function as a place to paste in frt() as well.


1;
__END__

=head1 SYNOPSIS

    use Test::Fetchware ':TESTING';

    eval_ok($code, $expected_exception_text_or_regex, $test_name);
    eval_ok(sub { some_code_that_dies()},
        <<EOE, 'check some_code_that_dies() exception()');
    some_code_that_dies() died with this message!
    EOE
    eval_ok(sub { some_code_whose_messages_change(),
        qr/A regex that matches some_code_whose_messages_change() error message/,
        'checked some_code_whose_messages_change() exception');

    print_ok(\&printer, $expected, $test_name);
    print_ok(sub { some_func_that_prints()},
        \$expected, 'checked some_func_that_prints() printed $expected');
    print_ok(sub {some_func_that_prints()},
        qr/some regex that matches what some_func_that_prints() prints/,
        'checked some_func_that_prints() printed matched expected regex');
    print_ok(sub { some_func_that_prints()},

    sub { # a coderef that returns true of some_func_that_prints() printed what it
        #should print and returns false if it did not
        }, 'checked some_func_that_prints() printed matched coderefs expectations.');

    subtest 'some subtest that tests fetchware' => sub {
        skip_all_unless_release_testing();

        # ... Your tests go here that will be skipped unless
        # FETCHWARE_RELEASE_TESTING among other env vars are set properly.
    };

    make_clean();

    my $test_dist_path = make_test_dist($file_name, $ver_num, rel2abs($destination_directory));

    my $md5sum_fil_path = md5sum_file($archive_to_md5);


    my $expected_filename_listing = expected_filename_listing()

=cut

=head1 DESCRIPTION

These subroutines provide miscellaneous subroutines that App::Fetchware's test
suite uses. Some are quite specific such as make_test_dist(), while others are
simple subroutines replacing entire CPAN modules such as eval_ok (similar to
Test::Exception) and print_ok (similar to Test::Output). I wrote them instead of
using the CPAN dependency, because all it would take is a relatively simple
function that I could easily write and test. And their interfaces disagreed with
me. 

=cut

=head1 ERRORS

As with the rest of App::Fetchware, Test::Fetchware does not return any error
codes; instead, all errors are die()'d if it's Test::Fetchware's error, or
croak()'d if its the caller's fault. These exceptions are simple strings, and
are listed in the L</DIAGNOSTICS> section below.

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

=head1 SEE ALSO

L<Test::Exception> is similar to Test::Fetchware's eval_ok().

L<Test::Output> is similar to Test::Fetchware's print_ok().

=cut
