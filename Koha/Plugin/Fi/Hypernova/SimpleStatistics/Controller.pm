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

Renders the report table. Handles a POST deploy action (CSRF-protected) that
un-masks and deploys a single report, then redirects back.

=cut

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $userenv = C4::Context->userenv;
    my $borrowernumber = $userenv ? $userenv->{'number'} : undef;

    my $error;
    if ( $cgi->param('deploy') ) {
        my $ok = Koha::Token->new->check_csrf(
            {
                session_id => scalar $cgi->cookie('CGISESSID'),
                token      => scalar $cgi->param('csrf_token'),
            }
        );
        die "Wrong CSRF token\n" unless $ok;

        my $code     = $cgi->param('code') // q{};
        my $deployed = eval {
            Koha::Plugin::Fi::Hypernova::SimpleStatistics::Store::deploy_report(
                $self, $code, $borrowernumber );
            1;
        };
        if ($deployed) {
            print $cgi->redirect(
                '/cgi-bin/koha/plugins/run.pl?class=Koha::Plugin::Fi::Hypernova::SimpleStatistics&method=configure'
            );
            return;
        }
        else {
            $error = $@ // 'Unknown error';
            Koha::Logger->get
                ->error("koha-plugin-simple-statistics: deploy '$code' failed: $error");
        }
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

    my $template = $self->get_template( { file => 'configure.tt' } );
    $template->param(
        reports          => $reports,
        error            => $error,
        default_language => $default_language,
    );
    $self->output_html( $template->output() );
}

1;
