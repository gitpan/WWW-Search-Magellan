# Magellan.pm
# Copyright (c) 1998 by Martin Thurn
# $Id: Magellan.pm,v 1.22 2001/01/16 14:28:02 mthurn Exp $

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

=head2 2.09, 2001-01-16

handle no-response more gracefully

=head2 2.08, 2000-12-11

more robust parsing

=head2 2.07, 2000-11-13

handle new output format; rewrite using HTML::TreeBuilder

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
$VERSION = '2.09';
$MAINTAINER = 'Martin Thurn <MartinThurn@iname.com>';

use Carp ();
use HTML::Form;
use HTML::TreeBuilder;
use WWW::Search qw(generic_option);
use WWW::SearchResult;

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

  my $sBaseURL = $self->{_next_url};
  # Get some results, adhering to the WWW::Search mechanism:
  print STDERR " *   sending request ($sBaseURL)\n" if $self->{'_debug'};
  my($response) = $self->http_request('GET', $sBaseURL);
  $self->{response} = $response;
  if (!$response->is_success)
    {
    return undef;
    }

  print STDERR " +   got response\n" if $self->{'_debug'};
  print STDERR " + >>>>>>>>>>", $response->content, "<<<<<<<<<<\n" if 8 < $self->{'_debug'};
  $self->{'_next_url'} = undef;

  # Parse the output
  my $tree = new HTML::TreeBuilder;
  $tree->parse($response->content);
  $tree->eof;

  # All the results are in the fourth <table>:
  my @aoTABLE = $tree->look_down('_tag', 'table');
  my $oTABLE = $aoTABLE[2];
  # print STDERR " + TABLE =====", $oTABLE->as_HTML, "=====\n";

  # The result count is in the first (strict sub)table:
  my @aoTABLEsub = $oTABLE->look_down('_tag', 'table');
  # look_down returns $oTABLE as the first one found:
  shift @aoTABLEsub;
  my $oTABLEsub = $aoTABLEsub[0];
  # print STDERR " + SUBTABLE =====", $oTABLEsub->as_text, "=====\n";
  if (! ref $oTABLEsub)
    {
    print STDERR " --- can not find result-count subtable\n" if 1 < $self->{'_debug'};
    }
  elsif ($oTABLEsub->as_text =~ m!web site results of ([\d,]+) for!i)
    {
    my $iCount = $1;
    $iCount =~ s/,//g;
    $self->approximate_result_count($iCount);
    } # if
  # The next button is in a FORM within this main table:
  my $oFORM = $oTABLE->look_down('_tag', 'form');
  if (ref($oFORM))
    {
    my $sForm = $oFORM->as_HTML;
    # print STDERR " + FORM == $sForm" if 1 < $self->{'_debug'};
    my $oForm = HTML::Form->parse($sForm, $sBaseURL);
    my $oNextButton = $oForm->find_input('next');
    if (ref($oNextButton))
      {
      # print STDERR " +   NEXT == ", $oNextButton, "\n" if 1 < $self->{'_debug'};
      $self->{_next_url} = new $HTTP::URI_CLASS($oNextButton->click($oForm)->uri);
      # print STDERR " +   URL  == ", $self->{_next_url}, "\n" if 1 < $self->{'_debug'};
      } # if
    $oFORM->delete;
    } # if

  # Delete all sub-tables:
  foreach my $oTABLEsub (@aoTABLEsub)
    {
    next unless ref $oTABLEsub;
    $oTABLEsub->detach;
    $oTABLEsub->delete;
    } # foreach

  # print STDERR " + MAIN TABLE =====", $oTABLE->as_HTML, "=====\n";
  my $oFONT = $oTABLE->look_down('_tag', 'font');
  goto ALL_DONE unless ref($oFONT);
  while ($oFONT->content_list)
    {
    my @ao = $oFONT->splice_content(0, 1);
    my $o = shift @ao;
    # print STDERR " +   CONTENT ===", $o, "===\n";
    if (ref($o) && ($o->tag eq 'b') && (my $oA = $o->look_down('_tag', 'a')))
      {
      $sURL = $oA->attr('href');
      $sTitle = $oA->as_text;
      # Look ahead to the second chunk of plain text:
      while (ref($o) && $oFONT->content_list)
        {
        my @ao = $oFONT->splice_content(0, 1);
        $o = shift @ao;
        } # while
      $o = new HTML::Element('dummy');
      while (ref($o) && $oFONT->content_list)
        {
        my @ao = $oFONT->splice_content(0, 1);
        $o = shift @ao;
        } # while
      if (!ref($o) && ($o ne ''))
        {
        $sDesc = $o;
        my $hit = new WWW::SearchResult;
        $hit->add_url($sURL);
        $hit->title($sTitle);
        $hit->description($sDesc);
        push(@{$self->{cache}}, $hit);
        $self->{'_num_hits'}++;
        $hits_found++;
        } # if
      } # if
    } # while
 ALL_DONE:
  $oFONT->delete if ref($oFONT);
  $tree->delete if ref($tree);
  return $hits_found;
  } # native_retrieve_some

1;

__END__

new URL as of 2000-02-28:

http://search.excite.com/search.gw?search=SQL+handbook&look=magellan
