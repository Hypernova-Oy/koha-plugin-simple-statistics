#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.

BEGIN {
    $ENV{KOHA_PLUGIN_DEV_MODE} = 1;
}

use Modern::Perl;

use Test::More;
use File::Spec;
use File::Find;
use English qw( -no_match_vars );

use_ok('Koha::Plugin::Fi::Hypernova::SimpleStatistics');

my $package_path = 'Koha/Plugin/Fi/Hypernova/SimpleStatistics';
my $lib = File::Spec->rel2abs('Koha/Plugin/Fi/Hypernova/SimpleStatistics');
find(
    {
        bydepth   => 1,
        no_chdir  => 1,
        wanted    => sub {
            my $m = $_;
            return unless $m =~ s/[.]pm$//;
            $m =~ s{^.*/$package_path/}{$package_path/};
            $m =~ s{/}{::}g;
            use_ok($m) || BAIL_OUT("***** PROBLEMS LOADING FILE '$m'");
        },
    },
    $lib
);

done_testing();
