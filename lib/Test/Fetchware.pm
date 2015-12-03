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
use Fcntl qw(:flock :mode);
use Perl::OSType 'is_os_type';
use File::Temp 'tempfile';
use File::Path 'remove_tree';

use App::Fetchware::Util ':UTIL';
use App::Fetchware::Config ':CONFIG';

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
        fork_ok
        skip_all_unless_release_testing
        make_clean
        make_test_dist
        md5sum_file
        expected_filename_listing
        verbose_on
        export_ok
        end_ok
        add_prefix_if_nonroot
        create_test_fetchwarefile
        rmdashr_ok
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

Tests if $expected is in the output that C<\&printer-E<gt>()> produces on C<STDOUT>.

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
    } or do {
        $error = $@ if $@;
        fail($error) if defined $error;
    };

    # Since Test::More's testing subroutines return true or false if the test
    # passes or fails, return this true or false value back to the caller.
    if (ref($expected) eq '') {
        return is($stdout, $expected,
            $test_name);
    } elsif (ref($expected) eq 'Regexp') {
        return like($stdout, $expected,
            $test_name);
    } elsif (ref($expected) eq 'CODE') {
        # Call the provided callback with what $printer->() printed.
        return ok($expected->($stdout),
            $test_name);
    }
}


=head2 fork_ok()

    fork_ok(&code_fork_should_do, $test_name);

Simply properly forks, and runs the caller's provided coderef in the child,
and tests that the child's exit value is 0 for success using a simple ok() call from
Test::More. The child's exit value is controlled by the caller based on what
&code_fork_should_do returns. If &code_fork_should_do returns true, then the
child returns C<0> for success, and if &code_fork_should_do returns false, then
the child returns C<1> for failure.

Because the fork()ed child is a copy of the current perl process you can still
access whatever Test::More or Test::Fetchware testing subroutines you may have
imported for use in the test file that uses fork_ok().

This testing helper subroutine only exists for testing fetchware's command line
interface. This interface is fetchware's run() subroutine and when you actually
execute the fetchware program from the command line such as C<fetchware help>.

=over

=item WARNING

fork_ok() has a major bug that makes any tests you attempt to run in
&code_fork_should_do that fail never report this failure properly to
Test::Builder. Also, any success is not reported either. This is not fork_ok()'s
fault it is Test::Builder's fault for still not having support for forking. This
lack of support for forking may be fixed in Test::Builder 1.5 or perhaps 2.0,
but those are still in development.

=back

=cut

sub fork_ok {
    my $coderef = shift;
    my $test_name = shift;


    my $kid = fork;
    die "Couldn't fork: $!\n" if not defined $kid;
    # ... parent code here ...
    if ( $kid ) {
        # Block waiting for the child process ($kid) to exit.
        waitpid($kid, 0);
    }
    # ... child code here ...
    else {
        # Run caller's code wihtout any args.
        # And exit based on the success or failure of $coderef.
        $coderef->() ? exit 0 : exit 1;
    }

    # And test that the child returned successfully.
    ok($? == 0, $test_name);

    return $?;
}


=head2 skip_all_unless_release_testing()

    subtest 'some subtest that tests fetchware' => sub {
        skip_all_unless_release_testing();

        # ... Your tests go here that will be skipped unless
        # FETCHWARE_RELEASE_TESTING among other env vars are set properly.
    };

Skips all tests in your test file or subtest() if fetchware's testing
environment variable, C<FETCHWARE_RELEASE_TESTING>, is not set to its proper
value. See L<App::Fetchware/2. Call skip_all_unless_release_testing() as needed>
for more information.

=over

=item WARNING

If you call skip_all_unless_release_testing() in your main test file without
being enclosed inside a subtest, then skip_all_unless_release_testing() will
skip all of your test from that point on till then end of the file, so be
careful where you use it, or just I<only> use it in subtests to be safe.

=back

=cut

sub skip_all_unless_release_testing {
    if (not exists $ENV{FETCHWARE_RELEASE_TESTING}
        or not defined $ENV{FETCHWARE_RELEASE_TESTING}
        or $ENV{FETCHWARE_RELEASE_TESTING}
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
    ) {
        plan skip_all => 'Not testing for release.';
    }
}


=head2 make_clean()

    make_clean();

