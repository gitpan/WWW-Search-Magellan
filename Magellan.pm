# Magellan.pm
# Copyright (c) 1998 by Martin Thurn
# $Id: Magellan.pm,v 1.19 2000/05/22 16:22:59 mthurn Exp $

=head1 NAME

WWW::Search::Magellan - class for searching Magellan 

=head1 SYNOPSIS

  use WWW::Search;
  my $oSearch = new WWW::Search('Magellan');
  my $sQuery = WWW::Search::escape_query("+sushi restaurant +Columbus Ohio");
  $oSearch->native_query($sQuery);
  while (my $oResult = $oSearch->next_result())
    print $oResult->url, "\n";

=head1 DESCRIPTION

This class is a Magellan specialization of WWW::Search.
It handles making and interpreting Magellan searches
F<http://www.mckinley.com>.

This class exports no public interface; all interaction should
be done through L<WWW::Search> objects.

=head1 SEE ALSO

To make new back-ends, see L<WWW::Search>.

=head1 BUGS

Please tell the author if you find any!

=head1 TESTING

This module adheres to the C<WWW::Search> test suite mechanism. 

=head1 AUTHOR

As of 1998-03-17, C<WWW::Search::Magellan> is maintained by Martin Thurn
(MartinThurn@iname.com).

C<WWW::Search::Magellan> was originally written by Martin Thurn
based on C<WWW::Search::WebCrawler>.

=head1 LEGALESE

THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

=head1 VERSION HISTORY

=head2 2.06, 2000-05-22

new output format (deleted percent scores)

=head2 2.05, 2000-02-28

new base URL for searches

=head2 2.04, 2000-01-31

new test cases

=head2 2.03, 1999-12-10

new test cases

=head2 2.02, 1999-10-05

now uses hash_to_cgi_string()

=head2 2.01, 1999-07-13

=head2 1.7, 1998-10-09

Now uses split_lines function

=head2 1.6

Now parses score (percentage) from Magellan's output.

=head2 1.2

First publicly-released version.

=cut

#####################################################################

package WWW::Search::Magellan;

require Exporter;
@EXPORT = qw();
@EXPORT_OK = qw();
@ISA = qw(WWW::Search Exporter);
$VERSION = '2.06';
$MAINTAINER = 'Martin Thurn <MartinThurn@iname.com>';

use Carp ();
use WWW::Search(generic_option);
require WWW::SearchResult;

# private
sub native_setup_search
  {
  my($self, $native_query, $native_options_ref) = @_;

  $self->{'_hits_per_page'} = 50;

  $self->{agent_e_mail} = 'MartinThurn@iname.com';
  $self->user_agent(0);

  $self->{'_next_to_retrieve'} = 0;
  $self->{'_num_hits'} = 0;

  # Remove '*' at end of query terms within the user's query.  If the
  # query string is not escaped (even though it's supposed to be),
  # change '* ' to ' ' at end of words and at the end of the string.
  # If the query string is escaped, change '%2A+' to '+' at end of
  # words and delete '%2A' at the end of the string.
  $native_query =~ s/(\w)\052\s/$1\040/g;
  $native_query =~ s/(\w)\052$/$1\040/g;
  $native_query =~ s/(\w)\0452A\053/$1\053/g;
  $native_query =~ s/(\w)\0452A$/$1/g;

  if (!defined($self->{_options})) 
    {
    $self->{_options} = {
                         'look' => 'magellan',
                         'perPage' => $self->{'_hits_per_page'},
                         'search' => $native_query,
                         'search_url' => 'http://search.excite.com/search.gw',
                         'showSummary' => 'true',
                         'start' => $self->{'_next_to_retrieve'},
                        };
    } # if
  my $options_ref = $self->{_options};
  if (defined($native_options_ref)) 
    {
    # Copy in new options.
    foreach (keys %$native_options_ref) 
      {
      $options_ref->{$_} = $native_options_ref->{$_};
      } # foreach
    } # if

  # Finally, figure out the url.
  $self->{_next_url} = $self->{_options}{'search_url'} .'?'. $self->hash_to_cgi_string($options_ref);

  # Set some private variables:
  $self->{_debug} = $options_ref->{'search_debug'};
  $self->{_debug} = 2 if ($options_ref->{'search_parse_debug'});
  $self->{_debug} = 0 if (!defined($self->{_debug}));
  } # native_setup_search


