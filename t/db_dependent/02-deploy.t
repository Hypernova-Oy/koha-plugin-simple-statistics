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
use Koha::Plugin::Fi::Hypernova::SimpleStatistics;
use Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store;

my $dbh   = C4::Context->dbh;
my $class = 'Koha::Plugin::Fi::Hypernova::SimpleStatistics';
my $table = 'koha_plugin_fi_hypernova_simplestatistics_report_mappings';

my @report_names = (
    'Viestijono',
    'Viimeisimmät aktiiviset asiakkaat',
    'Kaikki niteiden huomautukset',
    'MARC-tietojen huomautukset',
    'Viestit, joiden lähetys on epäonnistunut',
    'Asiakkaiden tietojenkäsittelyn suostumukset',
    'Lainatilasto',
    'Säästetty raha',
    'Vuositilasto',
    'Kartunta ja poistot',
    'Uudet ja poistetut asiakkaat',
    'Tilausseuranta',
    'Hankinnat toimittajittain',
);

my $placeholders = join ',', map {'?'} @report_names;

# --- Clean any previous state ---
$dbh->do(
    "DELETE FROM saved_sql WHERE report_name IN ($placeholders) AND borrowernumber IS NULL",
    undef, @report_names
);
$dbh->do("DROP TABLE IF EXISTS `$table`");
$dbh->do("DELETE FROM plugin_data WHERE plugin_class = ?",          undef, $class);
$dbh->do("DELETE FROM plugin_methods WHERE plugin_class = ?", undef, $class);

# --- Fresh install ---
my $plugin = Koha::Plugin::Fi::Hypernova::SimpleStatistics->new();
ok( $plugin->retrieve_data('__INSTALLED__'), 'plugin installed' );

my $reports = Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::list_reports($plugin);
is( scalar(@$reports), 13, 'thirteen reports listed' );
is( ( grep { $_->{status} eq 'deployed' } @$reports ), 13, 'all reports deployed after install' );

# --- Masking: deleting a report from saved_sql marks it masked ---
my ($first) = grep { $_->{code} eq 'message-queue' } @$reports;
$dbh->do( "DELETE FROM saved_sql WHERE id = ?", undef, $first->{saved_sql_id} );

$reports = Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::list_reports($plugin);
my ($masked) = grep { $_->{code} eq 'message-queue' } @$reports;
is( $masked->{status}, 'masked', 'deleted report is masked' );
ok( !$masked->{deployed}, 'masked report is not deployed' );

# --- Masked reports are not auto-redeployed on upgrade ---
my $auto = Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::deploy_available( $plugin, undef );
is( scalar(@$auto), 0, 'masked report is not auto-redeployed' );

# --- Manual deploy un-masks and redeploys ---
my $new_id = Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::deploy_report(
    $plugin, 'message-queue', undef );
ok( $new_id, 'manual deploy returned a new saved_sql id' );

$reports = Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::list_reports($plugin);
my ($redeployed) = grep { $_->{code} eq 'message-queue' } @$reports;
is( $redeployed->{status}, 'deployed', 'manually redeployed report is deployed again' );

# --- deploy_report is idempotent ---
my $again = Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::deploy_report(
    $plugin, 'message-queue', undef );
is( $again, $new_id, 'deploy_report is idempotent' );

# --- Public reports are never auto-deployed ---
{
    package FakePlugin;
    sub get_qualified_table_name { my ( $self, $t ) = @_; return "ss_pubtest_$t"; }
    sub mbf_read { return <<'YAML';
reports:
  - code: pub-only
    name: "Public only"
    description: "public report"
    public: true
    sql: "SELECT 1"
  - code: priv-only
    name: "Private only"
    description: "private report"
    public: false
    sql: "SELECT 1"
YAML
    }
    package main;
}

my $fake = bless {}, 'FakePlugin';
Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::create_mapping_table($fake);
my $auto_pub = Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::deploy_available( $fake, undef );
is( scalar(@$auto_pub), 1, 'public report is skipped on auto-deploy' );
is( $auto_pub->[0]{code}, 'priv-only', 'only the non-public report was auto-deployed' );

# --- Cleanup ---
$dbh->do(
    "DELETE FROM saved_sql WHERE report_name IN ($placeholders) AND borrowernumber IS NULL",
    undef, @report_names
);
$dbh->do("DELETE FROM saved_sql WHERE report_name = 'Private only' AND borrowernumber IS NULL");
Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::drop_mapping_table($fake);
$plugin->uninstall();

done_testing();
