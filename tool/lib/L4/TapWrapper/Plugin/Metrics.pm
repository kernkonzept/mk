package L4::TapWrapper::Plugin::Metrics;

use strict;
use warnings;

use parent 'L4::TapWrapper::Plugin::TagPluginBase';

sub new {
  my ($type, $args) = @_;
  $args->{tag} = "metrics";

  my $parent = L4::TapWrapper::Plugin::TagPluginBase->new($args);
  my $self = bless $parent, $type;

  $self->{args} = $args;

  $self->{metrics} = [];
  $self->{faulty_lines} = [];

  return $self;
}

sub process_mine {
  my ($self, $line) = @_;

  my @datapoint;
  my %keys_special = map { uc($_) => 1 } qw(NAME VALUE UNIT CREATED VALUE_ID);
  my %keys_forbidden = map { uc($_) => 1 } qw(CREATED VALUE_ID);
  my %keys_seen;
  my $faulty = 0;

  my $rest = $line;

  while ($rest =~ s/^\s*([a-zA-Z_][a-zA-Z0-9_]*)=([^"\s]+|"((\\.|[^\"])+)"|)//)
    {
      my ($k, $v) = ($1, $3 // $2);

      my $k_uc = uc $k;

      if ($keys_seen{$k_uc} || $keys_forbidden{$k_uc})
        {
          $faulty = 1;
          last;
        }

      $keys_seen{$k_uc} = 1;

      $k = ($keys_special{$k_uc}) ? (uc $k) : (lc $k);

      push @datapoint, [ $k, $v ];
    }

  # If the line is faulty in any way, we drop the data point and show this
  # line as a TAP comment only.

  $faulty = 1 unless $keys_seen{NAME};
  $faulty = 1 unless $keys_seen{VALUE};
  $faulty = 1 unless @datapoint > 0;
  $faulty = 1 unless $rest =~ /^\s*$/;

  if ($faulty)
    {
      push @{$self->{faulty_lines}}, $line;
      return;
    }

  push @{$self->{metrics}}, \@datapoint
}

sub finalize {
  my ($self) = @_;

  if (@{$self->{metrics}})
    {
      $self->add_raw_tap_line("  ---\n");
      $self->add_raw_tap_line("  BenchmarkAnythingData:\n");

      for my $metric (@{$self->{metrics}})
        {
          $self->add_raw_tap_line("    -\n");

          for my $pair (@$metric)
            {
              my ($key, $value) = @$pair;
              $self->add_raw_tap_line("      $key: \"$value\"\n");
            }
        }

      $self->add_raw_tap_line("  ...\n");

      for my $line (@{$self->{faulty_lines}})
        {
          # Restrict line length
          $line =~ s/^(.{128}).+$/$1.../;

          $self->add_raw_tap_line("# FAULTY DATA POINT: $line\n");
        }
    }

  return $self->SUPER::finalize();
}

1;

__END__

=head1 Plugin to transform metric lines into BenchmarkAnythingData

This plugin parses special metric lines in the output of the test and turns
their content into BenchmarkAnythingData, which is then later embedded in the
TAP. Because this plugin merely collects metrics, does not wait for any
particular output and does not produce any TAP lines providing any test results,
it is supposed to be used in tandem with another plugin, such as TAPOutput or
OutputMatching.

=head2 Metrics format

The Metrics plugin uses the TagPluginBase format, which means there are two
methods to provide data points. The first method involves prefixing each data
point with "@@ metrics: ", e.g.:

  @@ metrics: NAME=l4re.bmk.fiasco.foobar VALUE=5 UNIT=us ...

The other method is for providing a whole block of data points, where each data
point is its own line. The block is started with the line

  @@ metrics @< BLOCK

and finished with the line

  @@ metrics BLOCK >@

Each line between these markers is then considered a separate data point. The
begin marker may be prefixed by other output, however all lines within the block
as well as the line with the end marker need to have the same prefix. Example:

  benchmark | @@ metrics @< BLOCK
  benchmark | NAME=l4re.bmk.fiasco.foobar VALUE=5 UNIT=us
  benchmark | NAME=l4re.bmk.fiasco.baz VALUE=6 UNIT=%
  benchmark | NAME=l4re.bmk.fiasco.time VALUE=2 UNIT=hour
  benchmark | NAME=l4re.bmk.fiasco.width VALUE=8 UNIT=meter
  benchmark | NAME=l4re.bmk.fiasco.height VALUE=20 UNIT=cm
  benchmark | @@ metrics BLOCK >@

=head2 Data point

Each data point is described by an inline list of one or more key value pairs,
as follows:

  NAME=l4re.bmk.fiasco.foobar VALUE=5 UNIT=us ...

=over

=item *

Each data point line may only contain a list of key-value pairs, encoded as
I<key>=I<value>.

=item *

There B<must not> be any whitespace before or after the
equal-sign (=).

=item *

The I<key> B<must> only contain lowercase and uppercase letters, digits and
underscores, but B<must not> start with a digits.

=item *

No I<key> may be specified more than once.

=item *

The I<key> B<must not> be C<CREATED> or C<VALUE_ID>.

=item *

The I<keys> C<NAME> and C<VALUE> are required.

=item *

The I<value> of a key value pair B<can> either be

=over

=item 1.

a series of zero or more non-whitespace characters also excluding double-quotes,
e.g. meter

=item 2.

or alternatively a properly escaped string in double-quotes, e.g. "This is a
full sentence with a \""

=back

=item *

Two consecutive I<key-value> pairs B<must> be separated by one or more
whitespace characters.

=item *

After the I<key-value> pairs the line B<must not> contain any characters except
for whitespace characters.

=item *

Improperly formatted data points are ignored, but added as a TAP comment.

=item *

The order of keys is retained while converting the data point into the
BenchmarkAnythingData format.


=back

=head2 Best practices

=over

=item *

The key C<NAME> is specified as the first key-value pair.

=item *

The key C<VALUE> is specified as the second key-value pair.

=item *

The optional key C<UNIT> is specified as the third key-value pair.

=item *

Any key, except for C<NAME>, C<VALUE> and C<UNIT>, are lowercase.

By convention UPPERCASED keys are reserved for special meaning, like NAME,
VALUE, and UNIT. The data storage augments these with some more special keys,
like a unique VALUE_ID and a CREATED timestamp. Therefore any other,
user-specified keys B<must> be lower case.

=back

=head2 Options

This plugin has no options

=head2 Usage

Specify for a particular testrun using the TEST_TAP_PLUGINS variable.
Example:

  TEST_TAP_PLUGINS="Metrics <other plugins>"

=cut
