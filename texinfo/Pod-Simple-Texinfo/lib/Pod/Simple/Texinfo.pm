# See informations on this perl module at the end of the file, in the pod
# section.

package Pod::Simple::Texinfo;

require 5;
use strict;

use Carp qw(cluck);
#use Pod::Simple::Debug (3);
use Pod::Simple::PullParser ();

use Texinfo::Convert::NodeNameNormalization qw(normalize_node);
use Texinfo::Parser qw(parse_texi_line);
use Texinfo::Convert::Texinfo;
use Texinfo::Common qw(protect_comma_in_tree);

use vars qw(
  @ISA $VERSION
);

@ISA = ('Pod::Simple::PullParser');
$VERSION = '0.01';

#use UNIVERSAL ();

# Allows being called from the comand line as
# perl -w -MPod::Simple::Texinfo -e Pod::Simple::Texinfo::go thingy.pod
sub go { Pod::Simple::Texinfo->parse_from_file(@ARGV); exit 0 }

my %head_commands_level;
foreach my $level (1 .. 4) {
  $head_commands_level{'head'.$level} = $level;
}

my @numbered_sectioning_commands = ('part', 'chapter', 'section', 'subsection', 
  'subsubsection');
my @unnumbered_sectioning_commands = ('part', 'unnumbered', 'unnumberedsec', 
  'unnumberedsubsec', 'unnumberedsubsubsec');

my @raw_formats = ('html', 'HTML', 'docbook', 'DocBook', 'texinfo',
                       'Texinfo');

# from other Pod::Simple modules.  Creates accessor subroutine.
__PACKAGE__->_accessorize(
  'texinfo_sectioning_base_level',
  'texinfo_man_url_prefix',
  'texinfo_sectioning_style',
  'texinfo_add_upper_sectioning_command',
  'texinfo_internal_pod_manuals',
);

my $sectioning_style = 'numbered';
#my $sectioning_base_level = 2;
my $sectioning_base_level = 0;
my $man_url_prefix = 'http://man.he.net/man';

sub new
{
  my $class = shift;
  my $new = $class->SUPER::new(@_);
  $new->accept_targets(@raw_formats);
  $new->preserve_whitespace(1);
  $new->texinfo_sectioning_base_level ($sectioning_base_level);
  $new->texinfo_man_url_prefix ($man_url_prefix);
  $new->texinfo_sectioning_style ($sectioning_style);
  $new->texinfo_add_upper_sectioning_command(1);
  return $new;
}

sub run
{
  my $self = shift;

  # In case the caller changed the formats
  my @formats = $self->accept_targets();
  foreach my $format (@formats) {
    if (lc($format) eq 'texinfo') {
      $self->{'texinfo_raw_format_commands'}->{$format} = '';
      $self->{'texinfo_if_format_commands'}->{':'.$format} = '';
    } else {
      $self->{'texinfo_raw_format_commands'}->{$format} = lc($format);
      $self->{'texinfo_if_format_commands'}->{':'.$format} = lc($format);
    }
  }
  my $base_level = $self->texinfo_sectioning_base_level;
  $base_level = 1 if ($base_level <= 1);
  if ($self->texinfo_sectioning_style eq 'numbered') {
    $self->{'texinfo_sectioning_commands'} = \@numbered_sectioning_commands;
  } else {
    $self->{'texinfo_sectioning_commands'} = \@unnumbered_sectioning_commands;
  }
  foreach my $heading_command (keys(%head_commands_level)) {
    my $level = $head_commands_level{$heading_command} + $base_level -1;
    if (!defined($self->{'texinfo_sectioning_commands'}->[$level])) {
      $self->{'texinfo_head_commands'}->{$heading_command}
        = $self->{'texinfo_sectioning_commands'}->[-1];
    } else {
      $self->{'texinfo_head_commands'}->{$heading_command}
        = $self->{'texinfo_sectioning_commands'}->[$level];
    }
  }
  $self->{'texinfo_internal_pod_manuals_hash'} = {};
  my $manuals = $self->texinfo_internal_pod_manuals();
  if ($manuals) {
    foreach my $manual (@$manuals) {
       $self->{'texinfo_internal_pod_manuals_hash'}->{$manual} = 1;
    }
  }

  if ($self->bare_output()) {
    $self->_convert_pod();
  } else {
    #my $string = '';
    #$self->output_string( \$string );
    $self->_preamble();
    $self->_convert_pod();
    $self->_postamble(); 
    #print STDERR $string;
  }
}

