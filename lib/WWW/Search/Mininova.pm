package WWW::Search::Mininova;

use 5.008008;
use strict;
use warnings;
use LWP::UserAgent;
use HTML::TokeParser::Simple;
use HTML::Entities;
use URI;
use Carp;

our $VERSION = '0.02';
my $DEBUG = 0;

sub new {
    my ( $class, %args ) = @_;

    my $self = bless {}, $class;
    
    unless ( $args{ua} ) {
        $self->ua( 'Mozilla/5.0 (X11; U; Linux i686; '
                    . 'en-US; rv:1.8.1.11) Gecko/20071204 '
                    . 'Ubuntu/7.10 (gutsy) Firefox/2.0.0.11' );
    }
    
    unless ( $args{timeout} ) {
        $self->timeout( 60 );
    }
    
    keys %args;
    while ( my ( $key, $value ) = each %args ) {
        $key = lc $key;
        $self->$key( $value );
    }

    return $self;
}

sub make_uri {
    my ( $self, $what ) = @_;
    croak "No search term provied in ->make_uri"
        unless defined $what;
    
    my $uri = URI->new( 'http://www.mininova.org' );
    $uri->path_segments(
        'search',
        $what,
        $self->_make_category_segment,
        $self->_make_sort_segment,
    );
    print STDERR "Search URI: $uri\n"
        if $DEBUG;
    return $uri;
}

sub search {
    my ( $self, $what ) = @_;
    croak "No search term provied in ->search"
        unless defined $what;
        
    my $ua = LWP::UserAgent->new(
        agent => $self->ua,
        timeout => $self->timeout,
    );

    my $response = $ua->get( $self->make_uri( $what ) );
    
    if ( $response->is_success ) {
        return $self->_parse_search( $response->content );
    }
    else {
        $self->error( "Failed to fetch search results: " 
                        . $response->status_line );
        return;
    }

}