Runs C<make clean> and then chdirs to the parent directory. This subroutine is
used in build() and install()'s test scripts to run make clean in between test
runs. If you override build() or install() you may wish to use make_clean to
automate this for you.


make_clean() also makes some simple checks to ensure that you are not running it
inside of fetchware's own build directory. If it detects this, it BAIL_OUT()'s
of the test file to indicate that the test file has gone crazy, and is about to
do something it shouldn't.

=cut

sub make_clean {
    BAIL_OUT(<<EOF) if -e 'lib/Test/Fetchware.pm' && -e 't/App-Fetchware-build.t';
Running make_clean() inside of fetchware's own directory! make_clean() should
only be called inside testing build directories, and perhaps also only called if
FETCHWARE_RELEASE_TESTING has been set.
EOF
    system('make', 'clean');
    chdir(updir()) or fail(q{Can't chdir(updir())!});
}


=head2 make_test_dist()

    my $test_dist_path = make_test_dist(
        file_name => $file_name,
        ver_num = $ver_num,
        # These are all optional...
        destination_directory => rel2abs($destination_directory),
        fetchwarefile => $fetchwarefile,
        # You can only specify fetchwarefile *or* append_option.
        append_option => q{fetchware_option 'some value';},
        configure => <<EOF,
    #!/bin/sh

    # A test ./configure for testing ./configure failure...it always fails.

    echo "fetchware: ./configure failed!
    # Return failure exit status to truly indicate failure.
    exit 1
    EOF
        makefile => <<EOF,
    # Test Makefile.
    all:
        sh -c 'echo "fetchware make failed!"'
    EOF
    );

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

make_test_dist() supports customizing the C<Fetchwarefile>, C<./configure>, and
C<Makefile> of the generated make_test_dist():

=over

=item * C<fetchwarefile> - option takes a string that will be written to disk as that test dist's actual Fetchwarefile.

=item * C<append_option> - option confilicts with fetchwarefile option, so only one or the other can be used at the same time. C<append_option> quite literally just appends a fetchware option (or any other string) to the default C<Fetchwarefile>

=item * C<configure> - option takes a string that will completely replace the default ./configure file in your generated test dist. This file is expected to be a shell script by fetchware, but will probably transition into being a perl script file for better Windows support in the future.

=item * C<makefile> - option takes a string that will completely replace the default Makefile that is placed in your generated test dist. This file is expected to actually be a real Makefile.

=back

=over

=item WARNING

When you specify your own $destination_directory, you must also B<ensure> that
it's permissions are C<0755>, because during testing fetchware may drop_privs()
causing it to lose its ability to access the $destination_directory. Therefore,
when specifying your own $destination_directory, please C<chmod> it to to
C<0755> to ensure its child can still access the test distribution in your
$destination_directory.

=back

=cut

###BUGALERT### make_test_dist() only works properly on Unix, because of its
#dependencies on the shell and make, just replace those commands with perl
#itself, which we can pretty much guaranteed to be installed.
sub make_test_dist {
    my %opts = @_;

    # Validate options, and set defaults if they need to be set.
    if (not defined $opts{file_name}) {
        die <<EOD;
Test-Fetchware: file_name named parameter is a mandatory options, and must be
specified despite it pretty much always being just 'test-dist'. It is still
mandatory.
EOD
    }
    if (not defined $opts{ver_num}) {
        die <<EOD;
Test-Fetchware: ver_num named parameter is a mandatory options, and must be
specified despite it pretty much always being just '1.00'. It is still
mandatory.
EOD
    }
    # $destination_directory is a mandatory option, but if the caller does not
    # provide one, then simply use a tempdir().
    if (not defined $opts{destination_directory}) {
        $opts{destination_directory}
            = tempdir("fetchware-test-$$-XXXXXXXXXXX", TMPDIR => 1, CLEANUP => 1);
        # Don't *only* create the tempdid $destination_directory, also, it must
        # be chmod()'d to 755, unless stay_root is set, so that the dropped priv
        # user can still access the directory make_test_dist() creates.
        chmod 0755, $opts{destination_directory} or die <<EOD;
Test-Fetchware: Fetchware failed to change the permissions of it's testing
destination directory [$opts{destination_directory}] this shouldn't happen, and is
perhaps a bug. The OS error was [$!].
EOD
    }
    # This %opts check must go before the code below sets fetchwarefile even if
    # the user did not supply it. Perhaps separate things should stay separate,
    # and %opts and %test_dist_files should both exist for this, but why bother
    # duplicating the same information if only one options is annoyed?
    if (defined $opts{fetchwarefile} and defined $opts{append_option}) {
        die <<EOD;
fetchware: Run-time error. make_test_dist() can only be called with the
Fetchwarefile option *or* the append_option named parameters never both. Only
specify one.
EOD
    }
    if (not defined $opts{fetchwarefile}) {
        $opts{fetchwarefile} = <<EOF;
# $opts{file_name} is a fake "test distribution" meant for testing fetchware's basic
# installing, upgrading, and so on functionality.
use App::Fetchware;

program '$opts{file_name}';

# Every Fetchwarefile needs a lookup_url...
lookup_url 'file://$opts{destination_directory}';

# ...and a mirror.
mirror 'file://$opts{destination_directory}';

# Need to filter out the cruft.
filter '$opts{file_name}';

# Just use MD5 to verify it.
verify_method 'md5';

EOF
    }
    if (not defined $opts{configure}) {
        $opts{configure} = <<EOF;
#!/bin/sh

# A Test ./configure file for testing Fetchware's install, upgrade, and so on
# functionality.

echo "fetchware: ./configure ran successfully!"
EOF
    }
    if (not defined $opts{makefile}) {
        $opts{makefile} = <<EOF;
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
    }
    if (defined $opts{append_option}) {
        $opts{fetchware} .= "\n$opts{append_option}\n"
    }


    # Set up some variables used during test_dist creation.
    # Append $ver_num to $file_name to complete the dist's name.
    my $dist_name = "$opts{file_name}-$opts{ver_num}";
    $opts{destination_directory} = rel2abs($opts{destination_directory});
    my $test_dist_filename = catfile($opts{destination_directory}, "$dist_name.fpkg");
    my $configure_path = catfile($dist_name, 'configure');


    # Be sure to add a prefix to the generated Fetchwarefile if fetchware is not
    # running as root to ensure that our test installs succeed.
    add_prefix_if_nonroot(sub {
        my $prefix_dir = tempdir("fetchware-test-$$-XXXXXXXXXX",
            TMPDIR => 1, CLEANUP => 1);
        $opts{fetchwarefile}
            .= 
            "prefix '$prefix_dir';";
        }
    );


    # Create a temp dir to create or test-dist-1.$opts{ver_num} directory in.
    # Must be done before original_cwd() is used to set $opts{destination_directory},
    # because original_cwd() is undef until create_tempdir() sets it.
    my $temp_dir = create_tempdir();

    mkdir($dist_name) or die <<EOD;
fetchware: Run-time error. Fetchware failed to create the directory
[$dist_name] in the current directory of [$temp_dir]. The OS error was
[$!].
EOD

    my %test_dist_files = (
        './Fetchwarefile' => $opts{fetchwarefile},
        $configure_path => $opts{configure},
        catfile($dist_name, 'Makefile') => $opts{makefile},
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

    cmd_deeply($got_filelisting, eval(expected_filename_listing()),
        'test name');

Returns a crazy string meant for use with Test::Deep for testing that Apache
directory listings have been parsed correctly by lookup().

You must surround expected_filename_listing() with an eval, because Test::Deep's
crazy subroutines for creating complex data structure tests are actual
subroutines that need to be executed. They are not strings that can just be
returned by expected_filename_listing(), and then forwarded along to Test::Deep,
they must be executed:

    cmd_deeply($got_filelisting, eval(expected_filename_listing()),
        'test name');

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
                re(qr/\d{10,12}/)
                ) # end any
            )
        );
EOC

    return $expected_filename_listing;
}


