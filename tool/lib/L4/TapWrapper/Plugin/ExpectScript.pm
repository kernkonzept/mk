package L4::TapWrapper::Plugin::ExpectScript;

use strict;
use warnings;

use POSIX ":sys_wait_h";

use IPC::Open2;

use parent 'L4::TapWrapper::Plugin';

sub new {
  my $type = shift;
  my $parent = L4::TapWrapper::Plugin->new();
  my $self = bless $parent, $type;

  $self->{args} = shift;

  die "Missing tap_description"
    unless $self->{args}{tap_description};

  my $file = $self->{args}{file};

  if ($file !~ m{^/} && exists $ENV{SEARCHPATH})
    {
      foreach my $p (split(/:/, $ENV{SEARCHPATH}))
        {
          if (-f "$p/$file")
            {
              $file = "$p/$file";
              last;
            }
        }
    }

  die "Unable to find expect script $file"
    unless -f $file;

  $self->inhibit_exit();

  my $pid = open2(my $out, my $stream,
                 'expect',
                 '-c', 'set spawn_id $user_spawn_id', # expect on stdin
                 '-c', 'set timeout -1', # disable timeout as default. tap-wrapper handles it.
                 '-c', 'expect_after timeout {exit 1}', # default reaction to timeout is to fail.
                 '-f', $file) or die "Unable to run expect";

  $self->{expect_proc} = {
    pid => $pid,
    stream => $stream,
  };

  die "SIGCHLD already occupied"
    if defined $SIG{CHLD};

  $SIG{CHLD} = sub {
    if (waitpid($pid, WNOHANG) == $pid)
      {
        $self->expect_proc_terminated($? >> 8);

        $self->{expect_proc} = undef;

        # stop reacting to SIGCHLD
        delete $SIG{CHLD};

        # SIGCHLD will also interrupt sysread in tap-wrapper
      }
  };

  return $self;
}

sub expect_proc_terminated {
  my ($self, $exit_code) = @_;

  $self->permit_exit();

  $self->add_tap_line($exit_code == 0, $self->{args}{tap_description});
  $self->add_raw_tap_line("# Test-uuid: $self->{args}{uuid}\n")
    if defined $self->{args}{uuid};
  $self->add_raw_tap_line("1..1\n");
}

sub process_any {
  my ($self, $line) = @_;

  return unless defined $self->{expect_proc};

  $line =~ s/\e\[[\d,;\s]*[A-Za-z]//gi; #Strip color escapes
  $line =~ s/\r+(\n)?$/$1/g; # Remove \r, keep \n if present

  print { $self->{expect_proc}{stream} } $line;
}

sub on_exit {
  my $self = shift;

  # stop reacting to SIGCHLD
  delete $SIG{CHLD};

  # then kill expect process
  kill('TERM', $self->{expect_proc}{pid})
    if defined $self->{expect_proc};
}

1;

__END__

=head1 Plugin for matching output lines using Tcl/Expect

Match all output lines using a Tcl/Expect script. Exit code of the Tcl/Expect
script determines success of the test.

=head1 Options

The following options are defined

=over

=item C<file>

The Tcl/Expect script. Mandatory.

=item C<tap_description>

The tap description to be used in the ok/not ok line. Mandatory.

=item C<uuid>

The globally unique identifier of the test. Optional.

=back

=head1 Usage

Specify for a particular test using the TEST_TAP_PLUGINS variable.
Example:

  TEST_TAP_PLUGINS=ExpectScript:file=test.exp,uuid=<`uuidgen -r`>

=cut
