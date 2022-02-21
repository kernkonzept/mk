package L4::TapWrapper::Plugin::TagPluginBase;

use strict;
use warnings;

use File::Basename;
BEGIN { unshift @INC, dirname($0) . '/../lib'; }

use parent 'L4::TapWrapper::Plugin';
use L4::TapWrapper;

sub new {
  my $type = shift;
  my $self = L4::TapWrapper::Plugin->new();

  $self->{args} = shift;
  L4::TapWrapper::fail_test("Tag not specified for plugin!")
    unless defined($self->{args}{tag});
  print "Tag: $self->{args}{tag}\n";

  $self->inhibit_exit() if $self->{args}{require_blocks};
  return bless $self, $type;
}

sub check_start {
  my $self = shift;
  return unless shift =~ m/^@@ $self->{args}{tag} @< BLOCK *(.*)/;
  $self->{in_block} = 1;
  $self->{block_info} = $1;

  # Inhibit unless we already do because we require more blocks
  $self->inhibit_exit() unless $self->{args}{require_blocks};
}

sub check_end {
  my $self = shift;
  return unless shift =~ m/^@@ $self->{args}{tag} BLOCK >@/;
  $self->{in_block} = 0;
  $self->permit_exit()
    unless $self->{args}{require_blocks} && --$self->{args}{require_blocks};
}

sub has_tag {
  my $self = shift;
  return $self->{clean_line} =~ s/^@@ $self->{args}{tag}://;
}

1;

__END__

=head1 Base for tagged plugins

Plugins parsing output in the standard tag format should use this plugin as a
base. It provides the logic to detect tags using the following standardized
format, where TAG corresponds to the tag set using the tag option for the
plugin:

=over

=item Block start

C</^@@ TAG @< BLOCK *(.*)/>

=item Block end

C</^@@ TAG BLOCK E<gt>@/>

=item Single line

C</^@@ TAG:/>

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

=head1 Usage

The plugin calls the C<process_mine> function for all lines that belong to the
tag, either due to a block or individually tagged line. The sole parameter to
the function will be the cleaned up block (read: without any tag). The raw line
containing the tag can be accessed using C<$self-E<gt>{raw_line}>.

=cut