=head2 verbose_on()

    verbose_on();

Just turns C<$fetchware::vebose> on, by setting it to 1. It does not do anything
else. There is no corresponding verbose_off(). Just a vebose_on().

Meant to be used in test suites, so that you can see any vmsg()s that print
during testing for debugging purposes.

=cut

sub verbose_on {
    # Turn on verbose functionality.
    $fetchware::verbose = 1;
}


=head2 export_ok()

    export_ok($sorted_subs, $sorted_export);
    
    my @api_subs
        = qw(start lookup download verify unarchive build install uninstall);
    export_ok(\@api_subs, \@TestPackage::EXPORT);

Just loops over C<@{$sorted_subs}>, and array ref, and ensures that each one
matches the same element of C<@{$sorted_export}>. You do not have to pre sort
these array refs, because export_ok() will copy them, and sort that copy of
them. Uses Test::More's pass() or fail() for each element in the arrays.

=cut

sub export_ok{
    my ($sorted_subs, $sorted_export) = @_;

    package main;
    my @sorted_subs = sort @$sorted_subs;
    my @sorted_export = sort @$sorted_export;

    fail("Specified arrays have a different length.\n[@sorted_subs]\n[@sorted_export]")
        if @sorted_subs != @sorted_export;

    my $i = 0;
    for my $e (@sorted_subs) {
        if ($e eq $sorted_export[$i]) {
            pass("[$e] matches [$sorted_export[$i]]");
        } else {
            fail("[$e] does *not* match [$sorted_export[$i]]");
        }
        $i++;
    }
}


