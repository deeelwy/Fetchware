#!perl
# bin-fetchware-new.t tests bin/fetchware's cmd_new() subroutine, which
# interactively creates new Fetchwarefiles, and optionally initially installs
# them as fetchware packages.
use strict;
use warnings;
use diagnostics;
use 5.010001;


# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '14'; #Update if this changes.

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


subtest 'test extension_name success' => sub {
    my $test_value = 'App::Fetchware';

    # Test extension_name()'s ability to set and return the one value it is
    # called with.
    is(extension_name($test_value), $test_value,
        'checked extension_name() set success.');

    # Test extension_name()'s exception when called more than just once.
    eval_ok(sub {extension_name($test_value)},
        <<EOE, 'checked extension_name() exception.');
App-Fetchware: extension_name() was called more than once. It is a singleton,
and therefore can only be called once. Please only call it once to set its
value, and then call it repeatedly wherever you need that value. see perldoc
App::Fetchware for more details.
EOE

    # Test extension_name()'s ability to return its singleton value when called
    # with nothing.
    is(extension_name(), $test_value,
        'checked extension_name() return success.');
    is(extension_name(), $test_value,
        'checked extension_name() return success.');
};


SKIP: {
    # Must be 1 less than the number of tests in the Test::More use line above.
    my $how_many = 13;
    # Skip testing if STDIN is not a terminal, or if AUTOMATED_TESTING is set,
    # which most likely means we're running under a CPAN Tester's smoker, which
    # may be chroot()ed or something else like LXC that might screw up having a
    # functional terminal.
    if (not exists $ENV{AUTOMATED_TESTING}
            and $ENV{AUTOMATED_TESTING}
            and not -t
        ) {
        skip 'Not on a terminal', $how_many; 
    }


subtest 'test opening_message() success' => sub {
    my $opening_message = "Testing...1...2...3...for opening_message().\n";
    print_ok(sub {opening_message($opening_message)},
        $opening_message, 'test opening_message() success.');
};


# Set Term::UI's AUTOREPLY to true so that it will answer with whatever default
# option I provide or if no default option is provided Term::UI will reply with
# undef.
#
# This lame hack is, so that I can test my use of Term::UI, which is just as
# untestable as Term::ReadLine with which it is based. Term::UI tests itself
# using this exact same method except it uses a default option, but I do not
# want my calls to have a default option or add some stupid wrapper to do it for
# me. This works just fine. Just remember to ignore the warning:
# You have '$AUOTREPLY' set to true, but did not provide a default!
#
# I have tried to figure out how to test this. I even posted some insane code
# that sadly does not work on perlmonks:
# http://www.perlmonks.org/?node_id=991229
$Term::UI::AUTOREPLY = 1;
###BUGALERT### Because I can't test things interactvely, even using the cool
#insane code listed in the perlmonks post above, I'm stuck using the lame
#AUTOREPLY garbage. Either figure out how to programatically press <Enter>, or
#create a interactive option for this test file similar to what Term::ReadLine
#itself does. At least add an xt/ and FETCHWARE_RELEASE_TESTING test that
#prints a lame reminder to at least test new() manually using fetchware new
#itself.


subtest 'test name_program() success' => sub {
    # Create test Term::UI object.
    my $term = Term::ReadLine->new('fetchware');

    is(name_program($term), undef,
        'checked name_program() success');
};


subtest 'test get_lookup_url() success' => sub {
    # Create test Term::UI object.
    my $term = Term::ReadLine->new('fetchware');

    is(get_lookup_url($term), undef,
        'checked get_lookup_url() success');
};


subtest 'test download_lookup_url() success' => sub {
    skip_all_unless_release_testing();

    # Create test Term::UI object.
    my $term = Term::ReadLine->new('fetchware');

    cmp_deeply(download_lookup_url($term, $ENV{FETCHWARE_HTTP_LOOKUP_URL}),
        array_each(
            re(qr/[-\w\d\._]+/),
            re(qr/\d{12}/),
        ), 'checked download_lookup_url() success.');
};



subtest 'test download_lookup_url() test-dist success' => sub {
    # Create test Term::UI object.
    my $term = Term::ReadLine->new('fetchware');

    ###Use download_dirlist() instead of get_directory_listing, which takes *NO*
    #params!!!!!!!!!!!!!!!!!!!!!!
    eval_ok(sub {download_lookup_url($term, 'badschem://fake.url')},
        <<EOE, 'checked download_lookup_url() test-dist exception');
fetchware: run-time error. The lookup_url you provided [] is not a
usable lookup_url because of the error below:
[App-Fetchware: run-time syntax error: the url parameter your provided in
your call to download_dirlist() [] does not have a supported URL scheme (the
http:// or ftp:// part). The only supported download types, schemes, are FTP and
HTTP. See perldoc App::Fetchware.
]
Please see perldoc App::Fetchware for troubleshooting tips and rerun
fetchware new.
EOE

};


subtest 'test prompt_for_other_options() success' => sub {
    plan(skip_all => 'Optional Test::Expect testing module not installed.')
        unless eval {require Test::Expect; Test::Expect->import(); 1;};

    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
    # something crazy like Test::Expect, this will have to be tested "manually."
    local $Term::UI::AUTOREPLY = 0;
    # Fix the "out of orderness" thanks to Test::Builder messing with
    # STD{OUT,ERR}.
    local $| = 1;

    # Have Expect tell me what it's doing for easier debugging.
    #$Expect::Exp_Internal = 1;

    expect_run(
        command => 't/bin-fetchware-new-prompt_for_other_options',
        prompt => [-re => qr/: |\? /],
        quit => "\cC"
    );

    # First test that the command produced the correct outout.
    expect_like(qr/Fetchware has many different configuration options that allow you to control its/,
        'checked prompt_for_other_options() received correct config options prompt');

    # Have Expect print an example URL.
    expect_send('y',
        'check prompt_for_other_options() sent Y.');

    # Check if upon receiving the URL the command prints out the next correct
    # prompt.
    # The including [y/N] below is a stupid workaround for some stupid bug in
    # Expect or in my code that I can't figure out. Fix this if you can.
    #expect_like(qr/Below is a listing of Fetchware's available configuration options./,
    expect_like(qr!\[y/N\]|Below is a listing of Fetchware's available configuration options.!,
        'checked prompt_for_other_options() received configuration options prompt.');

    # Note I have no clue what numbers will line up with what configuration
    # options, because the configuraiton options come from a hash, and hash's
    # order changes each time the program is compiled. I could parse the actual
    # output with a regex or something, but as of now I'm not.
    expect_send('1 5 9',
        'checked prompt_for_other_options() specify some configuration options.');

    # The weird regex is just so it can match any possible configuration option,
    # because due to hashes being unordered I don't know which options are which
    # numbers without complicated parsing that I'm not doing.
    expect_like(qr/[\w .,?!]+/,
        'checked prompt_for_other_options() received a specifc config option.');
    expect_send('Some test value who cares',
        'checked prompt_for_other_options() specify a specific config option.');

    expect_like(qr/[\w .,?!]+/,
        'checked prompt_for_other_options() received a specifc config option.');
    expect_send('Some test value who cares',
        'checked prompt_for_other_options() specify a specific config option.');

    expect_like(qr/[\w .,?!]+/,
        'checked prompt_for_other_options() received a specifc config option.');
    expect_send('Some test value who cares',
        'checked prompt_for_other_options() specify a specific config option.');

    expect_quit();
    
};


subtest 'test get_mirrors() success' => sub {
    skip_all_unless_release_testing();

    plan(skip_all => 'Optional Test::Expect testing module not installed.')
        unless eval {require Test::Expect; Test::Expect->import(); 1;};

    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
    # something crazy like Test::Expect, this will have to be tested "manually."
    local $Term::UI::AUTOREPLY = 0;
    # Fix the "out of orderness" thanks to Test::Builder messing with
    # STD{OUT,ERR}.
    local $| = 1;

    # Have Expect tell me what it's doing for easier debugging.
    #$Expect::Exp_Internal = 1;

    expect_run(
        command => 't/bin-fetchware-new-get_mirrors',
        prompt => [-re => qr/: |\? /],
        quit => "\cC"
    );

    # First test that the command produced the correct outout.
    expect_like(qr/Fetchware requires you to please provide a mirror. This mirror is required,/,
        'checked add_mirror() received correct mirror prompt');

    # Have Expect print an example URL.
    expect_send('http://who.cares/whatever/',
        'check add_mirror() sent mirror URL.');

    # Check if upon receiving the URL the command prints out the next correct
    # prompt.
    expect_like(qr/Would you like to add any additional mirrors?/,
        'checked get_mirrors() received more mirrors prompt.');

    expect_send('N', 'checked get_mirrors() say No to more mirrors.');

    expect_quit();

    # Test answering Yes for more mirrors.

    expect_run(
        command => 't/bin-fetchware-new-get_mirrors',
        prompt => [-re => qr/: |\? /],
        quit => "\cC"
    );

    # First test that the command produced the correct outout.
    expect_like(qr/Fetchware requires you to please provide a mirror. This mirror is required,/,
        'checked add_mirror() received correct mirror prompt');

    # Have Expect print an example URL.
    expect_send('http://who.cares/whatever/',
        'check add_mirror() sent mirror URL.');

    # Check if upon receiving the URL the command prints out the next correct
    # prompt.
    expect_like(qr/Would you like to add any additional mirrors?/,
        'checked get_mirrors() received more mirrors prompt.');

    expect_send('Y', 'checked get_mirrors() say No to more mirrors.');

    expect_like(qr!\[y/N\]|Type in URL of mirror or done to continue!,
        'checked get_mirrors() received prompt to enter a mirror.');

    expect_send('ftp://afakemirror.blah/huh?',
        'checked get_mirrors() sent another mirror URL.');

    expect_like(qr/Type in URL of mirror or done to continue/,
        'checked get_mirrors() received prompt to enter a mirror.');

    expect_send('ftp://anotherfake.mirror/kasdjlfkjd',
        'checked get_mirrors() sent another mirror URL.');

    expect_like(qr/Type in URL of mirror or done to continue/,
        'checked get_mirrors() received prompt to enter a mirror.');

    expect_send('done',
        'checked get_mirrors() sent done.');

    expect_quit();
};


subtest 'test get_verification() success' => sub {
    skip_all_unless_release_testing();

    plan(skip_all => 'Optional Test::Expect testing module not installed.')
        unless eval {require Test::Expect; Test::Expect->import(); 1;};

    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
    # something crazy like Test::Expect, this will have to be tested "manually."
    local $Term::UI::AUTOREPLY = 0;
    # Fix the "out of orderness" thanks to Test::Builder messing with
    # STD{OUT,ERR}.
    local $| = 1;

    # Have Expect tell me what it's doing for easier debugging.
    #$Expect::Exp_Internal = 1;

    expect_run(
        command => 't/bin-fetchware-new-get_verification',
        prompt => [-re => qr/: |\? /],
        quit => "\cC"
    );

    # First test that the command produced the correct outout.
    expect_like(qr/Automatic KEYS file discovery failed. Fetchware needs the/,
        'checked get_verification() received correct mirror prompt');

    # Have Expect print an example URL.
    expect_send('Y',
        'check get_verification() sent manual KEYS file Y.');

    expect_like(qr<\[y/N\]|Automatic verification of your fetchware package has failed!>,
        'check get_verification() received no verify prompt.');

    expect_send('Y',
        'checked get_verification() sent no verify Y.');


    expect_quit();

    ###BUGALERT### Add tests for get_verification()'s other branches.
};


subtest 'test get_filter_option() success' => sub {
    skip_all_unless_release_testing();

    plan(skip_all => 'Optional Test::Expect testing module not installed.')
        unless eval {require Test::Expect; Test::Expect->import(); 1;};

    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
    # something crazy like Test::Expect, this will have to be tested "manually."
    local $Term::UI::AUTOREPLY = 0;
    # Fix the "out of orderness" thanks to Test::Builder messing with
    # STD{OUT,ERR}.
    local $| = 1;

    # Have Expect tell me what it's doing for easier debugging.
    #$Expect::Exp_Internal = 1;

    expect_run(
        command => 't/bin-fetchware-new-get_filter_option',
        prompt => [-re => qr/: |\? /],
        quit => "\cC" # CTRL-C
    );

    expect_like(qr/Analyzing the lookup_url you provided to determine if fetchware/,
        'checked get_filter_option() received correct filter prompt');

    expect_send('httpd-2.2',
        'check get_filter_option() provided filter.');

    expect_quit();
};


subtest 'test edit_manually() success' => sub {
    # Create test Term::UI object.
    my $term = Term::ReadLine->new('fetchware');

    my $fetchwarefile = '# Just testing.';

    my $expected_fetchwarefile = $fetchwarefile;

###BUGALERT### I don't want to use Expect for testing in /t, but nothing is
#stopping me from using Expect for interactive testing in /xt!!!!!!!!!!!!!!
    edit_manually($term, \$fetchwarefile);
    is($fetchwarefile, $expected_fetchwarefile,
        'check add_mirrors() success');

};


subtest 'test check_fetchwarefile() success' => sub {
    eval_ok(sub {check_fetchwarefile(\'')},
        <<EOE, 'checked check_fetchwarefile() lookup_url exception');
fetchware: The Fetchwarefile fetchware generated for you does not have a
lookup_url configuration option. Please add a lookup_url configuration file such
as [lookup_url 'My Program';] The generated Fetchwarefile was [

]
EOE

    eval_ok(sub {check_fetchwarefile(\q{lookup_url 'http://a.url/';})},
        <<EOE, 'checked check_fetchwarefile() mirror exception');
fetchware: The Fetchwarefile fetchware generated for you does not have a mirror
configuration option. Please add a mirror configuration file such as
[mirror 'My Program';] The generated Fetchwarefile was [
lookup_url 'http://a.url/';
]
EOE


    my $fetchwarefile = <<EOF;
lookup_url 'http://a.url/';
mirror 'ftp://who.cares/blah/blah/blacksheep/';
EOF
    eval_ok(sub {check_fetchwarefile(\$fetchwarefile)},
        <<EOE, 'checked check_fetchwarefile() program exception');
fetchware: The Fetchwarefile fetchware generated for you does not have a program
configuration option. Please add a program configuration file such as
[program 'My Program';] The generated Fetchwarefile was [
lookup_url 'http://a.url/';
mirror 'ftp://who.cares/blah/blah/blacksheep/';

]
EOE
    $fetchwarefile .= q{program 'program';};
    print_ok(sub {check_fetchwarefile(\$fetchwarefile)},
        <<EOE, 'checked check_fetchwarefile() verify exception');
Checking your Fetchwarefile to ensure it has all of the mandatory configuration
options properly configured.
Warning: gpg verification is *not* enabled. Please switch to gpg verification if
possible, because it is more secure against hacked 3rd party mirrors.
EOE

    $fetchwarefile .= q{gpg_keys_url 'ftp://gpg.keys.urk/dir'};
    ok(check_fetchwarefile(\$fetchwarefile),
        'checked check_fetchwarefile() success.');

};

subtest 'test ask_to_install_now_to_test_fetchwarefile success' => sub {
    skip_all_unless_release_testing();
    unless ($< == 0 or $> == 0) {
        plan skip_all => 'Test suite not being run as root.'
    }

    # Create test Term::UI object.
    my $term = Term::ReadLine->new('fetchware');

my $fetchwarefile = <<EOF;
use App::Fetchware;

program 'Apache 2.2';

lookup_url '$ENV{FETCHWARE_HTTP_LOOKUP_URL}';

mirror '$ENV{FETCHWARE_FTP_MIRROR_URL}';

gpg_keys_url "$ENV{FETCHWARE_HTTP_LOOKUP_URL}/KEYS";

filter 'httpd-2.2';
EOF

note('FETCHWAREFILE');
note("$fetchwarefile");



    my $new_fetchware_package_path =
        ask_to_install_now_to_test_fetchwarefile($term, \$fetchwarefile,
            'Apache 2.2');

    ok(grep /httpd-2\.2/, glob(catfile(fetchware_database_path(), '*')),
        'check cmd_install(Fetchware) success.');

    ok(unlink $new_fetchware_package_path,
        'checked ask_to_install_now_to_test_fetchwarefile() cleanup file');

};


##BROKEN##subtest 'test cmd_new() success' => sub {
##BROKEN##    skip_all_unless_release_testing();
##BROKEN##
##BROKEN##    plan(skip_all => 'Optional Test::Expect testing module not installed.')
##BROKEN##        unless eval {require Test::Expect; Test::Expect->import(); 1;};
##BROKEN##
##BROKEN##    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
##BROKEN##    # something crazy like Test::Expect, this will have to be tested "manually."
##BROKEN##    local $Term::UI::AUTOREPLY = 0;
##BROKEN##    # Fix the "out of orderness" thanks to Test::Builder messing with
##BROKEN##    # STD{OUT,ERR}.
##BROKEN###    local $| = 1;
##BROKEN##
##BROKEN##    # Have Expect tell me what it's doing for easier debugging.
##BROKEN##    $Expect::Exp_Internal = 1;
##BROKEN##
##BROKEN##    expect_run(
##BROKEN##        command => 't/bin-fetchware-new-cmd_new',
##BROKEN###        prompt => [-re => qr/((?<!\?  \[y\/N\]): |\? )/ms],
##BROKEN##        #prompt => [-re => qr/(\?|:) \[y\/N\] |\? |: /ims],
##BROKEN###        prompt => [-re => qr/((?:\?|:) \[y\/N\]: )|\? |: /i],
##BROKEN##        prompt => [-re => qr/ \[y\/N\]: |\? |: /i],
##BROKEN###        prompt => [-re => qr/\? \n/ims],
##BROKEN##        quit => "\cC"
##BROKEN##    );
##BROKEN##
##BROKEN##    # Have Expect restart its timeout anytime output is received. Should keep
##BROKEN##    # expect from timeingout while it's waiting for Apache to compile.
##BROKEN##    #my $exp = expect_handle();
##BROKEN##    #$exp->restart_timeout_upon_receive(1);
##BROKEN##
##BROKEN##    # First test that the command produced the correct outout.
##BROKEN##    expect_like(qr/Fetchware's new command is reasonably sophisticated, and is smart enough to/ms,
##BROKEN##        'checked cmd_new() received correct name prompt');
##BROKEN##
##BROKEN##    expect_send('Apache',
##BROKEN##        'check cmd_new() sent Apache as my name.');
##BROKEN##
##BROKEN##    expect_like(qr/Fetchware's heart and soul is its lookup_url. This is the configuration option/ms,
##BROKEN##        'checked cmd_new() received lookup_url prompt.');
##BROKEN##
##BROKEN##    expect_send("$ENV{FETCHWARE_HTTP_LOOKUP_URL}",
##BROKEN##        'checked cmd_new() say lookup_url.');
##BROKEN##
##BROKEN##    expect_like(qr/Fetchware requires you to please provide a mirror. This mirror is required,/ms,
##BROKEN##        'checked cmd_new() received mirror prompt.');
##BROKEN##
##BROKEN##    expect_send("$ENV{FETCHWARE_HTTP_MIRROR_URL}",
##BROKEN##        'checked cmd_new() say mirror.');
##BROKEN##
##BROKEN##    expect_like(qr/In addition to the one required mirror that you must define in order for/ms,
##BROKEN##        'checked cmd_new() received more mirrors prompt.');
##BROKEN##
##BROKEN##    expect_send('N',
##BROKEN##        'checked cmd_new() say N for more mirrors.');
##BROKEN##
##BROKEN##    #expect_like(qr!\[y/N\]|gpg digital signatures found. Using gpg verification.!ms,
##BROKEN##    expect_like(qr!.*|gpg digital signatures found. Using gpg verification.!ms,
##BROKEN##        'checked cmd_new() received filter prompt.');
##BROKEN##
##BROKEN##    expect_send('httpd-2.2',
##BROKEN##        'checked cmd_new() say httpd-2.2 for filter option.');
##BROKEN##
##BROKEN##    expect_like(qr/Fetchware has many different configuration options that allow you to control its/ms,
##BROKEN##        'checked cmd_new() received extra config prompt.');
##BROKEN##
##BROKEN##    expect_send('N',
##BROKEN##        'checked cmd_new() say N for more config options prompt.');
##BROKEN##
##BROKEN##    expect_like(qr/Fetchware has now asked you all of the needed questions to determine what it/ms,
##BROKEN##        'checked cmd_new() received edit config prompt.');
##BROKEN##
##BROKEN##    expect_send('N',
##BROKEN##        'checked cmd_new() say N for edit config prompt.');
##BROKEN##
##BROKEN##    expect_like(qr/It is recommended that fetchware go ahead and install the program based on the/ms,
##BROKEN##        'checked cmd_new() received install program prompt.');
##BROKEN##
##BROKEN##    # Say no to avoid actually installing Apache yet again.
##BROKEN##    expect_send('N',
##BROKEN##        'checked cmd_new() say N for install program prompt.');
##BROKEN##
##BROKEN##    expect_quit();
##BROKEN##};

} # #End of gigantic skip block.

# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