my $STDIN_DOCU_NAME = 'stdin';
sub _preamble($)
{
  my $self = shift;

  my $fh = $self->{'output_fh'};

  my $short_title = $self->get_short_title();
  if (defined($short_title) and $short_title =~ m/\S/) {
    $self->{'texinfo_short_title'} = $short_title;
  }

  if ($self->texinfo_sectioning_base_level == 0) {
    #print STDERR "$fh\n";
    print $fh '\input texinfo'."\n";
    my $setfilename;
    if (defined($self->{'texinfo_short_title'})) {
      $setfilename = _pod_title_to_file_name($self->{'texinfo_short_title'});
    } else {
      my $source_filename = $self->source_filename();
      if (defined($source_filename) and $source_filename ne '') {
        if ($source_filename eq '-') {
          $setfilename = $STDIN_DOCU_NAME;
        } else {
          $setfilename = $source_filename;
          $setfilename =~ s/\.(pod|pm)$//i;
        }
      }
    }
    if (defined($setfilename) and $setfilename =~ m/\S/) {
      $setfilename = _protect_text($setfilename);
      $setfilename .= '.info';
      print $fh "\@setfilename $setfilename\n\n"
    }

    my $title = $self->get_title();
    if (defined($title) and $title =~ m/\S/) {
      print $fh "\@settitle "._protect_text($title)."\n\n";
    }
    print $fh "\@node Top\n";
    if (defined($self->{'texinfo_short_title'})) {
       print $fh "\@top "._protect_text($self->{'texinfo_short_title'})."\n\n";
    }
  } elsif (defined($self->{'texinfo_short_title'})
           and $self->texinfo_add_upper_sectioning_command) {
      my $level = $self->texinfo_sectioning_base_level() - 1;
      print $fh "\@$self->{'texinfo_sectioning_commands'}->[$level] "
         ._protect_text($self->{'texinfo_short_title'})."\n\n";
  }
}


sub _output($$$)
{
  my $fh = shift;
  my $accumulated_stack = shift;
  my $text = shift;

  if (scalar(@$accumulated_stack)) {
    $accumulated_stack->[-1] .= $text;
  } else {
    print $fh $text;
  }
}

sub _protect_text($)
{
  my $text = shift;
  cluck if (!defined($text));
  $text =~ s/([\@\{\}])/\@$1/g;
  return $text;
}

sub _pod_title_to_file_name($)
{
  my $name = shift;
  $name =~ s/\s+/_/g;
  $name =~ s/::/-/g;
  $name =~ s/[^\w\.-]//g;
  $name = '_' if ($name eq '');
  return $name;
}

sub _protect_comma($) {
  my $texinfo = shift;
  my $tree = parse_texi_line(undef, $texinfo);
  $tree = protect_comma_in_tree(undef, $tree);
  return Texinfo::Convert::Texinfo::convert($tree);
}

sub _is_title($)
{
# Regexp from Pod::Simple::PullParser
  my $title = shift;
  return ($title =~ m/^(NAME | TITLE | VERSION | AUTHORS? | DESCRIPTION | SYNOPSIS
             | COPYRIGHT | LICENSE | NOTES? | FUNCTIONS? | METHODS?
             | CAVEATS? | BUGS? | SEE\ ALSO | SWITCHES | ENVIRONMENT)$/sx);

}

sub _section_manual_to_node_name($$$)
{
  my $self = shift;
  my $manual = shift;
  my $section = shift;
  my $base_level = shift;

  if (defined($manual) and $base_level > 0
      and _is_title($section)) {
    return "$manual $section";
  } else {
    return $section;
  }
}

sub _prepare_anchor($$)
{
  my $self = shift;
  my $texinfo_node_name = shift;

  $texinfo_node_name 
     = $self->_section_manual_to_node_name($self->{'texinfo_short_title'},
                                          $texinfo_node_name,
                                          $self->texinfo_sectioning_base_level);

  my $node_tree = parse_texi_line(undef, $texinfo_node_name);
  my $normalized_base = normalize_node($node_tree);
  my $normalized = $normalized_base;
  my $number_appended = 0;
  while ($self->{'texinfo_nodes'}->{$normalized}) {
    $number_appended++;
    $normalized = "${normalized_base}-$number_appended";
  }
  my $node_name;
  if ($number_appended) {
    $texinfo_node_name = "$texinfo_node_name $number_appended";
    $node_tree = parse_texi_line(undef, $texinfo_node_name);
  }
  $node_tree = protect_comma_in_tree(undef, $node_tree);
  $self->{'texinfo_nodes'}->{$normalized} = $node_tree;
  return Texinfo::Convert::Texinfo::convert($node_tree);
}

