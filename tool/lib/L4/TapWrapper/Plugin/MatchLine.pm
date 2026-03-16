package L4::TapWrapper::Plugin::MatchLine;

use strict;
use warnings;

use parent 'L4::TapWrapper::Plugin';

sub new {
  my ($type, $args) = @_;
  my $parent = L4::TapWrapper::Plugin->new($args);
  my $self = bless $parent, $type;

  $self->{args} = $args;

  die "MatchLine: Please specify 'good' option"
    unless defined $self->{args}{good};

  die "MatchLine: Please specify 'tap_description' option"
    unless defined $self->{args}{tap_description};

  $self->{goodre} = qr/$self->{args}{good}/;
  $self->{badre} = qr/$self->{args}{bad}/
    if defined $self->{args}{bad};

  $self->{done} = 0;

  $self->inhibit_exit();

  return $self;
}

sub process_any {
  my ($self, $line) = @_;

  return if $self->{done};

  chomp $line;

  $line =~ s/\e\[[\d,;\s]*[A-Za-z]//gi; # strip color escapes

  if ($line =~ $self->{goodre})
    {
      $self->{done} = 1;
      $self->permit_exit();
      $self->add_raw_tap_line("ok $self->{args}{tap_description}\n");
      $self->add_raw_tap_line("# Test-uuid: $self->{args}{uuid}\n") if $self->{args}{uuid};
      $self->add_raw_tap_line("1..1");
    }
  elsif (defined($self->{badre}) && $line =~ $self->{badre})
    {
      $self->{done} = 1;
      $self->permit_exit();
      $self->add_raw_tap_line("not ok $self->{args}{tap_description}\n");
      $self->add_raw_tap_line("# Test-uuid: $self->{args}{uuid}\n") if $self->{args}{uuid};
      $self->add_raw_tap_line("# $line\n");
      $self->add_raw_tap_line("1..1");
    }
}

1;

__END__

=head1 Plugin to match against a line of output

This plugin is a light variant of the OutputMatching plugin. It takes a
required `tap_description`, a required `good` regex, and an optional
`bad` regex as plugin arguments. If the `good` regex is found within a
line of the output, the test is deemed successful. If the `bad` regex
is specified and is found within a line of the output, the test is
deemed a failure. The `good` regex is prioritized, which means if both
regexes are found in the same line the test is deemed successful.

=head2 Options

This plugin has the following options:

=over

=item C<tap_description>

Required. The description after the "ok"/"not ok" keyword in the TAP.

=item C<good>

Required. The good regex. If this regex is found in the output, then the test
is deemed successful and a "ok" line will be added to the TAP with
C<tap_description> as the TAP description.

=item C<bad>

Optional. The bad regex. If this regex is found in the output, then the test
is deemed a failure and a "not ok" line will be added to the TAP with
C<tap_description> as the TAP description.

=item C<uuid>

Optional. The Test-uuid for this test.

=back

=head2 Usage

Specify for a particular testrun using the TEST_TAP_PLUGINS variable.
Example:

  TEST_TAP_PLUGINS="MatchLine:tap_description=MyTest,good='Hooray',bad='Booo'"

=cut
