package L4::TapWrapper::Util;

use warnings;
use strict;
use 5.010;

use POSIX;

use vars qw(@ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw(kill_ps_tree);

sub cat {
  my $file = shift;
  local $/ = undef;
  open my $fh, "<", $file or return undef;
  <$fh>;
};

sub get_pidmap
{
  opendir(my $proc_dh, "/proc");

  # Map parent -> child
  my %pidmap;
  # Map process -> state
  my %pidstate;

  while (my $pid = readdir($proc_dh))
    {
      next unless $pid =~ /^[0-9]+$/ && -d "/proc/$pid";

      # Turns $pid into integer
      $pid = 0+ $pid;

      my $stat = cat("/proc/$pid/stat");

      # process might have terminated since we called readdir
      next unless defined $stat;

      # The stat file's second field contains the cmdline wrapped in
      # parenthesis. This poses two problems when parsing it: The cmdline can
      # contain spaces, so we cannot just split the contents by whitespace
      # characters, and it may contain parenthesis too, so we can't just remove
      # it using a simple regex. The solution to this is removing everything
      # until the last closing parenthesis in the file plus the subsequent
      # whitespaces. Then the rest can be split by whitespace. This step removes
      # the first two fields, so info contains the fields starting with the 3rd
      # field: $info[0] is the running state (R/S/Z/...) and $info[1] is the
      # parent pid.
      $stat =~ s/^.+\)\s+([^\)]+)$/$1/;

      my @info = split /\s+/, $stat;

      # process state (R/S/Z/...)
      $pidstate{$pid} = $info[0];

      # parent pid
      my $ppid = 0+ $info[1];

      # Add an empty list of children unless there's already a list
      $pidmap{$ppid} = [] unless exists $pidmap{$ppid};

      # Add child to list
      push @{$pidmap{$ppid}}, $pid;
    }

  closedir $proc_dh;

  return (\%pidmap, \%pidstate);
}

sub get_ps_tree
{
  my ($pid) = @_;

  my ($pidmap,$pidstate) = get_pidmap();

  my @processing = ($pid);
  my @processed = ();

  while (my $p = shift @processing)
    {
      push @processing, @{$pidmap->{$p} || []};

      # Only gather non-zombie processes
      push @processed, $p unless $pidstate->{$p} eq "Z";
    }

  shift @processed if @processed && $processed[0] == $pid; # Remove $pid;

  return @processed;
}

# Kill a process tree beginning from the leaf nodes;
sub kill_ps_tree
{
  my ($pid) = @_;

  return unless $pid > 1;

  while (my @pids = get_ps_tree($pid))
    {
      my $innerpid = $pids[-1];
      if ($innerpid)
        {
          kill 'SIGTERM', $innerpid;
        }
    }
  kill 'SIGTERM', $pid;
  waitpid $pid, 0;
}

# Connect one fd pair to STDIN/STDOUT
# STDIN -> fdout
# fdin -> STDOUT
sub do_interactive
{
  my ($fdin,$fdout) = @_;

  my $fdno_stdin = fileno(STDIN);

  # Disable canonical mode (part of which is line buffering)
  my $termios = POSIX::Termios->new;
  $termios->getattr($fdno_stdin);
  my $old_lflag = $termios->getlflag;
  $termios->setlflag($old_lflag & ~(POSIX::ICANON | POSIX::ECHO));
  $termios->setattr($fdno_stdin, &POSIX::TCSADRAIN);

  my $rin = '';
  vec($rin,   $fdno_stdin, 1) = 1;
  vec($rin, fileno($fdin), 1) = 1;
  # Do interactive stuff
  while (1) {
    if (my $ret = select(my $rout = $rin, undef, undef, undef)) {
      my $buf;
      if ($ret == -1) {
        print STDERR "Select error: $!";
        last;
      } elsif (vec($rout, $fdno_stdin, 1)) {
        last if sysread(STDIN, $buf, 128) == 0;
        last if $buf =~ /\x03/; # Catch Ctrl-C
        syswrite($fdout, $buf);
      } elsif(vec($rout, fileno($fdin), 1)) {
        last if sysread($fdin, $buf, 128) == 0;
        syswrite(STDOUT, $buf);
      }
    }
  }

  # Enable canonical mode again (part of which is line buffering)
  $termios->setlflag($old_lflag);
  $termios->setattr($fdno_stdin, &POSIX::TCSADRAIN);
}

1;
