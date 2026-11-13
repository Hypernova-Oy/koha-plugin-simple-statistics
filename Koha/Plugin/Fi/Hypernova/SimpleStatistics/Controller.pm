package Koha::Plugin::Fi::Hypernova::SimpleStatistics::Controller;

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

use C4::Context;
use Koha::Logger;
use Koha::Token;

use Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store;

=head2 configure

Renders the report table. Handles CSRF-protected POST actions:

=over 4

=item * deploy     - deploy a single report (un-mask)

=item * deploy_all - deploy every available (never-deployed, non-public) report

=item * update     - overwrite a deployed report with the plugin's current version

=back

=cut

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $userenv = C4::Context->userenv;
    my $borrowernumber = $userenv ? $userenv->{'number'} : undef;

    my $error;
    if ( $cgi->param('deploy') || $cgi->param('deploy_all') || $cgi->param('update') ) {
        my $ok = Koha::Token->new->check_csrf(
            {
                session_id => scalar $cgi->cookie('CGISESSID'),
                token      => scalar $cgi->param('csrf_token'),
            }
        );
        die "Wrong CSRF token\n" unless $ok;

        my $code  = $cgi->param('code') // q{};
        my $done  = 0;
        my $label = 'deploy';

        if ( $cgi->param('deploy_all') ) {
            $label = 'deploy_all';
            my $ok_action = eval {
                Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::deploy_available(
                    $self, $borrowernumber );
                1;
            };
            if ($ok_action) {
                $done = 1;
            }
            else {
                $error = $@ // 'Unknown error';
            }
        }
        elsif ( $cgi->param('update') ) {
            $label = 'update';
            my $ok_action = eval {
                Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::update_report(
                    $self, $code, $borrowernumber );
                1;
            };
            if ($ok_action) {
                $done = 1;
            }
            else {
                $error = $@ // 'Unknown error';
            }
        }
        else {
            my $ok_action = eval {
                Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::deploy_report(
                    $self, $code, $borrowernumber );
                1;
            };
            if ($ok_action) {
                $done = 1;
            }
            else {
                $error = $@ // 'Unknown error';
            }
        }

        if ($done) {
            print $cgi->redirect(
                '/cgi-bin/koha/plugins/run.pl?class=Koha::Plugin::Fi::Hypernova::SimpleStatistics&method=configure'
            );
            return;
        }
        Koha::Logger->get
            ->error("koha-plugin-simple-statistics: $label '$code' failed: $error");
    }

    my $reports = eval {
        Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::list_reports($self);
    };
    if ( !$reports ) {
        $error //= $@ // 'Unable to load report definitions';
        $reports = [];
    }

    my $default_language = eval {
        Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::default_language($self);
    };

    my $has_available =
        ( grep { $_->{status} eq 'available' && !$_->{public} } @$reports ) ? 1 : 0;

    my $template = $self->get_template( { file => 'configure.tt' } );
    $template->param(
        reports          => $reports,
        error            => $error,
        default_language => $default_language,
        has_available    => $has_available,
    );
    $self->output_html( $template->output() );
}

1;