# private
sub native_retrieve_some
  {
  my ($self) = @_;
  
  # Fast exit if already done:
  return undef unless defined($self->{_next_url});
  
  # If this is not the first page of results, sleep so as to not overload the server:
  $self->user_agent_delay if 1 < $self->{'_next_to_retrieve'};
  
  # Get some results, adhering to the WWW::Search mechanism:
  print STDERR " *   sending request (",$self->{_next_url},")\n" if $self->{'_debug'};
  my($response) = $self->http_request('GET', $self->{_next_url});
  $self->{response} = $response;
  if (!$response->is_success) 
    {
    return undef;
    };

  print STDERR " *   got response\n" if $self->{'_debug'};
  $self->{'_next_url'} = undef;
  # Parse the output
  my ($HEADER1,$HEADER2, $HITS,$PERCENT,$H3, $DESC, $TRAILER) = qw(E1 E2 HH PE H3 DE TR);
  my $hits_found = 0;
  my $state = $HEADER1;
  my $hit;
  foreach ($self->split_lines($response->content())) 
    {
    next if m/^$/; # short circuit for blank lines
    print STDERR " *   $state ===$_===" if 2 <= $self->{'_debug'};
    if ($state eq $HEADER1 && 
        m{<b>(\d+)</b>\sresults\sreturned}i)
      {
      # Actual line of input is:
      # <B>377</B> results returned, ranked by relevance.
      # <!--<b>3457804</b> results returned, ranked by relevance.-->
      print STDERR "header line\n" if 2 <= $self->{'_debug'};
      $self->approximate_result_count($1);
      $state = $HITS;
      next;
      } # we're in HEADER mode, and line has number of results
    elsif ($state eq $PERCENT &&
           m{^(\d+)\%$})
      {
      print STDERR "hit percent line\n" if 2 <= $self->{'_debug'};
      # Actual line of input is:
      # 75%
      $hit->score($1);
      $state = $HITS;
      next;
      }
    elsif ($state eq $HITS && 
           m{^<A\sHREF=\"([^\"]+)\"\>([^\<]+)}i)

      {
      print STDERR "hit url line\n" if 2 <= $self->{'_debug'};
      # Actual line of input:
      #   <B><A HREF="http://www.tez.net/~arthurd/starwars.html">The Star Wars List of Links</A></B>&nbsp;&nbsp;&nbsp;
      # Sometimes there is an \r and/or \n before the </A>
      if (defined($hit))
        {
        push(@{$self->{cache}}, $hit);
        } # if
      $hit = new WWW::SearchResult;
      $hit->add_url($1);
      $hit->title($2);
      $self->{'_num_hits'}++;
      $hits_found++;
      $state = $DESC;
      }
    elsif ($state eq $DESC &&
          m{^<font.+?>(.+?)</font>$})
      {
      print STDERR "hit description line\n" if 2 <= $self->{'_debug'};
      $hit->description($1);
      $state = $HITS;
      } # line is description
    elsif ($state eq $HITS && m{\<input\s.*?\sVALUE=\"Next\sResults\"}i)
      {
      print STDERR " found next button\n" if 2 <= $self->{'_debug'};
      # Actual lines of input are:
      #              <input value="Next Results" type="submit" name="next">
      #              <INPUT TYPE=submit NAME=next VALUE="Next Results">
      # There is a "next" button on this page, therefore there are
      # indeed more results for us to go after next time.
      # Process the options.
      $self->{'_next_to_retrieve'} += $self->{'_hits_per_page'};
      $self->{'_options'}{'start'} = $self->{'_next_to_retrieve'};
      # Finally, figure out the url.
      $self->{_next_url} = $self->{_options}{'search_url'} .'?'. $self->hash_to_cgi_string($self->{_options});
      $state = $TRAILER;
      last;
      }
    else
      {
      print STDERR "didn't match\n" if 2 <= $self->{'_debug'};
      }
    } # foreach line of query results HTML page

  if ($state ne $TRAILER)
    {
    # End, no "next" page (or, some parsing error on this page)
    $self->{_next_url} = undef;
    }
  if (defined($hit)) 
    {
    push(@{$self->{cache}}, $hit);
    }
  
  return $hits_found;
  } # native_retrieve_some

1;

__END__

new URL as of 2000-02-28:

http://search.excite.com/search.gw?search=SQL+handbook&look=magellan