sub _parse_search {
    my ( $self, $content ) = @_;
    
    my $parser = HTML::TokeParser::Simple->new( \$content );
    my %nav = (
        get_number_of_results => 0,
        get_did_you_mean      => 0,
        is_in_results_table   => 0,
        get_added_date        => 0,
        get_category          => 0,
        is_private            => -1,
        get_name              => 0,
        get_subcategory       => 0,
        get_size              => 0,
        get_seeds             => 0,
        get_leechers          => 0,
        end_result            => 0,
    );
    my @results;
    my $results_found = 0;
    my $did_you_mean;
    my $category = $self->category || 'All';
    my %current_result;
    while ( my $t = $parser->get_token ) {
        if (    $t->is_start_tag('div')
            and $t->get_attr('id')
            and $t->get_attr('id') eq 'content'
        ) {
            $nav{get_number_of_results} = 1;
        }
        elsif ( $nav{get_number_of_results} == 1
            and $t->is_start_tag('h1')
        ) {
            $nav{get_number_of_results}++;
        }
        elsif ( $nav{get_number_of_results} == 2
            and $t->is_text
        ) {
            $results_found .= $t->as_is;
        }
        elsif ( $nav{get_number_of_results} == 2
            and $t->is_end_tag('h1')
        ) {
            ( $results_found )
                = $results_found =~ / .+ \( (\d+) \s+ torrents? \)/xi;
            $results_found ||= 0;
            @nav{ qw(get_number_of_results  get_did_you_mean ) } = (-1, 1);
        }
        elsif ( $nav{get_did_you_mean} == 1
            and $t->is_start_tag('p')
        ) {
            $nav{get_did_you_mean} = 2;
        }
        elsif ( $nav{get_did_you_mean} == 2
            and $t->is_start_tag('strong')
        ) {
            $nav{get_did_you_mean} = 3;
        }
        elsif ( $nav{get_did_you_mean} == 3
            and $t->is_start_tag('a')
        ) {
            $nav{get_did_you_mean} = 4;
        }
        elsif ( $nav{get_did_you_mean} == 4
            and $t->is_text
        ) {
            $nav{get_did_you_mean} = 0;
            $did_you_mean = decode_entities( $t->as_is );
        }
        elsif ( $nav{get_did_you_mean}
            and $t->is_end_tag('p')
        ) {
            $nav{get_did_you_mean} = 0;
        }
        elsif ( $t->is_start_tag('table')
            and $t->get_attr('class')
            and $t->get_attr('class') eq 'maintable'
        ) {
            $nav{is_in_results_table} = 1;
        }
        elsif ( $nav{is_in_results_table}
            and $t->is_start_tag('tr')
        ) {
            $nav{get_added_date} = 1;
        }
        elsif ( $nav{get_added_date} == 1
            and $t->is_start_tag('td')
        ) {
            $nav{get_added_date}++;
        }
        elsif ( $nav{get_added_date} == 2
            and $t->is_text
        ) {
            $current_result{added_date} = $t->as_is;
            $current_result{added_date} =~ s/&nbsp;/ /g;
            $nav{get_added_date} = 0;
            if ( $category eq 'All' ) {
                $nav{get_category} = 1;
            }
            else {
                $current_result{category} = $category;
                $nav{get_name} = 1;
            }
            print STDERR "Added date: $current_result{added_date}\n"
                if $DEBUG;
        }
        elsif ( $nav{get_category} == 1
            and $t->is_start_tag('a')
        ) {
            $nav{get_category} = 2;
        }
        elsif ( $nav{get_category} == 2
            and $t->is_text
        ) {
            $current_result{category} = $t->as_is;
            $current_result{category} =~ s/&nbsp;/ /g;
            @nav{ qw(get_category  get_name) } = (0, 1);
            print STDERR "Category: $current_result{category}\n"
                if $DEBUG;
        }
        elsif ( $nav{get_name}
            and $t->is_start_tag('a')
            and ( not $t->get_attr('class') )
        ) {
            $nav{get_name} = 2;
            my ( $tor_number ) = $t->get_attr('href') =~ /(\d+)$/;
            next
                unless defined $tor_number;

            $current_result{uri} = URI->new('http://www.mininova.org/');
            $current_result{uri}->path_segments( 'tor', $tor_number );

            $current_result{download_uri} 
                = URI->new('http://www.mininova.org/');
            $current_result{download_uri}->path_segments(
                'get', $tor_number
            );
        }
        elsif ( $nav{get_name} == 2
            and ( not $nav{get_sub_category} )
            and $t->is_text
        ) {
            $current_result{name} .= $t->as_is;
        }
        elsif ( $nav{get_name}
            and $t->is_start_tag('img')
            and $t->get_attr('class')
            and $t->get_attr('class') eq 'ti'
        ) {
            $current_result{is_private} = 1;
        }
        elsif ( $nav{get_name} == 2
            and $t->is_start_tag('small')
        ) {
            @nav{ qw(get_subcategory  get_name) } = (1, 0);
            $current_result{name} =~ s/&nbsp;/ /g;
        }
        elsif ( $nav{get_subcategory} == 1
            and $t->is_start_tag('a')
        ) {
            $nav{get_subcategory} = 2;
        }
        elsif ( $nav{get_subcategory} == 2 
            and $t->is_text
        ) {
            $current_result{subcategory} = $t->as_is;
            $current_result{subcategory} =~ s/&nbsp;/ /g;
            print STDERR "Subcategory: $current_result{subcategory}\n"
                if $DEBUG;
        }
        elsif ( $nav{get_subcategory} == 2
            and $t->is_end_tag('td')
        ) {
            @nav{ qw(get_name  get_size  get_subcategory) } = (0, 1, 0);
            $current_result{name} =~ s/^\s+|\s+$//g;
            $current_result{name} =~ s/&nbsp;/ /g;
            $current_result{is_private} ||= 0;
            print STDERR "Name: $current_result{name}\n"
                    . "Is private: $current_result{is_private}\n"
                if $DEBUG;
        }
        elsif ( $nav{get_size} == 1
            and $t->is_text
        ) {
            $current_result{size} = $t->as_is;
            $current_result{size} =~ s/&nbsp;/ /g;
            @nav{ qw(get_size get_seeds) } = (0, 1);
            print STDERR "Size: $current_result{size}\n"
                if $DEBUG;
        }
        elsif ( $nav{get_seeds} == 1
            and $t->is_start_tag('td')
        ) {
            $nav{get_seeds} = 2;
        }
        elsif ( $nav{get_seeds} == 2
            and $t->is_start_tag('span')
            and $t->get_attr('class')
            and ( $t->get_attr('class') eq 'g'
                or $t->get_attr('class') eq 'r'
            )
        ) {
            $nav{get_seeds} = 3;
        }
        elsif ( $nav{get_seeds} == 3
            and $t->is_text
        ) {
            $current_result{seeds} = $t->as_is;
            $current_result{seeds} =~ s/\D//g;
            @nav{ qw(get_seeds  get_leechers)  } = (0, 1);
            print STDERR "Seeds: $current_result{seeds}\n"
                if $DEBUG;
        }
        elsif ( $nav{get_seeds} == 2
            and $t->is_end_tag('td')
        ) {
            @nav{ qw(get_seeds  get_leechers) } = (0, 1);
            $current_result{seeds} = 'N/A';
        }
        elsif ( $nav{get_leechers} == 1 
            and $t->is_start_tag('td')
        ) {
            $nav{get_leechers} = 2;
        }
        elsif ( $nav{get_leechers} == 2
            and $t->is_start_tag('span')
            and $t->get_attr('class')
            and $t->get_attr('class') eq 'b'
        ) {
            $nav{get_leechers} = 3;
        }
        elsif ( $nav{get_leechers} == 3
            and $t->is_text
        ) {
            $current_result{leechers} = $t->as_is;
            $current_result{leechers} =~ s/\D//g;
            @nav{ qw(get_leechers  end_result) } = (0, 1);
        }
        elsif ( $nav{get_leechers} == 2
            and $t->is_end_tag('td')
        ) {
            @nav{ qw(get_leechers  end_result) } = (0, 1);
            $current_result{leechers} = 'N/A';
        }
        elsif ( $nav{end_result} == 1 ) {
            $nav{end_result} = 0;
            print STDERR "Leechers: $current_result{leechers}\n"
                if $DEBUG;
            decode_entities(
                @current_result{ qw(
                    is_private
                    name
                    leechers
                    size
                    seeds
                    subcategory
                    category
                    added_date
                ) }
            );
            push @results, { %current_result };
            %current_result = ();
        }
        elsif ( $nav{is_in_results_table}
            and $t->is_end_tag('table')
        ) {
            last;
        }
    }
    $self->results_found( $results_found );
    $self->results( \@results );
    $self->did_you_mean( $did_you_mean );
    my %return = (
        found => $results_found,
        results => \@results
    );
    if ( defined $did_you_mean ) {
        $return{did_you_mean} = $did_you_mean;
    }
    return \%return;
}