=head2 end_ok()

Because end() no longer uses File::Temp's cleanup() to delete B<all> temporary
File::Temp managed temporary directories when end() is called, you can no longer
test end() we a simple C<ok(not -e $temp_dir, $test_name);>; instead, you should
use this testing subroutine. It tests if the specified $temp_dir still has a
locked C<'fetchware.sem'> fetchware semaphore file. If the file is not locked,
then end_ok() reports success, but if it cannot obtain a lock, end_ok reports
failure simply using ok().

=cut

sub end_ok {
    my $temp_dir = shift;

    ok(open(my $fh_sem, '>', catfile($temp_dir, 'fetchware.sem')),
        'checked cleanup_tempdir() open fetchware lock file success.');
    ok( flock($fh_sem, LOCK_EX | LOCK_NB),
        'checked cleanup_tempdir() success.');
    ok(close $fh_sem,
        'checked cleanup_tempdir() released fetchware lock file success.');
}


=head2 add_prefix_if_nonroot()

    my $prefix = add_prefix_if_nonroot();

    my $callbacks_return_value = add_prefix_if_nonroot(sub { a callback });

fetchware is designed to be run as root, and to install system software in
system directories requiring root privileges. But, fetchware is flexible enough
to let you specifiy where you want the software you're going to install be
installed via the prefix configuration option. This subroutine when run creates
a temporary directory in File::Spec's tmpdir(), and then it directly runs
config() itself to create this config option for you.

However, if you supply a coderef, add_prefix_if_nonroot() will instead call your
coderef instead of using config() directly. If your callback returns a scalar
such as the temporary directory that add_prefix_if_nonroot() normally returns,
this scalar is also returned back to the caller.

It returns the path of the prefix that it configured for use, or it returns
false if it's conditions were not met causing it not to add a prefix.

=cut

sub add_prefix_if_nonroot {
    my $callback = shift;
    my $prefix;
    if (not is_os_type('Unix') or $> != 0 ) {
        if (not defined $callback) {
            $prefix = tempdir("fetchware-test-$$-XXXXXXXXXX",
                TMPDIR => 1, CLEANUP => 1);
            note("Running as nonroot or nonunix using prefix temp dir [$prefix]");
            config(prefix => $prefix);
        } else {
            ok(ref $callback eq 'CODE', <<EOD);
Received callback that is a proper coderef [$callback].
EOD
            $prefix = $callback->();
        }
        
        # Return the prefix that will be used.
        return $prefix;
    } else {
        # Return undef meaning no prefix was added.
        return;
    }
}


=head2 create_test_fetchwarefile()

    my $fetchwarefile_path = create_test_fetchwarefile($fetchwarefile_content);

Writes the provided $fetchwarefile_content to a C<Fetchwarefile> inside a
File::Temp::tempfile(), and returns that file's path, $fetchwarefile_path.

=cut

