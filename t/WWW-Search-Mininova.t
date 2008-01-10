# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl WWW-Search-Mininova.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 2;
BEGIN { use_ok('WWW::Search::Mininova') };

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

#########################


