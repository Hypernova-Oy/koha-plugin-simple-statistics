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

use Digest::SHA qw(sha256_hex);
use YAML::XS   qw(Load);

use C4::Context;
use C4::Languages  qw(getLanguages regex_lang_subtags);
use C4::Reports::Guided qw(save_report);

use Koha::AuthorisedValue;
use Koha::AuthorisedValues;
use Koha::Reports;

use constant MAPPING_TABLE => 'report_mappings';

=head1 NAME

Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store

Model/service layer for the Simple Statistics plugin: loads the bundled report
definitions, localizes them for the default staff interface language, tracks
the code -> saved_sql.id mapping, deploys reports and detects masked reports.

All functions are plain service functions taking the plugin object as their
first argument. Cross-calls within this package use plain function calls
because the plugin object itself does not inherit these methods.

=cut

=head2 mapping_table

The qualified name of the code -> saved_sql.id mapping table.

=cut

sub mapping_table {
    my ($self) = @_;
    return $self->get_qualified_table_name(MAPPING_TABLE);
}

=head2 create_mapping_table / drop_mapping_table

Create/drop the code -> saved_sql.id mapping table. create_mapping_table is
idempotent and also migrates installs created before the language/hash columns
existed.

=cut

sub create_mapping_table {
    my ($self) = @_;
    my $dbh   = C4::Context->dbh;
    my $table = mapping_table($self);
    $dbh->do(qq{
        CREATE TABLE IF NOT EXISTS `$table` (
            `code`               varchar(255) NOT NULL,
            `saved_sql_id`       int(11)      NOT NULL,
            `deployed_on`        datetime     NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `language`           varchar(32)  DEFAULT NULL,
            `canonical_sql_hash` varchar(64)  DEFAULT NULL,
            `deployed_sql_hash`  varchar(64)  DEFAULT NULL,
            PRIMARY KEY (`code`),
            KEY `saved_sql_id` (`saved_sql_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    });

    # Migrate installs created before the language/hash columns existed.
    unless ( _column_exists( $dbh, $table, 'language' ) ) {
        $dbh->do("ALTER TABLE `$table` ADD COLUMN `language` varchar(32) DEFAULT NULL AFTER `deployed_on`");
    }
    unless ( _column_exists( $dbh, $table, 'canonical_sql_hash' ) ) {
        $dbh->do("ALTER TABLE `$table` ADD COLUMN `canonical_sql_hash` varchar(64) DEFAULT NULL AFTER `language`");
    }
    unless ( _column_exists( $dbh, $table, 'deployed_sql_hash' ) ) {
        $dbh->do("ALTER TABLE `$table` ADD COLUMN `deployed_sql_hash` varchar(64) DEFAULT NULL AFTER `canonical_sql_hash`");
    }

    return $table;
}

sub drop_mapping_table {
    my ($self) = @_;
    my $dbh   = C4::Context->dbh;
    my $table = mapping_table($self);
    $dbh->do("DROP TABLE IF EXISTS `$table`");
}

=head2 load_definitions

Read the bundled sql-reports.yaml and return an arrayref of report definition
hashrefs (code, name, description, group, subgroup, public, sql, translations).

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
            code         => $code,
            name         => $r->{name} // $code,
            description  => $r->{description} // q{},
            group        => $r->{group} // q{},
            subgroup     => $r->{subgroup} // q{},
            public       => $r->{public} ? 1 : 0,
            sql          => $r->{sql},
            translations => $r->{translations} // {},
        };
    }

    return \@defs;
}

=head2 get_definition

Return a single report definition by code, or undef.

=cut

sub get_definition {
    my ( $self, $code ) = @_;
    my $defs = load_definitions($self);
    for my $def (@$defs) {
        return $def if $def->{code} eq $code;
    }
    return undef;
}

=head2 get_mappings

Return a hashref { code => { saved_sql_id, deployed_on, language,
canonical_sql_hash, deployed_sql_hash } }.

=cut

sub get_mappings {
    my ($self) = @_;
    my $dbh   = C4::Context->dbh;
    my $table = mapping_table($self);
    my $rows  = $dbh->selectall_arrayref(
        "SELECT code, saved_sql_id, deployed_on, language, canonical_sql_hash, deployed_sql_hash FROM `$table`",
        { Slice => {} }
    );
    my %map;
    $map{ $_->{code} } = $_ for @$rows;
    return \%map;
}

=head2 set_mapping

Record (or update) the saved_sql.id for a report code, together with the
language and checksums used at deploy time.

=cut

sub set_mapping {
    my ( $self, $code, $saved_sql_id, $meta ) = @_;
    $meta //= {};
    my $dbh   = C4::Context->dbh;
    my $table = mapping_table($self);
    $dbh->do(
        "REPLACE INTO `$table` (code, saved_sql_id, language, canonical_sql_hash, deployed_sql_hash) VALUES (?,?,?,?,?)",
        undef, $code, $saved_sql_id,
        $meta->{language}, $meta->{canonical_sql_hash}, $meta->{deployed_sql_hash}
    );
}

=head2 default_language

Resolve the default staff interface language: the topmost language of the
StaffInterfaceLanguages system preference (falling back to the legacy
`language` preference and then 'en'). Returns
{ code, primary, description } where description is the human-readable name.

=cut

sub default_language {
    my ($self) = @_;

    my $pref = C4::Context->preference('StaffInterfaceLanguages');
    $pref = C4::Context->preference('language') if !defined $pref || $pref eq q{};
    $pref = 'en' if !defined $pref || $pref eq q{};

    my @codes = map { ( my $c = $_ ) =~ s/^\s+|\s+$//g; $c } split /,/, $pref;
    my $code = $codes[0] // 'en';

    my $primary = _primary_subtag($code) // $code;

    my $description;
    my $langs = eval { getLanguages($code) };
    if ( ref($langs) eq 'ARRAY' ) {
        for my $l (@$langs) {
            if ( ( $l->{subtag} // q{} ) eq $primary ) {
                $description = $l->{language_description};
                last;
            }
        }
    }
    $description //= $code;

    return { code => $code, primary => $primary, description => $description };
}

=head2 resolve_text

Return { name, description } for a report definition, localized for the given
language with the fallback chain: exact code -> primary subtag -> English.

=cut

sub resolve_text {
    my ( $def, $langcode ) = @_;
    my $t = _translation_for( $def, $langcode );
    return {
        name        => ( defined $t->{name} && $t->{name} ne q{} ? $t->{name} : $def->{name} ),
        description => ( defined $t->{description} ? $t->{description} : $def->{description} ),
    };
}

=head2 localize_sql

Return the SQL for a report with English column aliases rewritten for the given
language. Aliases are listed under translations.<lang>.aliases as a map of
English alias -> localized alias, and are matched after the AS keyword.

=cut

sub localize_sql {
    my ( $def, $langcode ) = @_;
    my $sql = $def->{sql};
    my $t   = _translation_for( $def, $langcode );
    my $aliases = $t->{aliases} // {};
    return $sql unless ref($aliases) eq 'HASH';

    for my $en ( keys %$aliases ) {
        my $local = $aliases->{$en};
        next unless defined $local;
        $sql =~ s/AS\s+\Q'$en'\E/AS '$local'/ig;
        $sql =~ s/AS\s+\Q"$en"\E/AS "$local"/ig;
    }

    return $sql;
}

=head2 sql_hash

Return a SHA-256 hex digest of normalized SQL, so that two semantically
identical statements hash the same regardless of whitespace/case of keywords
and trailing semicolons.

=cut

sub sql_hash {
    my ($sql) = @_;
    return sha256_hex( _normalize_sql($sql) );
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

Deploy a single report to koha.saved_sql using the default staff interface
language, and record its id, language and checksums in the mapping table.
Un-masks a previously masked report. Idempotent: if the report is already
deployed, returns the existing id without creating a duplicate.

=cut

sub deploy_report {
    my ( $self, $code, $borrowernumber ) = @_;

    my $def = get_definition( $self, $code )
        or die "Unknown report code: $code\n";

    # Idempotent: if this code is already deployed (its saved_sql row still
    # exists), return the existing id instead of creating a duplicate.
    my $mappings = get_mappings($self);
    if ( exists $mappings->{$code} ) {
        my $existing_id = $mappings->{$code}{saved_sql_id};
        return $existing_id if Koha::Reports->find($existing_id);
    }

    my $lang = default_language($self);
    my $text = resolve_text( $def, $lang->{code} );
    my $sql  = localize_sql( $def, $lang->{code} );

    seed_report_av( $self, $def->{group}, $def->{subgroup} );

    my $id = save_report(
        {
            borrowernumber => $borrowernumber,
            sql            => $sql,
            name           => $text->{name},
            notes          => $text->{description},
            group          => ( $def->{group} ne q{} ? $def->{group} : undef ),
            subgroup       => ( $def->{subgroup} ne q{} ? $def->{subgroup} : undef ),
            cache_expiry   => 300,
            public         => $def->{public},
        }
    );

    set_mapping(
        $self, $code, $id,
        {
            language           => $lang->{code},
            canonical_sql_hash => sql_hash( $def->{sql} ),
            deployed_sql_hash  => sql_hash($sql),
        }
    );

    return $id;
}

=head2 deploy_available

Auto-deploy every non-public report that has not been seen before (neither
deployed nor masked). Used on install/upgrade. Returns the list of newly
deployed reports.

=cut

sub deploy_available {
    my ( $self, $borrowernumber ) = @_;

    my $defs     = load_definitions($self);
    my $mappings = get_mappings($self);

    my @deployed;
    for my $def (@$defs) {
        next if $def->{public};                     # never auto-deploy public reports
        next if exists $mappings->{ $def->{code} }; # already seen (deployed or masked)
        my $id = deploy_report( $self, $def->{code}, $borrowernumber );
        push @deployed, { code => $def->{code}, saved_sql_id => $id };
    }

    return \@deployed;
}

=head2 list_reports

Return the full list of reports localized for the default staff interface
language, with their deployment status. Status is one of:

=over 4

=item * deployed  - present in koha.saved_sql

=item * masked    - previously deployed but missing from koha.saved_sql

=item * available - never deployed

=back

=cut

sub list_reports {
    my ($self) = @_;

    my $defs     = load_definitions($self);
    my $mappings = get_mappings($self);
    my $lang     = default_language($self);

    my @reports;
    for my $def (@$defs) {
        my $text   = resolve_text( $def, $lang->{code} );
        my $status = 'available';
        my ( $saved_sql_id, $deployed_on, $language );

        if ( exists $mappings->{ $def->{code} } ) {
            my $m        = $mappings->{ $def->{code} };
            $saved_sql_id = $m->{saved_sql_id};
            $deployed_on  = $m->{deployed_on};
            $language     = $m->{language};
            my $report = Koha::Reports->find($saved_sql_id);
            $status    = $report ? 'deployed' : 'masked';
        }

        push @reports, {
            code         => $def->{code},
            name         => $text->{name},
            description  => $text->{description},
            group        => $def->{group},
            subgroup     => $def->{subgroup},
            public       => $def->{public},
            sql          => $def->{sql},
            saved_sql_id => $saved_sql_id,
            deployed_on  => $deployed_on,
            language     => $language,
            status       => $status,
            deployed     => ( $status eq 'deployed' ? 1 : 0 ),
            masked       => ( $status eq 'masked'   ? 1 : 0 ),
        };
    }

    return \@reports;
}

=head2 _translation_for

Return the translations hash for the best-matching language (exact code, then
primary subtag), or an empty hash.

=cut

sub _translation_for {
    my ( $def, $langcode ) = @_;
    my $t = $def->{translations} // {};
    return {} unless ref($t) eq 'HASH';

    if ( defined $langcode && exists $t->{$langcode} && ref( $t->{$langcode} ) eq 'HASH' ) {
        return $t->{$langcode};
    }

    my $primary = _primary_subtag($langcode);
    if ( defined $primary && exists $t->{$primary} && ref( $t->{$primary} ) eq 'HASH' ) {
        return $t->{$primary};
    }

    return {};
}

=head2 _primary_subtag

Return the primary language subtag of an RFC4646 code ('fi-FI' -> 'fi').

=cut

sub _primary_subtag {
    my ($code) = @_;
    return undef unless defined $code && $code ne q{};
    my $s = eval { regex_lang_subtags($code) };
    return $s->{language} if $s && $s->{language};
    return lc( ( split /-/, $code )[0] );
}

=head2 _normalize_sql

Collapse whitespace and strip a trailing semicolon so equivalent statements
produce comparable hashes.

=cut

sub _normalize_sql {
    my ($sql) = @_;
    return q{} unless defined $sql;
    $sql =~ s/;\s*$//;
    $sql =~ s/\s+/ /g;
    $sql =~ s/^\s+|\s+$//g;
    return $sql;
}

=head2 _column_exists

True if the given column exists on the given table in the current database.

=cut

sub _column_exists {
    my ( $dbh, $table, $column ) = @_;
    my ($count) = $dbh->selectrow_array(
        'SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?',
        undef, $table, $column
    );
    return $count ? 1 : 0;
}

1;
