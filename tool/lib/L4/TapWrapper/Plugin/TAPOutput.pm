package L4::TapWrapper::Plugin::TAPOutput;

use strict;
use warnings;

use File::Basename;

use parent 'L4::TapWrapper::Plugin';

sub new {
  my $self = L4::TapWrapper::Plugin->new();
  $self->inhibit_exit(); # We need at least one TAP block
  return bless $self, shift;
}

# We use the legacy format to pass
sub check_start {
  my $self = shift;
  return unless shift =~ m/^(.*)TAP TEST START/;
  $self->{block_prefix} = $1;
  $self->{in_block} = 1;
}

sub check_end {
  my $self = shift;
  return unless shift =~ m/TAP TEST FINISH/;
  $self->{in_block} = 0;
  $self->permit_exit();
}

sub process_mine {
  my $self = shift;
  my $line = shift;
  if ($line =~ s/^\Q$self->{block_prefix}\E//)
    {
      # strip color escapes
      $line =~ s/\e\[[\d,;\s]+[A-Za-z]//gi;
      $self->add_raw_tap_line($line);
    }
}

1;
