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
our $logdir;
our $print_to_tap_fd = 1;
our $harness_active;
our $plugintmpdir = undef;
our $timeout;
our $wait_for_more = 0;
our $test_description;
our $pid = -1;
our %loaded_plugins;

sub plugin_to_module { "L4::TapWrapper::Plugin::" . shift; }

sub __safe_load
{
  my $class = shift;

  eval {
    load $class;
    1;
  } or do {
    fail_test("Unable to load '$class'");
  };
}

sub __load_module
{
  my ($class, $arg) = @_;

  __safe_load($class);

  my $c = $class->new( $arg );

  fail_test("Unable to instantiate '$class': $@")
    unless defined $c;

  return $c;
}

sub get_plugin
{
  my $name = shift;
  my $arg = shift;
  my $class = plugin_to_module($name);
  return __load_module($class, $arg);
}

sub load_plugin
{
  my $name = shift;
  my $arg = shift;

  # Load class to check if plugin supports multiloading
  my $class = plugin_to_module($name);
  __safe_load($class);
  fail_test("Plugin '$name' does not support being loaded multiple times.")
    if $loaded_plugins{$class} && !$class->supports_multiload();

  print "Loading Plugin '$name' with args: " . Dumper($arg). "\n";

  my $plugin = get_plugin($name, $arg);

  $loaded_plugins{$class} = 1;

  push @_plugins, $plugin;
}


our %escape_map = (n => "\n", t => "\t", r => "\r", '"' => '"', "'" => "'");

sub parse_escape {
  my $str = shift;
  return undef unless defined $str;
  return $str =~ s,\\(.),$escape_map{$1} // "",rge;
}

