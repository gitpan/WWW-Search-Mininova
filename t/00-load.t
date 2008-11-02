#!/usr/bin/env perl

use Test::More tests => 8;

BEGIN {
    use_ok('LWP::UserAgent');
    use_ok('HTML::TokeParser::Simple');
    use_ok('HTML::Entities');
    use_ok('URI');
    use_ok('Carp');
	use_ok( 'WWW::Search::Mininova' );
}

diag( "Testing WWW::Search::Mininova $WWW::Search::Mininova::VERSION, Perl $], $^X" );

use WWW::Search::Mininova;

my $mini = WWW::Search::Mininova->new;
isa_ok($mini, 'WWW::Search::Mininova');

can_ok('WWW::Search::Mininova', qw(
    new
    make_uri
    search
    _parse_search
    result
    _make_category_segment
    _make_sort_segment
    debug
    results_found
    results
    ua
    timeout
    error
    sort
    category
    did_you_mean
));