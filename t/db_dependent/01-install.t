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

my @report_names = (
    'Viestijono',
    'Viimeisimmät aktiiviset asiakkaat',
    'Kaikki niteiden huomautukset',
    'MARC-tietojen huomautukset',
    'Viestit, joiden lähetys on epäonnistunut',
    'Asiakkaiden tietojenkäsittelyn suostumukset',
);
my $placeholders = join ',', map {'?'} @report_names;

# --- Clean any previous state (self-cleaning test) ---
$dbh->do(
    "DELETE FROM saved_sql WHERE report_name IN ($placeholders) AND borrowernumber IS NULL",
    undef, @report_names
);
$dbh->do("DROP TABLE IF EXISTS `koha_plugin_fi_hypernova_simplestatistics_report_mappings`");
$dbh->do( "DELETE FROM plugin_data WHERE plugin_class = ?",          undef, $class );
$dbh->do( "DELETE FROM plugin_methods WHERE plugin_class = ?", undef, $class );

# --- Install ---
my $plugin = Koha::Plugin::Fi::Hypernova::SimpleStatistics->new();
ok( $plugin->retrieve_data('__INSTALLED__'), 'plugin installed' );

my ($table_count) = $dbh->selectrow_array(
    q{SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?},
    undef, 'koha_plugin_fi_hypernova_simplestatistics_report_mappings'
);
ok( $table_count, 'mapping table created' );

my $deployed = $dbh->selectall_arrayref(
    "SELECT id, report_name FROM saved_sql WHERE report_name IN ($placeholders) AND borrowernumber IS NULL ORDER BY id",
    { Slice => {} }, @report_names
);
is( scalar(@$deployed), 6, 'all 6 reports auto-deployed on install' );

my ($method_count) = $dbh->selectrow_array(
    "SELECT COUNT(*) FROM plugin_methods WHERE plugin_class = ? AND plugin_method = 'configure'",
    undef, $class
);
ok( $method_count, 'configure method registered' );

# --- Upgrade must not duplicate reports ---
$plugin->store_data( { '__INSTALLED_VERSION__' => '0.0.0' } );
$plugin = Koha::Plugin::Fi::Hypernova::SimpleStatistics->new();
is( $plugin->get_metadata->{version}, $plugin->retrieve_data('__INSTALLED_VERSION__'), 'plugin upgraded' );

my $after_upgrade = $dbh->selectall_arrayref(
    "SELECT id FROM saved_sql WHERE report_name IN ($placeholders) AND borrowernumber IS NULL",
    { Slice => {} }, @report_names
);
is( scalar(@$after_upgrade), 6, 'no duplicate reports after upgrade' );

# --- Uninstall ---
$plugin->uninstall();
ok( !$plugin->retrieve_data('__INSTALLED__'), 'plugin uninstalled' );

my ($table_after) = $dbh->selectrow_array(
    q{SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?},
    undef, 'koha_plugin_fi_hypernova_simplestatistics_report_mappings'
);
ok( !$table_after, 'mapping table dropped on uninstall' );

my ($method_after) = $dbh->selectrow_array(
    "SELECT COUNT(*) FROM plugin_methods WHERE plugin_class = ?",
    undef, $class
);
ok( !$method_after, 'methods removed on uninstall' );

my $remaining = $dbh->selectall_arrayref(
    "SELECT id FROM saved_sql WHERE report_name IN ($placeholders) AND borrowernumber IS NULL",
    { Slice => {} }, @report_names
);
is( scalar(@$remaining), 6, 'reports remain in saved_sql after uninstall (by design)' );

# --- Cleanup: remove the reports this test deployed ---
$dbh->do(
    "DELETE FROM saved_sql WHERE report_name IN ($placeholders) AND borrowernumber IS NULL",
    undef, @report_names
);

done_testing();
