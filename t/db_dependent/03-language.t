#!/usr/bin/env perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.

BEGIN {
    $ENV{VERBOSE} = 1;
    $ENV{KOHA_PLUGIN_DEV_MODE} = 1;
}

use Modern::Perl;
use utf8;

use Test::More;
use C4::Context;
use Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store;

my $dbh = C4::Context->dbh;

my $default_language = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::default_language;
my $load_definitions = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::load_definitions;
my $resolve_text     = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::resolve_text;
my $localize_sql     = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::localize_sql;
my $sql_hash         = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::sql_hash;
my $deploy_report    = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::deploy_report;
my $create_table     = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::create_mapping_table;
my $drop_table       = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::drop_mapping_table;
my $get_mappings     = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::get_mappings;

my $orig_pref = C4::Context->preference('StaffInterfaceLanguages');
my $orig_lang = C4::Context->preference('language');

sub set_langs {
    my ( $staff, $lang ) = @_;
    C4::Context->set_preference( 'StaffInterfaceLanguages', $staff );
    C4::Context->set_preference( 'language',               $lang );
}

# A fake plugin with a translated + alias-bearing report.
{
    package FakePlugin;
    sub get_qualified_table_name { my ( $self, $t ) = @_; return "ss_langtest_$t"; }
    sub mbf_read { return <<'YAML';
reports:
  - code: demo
    name: "Demo"
    description: "English description"
    public: false
    translations:
      fi-FI:
        name: "Demot"
        description: "Suomenkielinen kuvaus"
        aliases:
          "First name": "Etunimi"
          "Surname": "Sukunimi"
      sv:
        name: "Demo (sv)"
    sql: |
      SELECT firstname AS 'First name', surname AS 'Surname' FROM borrowers
YAML
    }
    package main;
}

my $fake = bless {}, 'FakePlugin';

# --- default_language detection ---
set_langs( 'fi-FI', 'fi-FI' );
my $dl = $default_language->($fake);
is( $dl->{code},    'fi-FI', 'default code from StaffInterfaceLanguages' );
is( $dl->{primary}, 'fi',    'primary subtag' );
ok( $dl->{description}, 'description resolved' );

set_langs( 'en,fi-FI', 'en' );
$dl = $default_language->($fake);
is( $dl->{code}, 'en', 'topmost language wins' );

set_langs( '', 'sv-SE' );
$dl = $default_language->($fake);
is( $dl->{code}, 'sv-SE', 'falls back to the legacy language syspref' );

set_langs( '', '' );
$dl = $default_language->($fake);
is( $dl->{code}, 'en', 'falls back to English' );

# --- resolve_text fallback chain ---
my $def = ( $load_definitions->($fake) )->[0];
my $fi = $resolve_text->( $def, 'fi-FI' );
is( $fi->{name}, 'Demot', 'exact code translation used' );
my $sv = $resolve_text->( $def, 'sv-SE' );
is( $sv->{name}, 'Demo (sv)', 'primary subtag translation used' );
my $de = $resolve_text->( $def, 'de-DE' );
is( $de->{name}, 'Demo', 'English fallback used' );

# --- localize_sql alias substitution ---
my $sql_fi = $localize_sql->( $def, 'fi-FI' );
like( $sql_fi, qr/AS 'Etunimi'/,  'single-quoted alias localized' );
like( $sql_fi, qr/AS 'Sukunimi'/,  'second alias localized' );
unlike( $sql_fi, qr/First name/,   'English alias replaced' );

my $sql_en = $localize_sql->( $def, 'en' );
like( $sql_en, qr/AS 'First name'/, 'English alias kept for en' );

# --- sql_hash comparability ---
my $h_canon = $sql_hash->( $def->{sql} );
my $h_fi    = $sql_hash->($sql_fi);
isnt( $h_canon, $h_fi, 'canonical and localized hashes differ when aliases are localized' );
my $h_ws = $sql_hash->( "  SELECT firstname AS 'First name', surname AS 'Surname'\nFROM borrowers ; " );
is( $h_canon, $h_ws, 'hash ignores whitespace and trailing semicolon' );

# --- deploy_report uses the default language ---
set_langs( 'fi-FI', 'fi-FI' );
$create_table->($fake);
my $id = $deploy_report->( $fake, 'demo', undef );
ok( $id, 'deployed demo report' );

my ( $name, $savedsql ) = $dbh->selectrow_array(
    "SELECT report_name, savedsql FROM saved_sql WHERE id = ?", undef, $id );
is( $name, 'Demot', 'deployed report name is localized' );
like( $savedsql, qr/AS 'Etunimi'/, 'deployed SQL is localized' );

my $mappings = $get_mappings->($fake);
is( $mappings->{demo}{language},           'fi-FI', 'mapping records the deploy language' );
is( $mappings->{demo}{canonical_sql_hash}, $h_canon, 'mapping records the canonical hash' );
is( $mappings->{demo}{deployed_sql_hash},  $h_fi,    'mapping records the deployed hash' );

# --- cleanup + restore ---
$dbh->do( "DELETE FROM saved_sql WHERE id = ?", undef, $id );
$drop_table->($fake);
set_langs( $orig_pref, $orig_lang );

done_testing();
