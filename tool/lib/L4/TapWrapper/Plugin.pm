package L4::TapWrapper::Plugin;

use 5.010;

sub new {
  my $type = shift;
  my $self = {};
  $self->{inhibit_exit} = 0;
  $self->{tap_lines} = [];
  return bless $self, $type;
}

# For use by plugins to add a TAP line. Send to framework during finalize
sub add_tap_line {
  shift->add_raw_tap_line((shift ? "" : "not ") . "ok " . shift . "\n");
}

sub add_raw_tap_line {
  push @{shift->{tap_lines}}, shift;
}

# Things to do after test is finished. Usually providing output.
# Returns list of tap lines
sub finalize {
  return @{shift->{tap_lines}};
}

# Guarantee: Not called if already within a block
sub check_start { }

# Guarantee: Not called if not in a block
sub check_end { }

# By default no tag
sub has_tag { return 0; }

sub process_any {
  my $self = shift;
  $self->{raw_line} = shift;
  $self->{clean_line} = $self->{raw_line};
  $self->check_end($self->{raw_line}) if $self->{in_block};
  $self->process_mine($self->{clean_line})
    if $self->{in_block} || $self->has_tag($self->{raw_line});
  $self->check_start($self->{raw_line}) unless $self->{in_block};
}

# Called for anything belonging to the plugin (as determined by block or tag)
sub process_mine {}

# TODO: Fail if already inhibiting? Allow nested inhibiting?
# Inhibit exiting the test, used if more data expected by plugin
sub inhibit_exit { shift->{inhibit_exit} = 1; }
sub permit_exit  { shift->{inhibit_exit} = 0; }

1;

__END__

=head1 Plugin Interface

Generally plugins are developed by inheriting from L4::TapWrapper::Plugin and
putting the new plugin into the L4::TapWrapper::Plugin namespace.

Plugins may use the functionality of L<L4::TapWrapper> to interact with the
framework beyond the base implementation of the class. In particular, to
interpose between other plugins they can I<steal> them from the framework,
potentially invoking them themselves using their C<process_any> generic
input processing function. Beware that inhibitor handling and finalization of
I<stolen> plugins is the duty of the stealer!

Plugins may have arguments that are passed to the C<new> function upon
construction of the plugin in the form of a hash. Arguments and values must
contain neither spaces, equal signs, commas or colons.

=head2 Interface

Plugins may override / implement the following functions to process the test
output (input to the plugin).

=over

=item C<process_mine>

This function is called for every line of the input that is within a block
belonging to the plugin or tagged with a tag belonging to the plugin. See
C<check_start>, C<check_end> and C<has_tag>. The only argument passed to the
function is the raw line that is currently processed.

The default implementation is empty.

=item C<has_tag>

A function that receives the current raw line and returns B<true> if that line
matches the tag indicating that it belongs to the plugin, B<false> otherwise.

The function is only called if we are not currently in a block context for the
plugin (See C<check_start> and C<check_end> below.

The default implementation returns 0, indicating that no tagged lines exist
for the plugin. The plugin may set the clean_line data member on the class, in
case it wants the processing function to receive the cleaned up data without
the tag. The argument to the function is equivalent to C<$self-E<gt>{raw_line}>
and C<$self-E<gt>{clean_line}>.

=item C<check_start> / C<check_end>

Functions receiving a raw line as only input and determining the boundaries of
output blocks belonging to the plugin. If a plugin decides in a C<check_start>
call that all further code for it should be processed using its C<process_mine>
function then it needs to set the C<$self-E<gt>{in_block}> value to a B<true>
value. All further lines will be passed to C<process_mine> and C<check_end> (in
that order).

Plugins can determine the end of such a block by setting the
C<$self-E<gt>{in_block}> value to a B<false> value, preferably in a C<check_end>
function. Then all further lines will only be processed by C<check_start>
unless C<has_tag> returns a B<true> value.

The default implementation is empty, indicating that there are no block markers
for the plugin.

=item C<finalize>

Returns all TAP lines that the plugin wants to emit to the framework as an
array. The framework aggregates these lines. In particular it merges multiple
C<1..count> lines by creating a total C<1..sum_count> line at the end of the
output.

The default implementations returns all lines that have been added to the
C<$self-E<gt>{tap_lines}> array using the C<add_tap_line> and
C<add_tap_line_raw> functions (see below).

=back

=head2 Base Functions

Plugins may use the following functions to interact with the wrapper (or the
base plugin)

=over

=item C<permit_exit> / C<inhibit_exit>

A plugin is expected to call C<inhibit_exit> if it wants to prevent the
tap-wrapper from terminating the test because no plugin requires further input.
At least one plugin should call this in the constructor. Otherwise the wrapper
might immediately exit since no plugin depends on further output from the test.

If a plugin does not expect further input it B<must> call C<permit_exit>. It
will still receive calls to its interface functions that receive input so it
can decide to re-issue C<inhibit_exit> if it decides so based on that further
input.

The result of calling C<permit_exit> or C<inhibit_exit> repeatedly
(non-alternating) is undefined.

=item C<add_tap_line>, C<add_tap_line_raw>

Adds a line to the C<$self-E<gt>{tap_lines}> array, used for convenience such
that the default finalize implementation can be used. The C<add_tap_line_raw>
version just adds the sole argument to the array. The C<add_tap_line>
instantiation interprets the first argument as a boolean indicating success and
the second argument as a descriptive string, joining them for a complete TAP
line.

=back

=cut

