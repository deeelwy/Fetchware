#!perl
# bin-fetchware-new.t tests bin/fetchware's cmd_new() subroutine, which
# interactively creates new Fetchwarefiles, and optionally initially installs
# them as fetchware packages.
use strict;
use warnings;
use diagnostics;
use 5.010001;


# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '17'; #Update if this changes.

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


subtest 'test opening_message() success' => sub {
   print_ok(sub {opening_message()},
       <<EOM, 'test opening_message() success.');
Fetchware's new command is reasonably sophisticated, and is smart enough to
determine based on the lookup_url you provide if it can autogenerate a
Fetchwarefile for you. If Fetchware cannot, then it will ask you more
questions regarding the information it requires to be able to build a
installable fetchware package for you. After that, fetchware will ask you if
you would like to edit the Fetchwarefile, fetchware has created for you in an
editor. If you say yes, fetchware will open a editor for you, but if you say
no, fetchware will skip the custom editing. Next, fetchware will create a test
Fetchwarefile for you, and ask you if you would like to test it by trying to
install it now. If you say yes, fetchware will install it, and if you say no,
then fetchware will print the location of the Fetchwarefile it created for
you to later use to install your application.
EOM

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
        'checked get_lookup_url() success');
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
[App-Fetchware-Util: Failed to download the specifed URL [] or path
[] using the included hostname in the url you specifed or any
mirrors. The mirrors are []. And the urls
that fetchware tried to download were [ ].
]
Please see perldoc App::Fetchware for troubleshooting tips and rerun
fetchware new.
EOE

};


subtest 'test append_to_fetchwarefile() success' => sub {
    my $fetchwarefile;

    append_to_fetchwarefile(\$fetchwarefile,
        'program', 'test-dist', 'A meaningless test example.');
    is($fetchwarefile,
        <<EOE, 'checked append_to_fetchwarefile() success.');


# A meaningless test example.
program 'test-dist';
EOE

    undef $fetchwarefile;

    # Test a description with more than 80 chars.
    append_to_fetchwarefile(\$fetchwarefile,
                'program', 'test-dist',
            q{test with more than 80 chars to test the logic that chops it up into lines that are only 80 chars long. Do you think it will work?? Well, let's hope so!
    });
    is($fetchwarefile,
        <<EOE, 'checked append_to_fetchwarefile() success.');


# test with more than 80 chars to test the logic that chops it up into lines
# that are only 80 chars long. Do you think it will work?? Well, let's hope so!
program 'test-dist';
EOE

    eval_ok(sub {append_to_fetchwarefile($fetchwarefile,
        'program', 'test-dist', 'description')},
    <<EOE, 'checked append_to_fetchwarefile() excpetion');
fetchware: run-time error. You called append_to_fetchwarefile() with a
fetchwarefile argument that is not a scalar reference. Please add the need
backslash reference operator to your call to append_to_fetchwarefile() and try
again.
EOE
};


subtest 'test prompt_for_other_options() success' => sub {
    ###BUGALERT### Add interactive tests in xt/!!!
    # Create test Term::UI object.
    my $term = Term::ReadLine->new('fetchware');

    # It returns 0, because prompt_for_other_options() returns an empty hash by
    # default if no is pressed, or AUTOREPLY is set like it is in this test. And
    # empty hash is the empty list, and the empty list in scalar context has 0
    # elements so its return value is 0.
    is(prompt_for_other_options($term), 0,
        'checked prompt_for_other_options() success.');
    
};


