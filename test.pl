# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use ExtUtils::testlib;

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..5\n"; }
END {print "not ok 1\n" unless $loaded;}
use WWW::Search::Magellan;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $iTest = 2;

my $sEngine = 'Magellan';
my $oSearch = new WWW::Search($sEngine);
print ref($oSearch) ? '' : 'not ';
print "ok $iTest\n";
# $oSearch->{debug} = 9;

use WWW::Search::Test;

# This test returns no results (but we should not get an HTTP error):
$iTest++;
$oSearch->native_query($WWW::Search::Test::bogus_query);
@aoResults = $oSearch->results();
$iResults = scalar(@aoResults);
if (0 < $iResults)
  {
  print "not ok $iTest\n";
  }
else
  {
  print "ok $iTest\n";
  }

# This query returns 1 page of results:
$iTest++;
my $sQuery = '"Martin Thu'.'rn" AND Kenn'.'er';
$oSearch->native_query(WWW::Search::escape_query($sQuery));
@aoResults = $oSearch->results();
$iResults = scalar(@aoResults);
# print STDERR " + got $iResults results for $sQuery\n";
if ((2 <= $iResults) && ($iResults <= 49))
  {
  print "ok $iTest\n";
  }
else
  {
  print STDERR " --- got $iResults results for $sQuery, but expected 2..49\n";
  print "not ok $iTest\n";
  }

# This query returns a few pages of results:
$iTest++;
$sQuery = 'dise'.'stablishmentarianism';
$oSearch->native_query($sQuery);
@aoResults = $oSearch->results();
$iResults = scalar(@aoResults);
# print STDERR " + got $iResults results for $sQuery\n";
if (51 <= $iResults)
  {
  print "ok $iTest\n";
  }
else
  {
  print STDERR " --- got $iResults results for $sQuery, but expected 51..\n";
  print "not ok $iTest\n";
  }
