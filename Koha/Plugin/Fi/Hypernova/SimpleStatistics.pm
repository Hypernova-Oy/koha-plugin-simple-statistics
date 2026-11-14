package Koha::Plugin::Fi::Hypernova::SimpleStatistics;

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

use base qw(Koha::Plugins::Base);

use Koha::Plugin::Fi::Hypernova::SimpleStatistics::Install;
use Koha::Plugin::Fi::Hypernova::SimpleStatistics::Controller;

our $metadata = {
    name            => 'Simple Statistics',
    author          => 'Hypernova Oy',
    date_authored   => '2026-11-13',
    date_updated    => '2026-11-13',
    minimum_version => '25.11.00.000',
    maximum_version => undef,
    version         => '1.5.1',
    description     => 'Deploy and manage a curated set of SQL reports for Koha.',
    namespace       => 'simplestatistics',
};

our $VERSION = $metadata->{version};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'}            = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

sub install {
    return Koha::Plugin::Fi::Hypernova::SimpleStatistics::Install::install(@_);
}

sub uninstall {
    return Koha::Plugin::Fi::Hypernova::SimpleStatistics::Install::uninstall(@_);
}

sub upgrade {
    return Koha::Plugin::Fi::Hypernova::SimpleStatistics::Install::upgrade(@_);
}

sub configure {
    return Koha::Plugin::Fi::Hypernova::SimpleStatistics::Controller::configure(@_);
}

1;