subtest 'test append_options_to_fetchwarefile()' => sub {
    my $fetchwarefile = '# Nothing just testing.';

    eval_ok(sub {append_options_to_fetchwarefile(
        {doesntexistever => 'test 1 2 3.'}, \$fetchwarefile);},
        <<EOE, 'checked append_options_to_fetchwarefile exception');
fetchware: append_options_to_fetchwarefile() was called with \$options that it
does not support having a description for. Please call
append_options_to_fetchwarefile() with the correct \$options, or add the new,
missing option to append_options_to_fetchwarefile()'s internal
\%config_file_description hash. \$options was:
doesntexistever test 1 2 3.
EOE

    append_options_to_fetchwarefile(
        {temp_dir => '/var/tmp',
        prefix => '/tmp',
        make_options => '-j 4'}, \$fetchwarefile);

    is($fetchwarefile, <<EOS, 'checked append_options_to_fetchwarefile() success');
# Nothing just testing.

# temp_dir specifies what temporary directory fetchware will use to download and
# build this program.
temp_dir '/var/tmp';


# make_options specifes what options fetchware should pass to make when make is
# run to build and install your software.
make_options '-j 4';


# prefix specifies what base path your software will be installed under. This
# only works for software that uses GNU AutoTools to configure itself, it uses
# ./configure.
prefix '/tmp';
EOS
};


subtest 'test add_mirrors() success' => sub {
    skip_all_unless_release_testing();

    plan(skip_all => 'Optional Test::Expect testing module not installed.')
        unless eval {use Test::Expect; 1;};

    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
    # something crazy like Test::Expect, this will have to be tested "manually."
    local $Term::UI::AUTOREPLY = 0;
    # Fix the "out of orderness" thanks to Test::Builder messing with
    # STD{OUT,ERR}.
    local $| = 1;

    # Have Expect tell me what it's doing for easier debugging.
    #$Expect::Exp_Internal = 1;

    expect_run(
        command => 't/bin-fetchware-new-add_mirrors',
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
        'checked add_mirrors() received more mirrors prompt.');

    expect_send('N', 'checked add_mirrors() say No to more mirrors.');

    expect_quit();

    # Test answering Yes for more mirrors.

    expect_run(
        command => 't/bin-fetchware-new-add_mirrors',
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
        'checked add_mirrors() received more mirrors prompt.');

    expect_send('Y', 'checked add_mirrors() say No to more mirrors.');

    expect_like(qr!\[y/N\]|Type in URL of mirror or done to continue!,
        'checked add_mirrors() received prompt to enter a mirror.');

    expect_send('ftp://afakemirror.blah/huh?',
        'checked add_mirrors() sent another mirror URL.');

    expect_like(qr/Type in URL of mirror or done to continue/,
        'checked add_mirrors() received prompt to enter a mirror.');

    expect_send('ftp://anotherfake.mirror/kasdjlfkjd',
        'checked add_mirrors() sent another mirror URL.');

    expect_like(qr/Type in URL of mirror or done to continue/,
        'checked add_mirrors() received prompt to enter a mirror.');

    expect_send('done',
        'checked add_mirrors() sent done.');

    expect_quit();
};


subtest 'test add_verification() success' => sub {
    skip_all_unless_release_testing();

    plan(skip_all => 'Optional Test::Expect testing module not installed.')
        unless eval {use Test::Expect; 1;};

    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
    # something crazy like Test::Expect, this will have to be tested "manually."
    local $Term::UI::AUTOREPLY = 0;
    # Fix the "out of orderness" thanks to Test::Builder messing with
    # STD{OUT,ERR}.
    local $| = 1;

    # Have Expect tell me what it's doing for easier debugging.
    #$Expect::Exp_Internal = 1;

    expect_run(
        command => 't/bin-fetchware-new-add_verification',
        prompt => [-re => qr/: |\? /],
        quit => "\cC"
    );

    # First test that the command produced the correct outout.
    expect_like(qr/Automatic KEYS file discovery failed. Fetchware needs the/,
        'checked add_verification() received correct mirror prompt');

    # Have Expect print an example URL.
    expect_send('Y',
        'check add_verification() sent manual KEYS file Y.');

    expect_like(qr<\[y/N\]|Automatic verification of your fetchware package has failed!>,
        'check add_verification() received no verify prompt.');

    expect_send('Y',
        'checked add_verification() sent no verify Y.');


    expect_quit();

    ###BUGALERT### Add tests for add_verification()'s other branches.
};


