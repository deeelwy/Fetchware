#!perl
# Fetchware-override.t tests App::Fetchware's override() subroutine.
use strict;
use warnings;
use diagnostics;
use 5.010;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '4'; #Update if this changes.

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
BEGIN { use_ok('App::Fetchware', qw(:DEFAULT :TESTING)); }


# Print the subroutines that App::Fetchware imported by default when I used it.
diag("App::Fetchware's default imports [@App::Fetchware::EXPORT]");

my $class = 'App::Fetchware';

# Use extra private sub __CONFIG() to access App::Fetchware's internal state
# variable, so that I can test that the configuration subroutines work properly.
my $CONFIG = App::Fetchware::__CONFIG();

subtest 'override success' => sub {

    # Loop over the main subroutines and override them one by one with an
    # exception & once they've been tested with the exception override them with
    # nothing to test the next one.
    my @args;
    for my $sub (qw(start lookup download verify unarchive build install)) {

        # Clear last arg for new iteration.
        #$args[-1] = sub {} if @args;

        push @args, $sub, sub {};

        # Override the last subroutine ith the one that throws an exception to
        # test if its been overridden.
        $args[-1] = sub {
            die <<EOD;
Throw exception to test override.
EOD
        };

        diag("ARGS[@args]");

        eval_ok(sub {override @args},
            qr/Throw exception to test override/, "checked override $sub");

    }

};


subtest 'override no options' => sub {

    eval_ok(sub {override}, <<EOD, 'checked override no options');
App-Fetchware: syntax error: you called override with no options. It must be
called with a fake hash of name => value, pairs where the names are the names of
the Fetchwarefile steps you would like to override, and the values are a coderef
to a subroutine that implements that steps behavior. See perldoc App::Fetchware.
EOD

};



subtest 'override invalid options' => sub {

    eval_ok(sub { override __CONFIG => sub {} }, <<EOD, 'checked override invalid options');
App-Fetchware: run-time error. override was called specifying a subroutine to
override that it is not allowed to override. override is only allowed to
override App::Fetchware's *own* routines as listed in [check_lookup_config download_directory_listing parse_directory_listing determine_download_url ftp_parse_filelist http_parse_filelist lookup_by_timestamp lookup_by_versionstring lookup_determine_downloadurl download_dirlist ftp_download_dirlist http_download_dirlist download_file download_ftp_url download_http_url just_filename download_ftp_url download_http_url determine_package_path eval_ok skip_all_unless_release_testing clear_CONFIG make_clean start lookup download verify unarchive build install end gpg_verify sha1_verify md5_verify digest_verify check_archive_files].
See perldoc App::Fetchware.
EOD

};

# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
