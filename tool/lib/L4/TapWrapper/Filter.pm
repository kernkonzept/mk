package L4::TapWrapper::Filter;

use 5.010;

sub new {
  my $self = {};
  return bless $self, shift;
}

sub add_tap_line {
  my $self = shift;
  my $cname = (ref($self) =~ s/^L4::TapWrapper:://r);
  $self->add_raw_tap_line((shift ? "" : "not ") . "ok ($cname) " . shift . "\n");
}

sub add_raw_tap_line {
  push @{shift->{tap_lines}}, shift;
}

sub finalize {
  return @{shift->{tap_lines}};
}

sub process_any {
  my $self = shift;
  return ( shift );
}

1;

=head1 Filter Interface

Filters are developed by inheriting from L4::TapWrapper::Filter and
putting the new plugin into the L4::TapWrapper::Filter namespace.

Filters may use the functionality of L<L4::TapWrapper> to interact with the
framework beyond the base implementation of the class. In particular they may 
fail the whole testrun in case of unexpected input.

Filters may have arguments that are passed to the C<new> function upon
construction of the filter in the form of a hash. Arguments and values must
contain neither spaces, equal signs, commas or colons.

=head2 Interface

Filters operate line based. Any state keeping is the task of the individual
filter implementation. The filter should implement the following functions
to transform the input before it is passed to later filters or, finally to
the plugins. Filters also can perform checks on the input data during or
before transformation which will be output as TAP data once processing has
concluded.

=over

=item C<process_any>

This function is called for every line of the input. It must return a,
potentially empty, list of lines that is transformed according to the
requirements of the filter. Created lines are then fed to the next filter, but
will not be fed again to the current filter or any previous filters in the
processing pipeline.

=item C<finalize>

Returns a list of all TAP lines that the filter wants to emit to the
framework. The framework aggregates these lines. In particular it merges
multiple C<1..count> lines by creating a total C<1..sum_count> line at the end
of the output.
The default implementations returns all lines that have been added to the
C<$self-E<gt>{tap_lines}> array using the C<add_tap_line> and
C<add_tap_line_raw> functions (see below).

=head2 Base Functions

Filters may use the following function to interact with the base filter:

=over

=item C<add_tap_line>, C<add_tap_line_raw>

Adds a line to the C<$self-E<gt>{tap_lines}> array, used for convenience such
that the default finalize implementation can be used. The C<add_tap_line_raw>
version just adds the sole argument to the array. The C<add_tap_line>
instantiation interprets the first argument as a boolean indicating success and
the second argument as a descriptive string, joining them for a complete TAP
line. It also adds the class name to the tap line for easier identification.

=back

=cut

