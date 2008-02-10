#!perl

use strict;
use warnings;

die "Usage: mini.pl <search_term>\n"
    unless @ARGV;

use lib '../lib';
use WWW::Search::Mininova;

my $mini = WWW::Search::Mininova->new;

$mini->search(shift);

if ( defined $mini->did_you_mean ) {
    print "Did you mean to search for "
        . $mini->did_you_mean . "?\n";
}

print "Found " . $mini->results_found . " results\n";
foreach my $result ( @{ $mini->results } ) {
    print "\n";
    if ( $result->{is_private} ) {
        print "Private tracker\n";
    }
    print <<"END_RESULT_DATA";
    Torrent name: $result->{name}
    Number of seeds: $result->{seeds}
    Number of leechers: $result->{leechers}
    Torrent page: $result->{uri}
    Download URI: $result->{download_uri}
    Torrent size: $result->{size}
    Category: $result->{category}
    Sub category: $result->{subcategory}
    Was added on: $result->{added_date}

END_RESULT_DATA
}