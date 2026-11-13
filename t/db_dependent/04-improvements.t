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

my $validate_sql  = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::validate_sql;
my $deploy_report = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::deploy_report;
my $update_report = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::update_report;
my $list_reports  = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::list_reports;
my $create_table  = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::create_mapping_table;
my $drop_table    = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::drop_mapping_table;
my $prune         = \&Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::prune_mappings;

# --- validate_sql ---
my ( $ok, $errors ) = $validate_sql->("SELECT 1");
ok( $ok, 'SELECT is valid' );
( $ok, $errors ) = $validate_sql->("DELETE FROM borrowers");
ok( !$ok, 'DELETE is rejected' );
like( join( ' ', map { ( values %$_ )[0] } @$errors ), qr/DELETE/i, 'DELETE named in error' );
( $ok, $errors ) = $validate_sql->("FOO BAR");
ok( !$ok, 'non-SELECT is rejected' );

# --- Fake plugin with a grouped report ---
{
    package FakePlugin;
    sub get_qualified_table_name { my ( $self, $t ) = @_; return "ss_imptest_$t"; }
    sub mbf_read { return <<'YAML';
reports:
  - code: demo
    name: "Demo"
    description: "Demo description"
    public: false
    group: "TestGroup"
    subgroup: "TestSubgroup"
    sql: "SELECT 1"
YAML
    }
    package main;
}
my $fake = bless {}, 'FakePlugin';

# Pre-clean
$dbh->do("DELETE FROM saved_sql WHERE report_name = 'Demo' AND borrowernumber IS NULL");
$dbh->do("DELETE FROM authorised_values WHERE category = 'REPORT_GROUP' AND authorised_value = 'TestGroup'");
$dbh->do("DELETE FROM authorised_values WHERE category = 'REPORT_SUBGROUP' AND authorised_value = 'TestSubgroup' AND lib_opac = 'TestGroup'");
$drop_table->($fake);

# --- deploy seeds AVs + records mapping ---
$create_table->($fake);
my $id = $deploy_report->( $fake, 'demo', undef );
ok( $id, 'deployed demo report' );

my ($gcount) = $dbh->selectrow_array(
    "SELECT COUNT(*) FROM authorised_values WHERE category = 'REPORT_GROUP' AND authorised_value = 'TestGroup'");
is( $gcount, 1, 'REPORT_GROUP seeded' );
my ($scount) = $dbh->selectrow_array(
    "SELECT COUNT(*) FROM authorised_values WHERE category = 'REPORT_SUBGROUP' AND authorised_value = 'TestSubgroup' AND lib_opac = 'TestGroup'");
is( $scount, 1, 'REPORT_SUBGROUP seeded' );

# --- differs flag + update to plugin version ---
my $reports = $list_reports->($fake);
my ($r) = grep { $_->{code} eq 'demo' } @$reports;
is( $r->{differs}, 0, 'not differs right after deploy' );

$dbh->do( "UPDATE saved_sql SET savedsql = 'SELECT 999' WHERE id = ?", undef, $id );
$reports = $list_reports->($fake);
($r) = grep { $_->{code} eq 'demo' } @$reports;
is( $r->{differs}, 1, 'differs after librarian edit' );

my $updated_id = $update_report->( $fake, 'demo', undef );
is( $updated_id, $id, 'update_report returns the same id' );
my ($restored) = $dbh->selectrow_array( "SELECT savedsql FROM saved_sql WHERE id = ?", undef, $id );
is( $restored, 'SELECT 1', 'SQL restored to plugin version' );
$reports = $list_reports->($fake);
($r) = grep { $_->{code} eq 'demo' } @$reports;
is( $r->{differs}, 0, 'not differs after update' );

# --- prune_mappings removes codes no longer in the YAML ---
$dbh->do( "REPLACE INTO ss_imptest_report_mappings (code, saved_sql_id) VALUES ('ghost', 999999)" );
my $removed = $prune->($fake);
is( $removed, 1, 'prune removes one orphaned mapping' );
my ($ghost) = $dbh->selectrow_array( "SELECT COUNT(*) FROM ss_imptest_report_mappings WHERE code = 'ghost'" );
is( $ghost, 0, 'ghost mapping gone' );
my ($demo) = $dbh->selectrow_array( "SELECT COUNT(*) FROM ss_imptest_report_mappings WHERE code = 'demo'" );
is( $demo, 1, 'demo mapping kept' );

# --- cleanup ---
$dbh->do( "DELETE FROM saved_sql WHERE id = ?", undef, $id );
$dbh->do("DELETE FROM authorised_values WHERE category = 'REPORT_GROUP' AND authorised_value = 'TestGroup'");
$dbh->do("DELETE FROM authorised_values WHERE category = 'REPORT_SUBGROUP' AND authorised_value = 'TestSubgroup' AND lib_opac = 'TestGroup'");
$drop_table->($fake);

done_testing();
