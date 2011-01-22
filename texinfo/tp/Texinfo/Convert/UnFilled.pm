# UnFilled.pm: handle unfilled line of text.
#
# Copyright 2010 Free Software Foundation, Inc.
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License,
# or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# 
# Original author: Patrice Dumas <pertusus@free.fr>

# this module has nothing Texinfo specific.  It is similar with 
# Texinfo::Convert::Line, but simpler.

package Texinfo::Convert::UnFilled;

use 5.006;
use strict;

use Unicode::EastAsianWidth;

# initialize a paragraph object.
sub new($;$)
{
  my $class = shift;
  my $conf = shift;
  my $self = {'indent_length' => 0, 'counter' => 0, 'line_beginning' => 1,
              'leading_spaces' => '', 'only_spaces' => 1, 'lines_counter' => 0,
              'end_line_count' => 0};
  if (defined($conf)) {
    foreach my $key (keys(%$conf)) {
      if ($key eq 'text') {
        $self->{'counter'} = Texinfo::Convert::Unicode::string_width($conf->{$key});
        $self->{'line_beginning'} = 0 if ($self->{'counter'});
      } else {
        $self->{$key} = $conf->{$key};
      }
    }
  }
  bless $self, $class;
}

# for debug
sub dump($)
{
  my $self = shift;
  my $word = 'UNDEF';
  my $end_sentence = 'UNDEF';
  print STDERR "unfilled ($self->{'line_beginning'},$self->{'only_spaces'}) space `$self->{'leading_spaces'}'\n"; 
}

sub end_line($)
{
  my $line = shift;
  $line->{'end_line_count'} = 0;
  return $line->_end_line();
}

# end a line.
sub _end_line($)
{
  my $line = shift;
  $line->{'line_beginning'} = 1;
  $line->{'leading_spaces'} = '';
  $line->{'only_spaces'} = 1;
  $line->{'lines_counter'}++;
  $line->{'end_line_count'}++;
  print STDERR "END_LINE\n" if ($line->{'DEBUG'});
  return "\n";
}

sub end_line_count($)
{
  my $line = shift;
  return $line->{'end_line_count'};
}

sub _add_text($$)
{
  my $line = shift;
  my $text = shift;
  if ($line->{'line_beginning'}) {
    if ($line->{'indent_length'}) {
      $line->{'leading_spaces'} .= 
        ' ' x ($line->{'indent_length'} - $line->{'counter'});
      print STDERR "INDENT($line->{'counter'})\n" if ($line->{'DEBUG'});
    }
    $line->{'line_beginning'} = 0;
  }
  if ($line->{'only_spaces'}) {
    if ($text =~ /\S/) {
      $text = $line->{'leading_spaces'}.$text;
      $line->{'leading_spaces'} = '';
      $line->{'only_spaces'} = 0;
    }
    if ($text =~ /\n/) {
      $text =~ s/\s*$//;
      $text .= $line->_end_line;
    }
  } else {
    if ($text =~ /\n/) {
      $text =~ s/\s*$//;
      $text .= $line->_end_line;
    }
  }
  return $text;
}

# put a pending word and spaces in the result string.
sub add_pending_word($)
{
  my $line = shift;
  $line->{'end_line_count'} = 0;
  return '';
}

# end 
sub end($)
{
  my $line = shift;
  $line->{'end_line_count'} = 0;
  return '';
}

# add a word and/or spaces and end of sentence.
sub add_next($;$$$)
{
  my $line = shift;
  my $word = shift;
  my $space = shift;
  my $end_sentence = shift;
  $line->{'end_line_count'} = 0;
  my $result = '';

  if (defined($word)) {
    $result .= $line->_add_text($word);
  }
  if (defined($space)) {
    $result .= $line->_add_text($space);
  }
  return $result;
}

sub inhibit_end_sentence($)
{
  my $line = shift;
}

sub set_space_protection($$;$$$)
{
  return '';
}

# wrap a text.
sub add_text($$)
{
  my $line = shift;
  my $text = shift;
  $line->{'end_line_count'} = 0;
  return $line->_add_text($text);
}

1;
