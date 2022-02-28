package L4::TapWrapper::Plugin::BundleMode;

use File::Basename;

use parent 'L4::TapWrapper::Plugin';
use L4::TapWrapper::Plugin::TAPOutput;
use L4::TapWrapper;

sub new {
  my $self = L4::TapWrapper::Plugin->new();
  $self->{block_count} = 0;         # How many block starts we have seen
  $self->{block_count_expect} = -1; # Default that will indicate failure
  return bless $self, shift;
}

# We use the legacy format
sub check_start {
  my $self = shift;
  return unless shift =~ m/BUNDLE TEST START/;
  $self->{have_bundle} = 1;
  $self->{TAPOutput} = L4::TapWrapper::steal_plugin("TAPOutput");
  $self->inhibit_exit();

  $L4::TapWrapper::print_to_tap_fd = 1; # Bundles always print
  $self->{in_block} = 1;
}

sub check_end {
  my $self = shift;
  return unless shift =~ m/BUNDLE TEST FINISH/;
  $self->{in_block} = 0;
  $self->permit_exit();
}

sub process_mine {
  my $self = shift;
  my $line = shift;
  if ($line =~ /BUNDLE TEST EXPECT TEST COUNT (\d+)/)
    {
      $self->{block_count_expect} = 0 + $1;
    }
  else
    {
      $self->{TAPOutput}->process_any($line);

      # Look for new block if this one is done
      if (!$self->{TAPOutput}->{inhibit_exit})
        {
          $self->add_raw_tap_line($_) foreach $self->{TAPOutput}->finalize();
          $self->{TAPOutput} = L4::TapWrapper::Plugin::TAPOutput->new();
          $self->{block_count}++;
        }
    }
}

sub finalize {
  my $self = shift;
  return unless defined($self->{have_bundle});
  $self->add_raw_tap_line("1..1");
  $self->add_tap_line($self->{block_count_expect} == $self->{block_count},
                      "BUNDLE: Expected $self->{block_count_expect} TAP TEST blocks, found $self->{block_count}");
  return $self->SUPER::finalize();
}

1;