sub create_test_fetchwarefile {
    my $fetchwarefile_content = shift;

    # Use a temp dir outside of the installation directory 
    my ($fh, $fetchwarefile_path)
        =
        tempfile("fetchware-$$-XXXXXXXXXXXXXX", TMPDIR => 1, UNLINK => 1);

    # Chmod 644 to ensure a possibly dropped priv child can still at least read
    # the file. It doesn't need write access just read.
    unless (chmod 0644, $fetchwarefile_path
        and
        # Only Unix drops privs. Nonunix does not.
        is_os_type('Unix')
    ) {
        die <<EOD;
fetchware: Failed to chmod 0644, [$fetchwarefile_path]! This is a fatal error,
because if the file is not chmod()ed, then fetchware cannot access the file if
it was created by root, and then tried to read it, but root on Unix dropped
privs. OS error [$!].
EOD
    }

    # Be sure to add a prefix to the generated Fetchwarefile if fetchware is not
    # running as root to ensure that our test installs succeed.
    #
    # Prepend a newline to ensure that prefix is not added to an existing line.
    add_prefix_if_nonroot(sub {
            my $prefix_dir = tempdir("fetchware-test-$$-XXXXXXXXXX",
                TMPDIR => 1, CLEANUP => 1);
            $fetchwarefile_content
            .= 
            "\nprefix '$prefix_dir';";
        }
    );

    # Put test stuff in Fetchwarefile.
    print $fh "$fetchwarefile_content";

    # Close the file in case it bothers Archive::Tar reading it.
    close $fh;

    return $fetchwarefile_path;
}


=head2 rmdashr_ok()

    rmdashr_ok($dir_to_recursive_delete, $test_message)

Recursively deletes the specified directory using L<File::Path>'s remove_tree()
subroutine. Returns nothing, but does call L<Test::More>'s ok() for you with
your $test_message if remove_tree() was successful.

=over

=item NOTE:

rmdashr_ok() reports its test as PASS if I<any> number of files are successfully
deleted. It only reports FAIL if I<no> directories were deleted. L<Test::More>'s
note() is used to print out verbose info about exactly what files were deleted,
any errors, and number or errors/warnings and successfully deleted files are
printed using note(), which only shows the output if prove(1)'s C<-v> switch is
used.

=back

=cut

sub rmdashr_ok {
    my ($dir_to_recursive_delete, $test_message) = @_;

    # If $dir_to_recursive_delete is just a file, just unlink it.
    if (not -d $dir_to_recursive_delete) {
        unlink($dir_to_recursive_delete)
            or fail("Failed to unlink([$dir_to_recursive_delete]): $!")
    } else {
        # Delete the whole $tempdir. Use error and result for File::Path's
        # experimental error handling, and set safe to true to avoid borking the
        # filesystem. This might be run as root, so it really could screw up
        # your filesystem big time! So set safe to true to avoid doing so.
        my $ok = remove_tree($dir_to_recursive_delete, {
            error => \my $err,
            result => \my $res,
            safe => 1} );

        # Parse remove_tree()'s insane error handling system. It's expirimental,
        # but it's been experimental forever, so I can't see it changing.
        if (@$err) {
            for my $diag (@$err) {
                my ($file, $message) = %$diag;
                if ($file eq '') {
                    warn "general error: $message\n";
                } else {
                    warn "problem unlinking $file: $message\n";
                }
            }
        } else {
            note("No errors encountered during removal of [$dir_to_recursive_delete]\n");
        }


        # Summarize success or failure for user, so he doesn't have to dig
        # through a bunch of error messages to see if it worked right.
        note <<EOM if @$err > 0;
rmdashr_ok() had [@{[scalar @$err]}] files give errors.
EOM
        note <<EOM if @$res > 0;
rmdashr_ok() successfully deleted [@{[scalar @$res]}] directories. 
EOM

        ok($ok > 0, $test_message);
    }
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

    my $test_dist_path = make_test_dist(
        file_name => $file_name,
        ver_num = $ver_num,
        # These are all optional...
        destination_directory => rel2abs($destination_directory),
        fetchwarefile => $fetchwarefile,
        # You can only specify fetchwarefile *or* append_option.
        append_option => q{fetchware_option 'some value';},
        configure => <<EOF,
    #!/bin/sh

    # A test ./configure for testing ./configure failure...it always fails.

    echo "fetchware: ./configure failed!
    # Return failure exit status to truly indicate failure.
    exit 1
    EOF
        makefile => <<EOF,
    # Test Makefile.
    all:
        sh -c 'echo "fetchware make failed!"'
    EOF
    );

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
usually more than just one line long to help further describe the problem to
make fixing it easier.

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
