#!perl
# bin-fetchware-new.t tests bin/fetchware's cmd_new() subroutine, which
# interactively creates new Fetchwarefiles, and optionally initially installs
# them as fetchware packages.
use strict;
use warnings;
use diagnostics;
use 5.010001;


# Test::More version 0.98 is needed for proper subtest support.
use Test::More;# 0.98 tests => '17'; #Update if this changes.

use App::Fetchware::Config ':CONFIG';
use Test::Fetchware ':TESTING';
use Cwd 'cwd';
use File::Copy 'cp';
use File::Spec::Functions qw(catfile splitpath);
use Path::Class;
use Test::Deep;


# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Load bin/fetchware "manually," because it isn't a real module, and has no .pm
# extenstion use expects.
BEGIN {
    my $fetchware = 'fetchware';
    use lib 'bin';
    require $fetchware;
    fetchware->import(':TESTING');
    ok(defined $INC{$fetchware}, 'checked bin/fetchware loading and import')
}


##TEST##SKIP: {
##TEST##    # Must be 1 less than the number of tests in the Test::More use line above.
##TEST##    my $how_many = 16;
##TEST##    skip 'Not on a terminal', $how_many unless -t; 


subtest 'test opening_message() success' => sub {
    my $opening_message = "Testing...1...2...3...for opening_message().\n";
    print_ok(sub {opening_message($opening_message)},
        $opening_message, 'test opening_message() success.');
};


