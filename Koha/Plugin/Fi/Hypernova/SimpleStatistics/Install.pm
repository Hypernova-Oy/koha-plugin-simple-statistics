package Koha::Plugin::Fi::Hypernova::SimpleStatistics::Install;

# Copyright 2026 Hypernova Oy
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;

use Class::Inspector;

use C4::Context;
use Koha::Logger;
use Koha::DateUtils;

use Koha::Plugins::Methods;
use Koha::Plugins::Method;

use Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store;

sub install {
    my ( $self, $args ) = @_;
    my $logger = Koha::Logger->get();

    eval {
        Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::create_mapping_table($self);
        _seed_permissions( C4::Context->dbh );

        my $deployed =
            Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::deploy_available( $self, undef );
        if (@$deployed) {
            $logger->info(
                "koha-plugin-simple-statistics: auto-deployed " . scalar(@$deployed) . " report(s)" );
        }

        Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::prune_mappings($self);
        _register_methods($self);
        _store_last_upgraded($self);
    };
    if ($@) {
        $logger->error("Installing koha-plugin-simple-statistics failed: $@");
        die $@;
    }

    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;
    my $logger = Koha::Logger->get();

    eval {
        Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::create_mapping_table($self);
        _seed_permissions( C4::Context->dbh );

        my $deployed =
            Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::deploy_available( $self, undef );
        if (@$deployed) {
            $logger->info(
                "koha-plugin-simple-statistics: auto-deployed " . scalar(@$deployed) . " report(s)" );
        }

        Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::sync_report_metadata( $self, undef );
        Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::prune_mappings($self);
        _register_methods($self);
        _store_last_upgraded($self);
    };
    if ($@) {
        $logger->error("Upgrading koha-plugin-simple-statistics failed: $@");
        die $@;
    }

    return 1;
}

sub uninstall {
    my ( $self, $args ) = @_;
    my $logger = Koha::Logger->get();

    eval {
        Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::drop_mapping_table($self);
        my $dbh = C4::Context->dbh;
        $dbh->do( qq{DELETE FROM permissions WHERE code = 'manage_simple_statistics'} );
        $dbh->do( "DELETE FROM plugin_data WHERE plugin_class = ?", undef, ( $self->{class} ) );
        Koha::Plugins::Methods->search( { plugin_class => $self->{class} } )->delete();
    };
    if ($@) {
        $logger->error("Uninstalling koha-plugin-simple-statistics failed: $@");
        die $@;
    }

    return 1;
}

sub _seed_permissions {
    my ($dbh) = @_;
    $dbh->do(q{
        INSERT IGNORE INTO permissions (module_bit, code, description)
        SELECT bit, ?, ? FROM userflags WHERE flag = 'reports'
    }, undef, 'manage_simple_statistics', 'Simple Statistics: deploy and update SQL reports');
}

sub _register_methods {
    my ($self) = @_;

    foreach my $method ( @{ Class::Inspector->methods( $self->{class}, 'public' ) } ) {
        next
            if Koha::Plugins::Methods->find(
            { plugin_class => $self->{class}, plugin_method => $method } );
        Koha::Plugins::Method->new(
            {
                plugin_class  => $self->{class},
                plugin_method => $method,
            }
        )->store();
    }
}

sub _store_last_upgraded {
    my ($self) = @_;
    my $dt = Koha::DateUtils::dt_from_string();
    $self->store_data( { last_upgraded => $dt->ymd('-') . ' ' . $dt->hms(':') } );
}

1;