# from Pod::Simple::HTML general_url_escape
sub _url_escape($)
{
  my $string = shift;

  $string =~ s/([^\x00-\xFF])/join '', map sprintf('%%%02X',$_), unpack 'C*', $1/eg;
     # express Unicode things as urlencode(utf(orig)).

  # A pretty conservative escaping, behoovey even for query components
  #  of a URL (see RFC 2396)

  $string =~ s/([^-_\.!~*()abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789])/sprintf('%%%02X',ord($1))/eg;
   # Yes, stipulate the list without a range, so that this can work right on
   #  all charsets that this module happens to run under.
   # Altho, hmm, what about that ord?  Presumably that won't work right
   #  under non-ASCII charsets.  Something should be done
   #  about that, I guess?

  return $string;
}

my %tag_commands = (
  'F' => 'file',
  'S' => 'w',
  'I' => 'emph',
  'B' => 'strong', # or @b?
  'C' => 'code'
);

my %environment_commands = (
  'over-text' => 'table @asis',
  'over-bullet' => 'itemize',
  'over-number' => 'enumerate',
  'over-block' => 'quotation',
);

my %line_commands = (
  'item-bullet' => 'item',
  'item-text' => 'item',
  'item-number' => 'item',
  'encoding' => 'documentencoding'
);

