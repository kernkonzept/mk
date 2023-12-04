package L4::TapWrapper::Plugin::TagPluginBase;

use strict;
use warnings;

use File::Basename;

use parent 'L4::TapWrapper::Plugin';
use L4::TapWrapper;

sub new {
  my $type = shift;
  my $self = L4::TapWrapper::Plugin->new();

  $self->{args} = shift;
  L4::TapWrapper::fail_test("Tag not specified for plugin!")
    unless defined($self->{args}{tag});
  my $tags = $self->{args}{tag};
  if (length $tags)
    {
      my @ta = split(/;/, $tags);
      $self->{args}{tags} = \@ta;
    }
  my @tags = @{$self->{args}{tags}};
  print "Tags: @tags\n";
  # create a simple regular expression matching any of the tags set for the
  # plugin
  $self->{tagre} = join("|", @tags);

  $self->inhibit_exit() if $self->{args}{require_blocks};
  return bless $self, $type;
}

sub check_start {
  my $self = shift;
  return unless shift =~ m/^(.*)@@ ($self->{tagre}) @< BLOCK *([^\v]*)/;
  $self->{in_block} = 1;
  $self->{block_prefix} = $1;
  $self->{cur_tag} = $2;
  $self->{block_info} = ($3 =~ s/\e\[[\d,;\s]+[A-Za-z]//gir); # strip color escapes
  $self->start_block($self->{block_info});

  # Inhibit unless we already do because we require more blocks
  $self->inhibit_exit() unless $self->{args}{require_blocks};
}

sub check_end {
  my $self = shift;
  $self->{clean_line} =~ s/^\Q$self->{block_prefix}\E//;
  return unless shift =~ m/^\Q$self->{block_prefix}\E@@ $self->{cur_tag} BLOCK >@/;
  $self->{in_block} = 0;
  $self->{cur_tag} = "";
  $self->end_block();
  $self->permit_exit()
    unless $self->{args}{require_blocks} && --$self->{args}{require_blocks};
}

sub has_tag {
  my $self = shift;

  # The following line contains a regular expression. Regular expressions
  # are used to match parts of a string based on rules. They also allow
  # to "capture" part of the matched string into variables. Further regular
  # expressions know the concept of character classes that describe a set of
  # characters where any single character from the class is matched. The
  # expression below uses the following syntax elements of the perl regular
  # expression syntax:
  #
  # Capturing groups put in parentheses '(foobar)'
  # Non-capturing groups, where the content of the parentheses starts with ?:
  # Character classes enclosed in square brackets '[abc]'
  # A negation character '^' inside the character class to invert the set of
  #   matching characters, effectively matching any except the one specified.
  # A '*' character matches the preceding expression element an arbitrary
  #   number of times, including never.
  # A '?' character matches the preceding syntax element once or not at all.
  #   If it is the first character of a capture group this does not apply.
  #
  # Characters that have a special meaning, such as brackets and parentheses
  # must be escaped by a preceding '\' character if they are to be matched
  # literally. An exception used in this expression is that a closing bracket
  # that is the first character of a character class, or the second of a
  # class starting with the '^' character, must not be escaped. This is
  # somewhat obvious since an empty character class (or one matching all
  # characters in the inverted case) would be redundant and not make a lot of
  # sense.
  #
  # For more details please refer to:
  #
  # https://perldoc.perl.org/perlretut
  # https://perldoc.perl.org/perlrecharclass#Special-Characters-Inside-a-Bracketed-Character-Class
  $self->{clean_line} =~ s/\e\[[\d,;\s]+[A-Za-z]//gi;
  if ($self->{clean_line} =~ s/^.*@@ ($self->{tagre})(?:\[([^]]*)\])?://)
    {
      $self->{cur_tag} = $1;
      $self->{block_info} = $2; # strip color escapes
      return 1;
    }
  return 0
}

sub start_block {}
sub end_block {}

1;

__END__

=head1 Base for tagged plugins

Plugins parsing output in the standard tag format should use this plugin as a
base. It provides the logic to detect tags using the following standardized
format, where TAG corresponds to any of the tags set using the tag option for
the plugin:

=over

=item Block start

C</^@@ TAG @< BLOCK *(.*)/>

=item Block end

C</^@@ TAG BLOCK E<gt>@/>

=item Single line

C</^@@ TAG(?:\[([^]]*)\])?::/>

=back

=head1 Options

The following options are defined

=over

=item C<tag>

The tag for blocks and single lines. See above for details on the matching
expressions.

=item C<require_blocks>

An optional numerical argument indicating how many blocks must arrive before the
plugin stops inhibiting test exit. The default is zero zero indicating that the
plugin does not inhibit exits and works opportunistically.

=back

=head1 Functions

The following functions are implemented that plugins based on this can hook
into:

=item C<end_block>

Is called whenever the current block is terminated.

=item C<start_block>

Is called for every new block. The extra block info (see capture in the block
start regex) is passed as a parameter.

=back

=head1 Usage

The plugin calls the C<process_mine> function for all lines that belong to the
tag, either due to a block or individually tagged line. The sole parameter to
the function will be the cleaned up block (read: without any tag). The raw line
containing the tag can be accessed using C<$self-E<gt>{raw_line}>.

=cut

