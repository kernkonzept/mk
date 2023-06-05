package L4::Makeconf;
use strict;
use warnings;
use Cwd qw(realpath);

sub get {
  my ($objdir, $var) = @_;
  my $l4dir = $ENV{L4DIR} || realpath("${objdir}/source");

  die "Could not find L4DIR"
    unless defined $l4dir;

  my $value = qx(echo 'include mk/Makeconf\nall::\n\t\@echo;echo;echo \$(${var})' | make -C "${l4dir}" -f - --no-print-directory O="${objdir}" L4DIR="${l4dir}" INCLUDE_BOOT_CONFIG=y | tail -1);
  chomp $value;

  $value = undef if $value eq "";

  return $value;
}

1;
