use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'WWW::Search::Mininova',
    license             => 'perl',
    dist_author         => 'Zoffix Znet <zoffix@cpan.org>',
    dist_version_from   => 'lib/WWW/Search/Mininova.pm',
    build_requires => {
        'Test::More' => 0,
        'Test::Kwalitee' => 0,
        'Test::Pod'      => 1.22,
        'Test::Pod::Coverage' => 1.08,
        'Pod::Coverage'       => 0.18,
    },
    requires => {
        'LWP::UserAgent'           => 2.036,
        'HTML::TokeParser::Simple' => 3.15,
        'HTML::Entities'           => 1.35,
        'URI'                      => 1.35,
        'Carp'                     => 1.04,
    },
    add_to_cleanup      => [ 'WWW-Search-Mininova-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