# do not appear as parsed token
# E entity/character
sub _convert_pod($)
{
  my $self = shift;

  my $fh = $self->{'output_fh'};

  my ($token, $type, $tagname, $top_seen);

  my @accumulated_output;
  my @format_stack;
  while($token = $self->get_token()) {
    my $type = $token->type();
    #print STDERR "* type $type\n";
    #print STDERR $token->dump()."\n";
    if ($type eq 'start') {
      my $tagname = $token->tagname();
      if ($head_commands_level{$tagname} or $tagname eq 'item-text') {
        push @accumulated_output, '';
      } elsif ($tag_commands{$tagname}) {
        _output($fh, \@accumulated_output, "\@$tag_commands{$tagname}\{");
      } elsif ($tagname eq 'Verbatim') {
        print $fh '@verbatim'."\n";
        push @format_stack, 'verbatim';
      } elsif ($environment_commands{$tagname}) {
        print $fh "\@$environment_commands{$tagname}\n";
      } elsif ($tagname eq 'for') {
        my $target = $token->attr('target');
        push @format_stack, $target;
        if ($self->{'texinfo_raw_format_commands'}->{$target}) {
          print $fh "\@$self->{'texinfo_raw_format_commands'}->{$target}\n";
        } elsif ($self->{'texinfo_if_format_commands'}->{$target}) {
          print $fh "\@if$self->{'texinfo_if_format_commands'}->{$target}\n";
        }
      } elsif ($line_commands{$tagname}) {
        print $fh "\@$line_commands{$tagname} ";
      } elsif ($tagname eq 'L') {
        my $linktype = $token->attr('type');
        my $content_implicit = $token->attr('content-implicit');
        #print STDERR " L: $linktype";
        my ($url_arg, $texinfo_node, $texinfo_manual);
        if ($linktype eq 'man') {
          # NOTE: the .'' is here to force the $token->attr to ba a real
          # string and not an object.
          my $replacement_arg = $token->attr('to').'';
          # regexp from Pod::Simple::HTML resolve_man_page_link
          # since it is very small, it is likely that copyright cannot be
          # claimed for that part.
          $replacement_arg =~ /^([^(]+)(?:[(](\d+)[)])?$/;
          my $page = $1;
          my $section = $2;
          if (defined($page) and $page ne '') {
            $section = 1 if (!defined($section));
            # it is unlikely that there is a comma because of _url_escape
            # but to be sure there is still a call to _protect_comma.
            $url_arg 
              = _protect_comma(_protect_text(
                  $self->texinfo_man_url_prefix
                  ."$section/"._url_escape($page)));
          } else {
            $url_arg = '';
          }
          $replacement_arg = _protect_text($replacement_arg);
          _output($fh, \@accumulated_output, "\@url{$url_arg,,$replacement_arg}");
        } else {
          if ($linktype eq 'url') {
            # NOTE: the .'' is here to force the $token->attr to be a real
            # string and not an object.
            $url_arg = _protect_comma(_protect_text($token->attr('to').''));
          } elsif ($linktype eq 'pod') {
            my $manual = $token->attr('to');
            my $section = $token->attr('section');
            $manual .= '' if (defined($manual));
            $section .= '' if (defined($section));
            #print STDERR "$manual/$section\n";
            if (defined($manual)) {
              if (! defined($section) or $section !~ m/\S/) {
                if ($self->{'texinfo_internal_pod_manuals_hash'}->{$manual}) {
                  $section = 'NAME';
                } else {
                  $section = 'Top';
                }
              }
              if ($self->{'texinfo_internal_pod_manuals_hash'}->{$manual}) {
                $texinfo_node =
                 $self->_section_manual_to_node_name($manual, $section, 1);
              } else {
                $texinfo_manual = _protect_text(_pod_title_to_file_name($manual));
                $texinfo_node = $section;
              }
            } elsif (defined($section) and $section =~ m/\S/) {
              $texinfo_node = $section;
            }
            $texinfo_node = 'Top' if (!defined($texinfo_node));
            $texinfo_node = _protect_comma(_protect_text($texinfo_node));
          }
          # for pod, 'to' is the pod manual name.  Then 'section' is the 
          # section.
        }
        push @accumulated_output, '';
        push @format_stack, [$linktype, $content_implicit, $url_arg, 
                             $texinfo_manual, $texinfo_node];
        #if (defined($to)) {
        #  print STDERR " | $to\n";
        #} else { 
        #  print STDERR "\n";
        #}
        #print STDERR $token->dump."\n";
      } elsif ($tagname eq 'X') {
        print $fh '@cindex ';
      }
    } elsif ($type eq 'text') {
      my $text;
      if (!(@format_stack) or ref($format_stack[-1]) 
          or ($format_stack[-1] ne 'verbatim' 
              and !$self->{'texinfo_raw_format_commands'}->{$format_stack[-1]})) {
        $text = _protect_text($token->text());
      } else {
        $text = $token->text();
      }
      _output($fh, \@accumulated_output, $text);
      my $next_token = $self->get_token();
      if ($next_token) {
        if ($next_token->type() eq 'start' and $next_token->tagname() eq 'X') {
          print $fh "\n";
        }
        $self->unget_token($next_token);
      }
    } elsif ($type eq 'end') {
      my $tagname = $token->tagname();
      my $result;
      if ($head_commands_level{$tagname} or $tagname eq 'item-text') {
        my $command_result = pop @accumulated_output;
        my $node_name = _prepare_anchor ($self, $command_result);
        #print $fh "\@node $node_name\n";
        if ($head_commands_level{$tagname}) {
          my $command;
          $command 
            = $self->{'texinfo_head_commands'}->{$tagname};
          print $fh "\@$command $command_result\n";
        } else {
          print $fh "\@$line_commands{$tagname} $command_result\n";
        }
        print $fh "\@anchor{$node_name}\n";
        print $fh "\n" if ($head_commands_level{$tagname});
      } elsif ($tagname eq 'Para') {
        print $fh "\n\n";
        #my $next_token = $self->get_token();
        #if ($next_token) {
        #  if ($next_token->type() ne 'start' 
        #      or $next_token->tagname() ne 'Para') {
        #    print $fh "\n";
        #  }
        #  $self->unget_token($next_token);
        #}
      } elsif ($tag_commands{$tagname}) {
        _output($fh, \@accumulated_output, "}");
      } elsif ($tagname eq 'Verbatim') {
        pop @format_stack;
        print $fh "\n".'@end verbatim'."\n\n";
      } elsif ($environment_commands{$tagname}) {
        my $tag = $environment_commands{$tagname};
        $tag =~ s/ .*//;
        print $fh "\@end $tag\n\n";
      } elsif ($tagname eq 'for') {
        my $target = pop @format_stack;
        if ($self->{'texinfo_raw_format_commands'}->{$target}) {
          print $fh "\n\@end $self->{'texinfo_raw_format_commands'}->{$target}\n";
        } elsif ($self->{'texinfo_if_format_commands'}->{$target}) {
          print $fh "\@end if$self->{'texinfo_if_format_commands'}->{$target}\n";
        }
      } elsif ($line_commands{$tagname}) {
        print $fh "\n";
      } elsif ($tagname eq 'L') {
        my $result = pop @accumulated_output;
        my $format = pop @format_stack;
        my ($linktype, $content_implicit, $url_arg, 
            $texinfo_manual, $texinfo_node) = @$format;
        if ($linktype ne 'man') {
          my $explanation;
          if (defined($result) and $result =~ m/\S/ and !$content_implicit) {
            $explanation = ' '. _protect_comma($result);
          }
          if ($linktype eq 'url') {
            if (defined($explanation)) {
              _output($fh, \@accumulated_output, 
                       "\@url{$url_arg,$explanation}");
            } else {
              _output($fh, \@accumulated_output, 
                       "\@url{$url_arg}");
            }
          } elsif ($linktype eq 'pod') {
            if (defined($texinfo_manual)) {
              $explanation = '' if (!defined($explanation));
              _output($fh, \@accumulated_output,
                       "\@ref{$texinfo_node,$explanation,, $texinfo_manual}");
            } elsif (defined($explanation)) {
              _output($fh, \@accumulated_output,
                       "\@ref{$texinfo_node,$explanation}");
            } else {
              _output($fh, \@accumulated_output,
                       "\@ref{$texinfo_node}");
            }
          }
        }
      } elsif ($tagname eq 'X') {
        my $next_token = $self->get_token();
        if ($next_token) {
          if ($next_token->type() eq 'text') {
            print $fh "\n";
          }
          $self->unget_token($next_token);
        }
      }
    }
  }
}

sub _postamble($)
{
  my $self = shift;

  my $fh = $self->{'output_fh'};
  if ($self->texinfo_sectioning_base_level == 0) {
    #print STDERR "$fh\n";
    print $fh "\@bye\n";
  }
}

1;

__END__

=head1 NAME

Pod::Simple::Texinfo - format Pod as Texinfo

=head1 SYNOPSIS

  # From the command like
  perl -MPod::Simple::Texinfo -e Pod::Simple::Texinfo::go thingy.pod

  # From perl
  my $new = Pod::Simple::Texinfo->new;
  $new->texinfo_sectioning_style('unnumbered');
  my $from = shift @ARGV;
  my $to = $from;
  $to =~ s/\.(pod|pm)$/.texi/i;
  $new->parse_from_file($from, $to);

=head1 DESCRIPTION

This class is for making a Texinfo rendering of a Pod document.

This is a subclass of L<Pod::Simple::PullParser> and inherits all its
methods (and options).

It supports producing a standalone manual per Pod (the default) or 
render the Pod as a chapter, see L</texinfo_sectioning_base_level>.

=head1 METHODS

=over

=item texinfo_sectioning_base_level

Sets the level of the head1 commands.  1 is for the @chapter/@unnumbered 
level.  If set to 0, the head1 commands level is still 1, but the output 
manual is considered to be a standalone manual.  If not 0, the pod file is 
rendered as a fragment of a Texinfo manual.

=item texinfo_man_url_prefix

String used as a prefix for man page urls.  Default 
is C<http://man.he.net/man>.

=item texinfo_sectioning_style

Default is C<numbered>, using the numbered sectioning Texinfo @-commands
(@chapter, @section...), any other value would lead to using unnumbered
sectioning command variants (@unnumbered...).

=item texinfo_add_upper_sectioning_command

If set (the default case), a sectioning command is added at the beginning 
of the output for the whole document, using the module name, at the level
above the level set by L<texinfo_sectioning_base_level>.  So there will be
a C<@part> if the level is equal to 1, a C<@chapter> if the level is equal
to 2 and so on and so forth.  If the base level is 0, a C<@top> command is 
output instead.

=back

=head1 SEE ALSO

L<Pod::Simple>. L<Pod::Simple::PullParser>. The Texinfo manual.

=head1 COPYRIGHT

Copyright (C) 2011 Patrice Dumas

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

C<_url_escape> is C<general_url_escape> from L<Pod::Simple::HTML>.

=head1 AUTHOR

Patrice Dumas E<lt>pertusus@free.frE<gt>.  Parts from L<Pod::Simple::HTML>.

=cut