sub result {
    my ( $self, $result_number ) = @_;
    $result_number ||= 0;
    return @{ $self->results || [] }[ $result_number ];
}

#####
# PRIVATE METHODS
####
sub _make_category_segment {
    my $self = shift;
    my $category = $self->category || 'All';
    my %segment_for = (
        'All'       => 0,
        'Anime'     => 1,
        'Books'     => 2,
        'Games'     => 3,
        'Movies'    => 4,
        'Music'     => 5,
        'Pictures'  => 6,
        'Software'  => 7,
        'Tv shows'  => 8,
        'Other'     => 9,
        'Featured'  => 10,
    );
    return $segment_for{ $category };
}

sub _make_sort_segment {
    my $self = shift;
    my $sort = $self->sort || 'Added';
    my %segment_for = (
        'Category' => 'cat',
        'Added'    => 'added',
        'Name'     => 'name',
        'Size'     => 'size',
        'Seeds'    => 'seeds',
        'Leechers' => 'leech',
    );

    return $segment_for{ $sort };
}

#####
# ACCESSORS
####

sub debug {
    my $self = shift;
    if ( @_ ) {
        $DEBUG = shift;
    }
    return $DEBUG;
}

sub results_found {
    my $self = shift;
    if ( @_ ) {
        $self->{ RESULTS_FOUND } = shift;
    }
    return $self->{ RESULTS_FOUND };
}


