package L4::Makeconf;
use strict;
use warnings;
use Cwd qw(realpath);

sub get {
  my ($objdir, $var) = @_;
  my $l4dir = realpath($ENV{L4DIR});

  my $value = qx(echo 'include mk/Makeconf\nall::\n\t\@echo \$(${var})' | make -C "${l4dir}" -f - --no-print-directory O="${objdir}" L4DIR="${l4dir}");
  chomp $value;

  $value = undef if $value eq "";

  return $value;
}

1;
