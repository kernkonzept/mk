package L4::TapWrapper;

use warnings;
use strict;
use 5.010;

use File::Basename;
use Module::Load;
use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Indent = 0;

use L4::TapWrapper::Util qw/kill_ps_tree/;

our @_plugins;
our @_filters;
our $TAP_FD;
our $print_to_tap_fd = 1;
our $plugintmpdir = undef;
our %_have_plugins = ();
our $timeout;
our $wait_for_more = 0;
our $test_description;
our $expline;
our $pid = -1;

sub __load_module
{
  my $class = shift;
  my $arg = shift;
  my $c;
  eval {
    load $class;
    $c = $class->new( $arg );
    die unless $c;
    1;
  } or do {
    fail_test("Unable to load '$class': $@");
  };
  return $c;
}

sub get_plugin
{
  my $name = shift;
  my $arg = shift;
  my $class = "L4::TapWrapper::Plugin::$name";
  return __load_module($class, $arg);
}

sub load_plugin
{
  my $name = shift;
  my $arg = shift;
  return if defined $_have_plugins{$name}; # Do not load twice
  print "Loading Plugin '$name' with args: " . Dumper($arg). "\n";
  my $plugin = get_plugin($name, $arg);
  push @_plugins, $plugin;
  $_have_plugins{$name} = $plugin;
}

sub parse_plugin
{
  my ($name, $arg) = split(/:/, shift, 2);
  $arg = "" unless defined $arg;
  my %harg = map { split(/=/, $_, 2) } (split (/,/, $arg));
  return ($name, \%harg);
}

sub load_filter
{
  my $name = shift;
  my $arg = shift;

  print "Loading Filter '$name' with args: " . Dumper($arg). "\n";
  my $class = "L4::TapWrapper::Filter::$name";
  my $filter = __load_module($class, $arg);
  push @_filters, $filter;
}

sub has_plugins_loaded
{
  return !!@_plugins;
}

sub plugin_features
{
  my $feature = shift;
  map { $_->{features}{$feature} } @_plugins;
}

# Removes named plugin and returns reference (if it existed, undef otherwise)
sub steal_plugin
{
  my $plugin = shift;
  @_plugins = grep { $_ != $_have_plugins{$plugin} } @_plugins;
  my $old_plugin = $_have_plugins{$plugin};
  delete $_have_plugins{$plugin};
  return $old_plugin;
}

sub process_input
{
  my @data = ( shift );

  for my $filter (@_filters)
    {
      @data = map { $filter->process_any($_) } @data;
    }

  for my $line ( @data )
    {
      my $no_exit = 0;
      for my $plugin (@_plugins)
        {
          $plugin->process_any($line);
          $no_exit ||= $plugin->{inhibit_exit};
        }
      return 1 unless $no_exit;
    }
  return 0;
}

sub finalize {
  # tell test runner to finish up
  # signals aren't passed to whole children tree - kill explicit
  kill_ps_tree($pid);
  $pid = -1; # clean behaviour on multiple calling

  my $plan_found = 0;
  my $taplines = 0;
  foreach (@_plugins, @_filters)
    {
      foreach ($_->finalize())
        {
          if (/^1\.\.([0-9]+)/)
            {
              $taplines += $1;
              $plan_found = 1;
            }
          else
            {
              # carriage returns in TAP lead to problems down the line
              s/\r+\n/\n/g;

              print $TAP_FD $_ if $print_to_tap_fd;
            }
        }
    }
  print $TAP_FD "1..$taplines\n" if $print_to_tap_fd && $plan_found;
}

sub fail_test
{
  my $long_msg = shift;
  my $exit_code = shift || 1;
  chomp $long_msg;

  print $TAP_FD <<EOT;
1..1
not ok 1 - execution - exit code $exit_code - $L4::TapWrapper::test_description
# Test-uuid: 00000000-0000-0000-0000-000000000000
  ---
  message: $long_msg
  severity: fail
  ...
EOT

  exit_test($exit_code)
}

sub exit_test
{
  my ($exit_code) = @_;

  # tell test runner to finish up
  # signals aren't passed to whole children tree - kill explicit
  kill_ps_tree($pid);
  $pid = -1; # clean behaviour on multiple calling

  # graceful exit override
  $exit_code = 0
    if (not defined $exit_code   # default
      or $exit_code == 69        # SKIP tests
      or $ENV{HARNESS_ACTIVE});  # run under 'prove'


  close($TAP_FD);
  exit($exit_code);
}

1;

__END__

=head1 TapWrapper tools

The generic TapWrapper functionality that can be re-used by plugins. This is
used to interact with the framework and the output processing.

=head2 Functions

The following functions are intended to be used by plugins for advanced
input processing:

=over

=item1 C<load_plugin>

Can be used to load an additional plugin (for example a dependency). Arguments
to the function are the name of the plugin to load as well as the argument
passed to its constructor.

=item1 C<steal_plugin>

If an argument with the name given in the only argument is already registered
it is removed from the list of all plugins and returned by the function. The
plugin will no longer be passed new input.

B<Important:> When a new plugin with the same name will be laded later on, a new
instance will be constructed! There will be no duplicate checking for stolen
plugins.

=item1 C<plugin_features>

Returns a list that for each plugin contains an entry indicating if that plugin
supports the feature. Can be used to control the test execution depending on
the loaded plugins. See Plugin.pm for defined features.

=item C<process_input>

Can be used to feed input to all plugins using the normal input loop, basically
generating additional input. It is advised to not use the function for such
purposes if possible and rely on input stealing and filtering / explicit input
feeding instead.

=item C<fail_test>

Creates a TAP output with a I<not ok> status containing the error message
provided as the first argument and the exit code given as second argument.

Afterwards the wrapper is terminated with the given exit code.

If no exit code is provided it is assumed to be C<1>.

=item C<exit_test>

Terminates the wrapper using the exit code given as first argument without any
further TAP output. Before exiting the test runners' process tree is also
recursively terminated.

An exit code of C<0> is assumed if none is provided as argument.

=back

=head2 Variables

The namespace variables are provided to give plugins access to the test
environment:

=over

=item C<timeout>

The test timeout in seconds as set by the C<TEST_TIMEOUT> environment variable.
Defaults to C<10>.

=item C<test_description>

The test description string as provided by the C<TEST_DESCRIPTION> environment
variable. Defaults to the name of the test target.

=item C<expline>

A string describing what is expected from the output next. Used for more
informative diganostic output. This is mainly used by the OutputMatching plugin,
since the concept is ambiguous in the presence of multiple plugins.

=item C<wait_for_more>

A boolean variable indicating if, after all plugins signaled that the no longer
block exiting, we should wait for more data. Plugins that expect data of
undetermined amount after others have finished processing should set this to 1.

Defaults to 0.

=back


=cut