subtest 'test determine_mandatory_options() success' => sub {
    skip_all_unless_release_testing();

    plan(skip_all => 'Optional Test::Expect testing module not installed.')
        unless eval {use Test::Expect; 1;};

    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
    # something crazy like Test::Expect, this will have to be tested "manually."
    local $Term::UI::AUTOREPLY = 0;
    # Fix the "out of orderness" thanks to Test::Builder messing with
    # STD{OUT,ERR}.
    local $| = 1;

    # Have Expect tell me what it's doing for easier debugging.
    #$Expect::Exp_Internal = 1;

    expect_run(
        command => 't/bin-fetchware-new-mandatory_options',
        prompt => [-re => qr/: |\? /],
        quit => "\cC" # CTRL-C
    );

    expect_like(qr/Fetchware requires you to please provide a mirror. This mirror/,
        'checked add_verification() received correct mirror prompt');

    expect_send('http://somefakemirror.who/cares',
        'check determine_mandatory_options() provided mirror.');

    expect_like(qr!\[y/N\]|In addition to the one required mirror that you must!,
        'check determine_mandatory_options() received addional mirrors prompt.');

    expect_send('N',
        'checked add_verification() sent no verify Y.');

    expect_like(qr!\[y/N\]|Would you like to import the author's key yourself !,
        'checked determine_mandatory_options() received manual import of KEYS.');

    expect_send('Y',
        'checked determine_mandatory_options() sent Yes to user_keyring option');

    expect_quit();
};


subtest 'test determine_filter_option() success' => sub {
    skip_all_unless_release_testing();

    plan(skip_all => 'Optional Test::Expect testing module not installed.')
        unless eval {use Test::Expect; 1;};

    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
    # something crazy like Test::Expect, this will have to be tested "manually."
    local $Term::UI::AUTOREPLY = 0;
    # Fix the "out of orderness" thanks to Test::Builder messing with
    # STD{OUT,ERR}.
    local $| = 1;

    # Have Expect tell me what it's doing for easier debugging.
    #$Expect::Exp_Internal = 1;

    expect_run(
        command => 't/bin-fetchware-new-filter_option',
        prompt => [-re => qr/: |\? /],
        quit => "\cC" # CTRL-C
    );

    expect_like(qr/Analyzing the lookup_url you provided to determine if fetchware/,
        'checked determine_filter_option() received correct filter prompt');

    expect_send('httpd-2.2',
        'check determine_filter_option() provided filter.');

    expect_quit();
};


subtest 'test analyze_lookup_listing() success' => sub {
    skip_all_unless_release_testing();

    plan(skip_all => 'Optional Test::Expect testing module not installed.')
        unless eval {use Test::Expect; 1;};

    # Disable Term::UI's AUTOREPLY for this subtest, because unless I use
    # something crazy like Test::Expect, this will have to be tested "manually."
    local $Term::UI::AUTOREPLY = 0;
    # Fix the "out of orderness" thanks to Test::Builder messing with
    # STD{OUT,ERR}.
    local $| = 0;

    # Have Expect tell me what it's doing for easier debugging.
    #$Expect::Exp_Internal = 1;

    expect_run(
        command => 't/bin-fetchware-new-analyze_lookup_listing',
        prompt => [-re => qr/: |\? /],
        quit => "\cC" # CTRL-C
    );

    expect_like(qr/Fetchware requires you to please provide a mirror. This mirror/,
        'checked analyze_lookup_listing() received correct filter prompt');

    expect_send('http://kdjfkldjfkdj',
        'check analyze_lookup_listing() provided mirror.');

    expect_like(qr/In addition to the one required mirror that you must define/,
        'checked analyze_lookup_listing() received more mirrors prompt.');

    expect_send('N',
        'checked analyze_lookup_listing() sent No for more mirrors.');

    expect_like(qr!\[y/N\]|gpg digital signatures found. Using gpg verification.!,
        'checked analyze_lookup_listing() received KEYS question.');

    expect_send('Y',
        'checked analyze_lookup_listing() sent Y to user_keyring');

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


###BUGALERT### Actually implement this test.
#subtest 'test cmd_new() success' => sub {
    #skip_all_unless_release_testing();


#};

# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
