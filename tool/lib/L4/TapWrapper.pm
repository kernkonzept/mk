package L4::TapWrapper;

use warnings;
use strict;
use 5.010;

use File::Basename;
use Module::Load;
use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Indent = 0;

BEGIN { unshift @INC, dirname($0).'/../lib'; }

our @_plugins;
our $TAP_FD;
our $print_to_tap_fd = 1;
our %_have_plugins = ();

sub load_plugin
{
  my $name = shift;
  my $arg = shift;
  return if defined $_have_plugins{$name}; # Do not load twice
  print "Loading Plugin '$name' with args: " . Dumper($arg). "\n";
  my $class = "L4::TapWrapper::Plugin::$name";
  load $class;
  my $plugin = $class->new( $arg );
  push @_plugins, $plugin;
  $_have_plugins{$name} = $plugin;
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
  my $data = shift;
  my $no_exit = 0;

  for (@_plugins)
    {
      $_->process_any($data);
      $no_exit ||= $_->{inhibit_exit};
    }
  return !$no_exit;
}

sub finalize {
  my $taplines = 0;
  foreach (@_plugins)
    {
      foreach ($_->finalize())
        {
          if (/^1\.\.([0-9]+)/)
            {
              $taplines += $1;
            }
          else
            {
              print $TAP_FD $_ if $print_to_tap_fd;
            }
        }
    }
  print $TAP_FD "1..$taplines\n" if $print_to_tap_fd;
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

=item C<process_input>

Can be used to feed input to all plugins using the normal input loop, basically
generating additional input. It is advised to not use the function for such
purposes if possible and rely on input stealing and filtering / explicit input
feeding instead.

=back

=cut

