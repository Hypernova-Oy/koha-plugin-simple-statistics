package Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store;

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

use YAML::XS qw(Load);

use C4::Context;
use C4::Reports::Guided qw(save_report);

use Koha::AuthorisedValue;
use Koha::AuthorisedValues;
use Koha::Reports;

use constant MAPPING_TABLE => 'report_mappings';

=head1 NAME

Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store

Model/service layer for the Simple Statistics plugin: loads the bundled report
definitions, tracks the code -> saved_sql.id mapping, deploys reports and
detects masked reports.

=cut

=head2 mapping_table

The qualified name of the code -> saved_sql.id mapping table.

=cut

sub mapping_table {
    my ($self) = @_;
    return $self->get_qualified_table_name(MAPPING_TABLE);
}

=head2 create_mapping_table / drop_mapping_table

Create/drop the code -> saved_sql.id mapping table.

=cut

sub create_mapping_table {
    my ($self) = @_;
    my $dbh   = C4::Context->dbh;
    my $table = $self->mapping_table;
    $dbh->do(qq{
        CREATE TABLE IF NOT EXISTS `$table` (
            `code`         varchar(255) NOT NULL,
            `saved_sql_id` int(11)      NOT NULL,
            `deployed_on`  datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`code`),
            KEY `saved_sql_id` (`saved_sql_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    });
    return $table;
}

sub drop_mapping_table {
    my ($self) = @_;
    my $dbh   = C4::Context->dbh;
    my $table = $self->mapping_table;
    $dbh->do("DROP TABLE IF EXISTS `$table`");
}

=head2 load_definitions

Read the bundled sql-reports.yaml and return an arrayref of report definition
hashrefs (code, name, description, group, subgroup, public, sql).

=cut

sub load_definitions {
    my ($self) = @_;

    my $yaml = $self->mbf_read('sql-reports.yaml');
    die "Unable to read bundled sql-reports.yaml\n" unless defined $yaml;

    my $data    = Load($yaml);
    my $reports = $data->{reports};
    die "Invalid sql-reports.yaml: missing 'reports' list\n"
        unless ref($reports) eq 'ARRAY';

    my %seen;
    my @defs;
    for my $r (@$reports) {
        my $code = $r->{code};
        die "Invalid sql-reports.yaml: each report needs a 'code'\n"
            unless defined $code && $code ne q{};
        die "Invalid sql-reports.yaml: duplicate code '$code'\n"
            if $seen{$code}++;
        die "Invalid sql-reports.yaml: report '$code' needs 'sql'\n"
            unless defined $r->{sql} && $r->{sql} =~ /\S/;

        push @defs, {
            code        => $code,
            name        => $r->{name} // $code,
            description => $r->{description} // q{},
            group       => $r->{group} // q{},
            subgroup    => $r->{subgroup} // q{},
            public      => $r->{public} ? 1 : 0,
            sql         => $r->{sql},
        };
    }

    return \@defs;
}

=head2 get_definition

Return a single report definition by code, or undef.

=cut

sub get_definition {
    my ( $self, $code ) = @_;
    my $defs = $self->load_definitions;
    for my $def (@$defs) {
        return $def if $def->{code} eq $code;
    }
    return undef;
}

=head2 get_mappings

Return a hashref { code => { saved_sql_id, deployed_on } }.

=cut

sub get_mappings {
    my ($self) = @_;
    my $dbh   = C4::Context->dbh;
    my $table = $self->mapping_table;
    my $rows  = $dbh->selectall_arrayref(
        "SELECT code, saved_sql_id, deployed_on FROM `$table`",
        { Slice => {} }
    );
    my %map;
    $map{ $_->{code} } = $_ for @$rows;
    return \%map;
}

=head2 set_mapping

Record (or update) the saved_sql.id for a report code.

=cut

sub set_mapping {
    my ( $self, $code, $saved_sql_id ) = @_;
    my $dbh   = C4::Context->dbh;
    my $table = $self->mapping_table;
    $dbh->do(
        "REPLACE INTO `$table` (code, saved_sql_id) VALUES (?,?)",
        undef, $code, $saved_sql_id
    );
}

=head2 seed_report_av

Ensure the REPORT_GROUP / REPORT_SUBGROUP authorised values exist for a
report's group/subgroup so Koha can render their labels. A subgroup requires
a group.

=cut

sub seed_report_av {
    my ( $self, $group, $subgroup ) = @_;

    return unless defined $group && $group ne q{};

    my $group_exists = Koha::AuthorisedValues->search(
        { category => 'REPORT_GROUP', authorised_value => $group }
    )->count;
    unless ($group_exists) {
        eval {
            Koha::AuthorisedValue->new(
                {
                    category         => 'REPORT_GROUP',
                    authorised_value => $group,
                    lib              => $group,
                }
            )->store;
        };
    }

    return unless defined $subgroup && $subgroup ne q{};

    my $subgroup_exists = Koha::AuthorisedValues->search(
        {
            category         => 'REPORT_SUBGROUP',
            authorised_value => $subgroup,
            lib_opac         => $group,
        }
    )->count;
    unless ($subgroup_exists) {
        eval {
            Koha::AuthorisedValue->new(
                {
                    category         => 'REPORT_SUBGROUP',
                    authorised_value => $subgroup,
                    lib              => $subgroup,
                    lib_opac         => $group,
                }
            )->store;
        };
    }
}

=head2 deploy_report

Deploy a single report to koha.saved_sql and record its id in the mapping
table. Un-masks a previously masked report. Idempotent: if the report is
already deployed, returns the existing id without creating a duplicate.

=cut

sub deploy_report {
    my ( $self, $code, $borrowernumber ) = @_;

    my $def = $self->get_definition($code)
        or die "Unknown report code: $code\n";

    # Idempotent: if this code is already deployed (its saved_sql row still
    # exists), return the existing id instead of creating a duplicate.
    my $mappings = $self->get_mappings;
    if ( exists $mappings->{$code} ) {
        my $existing_id = $mappings->{$code}{saved_sql_id};
        return $existing_id if Koha::Reports->find($existing_id);
    }

    $self->seed_report_av( $def->{group}, $def->{subgroup} );

    my $id = save_report(
        {
            borrowernumber => $borrowernumber,
            sql            => $def->{sql},
            name           => $def->{name},
            notes          => $def->{description},
            group          => ( $def->{group} ne q{} ? $def->{group} : undef ),
            subgroup       => ( $def->{subgroup} ne q{} ? $def->{subgroup} : undef ),
            cache_expiry   => 300,
            public         => $def->{public},
        }
    );

    $self->set_mapping( $code, $id );

    return $id;
}

=head2 deploy_available

Auto-deploy every non-public report that has not been seen before (neither
deployed nor masked). Used on install/upgrade. Returns the list of newly
deployed reports.

=cut

sub deploy_available {
    my ( $self, $borrowernumber ) = @_;

    my $defs     = $self->load_definitions;
    my $mappings = $self->get_mappings;

    my @deployed;
    for my $def (@$defs) {
        next if $def->{public};                     # never auto-deploy public reports
        next if exists $mappings->{ $def->{code} }; # already seen (deployed or masked)
        my $id = $self->deploy_report( $def->{code}, $borrowernumber );
        push @deployed, { code => $def->{code}, saved_sql_id => $id };
    }

    return \@deployed;
}

=head2 list_reports

Return the full list of reports with their deployment status. Status is one of:

=over 4

=item * deployed  - present in koha.saved_sql

=item * masked    - previously deployed but missing from koha.saved_sql

=item * available - never deployed

=back

=cut

sub list_reports {
    my ($self) = @_;

    my $defs     = $self->load_definitions;
    my $mappings = $self->get_mappings;

    my @reports;
    for my $def (@$defs) {
        my $status = 'available';
        my $saved_sql_id;
        my $deployed_on;

        if ( exists $mappings->{ $def->{code} } ) {
            my $m        = $mappings->{ $def->{code} };
            $saved_sql_id = $m->{saved_sql_id};
            $deployed_on  = $m->{deployed_on};
            my $report = Koha::Reports->find($saved_sql_id);
            $status    = $report ? 'deployed' : 'masked';
        }

        push @reports, {
            %$def,
            saved_sql_id => $saved_sql_id,
            deployed_on  => $deployed_on,
            status       => $status,
        };
    }

    return \@reports;
}

1;