sub results {
    my $self = shift;
    if ( @_ ) {
        $self->{ RESULTS } = shift;
    }
    return $self->{ RESULTS };
}

sub ua {
    my $self = shift;
    if ( @_ ) {
        $self->{ UA } = shift;
    }
    return $self->{ UA };
}

sub timeout {
    my $self = shift;
    if ( @_ ) {
        $self->{ TIMEOUT } = shift;
    }
    return $self->{ TIMEOUT };
}

sub error {
    my $self = shift;
    if ( @_ ) {
        $self->{ ERROR } = shift;
    }
    return $self->{ ERROR };
}

sub sort {
    my $self = shift;
    if ( @_ ) {
        $self->{ SORT } = ucfirst lc shift;
    }
    return $self->{ SORT };
}

sub category {
    my $self = shift;
    if ( @_ ) {
        $self->{ CATEGORY } = ucfirst lc shift;
    }
    return $self->{ CATEGORY };
}

sub did_you_mean {
    my $self = shift;
    if ( @_ ) {
        $self->{ DID_YOU_MEAN } = shift;
    }
    return $self->{ DID_YOU_MEAN };
}


1;
__END__

=head1 NAME

WWW::Search::Mininova - Interface to www.mininova.org Torrent site

=head1 SYNOPSIS

    use WWW::Search::Mininova;
    my $mini = WWW::Search::Mininova->new;
    $mini->search('foo')->{results}[0]{download_uri};
    
    use WWW::Search::Mininova;
    my $mini = WWW::Search::Mininova->new(
        category => 'Music',
        sort     => 'Seeds',
    );
    
    $mini->search('foo');
    
    if ( defined $mini->did_you_mean ) {
        print "Did you mean to search for "
            . $mini->did_you_mean . "?\n";
    }
    
    print "Found " . $mini->results_found . " results\n";
    foreach my $result ( @{ $mini->results } ) {
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


=head1 DESCRIPTION

Module provides interface to Mininova.org website. Facilitates
search and torrent URI grabber as well as statistics information.

=head1 METHODS

=head2 new

    my $mini = WWW::Search::Mininova->new;
    
    my $mini = WWW::Search::Mininova->new(
        category  => 'Music',
        sort      => 'Seeds',
        timeout   => 10,
    );

Creates and returns WWW::Search::Mininova object. The following
I<optional> arguments may be specified:

=head3 category

    { category => 'TV Shows' }

Specifies which torrent category to search. If not specified 
defaults to C<'All'>. May also be set with C<-E<gt>category> method.
Accepts the following values (I<case insenitive>):

=over 6

=item All

=item Anime

=item Books

=item Games

=item Movies

=item Music

=item Pictures

=item Software

=item TV Shows

=item Other

=item Featured

=back

=head3 sort

    { sort => 'Seeds' }

Specifies which column to sort by. If not specified defaults to
C<'Added'>. May also be set with C<-E<gt>sort> method. Accepts the
following values (B<case insensitive>):

=over 6

=item Category

=item Added

=item Name

=item Size

=item Seeds

=item Leechers

=back

Note that sorting by 'Category' in any but 'All' category searches
doesn't make much sense ;)

=head3 timeout

    { timeout => 10 }

The number of seconds to wait for the search results. Defaults to
C<60>. The value goes directly into L<LWP::UserAgent> object, might
want to read the docs of it for more details.

=head3 ua

    { ua => 'Torrent UserAgent' }

The user agent string to send when requesting search results.
Defaults to FireFox's on Ubuntu UA string. In particular:

    Mozilla/5.0 (X11; U; Linux i686 en-US; rv:1.8.1.11 Gecko/20071204 Ubuntu/7.10 (gutsy) Firefox/2.0.0.11

However, it may change in future releases.
The value goes directly into L<LWP::UserAgent> object, you might
want to read the docs of it for more details.

=head3 debug

    { debug => 1 }

When set to a true value causes some debug messages to appear on
STDERR, whether they are useful or not is another story :).
Defaults to C<0> for obvious reasons.

=head2 search

    $mini->search('foos');
    
    my $results_ref = $mini->search('foos');
    
    my $results_data_ref = $mini->search('foos')->{results};

Performs search on a given argument which must be a scalar. If an
error occures (as well if I<timeout> timeouts (see C<-E<gt>timeout>
method)) returns undef and the reason for error can be fetched with
C<-E<gt>error> method. Returns a hashref containing the following
keys (I<each of which can be fetched with separate methods, thus
storing the return value is not particularly necessary>):

=over 6

=item found

The number of results that was found. Ranges from 0 to 500.
B<Note:> the actual number of results will B<NOT> be 500, but it
will be however many results www.mininova.org displays per page.

=item results

An arrayref containing search results (items are hashref, see
RESULTS section for explanation of their keys).

=item did_you_mean

If your search triggered the "Did you mean?" annoyance this key 
will be present and the value will be the suggested correction.
Othewise the key won't be present (thus is can be checked with
C<exists>)

