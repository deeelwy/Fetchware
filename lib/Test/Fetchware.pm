package Test::Fetchware;
# ABSTRACT: Provides testing subroutines for App::Fetchware.
###BUGALERT### Uses die instead of croak. croak is the preferred way of throwing
#exceptions in modules. croak says that the caller was the one who caused the
#error not the specific code that actually threw the error.
use strict;
use warnings;

# CPAN modules making Fetchwarefile better.
use File::Temp 'tempdir';
use File::Spec::Functions qw(catfile rel2abs updir);
use Test::More 0.98; # some utility test subroutines need it.
use Cwd;
use Archive::Tar;
use Path::Class;
use Digest::MD5;

use App::Fetchware::Util ':UTIL';
use App::Fetchware::Config '__clear_CONFIG';

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
    TESTING => [qw(
        eval_ok
        print_ok
        skip_all_unless_release_testing
        make_clean
        make_test_dist
        md5sum_file
        expected_filename_listing
    )],
);
# *All* entries in @EXPORT_TAGS must also be in @EXPORT_OK.
our @EXPORT_OK = map {@{$_}} values %EXPORT_TAGS;


=head1 TESTING SUBROUTINES

These subroutines provide utility functions for testing and downloading files
and dirlists that may also be helpful for anyone who's writing a custom
Fetchwarefile to provide easier testing.

=cut 


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
testing fetchware's functionality without actually installing anything. All of
the tests in the t/ directory use this, while all of the tests in the xt/
directory use real programs like apache and ctags to test fetchware's
functionality.

Reuses start() to create a temp directory that is used to put the test-dist's
files in. Then an archive is created based on original_cwd() or
$destination_directory if provided, which is the current working directory
before you call make_test_dist(). After the archive is created in original_cwd(),
make_test_dist() deletes the $temp_dir using end().

If $destination_directory is not provided as an argument, then make_test_dist()
will just use cwd(), your current working directory.

Returns the full path to the created test-dist fetchwware package.

=cut

sub make_test_dist {
    my $file_name = shift;
    my $ver_num = shift;

    # Create a temp dir to create or test-dist-1.$ver_num directory in.
    # Must be done before original_cwd() is used to set $destination_directory,
    # because original_cwd() is undef until create_tempdir() sets it.
    my $temp_dir = create_tempdir();

    my $destination_directory;
    if ($destination_directory = shift) {
        $destination_directory = catfile(original_cwd(), $destination_directory);

    } else {
        $destination_directory = original_cwd();
    }

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

    # Cd back to original_cwd() and delete $temp_dir.
    cleanup_tempdir();

    return rel2abs($test_dist_filename);
}


=head2 md5sum_file()

    my $md5sum_fil_path = emd5sum_file($archive_to_md5);

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











1;