##TEST### Set Term::UI's AUTOREPLY to true so that it will answer with whatever default
##TEST### option I provide or if no default option is provided Term::UI will reply with
##TEST### undef.
##TEST###
##TEST### This lame hack is, so that I can test my use of Term::UI, which is just as
##TEST### untestable as Term::ReadLine with which it is based. Term::UI tests itself
##TEST### using this exact same method except it uses a default option, but I do not
##TEST### want my calls to have a default option or add some stupid wrapper to do it for
##TEST### me. This works just fine. Just remember to ignore the warning:
##TEST### You have '$AUOTREPLY' set to true, but did not provide a default!
##TEST###
##TEST### I have tried to figure out how to test this. I even posted some insane code
##TEST### that sadly does not work on perlmonks:
##TEST### http://www.perlmonks.org/?node_id=991229
##TEST##$Term::UI::AUTOREPLY = 1;
##TEST#####BUGALERT### Because I can't test things interactvely, even using the cool
##TEST###insane code listed in the perlmonks post above, I'm stuck using the lame
##TEST###AUTOREPLY garbage. Either figure out how to programatically press <Enter>, or
##TEST###create a interactive option for this test file similar to what Term::ReadLine
##TEST###itself does. At least add an xt/ and FETCHWARE_RELEASE_TESTING test that
##TEST###prints a lame reminder to at least test new() manually using fetchware new
##TEST###itself.
##TEST##
##TEST##
##TEST##subtest 'test name_program() success' => sub {
##TEST##    # Create test Term::UI object.
##TEST##    my $term = Term::ReadLine->new('fetchware');
##TEST##
##TEST##    is(name_program($term), undef,
##TEST##        'checked name_program() success');
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test get_lookup_url() success' => sub {
##TEST##    # Create test Term::UI object.
##TEST##    my $term = Term::ReadLine->new('fetchware');
##TEST##
##TEST##    is(get_lookup_url($term), undef,
##TEST##        'checked get_lookup_url() success');
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test download_lookup_url() success' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    # Create test Term::UI object.
##TEST##    my $term = Term::ReadLine->new('fetchware');
##TEST##
##TEST##    cmp_deeply(download_lookup_url($term, $ENV{FETCHWARE_HTTP_LOOKUP_URL}),
##TEST##        array_each(
##TEST##            re(qr/[-\w\d\._]+/),
##TEST##            re(qr/\d{12}/),
##TEST##        ), 'checked download_lookup_url() success.');
##TEST##};
##TEST##
##TEST##
##TEST##
##TEST##subtest 'test download_lookup_url() test-dist success' => sub {
##TEST##    # Create test Term::UI object.
##TEST##    my $term = Term::ReadLine->new('fetchware');
##TEST##
##TEST##    ###Use download_dirlist() instead of get_directory_listing, which takes *NO*
##TEST##    #params!!!!!!!!!!!!!!!!!!!!!!
##TEST##    eval_ok(sub {download_lookup_url($term, 'badschem://fake.url')},
##TEST##        <<EOE, 'checked download_lookup_url() test-dist exception');
##TEST##fetchware: run-time error. The lookup_url you provided [] is not a
##TEST##usable lookup_url because of the error below:
##TEST##[App-Fetchware: run-time syntax error: the url parameter your provided in
##TEST##your call to download_dirlist() [] does not have a supported URL scheme (the
##TEST##http:// or ftp:// part). The only supported download types, schemes, are FTP and
##TEST##HTTP. See perldoc App::Fetchware.
##TEST##]
##TEST##Please see perldoc App::Fetchware for troubleshooting tips and rerun
##TEST##fetchware new.
##TEST##EOE
##TEST##
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test append_to_fetchwarefile() success' => sub {
##TEST##    my $fetchwarefile;
##TEST##
##TEST##    append_to_fetchwarefile(\$fetchwarefile,
##TEST##        'program', 'test-dist', 'A meaningless test example.');
##TEST##    is($fetchwarefile,
##TEST##        <<EOE, 'checked append_to_fetchwarefile() success.');
##TEST##
##TEST##
##TEST### A meaningless test example.
##TEST##program 'test-dist';
##TEST##EOE
##TEST##
##TEST##    undef $fetchwarefile;
##TEST##
##TEST##    # Test a description with more than 80 chars.
##TEST##    append_to_fetchwarefile(\$fetchwarefile,
##TEST##                'program', 'test-dist',
##TEST##            q{test with more than 80 chars to test the logic that chops it up into lines that are only 80 chars long. Do you think it will work?? Well, let's hope so!
##TEST##    });
##TEST##    is($fetchwarefile,
##TEST##        <<EOE, 'checked append_to_fetchwarefile() success.');
##TEST##
##TEST##
##TEST### test with more than 80 chars to test the logic that chops it up into lines
##TEST### that are only 80 chars long. Do you think it will work?? Well, let's hope so!
##TEST##program 'test-dist';
##TEST##EOE
##TEST##
##TEST##    eval_ok(sub {append_to_fetchwarefile($fetchwarefile,
##TEST##        'program', 'test-dist', 'description')},
##TEST##    <<EOE, 'checked append_to_fetchwarefile() excpetion');
##TEST##fetchware: run-time error. You called append_to_fetchwarefile() with a
##TEST##fetchwarefile argument that is not a scalar reference. Please add the need
##TEST##backslash reference operator to your call to append_to_fetchwarefile() and try
##TEST##again.
##TEST##EOE
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test prompt_for_other_options() success' => sub {
##TEST##    plan(skip_all => 'Optional Test::Expect testing module not installed.')
##TEST##        unless eval {require Test::Expect; Test::Expect->import(); 1;};
##TEST##
##TEST##    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
##TEST##    # something crazy like Test::Expect, this will have to be tested "manually."
##TEST##    local $Term::UI::AUTOREPLY = 0;
##TEST##    # Fix the "out of orderness" thanks to Test::Builder messing with
##TEST##    # STD{OUT,ERR}.
##TEST##    local $| = 1;
##TEST##
##TEST##    # Have Expect tell me what it's doing for easier debugging.
##TEST##    #$Expect::Exp_Internal = 1;
##TEST##
##TEST##    expect_run(
##TEST##        command => 't/bin-fetchware-new-prompt_for_other_options',
##TEST##        prompt => [-re => qr/: |\? /],
##TEST##        quit => "\cC"
##TEST##    );
##TEST##
##TEST##    # First test that the command produced the correct outout.
##TEST##    expect_like(qr/Fetchware has many different configuration options that allow you to control its/,
##TEST##        'checked prompt_for_other_options() received correct config options prompt');
##TEST##
##TEST##    # Have Expect print an example URL.
##TEST##    expect_send('y',
##TEST##        'check prompt_for_other_options() sent Y.');
##TEST##
##TEST##    # Check if upon receiving the URL the command prints out the next correct
##TEST##    # prompt.
##TEST##    # The including [y/N] below is a stupid workaround for some stupid bug in
##TEST##    # Expect or in my code that I can't figure out. Fix this if you can.
##TEST##    #expect_like(qr/Below is a listing of Fetchware's available configuration options./,
##TEST##    expect_like(qr!\[y/N\]|Below is a listing of Fetchware's available configuration options.!,
##TEST##        'checked prompt_for_other_options() received configuration options prompt.');
##TEST##
##TEST##    # Note I have no clue what numbers will line up with what configuration
##TEST##    # options, because the configuraiton options come from a hash, and hash's
##TEST##    # order changes each time the program is compiled. I could parse the actual
##TEST##    # output with a regex or something, but as of now I'm not.
##TEST##    expect_send('1 5 9',
##TEST##        'checked prompt_for_other_options() specify some configuration options.');
##TEST##
##TEST##    # The weird regex is just so it can match any possible configuration option,
##TEST##    # because due to hashes being unordered I don't know which options are which
##TEST##    # numbers without complicated parsing that I'm not doing.
##TEST##    expect_like(qr/[\w .,?!]+/,
##TEST##        'checked prompt_for_other_options() received a specifc config option.');
##TEST##    expect_send('Some test value who cares',
##TEST##        'checked prompt_for_other_options() specify a specific config option.');
##TEST##
##TEST##    expect_like(qr/[\w .,?!]+/,
##TEST##        'checked prompt_for_other_options() received a specifc config option.');
##TEST##    expect_send('Some test value who cares',
##TEST##        'checked prompt_for_other_options() specify a specific config option.');
##TEST##
##TEST##    expect_like(qr/[\w .,?!]+/,
##TEST##        'checked prompt_for_other_options() received a specifc config option.');
##TEST##    expect_send('Some test value who cares',
##TEST##        'checked prompt_for_other_options() specify a specific config option.');
##TEST##
##TEST##    expect_quit();
##TEST##    
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test append_options_to_fetchwarefile()' => sub {
##TEST##    my $fetchwarefile = '# Nothing just testing.';
##TEST##
##TEST##    eval_ok(sub {append_options_to_fetchwarefile(
##TEST##        {doesntexistever => 'test 1 2 3.'}, \$fetchwarefile);},
##TEST##        <<EOE, 'checked append_options_to_fetchwarefile exception');
##TEST##fetchware: append_options_to_fetchwarefile() was called with \$options that it
##TEST##does not support having a description for. Please call
##TEST##append_options_to_fetchwarefile() with the correct \$options, or add the new,
##TEST##missing option to append_options_to_fetchwarefile()'s internal
##TEST##%config_file_description hash. \$options was:
##TEST##\$VAR1 = {
##TEST##          'doesntexistever' => 'test 1 2 3.'
##TEST##        };
##TEST##
##TEST##EOE
##TEST##
##TEST##    append_options_to_fetchwarefile(
##TEST##        {temp_dir => '/var/tmp',
##TEST##        prefix => '/tmp',
##TEST##        make_options => '-j 4'}, \$fetchwarefile);
##TEST##
##TEST##    is($fetchwarefile, <<EOS, 'checked append_options_to_fetchwarefile() success');
##TEST### Nothing just testing.
##TEST##
##TEST### temp_dir specifies what temporary directory fetchware will use to download and
##TEST### build this program.
##TEST##temp_dir '/var/tmp';
##TEST##
##TEST##
##TEST### make_options specifes what options fetchware should pass to make when make is
##TEST### run to build and install your software.
##TEST##make_options '-j 4';
##TEST##
##TEST##
##TEST### prefix specifies what base path your software will be installed under. This
##TEST### only works for software that uses GNU AutoTools to configure itself, it uses
##TEST### ./configure.
##TEST##prefix '/tmp';
##TEST##EOS
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test add_mirrors() success' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    plan(skip_all => 'Optional Test::Expect testing module not installed.')
##TEST##        unless eval {require Test::Expect; Test::Expect->import(); 1;};
##TEST##
##TEST##    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
##TEST##    # something crazy like Test::Expect, this will have to be tested "manually."
##TEST##    local $Term::UI::AUTOREPLY = 0;
##TEST##    # Fix the "out of orderness" thanks to Test::Builder messing with
##TEST##    # STD{OUT,ERR}.
##TEST##    local $| = 1;
##TEST##
##TEST##    # Have Expect tell me what it's doing for easier debugging.
##TEST##    #$Expect::Exp_Internal = 1;
##TEST##
##TEST##    expect_run(
##TEST##        command => 't/bin-fetchware-new-add_mirrors',
##TEST##        prompt => [-re => qr/: |\? /],
##TEST##        quit => "\cC"
##TEST##    );
##TEST##
##TEST##    # First test that the command produced the correct outout.
##TEST##    expect_like(qr/Fetchware requires you to please provide a mirror. This mirror is required,/,
##TEST##        'checked add_mirror() received correct mirror prompt');
##TEST##
##TEST##    # Have Expect print an example URL.
##TEST##    expect_send('http://who.cares/whatever/',
##TEST##        'check add_mirror() sent mirror URL.');
##TEST##
##TEST##    # Check if upon receiving the URL the command prints out the next correct
##TEST##    # prompt.
##TEST##    expect_like(qr/Would you like to add any additional mirrors?/,
##TEST##        'checked add_mirrors() received more mirrors prompt.');
##TEST##
##TEST##    expect_send('N', 'checked add_mirrors() say No to more mirrors.');
##TEST##
##TEST##    expect_quit();
##TEST##
##TEST##    # Test answering Yes for more mirrors.
##TEST##
##TEST##    expect_run(
##TEST##        command => 't/bin-fetchware-new-add_mirrors',
##TEST##        prompt => [-re => qr/: |\? /],
##TEST##        quit => "\cC"
##TEST##    );
##TEST##
##TEST##    # First test that the command produced the correct outout.
##TEST##    expect_like(qr/Fetchware requires you to please provide a mirror. This mirror is required,/,
##TEST##        'checked add_mirror() received correct mirror prompt');
##TEST##
##TEST##    # Have Expect print an example URL.
##TEST##    expect_send('http://who.cares/whatever/',
##TEST##        'check add_mirror() sent mirror URL.');
##TEST##
##TEST##    # Check if upon receiving the URL the command prints out the next correct
##TEST##    # prompt.
##TEST##    expect_like(qr/Would you like to add any additional mirrors?/,
##TEST##        'checked add_mirrors() received more mirrors prompt.');
##TEST##
##TEST##    expect_send('Y', 'checked add_mirrors() say No to more mirrors.');
##TEST##
##TEST##    expect_like(qr!\[y/N\]|Type in URL of mirror or done to continue!,
##TEST##        'checked add_mirrors() received prompt to enter a mirror.');
##TEST##
##TEST##    expect_send('ftp://afakemirror.blah/huh?',
##TEST##        'checked add_mirrors() sent another mirror URL.');
##TEST##
##TEST##    expect_like(qr/Type in URL of mirror or done to continue/,
##TEST##        'checked add_mirrors() received prompt to enter a mirror.');
##TEST##
##TEST##    expect_send('ftp://anotherfake.mirror/kasdjlfkjd',
##TEST##        'checked add_mirrors() sent another mirror URL.');
##TEST##
##TEST##    expect_like(qr/Type in URL of mirror or done to continue/,
##TEST##        'checked add_mirrors() received prompt to enter a mirror.');
##TEST##
##TEST##    expect_send('done',
##TEST##        'checked add_mirrors() sent done.');
##TEST##
##TEST##    expect_quit();
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test add_verification() success' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    plan(skip_all => 'Optional Test::Expect testing module not installed.')
##TEST##        unless eval {require Test::Expect; Test::Expect->import(); 1;};
##TEST##
##TEST##    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
##TEST##    # something crazy like Test::Expect, this will have to be tested "manually."
##TEST##    local $Term::UI::AUTOREPLY = 0;
##TEST##    # Fix the "out of orderness" thanks to Test::Builder messing with
##TEST##    # STD{OUT,ERR}.
##TEST##    local $| = 1;
##TEST##
##TEST##    # Have Expect tell me what it's doing for easier debugging.
##TEST##    #$Expect::Exp_Internal = 1;
##TEST##
##TEST##    expect_run(
##TEST##        command => 't/bin-fetchware-new-add_verification',
##TEST##        prompt => [-re => qr/: |\? /],
##TEST##        quit => "\cC"
##TEST##    );
##TEST##
##TEST##    # First test that the command produced the correct outout.
##TEST##    expect_like(qr/Automatic KEYS file discovery failed. Fetchware needs the/,
##TEST##        'checked add_verification() received correct mirror prompt');
##TEST##
##TEST##    # Have Expect print an example URL.
##TEST##    expect_send('Y',
##TEST##        'check add_verification() sent manual KEYS file Y.');
##TEST##
##TEST##    expect_like(qr<\[y/N\]|Automatic verification of your fetchware package has failed!>,
##TEST##        'check add_verification() received no verify prompt.');
##TEST##
##TEST##    expect_send('Y',
##TEST##        'checked add_verification() sent no verify Y.');
##TEST##
##TEST##
##TEST##    expect_quit();
##TEST##
##TEST##    ###BUGALERT### Add tests for add_verification()'s other branches.
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test determine_mandatory_options() success' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    plan(skip_all => 'Optional Test::Expect testing module not installed.')
##TEST##        unless eval {require Test::Expect; Test::Expect->import(); 1;};
##TEST##
##TEST##    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
##TEST##    # something crazy like Test::Expect, this will have to be tested "manually."
##TEST##    local $Term::UI::AUTOREPLY = 0;
##TEST##    # Fix the "out of orderness" thanks to Test::Builder messing with
##TEST##    # STD{OUT,ERR}.
##TEST##    local $| = 1;
##TEST##
##TEST##    # Have Expect tell me what it's doing for easier debugging.
##TEST##    #$Expect::Exp_Internal = 1;
##TEST##
##TEST##    expect_run(
##TEST##        command => 't/bin-fetchware-new-mandatory_options',
##TEST##        prompt => [-re => qr/: |\? /],
##TEST##        quit => "\cC" # CTRL-C
##TEST##    );
##TEST##
##TEST##    expect_like(qr/Fetchware requires you to please provide a mirror. This mirror/,
##TEST##        'checked add_verification() received correct mirror prompt');
##TEST##
##TEST##    expect_send('http://somefakemirror.who/cares',
##TEST##        'check determine_mandatory_options() provided mirror.');
##TEST##
##TEST##    expect_like(qr!\[y/N\]|In addition to the one required mirror that you must!,
##TEST##        'check determine_mandatory_options() received addional mirrors prompt.');
##TEST##
##TEST##    expect_send('N',
##TEST##        'checked add_verification() sent no verify Y.');
##TEST##
##TEST##    expect_like(qr!\[y/N\]|Would you like to import the author's key yourself !,
##TEST##        'checked determine_mandatory_options() received manual import of KEYS.');
##TEST##
##TEST##    expect_send('Y',
##TEST##        'checked determine_mandatory_options() sent Yes to user_keyring option');
##TEST##
##TEST##    expect_quit();
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test determine_filter_option() success' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    plan(skip_all => 'Optional Test::Expect testing module not installed.')
##TEST##        unless eval {require Test::Expect; Test::Expect->import(); 1;};
##TEST##
##TEST##    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
##TEST##    # something crazy like Test::Expect, this will have to be tested "manually."
##TEST##    local $Term::UI::AUTOREPLY = 0;
##TEST##    # Fix the "out of orderness" thanks to Test::Builder messing with
##TEST##    # STD{OUT,ERR}.
##TEST##    local $| = 1;
##TEST##
##TEST##    # Have Expect tell me what it's doing for easier debugging.
##TEST##    #$Expect::Exp_Internal = 1;
##TEST##
##TEST##    expect_run(
##TEST##        command => 't/bin-fetchware-new-filter_option',
##TEST##        prompt => [-re => qr/: |\? /],
##TEST##        quit => "\cC" # CTRL-C
##TEST##    );
##TEST##
##TEST##    expect_like(qr/Analyzing the lookup_url you provided to determine if fetchware/,
##TEST##        'checked determine_filter_option() received correct filter prompt');
##TEST##
##TEST##    expect_send('httpd-2.2',
##TEST##        'check determine_filter_option() provided filter.');
##TEST##
##TEST##    expect_quit();
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test analyze_lookup_listing() success' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##
##TEST##    plan(skip_all => 'Optional Test::Expect testing module not installed.')
##TEST##        unless eval {require Test::Expect; Test::Expect->import(); 1;};
##TEST##
##TEST##    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
##TEST##    # something crazy like Test::Expect, this will have to be tested "manually."
##TEST##    local $Term::UI::AUTOREPLY = 0;
##TEST##    # Fix the "out of orderness" thanks to Test::Builder messing with
##TEST##    # STD{OUT,ERR}.
##TEST##    local $| = 0;
##TEST##
##TEST##    # Have Expect tell me what it's doing for easier debugging.
##TEST##    #$Expect::Exp_Internal = 1;
##TEST##
##TEST##    expect_run(
##TEST##        command => 't/bin-fetchware-new-analyze_lookup_listing',
##TEST##        prompt => [-re => qr/: |\? /],
##TEST##        quit => "\cC" # CTRL-C
##TEST##    );
##TEST##
##TEST##    expect_like(qr/Fetchware requires you to please provide a mirror. This mirror/,
##TEST##        'checked analyze_lookup_listing() received correct filter prompt');
##TEST##
##TEST##    expect_send('http://kdjfkldjfkdj',
##TEST##        'check analyze_lookup_listing() provided mirror.');
##TEST##
##TEST##    expect_like(qr/In addition to the one required mirror that you must define/,
##TEST##        'checked analyze_lookup_listing() received more mirrors prompt.');
##TEST##
##TEST##    expect_send('N',
##TEST##        'checked analyze_lookup_listing() sent No for more mirrors.');
##TEST##
##TEST##    expect_like(qr!\[y/N\]|gpg digital signatures found. Using gpg verification.!,
##TEST##        'checked analyze_lookup_listing() received KEYS question.');
##TEST##
##TEST##    expect_send('Y',
##TEST##        'checked analyze_lookup_listing() sent Y to user_keyring');
##TEST##
##TEST##    expect_quit();
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test edit_manually() success' => sub {
##TEST##    # Create test Term::UI object.
##TEST##    my $term = Term::ReadLine->new('fetchware');
##TEST##
##TEST##    my $fetchwarefile = '# Just testing.';
##TEST##
##TEST##    my $expected_fetchwarefile = $fetchwarefile;
##TEST##
##TEST#####BUGALERT### I don't want to use Expect for testing in /t, but nothing is
##TEST###stopping me from using Expect for interactive testing in /xt!!!!!!!!!!!!!!
##TEST##    edit_manually($term, \$fetchwarefile);
##TEST##    is($fetchwarefile, $expected_fetchwarefile,
##TEST##        'check add_mirrors() success');
##TEST##
##TEST##};
##TEST##
##TEST##
##TEST##subtest 'test check_fetchwarefile() success' => sub {
##TEST##    eval_ok(sub {check_fetchwarefile(\'')},
##TEST##        <<EOE, 'checked check_fetchwarefile() lookup_url exception');
##TEST##fetchware: The Fetchwarefile fetchware generated for you does not have a
##TEST##lookup_url configuration option. Please add a lookup_url configuration file such
##TEST##as [lookup_url 'My Program';] The generated Fetchwarefile was [
##TEST##
##TEST##]
##TEST##EOE
##TEST##
##TEST##    eval_ok(sub {check_fetchwarefile(\q{lookup_url 'http://a.url/';})},
##TEST##        <<EOE, 'checked check_fetchwarefile() mirror exception');
##TEST##fetchware: The Fetchwarefile fetchware generated for you does not have a mirror
##TEST##configuration option. Please add a mirror configuration file such as
##TEST##[mirror 'My Program';] The generated Fetchwarefile was [
##TEST##lookup_url 'http://a.url/';
##TEST##]
##TEST##EOE
##TEST##
##TEST##
##TEST##    my $fetchwarefile = <<EOF;
##TEST##lookup_url 'http://a.url/';
##TEST##mirror 'ftp://who.cares/blah/blah/blacksheep/';
##TEST##EOF
##TEST##    eval_ok(sub {check_fetchwarefile(\$fetchwarefile)},
##TEST##        <<EOE, 'checked check_fetchwarefile() program exception');
##TEST##fetchware: The Fetchwarefile fetchware generated for you does not have a program
##TEST##configuration option. Please add a program configuration file such as
##TEST##[program 'My Program';] The generated Fetchwarefile was [
##TEST##lookup_url 'http://a.url/';
##TEST##mirror 'ftp://who.cares/blah/blah/blacksheep/';
##TEST##
##TEST##]
##TEST##EOE
##TEST##    $fetchwarefile .= q{program 'program';};
##TEST##    print_ok(sub {check_fetchwarefile(\$fetchwarefile)},
##TEST##        <<EOE, 'checked check_fetchwarefile() verify exception');
##TEST##Checking your Fetchwarefile to ensure it has all of the mandatory configuration
##TEST##options properly configured.
##TEST##Warning: gpg verification is *not* enabled. Please switch to gpg verification if
##TEST##possible, because it is more secure against hacked 3rd party mirrors.
##TEST##EOE
##TEST##
##TEST##    $fetchwarefile .= q{gpg_keys_url 'ftp://gpg.keys.urk/dir'};
##TEST##    ok(check_fetchwarefile(\$fetchwarefile),
##TEST##        'checked check_fetchwarefile() success.');
##TEST##
##TEST##};
##TEST##
##TEST##subtest 'test ask_to_install_now_to_test_fetchwarefile success' => sub {
##TEST##    skip_all_unless_release_testing();
##TEST##    unless ($< == 0 or $> == 0) {
##TEST##        plan skip_all => 'Test suite not being run as root.'
##TEST##    }
##TEST##
##TEST##    # Create test Term::UI object.
##TEST##    my $term = Term::ReadLine->new('fetchware');
##TEST##
##TEST##my $fetchwarefile = <<EOF;
##TEST##use App::Fetchware;
##TEST##
##TEST##program 'Apache 2.2';
##TEST##
##TEST##lookup_url '$ENV{FETCHWARE_HTTP_LOOKUP_URL}';
##TEST##
##TEST##mirror '$ENV{FETCHWARE_FTP_MIRROR_URL}';
##TEST##
##TEST##gpg_keys_url "$ENV{FETCHWARE_HTTP_LOOKUP_URL}/KEYS";
##TEST##
##TEST##filter 'httpd-2.2';
##TEST##EOF
##TEST##
##TEST##note('FETCHWAREFILE');
##TEST##note("$fetchwarefile");
##TEST##
##TEST##
##TEST##
##TEST##    my $new_fetchware_package_path =
##TEST##        ask_to_install_now_to_test_fetchwarefile($term, \$fetchwarefile,
##TEST##            'Apache 2.2');
##TEST##
##TEST##    ok(grep /httpd-2\.2/, glob(catfile(fetchware_database_path(), '*')),
##TEST##        'check cmd_install(Fetchware) success.');
##TEST##
##TEST##    ok(unlink $new_fetchware_package_path,
##TEST##        'checked ask_to_install_now_to_test_fetchwarefile() cleanup file');
##TEST##
##TEST##};
##TEST##
##TEST##
##TEST####BROKEN##subtest 'test cmd_new() success' => sub {
##TEST####BROKEN##    skip_all_unless_release_testing();
##TEST####BROKEN##
##TEST####BROKEN##    plan(skip_all => 'Optional Test::Expect testing module not installed.')
##TEST####BROKEN##        unless eval {require Test::Expect; Test::Expect->import(); 1;};
##TEST####BROKEN##
##TEST####BROKEN##    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
##TEST####BROKEN##    # something crazy like Test::Expect, this will have to be tested "manually."
##TEST####BROKEN##    local $Term::UI::AUTOREPLY = 0;
##TEST####BROKEN##    # Fix the "out of orderness" thanks to Test::Builder messing with
##TEST####BROKEN##    # STD{OUT,ERR}.
##TEST####BROKEN###    local $| = 1;
##TEST####BROKEN##
##TEST####BROKEN##    # Have Expect tell me what it's doing for easier debugging.
##TEST####BROKEN##    $Expect::Exp_Internal = 1;
##TEST####BROKEN##
##TEST####BROKEN##    expect_run(
##TEST####BROKEN##        command => 't/bin-fetchware-new-cmd_new',
##TEST####BROKEN###        prompt => [-re => qr/((?<!\?  \[y\/N\]): |\? )/ms],
##TEST####BROKEN##        #prompt => [-re => qr/(\?|:) \[y\/N\] |\? |: /ims],
##TEST####BROKEN###        prompt => [-re => qr/((?:\?|:) \[y\/N\]: )|\? |: /i],
##TEST####BROKEN##        prompt => [-re => qr/ \[y\/N\]: |\? |: /i],
##TEST####BROKEN###        prompt => [-re => qr/\? \n/ims],
##TEST####BROKEN##        quit => "\cC"
##TEST####BROKEN##    );
##TEST####BROKEN##
##TEST####BROKEN##    # Have Expect restart its timeout anytime output is received. Should keep
##TEST####BROKEN##    # expect from timeingout while it's waiting for Apache to compile.
##TEST####BROKEN##    #my $exp = expect_handle();
##TEST####BROKEN##    #$exp->restart_timeout_upon_receive(1);
##TEST####BROKEN##
##TEST####BROKEN##    # First test that the command produced the correct outout.
##TEST####BROKEN##    expect_like(qr/Fetchware's new command is reasonably sophisticated, and is smart enough to/ms,
##TEST####BROKEN##        'checked cmd_new() received correct name prompt');
##TEST####BROKEN##
##TEST####BROKEN##    expect_send('Apache',
##TEST####BROKEN##        'check cmd_new() sent Apache as my name.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_like(qr/Fetchware's heart and soul is its lookup_url. This is the configuration option/ms,
##TEST####BROKEN##        'checked cmd_new() received lookup_url prompt.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_send("$ENV{FETCHWARE_HTTP_LOOKUP_URL}",
##TEST####BROKEN##        'checked cmd_new() say lookup_url.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_like(qr/Fetchware requires you to please provide a mirror. This mirror is required,/ms,
##TEST####BROKEN##        'checked cmd_new() received mirror prompt.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_send("$ENV{FETCHWARE_HTTP_MIRROR_URL}",
##TEST####BROKEN##        'checked cmd_new() say mirror.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_like(qr/In addition to the one required mirror that you must define in order for/ms,
##TEST####BROKEN##        'checked cmd_new() received more mirrors prompt.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_send('N',
##TEST####BROKEN##        'checked cmd_new() say N for more mirrors.');
##TEST####BROKEN##
##TEST####BROKEN##    #expect_like(qr!\[y/N\]|gpg digital signatures found. Using gpg verification.!ms,
##TEST####BROKEN##    expect_like(qr!.*|gpg digital signatures found. Using gpg verification.!ms,
##TEST####BROKEN##        'checked cmd_new() received filter prompt.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_send('httpd-2.2',
##TEST####BROKEN##        'checked cmd_new() say httpd-2.2 for filter option.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_like(qr/Fetchware has many different configuration options that allow you to control its/ms,
##TEST####BROKEN##        'checked cmd_new() received extra config prompt.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_send('N',
##TEST####BROKEN##        'checked cmd_new() say N for more config options prompt.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_like(qr/Fetchware has now asked you all of the needed questions to determine what it/ms,
##TEST####BROKEN##        'checked cmd_new() received edit config prompt.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_send('N',
##TEST####BROKEN##        'checked cmd_new() say N for edit config prompt.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_like(qr/It is recommended that fetchware go ahead and install the program based on the/ms,
##TEST####BROKEN##        'checked cmd_new() received install program prompt.');
##TEST####BROKEN##
##TEST####BROKEN##    # Say no to avoid actually installing Apache yet again.
##TEST####BROKEN##    expect_send('N',
##TEST####BROKEN##        'checked cmd_new() say N for install program prompt.');
##TEST####BROKEN##
##TEST####BROKEN##    expect_quit();
##TEST####BROKEN##};
##TEST##
##TEST##} # #End of gigantic skip block.

# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
done_testing();
