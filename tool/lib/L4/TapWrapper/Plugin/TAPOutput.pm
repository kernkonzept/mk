package L4::TapWrapper::Plugin::TAPOutput;

use strict;
use warnings;

use File::Basename;

use parent 'L4::TapWrapper::Plugin';

sub new {
  my ($type, $args) = @_;
  my $self = L4::TapWrapper::Plugin->new();

  $self->{args} = $args;
  $self->{args}{block_count} //= 1;

  L4::TapWrapper::fail_test(
    "TAPOutput parameter block_count needs to be greater or equal to 1.")
    unless $self->{args}{block_count} >= 1;

  $self->{blocks_collected} = 0;
  $self->{active_blocks} = {};

  $self->inhibit_exit(); # We need at least one TAP block
  return bless $self, shift;
}

sub handle_block_start {
  my $self = shift;
  return unless shift =~ m/^(.*)TAP TEST START/;
  my $prefix = $1;

  L4::TapWrapper::fail_test(
    "Several concurrent blocks with same prefix '$prefix'." .
    "Make sure to use different prefixes")
    if exists $self->{active_blocks}{$prefix};

  $self->{active_blocks}{$prefix} = [];

  L4::TapWrapper::fail_test("More TAP blocks found than anticipated.")
    if ($self->{blocks_collected} + scalar(keys %{$self->{active_blocks}}) > $self->{args}{block_count});

  return 1;
}

sub handle_block_end {
  my $self = shift;
  return unless shift =~ m/^(.*)TAP TEST FINISH/;
  my $prefix = $1;

  L4::TapWrapper::fail_test("End of block with prefix '$prefix' that wasn't started.")
    unless exists $self->{active_blocks}{$prefix};

  $self->add_raw_tap_line(@{$self->{active_blocks}{$prefix}});

  delete $self->{active_blocks}{$prefix};

  $self->{blocks_collected}++;

  $self->permit_exit()
    if $self->{blocks_collected} == $self->{args}{block_count} &&
    (keys %{$self->{active_blocks}} == 0);

  return 1;
}

sub process_any {
  my $self = shift;
  my $line = shift;

  # strip color escapes
  $line =~ s/\e\[[\d,;\s]+[A-Za-z]//gi;

  return if $self->handle_block_end($line);
  return if $self->handle_block_start($line);

  foreach my $prefix (sort { length($b) <=> length($a) } keys %{$self->{active_blocks}})
    {
      next unless $line =~ s/^\Q$prefix\E//;

      push @{$self->{active_blocks}{$prefix}}, $line;

      last;
    }
}

1;

__END__

=head1 Plugin for collecting TAP blocks from output

Collect one or more TAP blocks. TAP blocks are encased between a line "TAP TEST
START" and line "TAP TEST FINISH".

If there's a prefix, i.e. text in the same line in front of the "TAP TEST
START", only subsequent lines with the same prefix count for the same TAP block,
including the "TAP TEST FINISH" line.

The plugin by default only collects one TAP block. If more TAP blocks are to be
expected in the output, the plugin has to be passed the C<block_count> parameter
with an amount of TAP blocks to gather.

TAP blocks can be positioned one after the other within the output of a test, in
which case the prefix can be chosen arbitrarily and can even be reused. TAP
blocks can also be interleaved in which case they need to have different
prefixes in order to be separated correctly.

=head1 Options

The following options are defined

=over

=item C<block_count>

Number of TAP blocks to collect. Must be at least 1. Defaults to 1.

=back

=head1 Usage

Specify for a particular testrun using the TEST_TAP_PLUGINS variable.
Example:

  TEST_TAP_PLUGINS=TAPOutput:block_count=2

=cut