sub parse_options
{
  my ($rest) = @_;
  my %options;

  while ($rest =~ s/^(\w+)=([^',\s]*|'((\\.|[^'])*)')(,|\s+|$)//)
    {
      my ($k, $v, $delim) = ($1, parse_escape($3) // $2, $5);
      $options{$k} = $v;

      last unless $delim eq ",";
    }

  return (\%options, $rest);
}

sub __parse_one_plugin
{
  my ($rest) = @_;

  return (undef, undef, $rest) unless $rest =~ s/^\s*(\w+)(:)?//;

  my ($name, $delim) = ($1,$2);

  my $options = {};

  ($options, $rest) = parse_options($rest) if $delim;

  return ($name, $options, $rest);
}


sub parse_plugins
{
  my ($rest) = @_;

  my @load;
  my $name;
  my $options;

  while (1) {
    ($name, $options, $rest) = __parse_one_plugin($rest);

    last unless defined $name;

    push @load, [$name, $options];
  }

  die "Unable to parse rest of plugins '$rest'"
    unless $rest =~ /^\s*$/;

  return @load;
}

sub parse_plugin
{
  my ($rest) = @_;

  my $name;
  my $options;

  ($name, $options, $rest) = __parse_one_plugin($rest);

  die "Unable to parse rest of plugins '$rest'"
    unless $rest =~ /^\s*$/;

  return ($name, $options);
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

# Removes plugin(s) with provided name
sub unload_plugin
{
  my $name = shift;

  my $class = plugin_to_module($name);

  @_plugins = grep { ref($_) ne $class } @_plugins;

  delete $loaded_plugins{$class};
}

# Iterates over all plugin of type $name
sub iter_plugins($&)
{
  my ($name, $cb) = @_;

  my $class = plugin_to_module($name);

  foreach my $plugin (@_plugins)
    {
      next unless ref($plugin) eq $class;

      $cb->($plugin);
    }
}

sub process_input
{
  my $line = shift;

  for my $filter (@_filters)
    {
      $line = $filter->process_any($line);
    }

  for my $plugin (@_plugins)
    {
      $plugin->process_any($line);
    }
}

sub plugins_finished {
  my $inhibit_exit = 0;

  $inhibit_exit ||= $_->{inhibit_exit} foreach @_plugins;

  return !$inhibit_exit;
}

sub calculate_wait_for_more {
  # Backwards compatibility
  my $max_wfm_time = $wait_for_more ? 6 : 0;
  for my $plugin ( @_plugins )
    {
      my $wfm_time = $plugin->wait_for_more();
      $max_wfm_time = $wfm_time if $wfm_time > $max_wfm_time;
    }
  return $max_wfm_time;
}

sub finalize {
  # tell test runner to finish up
  # signals aren't passed to whole children tree - kill explicit
  kill_ps_tree($pid);
  $pid = -1; # clean behaviour on multiple calling

  my @all_log_lines;
  my $plan_found = 0;
  my @plan_explanations;
  my $plan_sum = 0;
  foreach my $pluggable (@_plugins, @_filters)
    {
      my ($tap_lines, $log_lines) = $pluggable->finalize();

      foreach (@$tap_lines)
        {
          if (/^1\.\.([0-9]+)(.*)$/)
            {
              $plan_sum += $1;
              $plan_found = 1;

              # Collect any #SKIPs at the end of plan lines
              my $explanation = $2 // "";
              $explanation =~ s/[\r\n]//g;
              $explanation =~ s/^\s+|\s+$//g;
              push @plan_explanations, [ref($pluggable),$explanation] if $explanation;
            }
          else
            {
              # carriage returns in TAP lead to problems down the line
              s/\r+\n/\n/g;

              print $TAP_FD $_ if $print_to_tap_fd;
            }
        }

      my $tag = ref($pluggable);
      $tag =~ s/^L4::TapWrapper::/@/;

      foreach (@$log_lines)
        {
          chomp;
          push @all_log_lines, "[$tag] $_\n";
        }
    }

  if (@all_log_lines)
    {
      # Write to plugin.log if harness active, else stdout
      my $fh;

      if ($harness_active)
        {
          open($fh, ">>", "$logdir/plugin.log");
        }
      else
        {
          $fh = \*STDOUT;
        }

      print $fh @all_log_lines;

      close($fh) if $harness_active;
    }

  return unless $print_to_tap_fd;

  if ($plan_sum != 0 || scalar(@plan_explanations) > 1)
    {
      foreach my $exp (@plan_explanations)
        {
          my ($class, $reason) = @$exp;
          $reason =~ s/^#\s*SKIP\s+//i;
          print $TAP_FD "ok $class #SKIP $reason\n";
          print $TAP_FD "# Test-uuid: 00000000-0000-0000-0000-000000000000\n";
          $plan_sum++;
        }
      @plan_explanations = ();
    }

  if ($plan_found)
    {
      print $TAP_FD "1..$plan_sum";
      if (@plan_explanations)
        {
          # Can only contain one here, because multiple are handled further up
          my ($class, $reason) = @{$plan_explanations[0]};

          print $TAP_FD " $reason";

          # We should not alter plain TAP output too much, so skip this when
          # using the TAPOutput plugin. In other cases we might want to know
          # which plugin added the reason
          print $TAP_FD " ($class)" unless $class eq plugin_to_module("TAPOutput");
        }
      print $TAP_FD "\n";
    }
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

  $_->on_exit() foreach @_plugins;

  # tell test runner to finish up
  # signals aren't passed to whole children tree - kill explicit
  kill_ps_tree($pid);
  $pid = -1; # clean behaviour on multiple calling

  # graceful exit override
  $exit_code = 0
    if (not defined $exit_code   # default
      or $exit_code == 69        # SKIP tests
      or $harness_active);       # run under 'prove'


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

=item1 C<unload_plugin>

Plugin with the name given in the only argument are removed from the list of all
plugins. The plugin will no longer be passed new input.

=item1 C<iter_plugins>

Iterates over all plugins with the name given as the first argument. For each
plugin found a callback, passed as the second argument, will be called with the
found plugin as first argument.

=item1 C<plugin_features>

Returns a list that for each plugin contains an entry indicating if that plugin
supports the feature. Can be used to control the test execution depending on
the loaded plugins. See Plugin.pm for defined features.

=item C<process_input>

Can be used to feed input to all plugins using the normal input loop, basically
generating additional input. It is advised to not use the function for such
purposes if possible and rely on input stealing and filtering / explicit input
feeding instead.

=item C<plugins_finished>

If any plugin inhibits the exit, returns 0. Otherwise 1.

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

=item C<wait_for_more>

(Deprecated: Please use wait_for_more in Plugin class)
A boolean variable indicating if, after all plugins signaled that the no longer
block exiting, we should wait for more data. Plugins that expect data of
undetermined amount after others have finished processing should set this to 1.

Defaults to 0.

=back


=cut
