package L4::TapWrapper::Util;

use warnings;
use strict;
use 5.010;

use vars qw(@ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw(kill_ps_tree);

sub get_ps_tree
{
  my ($pid) = @_;

  return () unless $pid && $pid > 1;

  my @pids = ($pid);
  eval
    {
      require Proc::Killfam;
      require Proc::ProcessTable;
      @pids = Proc::Killfam::get_pids([grep { $_->state ne 'defunct' } @{Proc::ProcessTable->new->table}], $pid);
    };
  if ($@) # no Proc::Killfam available; use external 'pstree';
    {
      # 'echo' turns deeper pstree output into one line;
      # pids are in (parens), so 'split' on '()' and take every 2nd entry
      my @pstree = map { split(/[()]/) } qx{echo \$(pstree -lp $pid)};
      @pids = @pstree[grep $_ % 2, 0..$#pstree];
      @pids = grep { system("ps -ax -o pid=,stat= | grep -q '^$_ Z\$'") != 0 } @pids; # ignore zombies
    }
  return @pids;
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
          waitpid $innerpid, 0;
        }
    }
  kill 'SIGTERM', $pid;
  waitpid $pid, 0;
}

1;
