package L4::TapWrapper::Plugin::BundleMode;

use File::Basename;

use parent 'L4::TapWrapper::Plugin';
use L4::TapWrapper;

sub new {
  my $self = L4::TapWrapper::Plugin->new();
  $self->{block_count} = 0;         # How many block starts we have seen
  $self->{block_count_expect} = -1; # Default that will indicate failure
  $self->{BundleControl} = "TAPOutput";
  return bless $self, shift;
}

# We use the legacy format
sub check_start {
  my $self = shift;
  return unless shift =~ m/BUNDLE TEST START/;
  $self->{have_bundle} = 1;
  $self->{SubPlugin} = L4::TapWrapper::steal_plugin("TAPOutput");
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
      my $hard_terminate_plugin = 0;
      # BUNDLE CONTROL must happen after one test output was finalized and
      # before any new output by the next test. It removes the currently loaded
      # plugin, discarding any tap lines it may have aquired between the
      # previous plugins finalization and the BUNDLE CONTROL line.
      if ($line =~ /BUNDLE CONTROL (.*)/)
        {
          $self->{BundleControl} = $1 =~ s/^\s+|\s+$//gr;
          $self->{SubPlugin}->permit_exit();
          $hard_terminate_plugin = 1;
        }
      else
        {
          $self->{SubPlugin}->process_any($line);
        }

      # Look for new block if this one is done
      if (!$self->{SubPlugin}->{inhibit_exit})
        {
          unless ($hard_terminate_plugin)
            {
              $self->add_raw_tap_line($_) foreach $self->{SubPlugin}->finalize();
              $self->{block_count}++;
            }
          my ($name, $arg) = L4::TapWrapper::parse_plugin($self->{BundleControl});
          $arg->{no_boot} = 1; # Make clear that no reboot happened!
          $self->{SubPlugin} = L4::TapWrapper::get_plugin($name, $arg);
        }
    }
}

sub finalize {
  my $self = shift;
  return unless defined($self->{have_bundle});
  $self->add_raw_tap_line("1..1\n");
  $self->add_tap_line($self->{block_count_expect} == $self->{block_count},
                      "BUNDLE: Expected $self->{block_count_expect} TAP TEST blocks, found $self->{block_count}");
  # Satisfy requirement for a uuid on every ok line, but don't use a real
  # looking UUID because this ok line doesn't really test anything substantial.
  $self->add_raw_tap_line("#  Test-uuid: 00000000-0000-0000-0000-000000000000\n");

  return $self->SUPER::finalize();
}

1;


__END__

=head1 Plugin for bundling together multiple tests

This is a special plugin that instantiates other plugins for multiple run tests.
The plugin will start running when it detects C<BUNDLE TEST START> at the
test output. It defaults to instantiating the TAPOutput plugin and will
re-instantiate the previous plugin every time a plugin has indicated it is
finished until it finds the line C<BUNDLE TEST FINISH>.

There is an integrity check. A bundle test must specify how many test instances
are supposed to be found. This is specified using the
C<BUNDLE TEST EXPECT TEST COUNT n> line, where C<n> is the number of expected
tests. This line must come after a C<BUNDLE TEST START> line. The amount of
actual tests and expected tests is checked at the end and a dedicated TAP line
is generated for this comparison.

To change which plugin is loaded BundleMode also interprets lines starting with
C<BUNDLE CONTROL plugin> where C<plugin> is the specification for the I<single>
plugin to be loaded. C<BUNDLE CONTROL > must only appear between test runs,
especially only after the previous test output was finished. This is because the
currently instantiated plugin will be force-fully terminated and replaced upon
encountering a C<BUNDLE CONTROL > line. Thus any test output from that plugin
may be lost. This does not lead to false positive test results due to the
C<EXPECTED TEST COUNT> integrity check.

To indicate that plugins must not expect a system boot the BundleMode plugin
sets the C<no_boot> plugin argument upon loading sub-plugins. Plugins that
expect a system boot (i.e. bootstrap or kernel boot output) should deal with
this, or they cannot be bundled.

=head1 Current limitations

This plugin currently does not work with repeat test runs. The results are
currently undefined. Don't use them.

Bundles cannot currently be nested. Do not try to do this.

C<BUNDLE CONTROL> only allows a single plugin to be specified.

=head1 Options

There are currently no options for this plugin.

=head1 Usage

Specify for a particular testrun using the TEST_TAP_PLUGINS variable.
Example:

  TEST_TAP_PLUGINS=BundleMode

=cut