=back

=head2 results

    my $results_ref = $mini->results;

Note the B<plural> form. Returns a possibly empty arrayref
containing search results (items
are hashref, see RESULTS section for explanation of their keys).
Must be called B<after> the call to C<-E<gt>search> method.

=head2 result

    my $result = $mini->result(10);

Note the B<singular> form. Returns a hashref containing information
for result number provided as an argument. (B<Note:> count starts
at B<zero>, like all normal counts. Thus to get the first result
you'd call C<-E<gt>result(0)>). Returns undef if no such result
exists (or if called before the call to C<-E<gt>search> method).

=head2 results_found

    my $total_results = $mini->results_found;

Returns the total number of results for the term you searched for.
B<Note:> this will B<NOT> be the total number of items you'd get in
C<-E<gt>results> arrayref. The highest number will be however many
results www.mininova.org displays per page.

=head2 did_you_mean

    if ( defined( my $correction =  $mini->did_you_mean ) ) {
        print "Did you mean: $correction?\n";
    }

If search triggered the "Did you mean?" annoyance returns the
suggested correction, otherwise returns C<undef>.

=head2 make_uri

    my $results_uri = $mini->make_uri('foos');

Returns a L<URI> object -- link to the page with the search
results on www.mininova.org. Respects the I<category> and I<sort>
settings (see C<-E<gt>category> and C<-E<gt>sort> methods). Will
C<croak> if argument is not defined.

=head2 error

Returns an error message if an error occured, or search timed out.
See C<-E<gt>timeout> and C<-E<gt>search> methods.

=head1 ACCESSORS MUTATORS

=head2 category

    my $current_category = $mini->category;
    $mini->category('Music');

When called without an optional argument returns the current
category the search will be performed on. Note that
you must call C<-E<gt>search> method in order for changes to take
effect.
The argument can be one
of the following (case insensitive):

=over 6

=item All

=item Anime

=item Books

=item Games

=item Movies

=item Music

=item Pictures

=item Software

=item TV Shows

=item Other

=item Featured

=back

=head2 sort

    $current_sort = $mini->sort;
    $mini->sort('Size');

When called without an optional argument returns current search
sorting column. With an argument -- sets sorting column. Note that
you must call C<-E<gt>search> method in order for sorting to take
effect. The argument can be any of the following case insensitive
values:

=over 6

=item Category

=item Added

=item Name

=item Size

=item Seeds

=item Leechers

=back

Note that sorting by 'Category' in any but 'All' category searches
doesn't make much sense.

=head2 timeout

    my $current_timeout = $mini->timeout;
    $mini->timeout( 120 );

When called without an optional argument returns current value for
timeout on C<-E<gt>search> method. When called with an argument
sets timeout for L<LWP::UserAgent> object which
WWW::Search::Mininova uses to get search results. Default is C<60>. Note that timeout
does not necessarily mean the maximum time the request will last.
See documentation for L<LWP::UserAgent> for more information.

=head2 ua

    my $current_ua = $mini->ua;
    $mini->ua('Torrent Searcher');

The user agent string to send when requesting search results.
Defaults to FireFox's on Ubuntu UA string. In particular:

    Mozilla/5.0 (X11; U; Linux i686 en-US; rv:1.8.1.11 Gecko/20071204 Ubuntu/7.10 (gutsy) Firefox/2.0.0.11

However, it may change in future releases.
The value goes directly into L<LWP::UserAgent> object, you might
want to read the docs of it for more details.

=head2 debug

    my $is_debug = $mini->debug;
    $mini->debug( 1 );

When called without an argument returns the current setting. An
argument can be either a true or false value. When argument is
true, causes debugging messages to be printed to STDERR.

=head1 RESULTS

    $VAR1 = {
        'is_private' => 0,
        'name' => 'Foos',
        'size' => '112.1 MB',
        'seeds' => '25',
        'leechers' => '5',
        'added_date' => '18 Jul 07',
        'category' => 'Music'
        'subcategory' => 'Rock',
        'uri' => bless( do{\(my $o = 'http://www.mininova.org/tor/444444')}, 'URI::http' ),
        'download_uri' => bless( do{\(my $o = 'http://www.mininova.org/get/444444')}, 'URI::http' ),
    }

Each item in an arrayref from either C<-E<gt>results> method or
the key C<results> from the C<-E<gt>search> method, as well as
the return of C<-E<gt>result> is a hashref. It contains information
about a certain torrent from the search results. The hashref
contains the following keys:

=over 6

=item is_private

When true indicates that torrent is hosted on a private tracker.
When false indicates public tracker.

=item name

The name of the torrent

=item size

The size of the torrent in whatever units it is presented on the
page. Usually it will be something along the lines of '300 MB',
or '3 GB'.

=item seeds

The number of seeds for the torrent. May be a string 'N/A', which
indicates that there is no data available.

=item leechers

The number of leechers for the torrent. May be a string 'N/A', which
indicates that there is no data available.

=item added_date

The date when the torrent was added. So far it should be in the
'31 Dec 07', but it's only a string gotten directly from the page.

=item category

Torrent's category. Technically the value can be used in the
C<-E<gt>category> method (not tested).

=item subcategory

Torrent's subcategory.

=item uri

A L<URI> object -- link to the torrent page (with its long 
description, comments, etc.).

=item download_uri

A L<URI> object -- link to the torrent itself. Content-type is
C<application/x-bittorrent> and if you are doing anything low-level
with it you might want to regard the I<Content-Disposition> header
which will contain an actual torrent filename.

=back

=head1 PREREQUISITES

This module requires L<URI>, L<LWP::UserAgent>, L<HTML::TokeParser::Simple>
and L<HTML::Entities> modules.

=head1 SEE ALSO

L<URI>, L<LWP::UserAgent>

=head1 AUTHOR

Zoffix Znet, E<lt>cpan@zoffix.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Zoffix Znet

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
