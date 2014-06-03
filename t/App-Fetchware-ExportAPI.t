#!perl
# App-Fetchware-ExportAPI.t tests App::Fetchware::ExportAPI, which is a helper
# class for fetchware extensions.
use strict;
use warnings;
use diagnostics;
use 5.010001;

# Test::More version 0.98 is needed for proper subtest support.
use Test::More 0.98 tests => '5'; #Update if this changes.

use Test::Fetchware ':TESTING';

# Set PATH to a known good value.
$ENV{PATH} = '/usr/local/bin:/usr/bin:/bin';
# Delete *bad* elements from environment to make it safer as recommended by
# perlsec.
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

# Test if I can load the module "inside a BEGIN block so its functions are exported
# and compile-time, and prototypes are properly honored."
# There is no ':OVERRIDE_START' to bother importing.
BEGIN { use_ok('App::Fetchware::ExportAPI'); }


subtest 'Test _export_api() exceptions.' => sub {
    package ExceptionPackage;
    use Test::Fetchware ':TESTING';
    my $caller = 'ExceptionPackage';
    eval_ok(sub {App::Fetchware::ExportAPI::_export_api($caller, KEEP => [],
                OVERRIDE => []);},
        <<EOE, 'checked _export_api() not all API subs specified.');
App-Fetchware-Util: export_api() must be called with either or both of the KEEP
and OVERRIDE options, and you must supply the names of all of fetchware's API
subroutines to either one of these 2 options.
EOE

    eval_ok(sub {App::Fetchware::ExportAPI::_export_api($caller, KEEP => [qw(new)])},
        <<EOE, 'checked _export_api() no KEEPing new.');
App-Fetchware-ExportAPI: Your call to _export_api() (or ExportAPI's import())
was called with [new] API subroutine specified as KEEP API a
subroutine. This is not allowed, because each fetchware extension must create
its own new() or new_install() subroutines, because App::Fetchware's own new()
and new_install() API subroutines are much too specific to App::Fetchware's
requirements that no amount of configuration options or subroutine arguments
would allow them to be usable by anyother App::Fetchware extension.

If you do not want to implement new() and new_install() for your App::Fetchware
extension, then please just implement them to throw an exception that your
extension does not support Fetchware's new command, and inform them that they'll
have to manually create a Fetchwarefile for your App::Fetchware extension.
EOE
    eval_ok(sub {App::Fetchware::ExportAPI::_export_api($caller, KEEP => [qw(new_install)])},
        <<EOE, 'checked _export_api() no KEEPing new_install.');
App-Fetchware-ExportAPI: Your call to _export_api() (or ExportAPI's import())
was called with [new_install] API subroutine specified as KEEP API a
subroutine. This is not allowed, because each fetchware extension must create
its own new() or new_install() subroutines, because App::Fetchware's own new()
and new_install() API subroutines are much too specific to App::Fetchware's
requirements that no amount of configuration options or subroutine arguments
would allow them to be usable by anyother App::Fetchware extension.

If you do not want to implement new() and new_install() for your App::Fetchware
extension, then please just implement them to throw an exception that your
extension does not support Fetchware's new command, and inform them that they'll
have to manually create a Fetchwarefile for your App::Fetchware extension.
EOE
    eval_ok(sub {App::Fetchware::ExportAPI::_export_api($caller, KEEP => [qw(new new_install)])},
        <<EOE, 'checked _export_api() no KEEPing both new and new_install.');
App-Fetchware-ExportAPI: Your call to _export_api() (or ExportAPI's import())
was called with [new] API subroutine specified as KEEP API a
subroutine. This is not allowed, because each fetchware extension must create
its own new() or new_install() subroutines, because App::Fetchware's own new()
and new_install() API subroutines are much too specific to App::Fetchware's
requirements that no amount of configuration options or subroutine arguments
would allow them to be usable by anyother App::Fetchware extension.

If you do not want to implement new() and new_install() for your App::Fetchware
extension, then please just implement them to throw an exception that your
extension does not support Fetchware's new command, and inform them that they'll
have to manually create a Fetchwarefile for your App::Fetchware extension.
EOE

    package main;
};


subtest 'Test _export_api() success.' => sub {
    package TestPackage;
    use App::Fetchware::Util ':UTIL';
    # I must load App::Fetchware, because export_api() will try to copy its API
    # subs into Test::Package's namespace.
    use App::Fetchware ();

    my $caller = 'TestPackage';
    
    my @api_subs
        = qw(check_syntax start lookup download verify unarchive build install end uninstall upgrade);
    App::Fetchware::ExportAPI::_export_api($caller, KEEP => \@api_subs);

    package main;
    # Test that _export_api() exports Exporter's import() into its caller's
    # package. This is *extremely* important, because if this does not happen,
    # then the caller's package will not have a import(), and will be unable to
    # export its fetchware API subroutines, and won't work properly.
    ok(TestPackage->can('import'),
        'checked _export_api() import() method creation.');
    export_ok(\@api_subs, \@TestPackage::EXPORT);

    package TestPackage2;
    use App::Fetchware::Util ':UTIL';
    sub check_syntax { return 'nothing'; }
    sub start { return 'nothing'; }
    sub lookup { return 'nothing'; }
    sub download { return 'nothing'; }
    sub verify { return 'nothing'; }
    sub unarchive { return 'nothing'; }
    sub build { return 'nothing'; }
    sub install { return 'nothing'; }
    sub end {return 'nothing'; }
    sub uninstall { return 'nothing'; }
    sub upgrade { return 'nothing'; }

    $caller = 'TestPackage2';

    App::Fetchware::ExportAPI::_export_api($caller, OVERRIDE => \@api_subs);


    package main;
    # Test that _export_api() exports Exporter's import() into its caller's
    # package. This is *extremely* important, because if this does not happen,
    # then the caller's package will not have a import(), and will be unable to
    # export its fetchware API subroutines, and won't work properly.
    ok(TestPackage2->can('import'),
        'checked _export_api() import() method creation.');
    
    export_ok(\@api_subs, \@TestPackage2::EXPORT);
};


subtest 'Test import() success.' => sub {
    # Must call import() as a class method.
    package TestPackage3;
    use App::Fetchware::Util ':UTIL';
    # I must load App::Fetchware, because export_api() will try to copy its API
    # subs into Test::Package's namespace.
    use App::Fetchware ();
    my @api_subs
        = qw(check_syntax start lookup download verify unarchive build install end uninstall upgrade);
    App::Fetchware::ExportAPI->import(KEEP => \@api_subs);

    package main;
    # Test that _export_api() exports Exporter's import() into its caller's
    # package. This is *extremely* important, because if this does not happen,
    # then the caller's package will not have a import(), and will be unable to
    # export its fetchware API subroutines, and won't work properly.
    ok(TestPackage3->can('import'),
        'checked _export_api() import() method creation.');

    export_ok(\@api_subs, \@TestPackage3::EXPORT);

    package TestPackage4;
    use App::Fetchware::Util ':UTIL';
    sub check_syntax { return 'nothing'; }
    sub start { return 'nothing'; }
    sub lookup { return 'nothing'; }
    sub download { return 'nothing'; }
    sub verify { return 'nothing'; }
    sub unarchive { return 'nothing'; }
    sub build { return 'nothing'; }
    sub install { return 'nothing'; }
    sub end {return 'nothing'; }
    sub uninstall { return 'nothing'; }
    sub upgrade { return 'nothing'; }
    App::Fetchware::ExportAPI->import(OVERRIDE => \@api_subs);

    package main;
    # Test that _export_api() exports Exporter's import() into its caller's
    # package. This is *extremely* important, because if this does not happen,
    # then the caller's package will not have a import(), and will be unable to
    # export its fetchware API subroutines, and won't work properly.
    ok(TestPackage4->can('import'),
        'checked _export_api() import() method creation.');
    
    export_ok(\@api_subs, \@TestPackage4::EXPORT);
};


subtest 'Test use App::Fetchware::ExportAPI.' => sub {
    package TestPackage5;
    use App::Fetchware::Util ':UTIL';
    # I must load App::Fetchware, because export_api() will try to copy its API
    # subs into Test::Package's namespace.
    use App::Fetchware ();

    my @api_subs
        = qw(check_syntax start lookup download verify unarchive build install end uninstall upgrade);

    use App::Fetchware::ExportAPI
        KEEP => [qw(check_syntax start lookup download verify unarchive build install end uninstall upgrade)];
# For debugging--you can't debug begin blocks and use's.
#    require App::Fetchware::ExportAPI;
#    App::Fetchware::ExportAPI->import(KEEP => \@api_subs);

    package main;
    # Test that _export_api() exports Exporter's import() into its caller's
    # package. This is *extremely* important, because if this does not happen,
    # then the caller's package will not have a import(), and will be unable to
    # export its fetchware API subroutines, and won't work properly.
    ok(TestPackage5->can('import'),
        'checked _export_api() import() method creation.');

    export_ok(\@api_subs, \@TestPackage5::EXPORT);

    package TestPackage6;
    use App::Fetchware::Util ':UTIL';
    sub check_syntax { return 'nothing'; }
    sub start { return 'nothing'; }
    sub lookup { return 'nothing'; }
    sub download { return 'nothing'; }
    sub verify { return 'nothing'; }
    sub unarchive { return 'nothing'; }
    sub build { return 'nothing'; }
    sub install { return 'nothing'; }
    sub end {return 'nothing'; }
    sub uninstall { return 'nothing'; }
    sub upgrade { return 'nothing'; }
    use App::Fetchware::ExportAPI

        OVERRIDE => [qw(check_syntax start lookup download verify unarchive build install end uninstall upgrade)];
# For debugging--you can't debug begin blocks and use's.
#    require App::Fetchware::ExportAPI;
#    App::Fetchware::ExportAPI->import(OVERRIDE => \@api_subs);

    package main;
    # Test that _export_api() exports Exporter's import() into its caller's
    # package. This is *extremely* important, because if this does not happen,
    # then the caller's package will not have a import(), and will be unable to
    # export its fetchware API subroutines, and won't work properly.
    ok(TestPackage6->can('import'),
        'checked _export_api() import() method creation.');
    
    export_ok(\@api_subs, \@TestPackage6::EXPORT);
};


# Remove this or comment it out, and specify the number of tests, because doing
# so is more robust than using this, but this is better than no_plan.
#done_testing();
