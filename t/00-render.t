#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.

use Modern::Perl;

use Test::More;
use Template;
use File::Spec;
use File::Temp qw(tempdir);

# Render configure.tt with stubbed wrapper/includes so we exercise the table
# logic (columns, badges, buttons, modal) without Koha's full auth/template stack.
my $plugin_dir = File::Spec->rel2abs('Koha/Plugin/Fi/Hypernova/SimpleStatistics');
my $tmp = tempdir( CLEANUP => 1 );

open my $fh, '>', "$tmp/wrapper-staff-tool-plugin.inc" or die $!;
print {$fh} "[% content %]\n";
close $fh;
open $fh, '>', "$tmp/csrf-token.inc" or die $!;
print {$fh} "";
close $fh;
open $fh, '>', "$tmp/datatables.inc" or die $!;
print {$fh} "";
close $fh;

my $tt = Template->new( { INCLUDE_PATH => [ $tmp, $plugin_dir ], ABSOLUTE => 1 } );

my $reports = [
    {
        code         => 'demo',
        name         => 'Demo report',
        description  => 'Demo description',
        group        => q{}, subgroup => q{},
        public       => 0,
        status       => 'available',
        deployed     => 0, masked => 0, differs => 0,
        sql          => 'SELECT 1',
        current_sql  => 'SELECT 1',
        deployed_sql => undef,
        diff         => undef,
        saved_sql_id => undef, language => undef, deployed_on => undef,
    },
    {
        code         => 'done',
        name         => 'Done report',
        description  => 'Done desc',
        group        => q{}, subgroup => q{},
        public       => 0,
        status       => 'deployed',
        deployed     => 1, masked => 0, differs => 0,
        sql          => 'SELECT 2',
        current_sql  => 'SELECT 2',
        deployed_sql => 'SELECT 2',
        diff         => undef,
        saved_sql_id => 42, language => 'fi-FI', deployed_on => '2026-11-13 10:00:00',
    },
];

my $out;
$tt->process(
    'configure.tt',
    {
        reports          => $reports,
        default_language => { code => 'fi-FI', primary => 'fi', description => 'Suomi' },
        has_available    => 1,
        CLASS            => 'Koha::Plugin::Fi::Hypernova::SimpleStatistics',
        METHOD           => 'configure',
    },
    \$out
) or die $tt->error;

like( $out, qr/Demo report/,                  'renders report name' );
like( $out, qr/Deploy/,                       'renders deploy button' );
like( $out, qr/Default staff interface language/, 'renders language banner' );
like( $out, qr/Suomi/,                         'renders language description' );
like( $out, qr/No/,                            'renders public column' );
like( $out, qr/Done report/,                   'renders deployed report name' );
like( $out, qr/Edit/,                          'renders Edit button' );
like( $out, qr/id=42&amp;op=show/,               'renders ID link to show view' );
like( $out, qr/Deployed/,                      'renders deployed status' );
like( $out, qr/Not deployed/,                  'renders not-deployed status' );
like( $out, qr/SQL/,                           'renders SQL peek button' );
like( $out, qr/simplestatistics-sql-overlay/,  'renders SQL modal' );

done_testing();
