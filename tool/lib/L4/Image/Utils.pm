package L4::Image::Utils;

use warnings;
use strict;
use Exporter;

use vars qw(@ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw(error check_syswrite check_sysread checked_sysseek
             filepos_get filepos_set sysreadz syswritez
             rtrim_zerobytes alignto alignto_fd);


sub error
{
  print STDERR "Error: ", shift, "\n";
  print STDERR "Call trace:\n";
  my $i = 0;
  my @d;
  print STDERR $d[1].":".$d[2]." (".$d[3].")\n" while @d = caller($i++);

  exit 1;
}

sub check_syswrite
{
  my $r = shift;
  my $wr_size = shift;
  error("Write error: $!") unless defined $r;
  error("Did not write all data ($r < $wr_size)") if $wr_size != $r;
  $r;
}

sub check_sysread
{
  my $r = shift;
  my $rd_size = shift;
  error("Read error: $!") unless defined $r;
  error("Did not read all data ($r < $rd_size)") if $rd_size != $r;
  $r;
}

sub sysreadz
{
  my $fd = shift;
  my $string_addr = filepos_get($fd);
  my $string = "";
  my $chunk;
  my $strlen;

  while (($strlen = index($string,"\0")) == -1)
    {
      sysread($fd,$chunk,16) or die "Incomplete c string: $!";
      $string .= $chunk;
    }

  # Move fd to after 0-byte
  filepos_set($fd, $string_addr + $strlen + 1);

  return substr($string, 0, $strlen);
}

sub syswritez
{
  my ($fd, $string) = @_;
  syswrite($fd, $string . "\0");
}

sub checked_sysseek
{
  my ($fd, $p, $what) = @_;

  my $r = sysseek($fd, $p, $what);
  die "sysseek failed" unless defined $r;

  return $r + 0;
}

sub filepos_get
{
  return checked_sysseek(shift, 0, 1);
}

sub filepos_set
{
  return checked_sysseek(shift, shift, 0);
}

sub rtrim_zerobytes {
  return shift =~ s/\0*$//r;
}

sub alignto {
  my ($addr, $alignment) = @_;

  my $padding = $alignment - ($addr % $alignment);
  $padding = 0 if $padding == $alignment;

  return $addr + $padding;
}

sub alignto_fd {
  my ($fd, $alignment) = @_;
  my $curpos = filepos_get($fd);
  my $newpos = alignto($curpos, $alignment);
  my $fsize = checked_sysseek($fd, 0, 2);

  if ($newpos < $fsize)
    {
      filepos_set($fd, $newpos);
    }
  else
    {
      syswrite($fd, "\0" x ($newpos - $fsize));
    }

  return $newpos;
}


1;
