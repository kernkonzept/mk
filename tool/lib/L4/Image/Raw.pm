# The RAW image format assumes that _start is at the start of the image file
# and everything is in a continuous address space from there on. The module
# data is expected to be at the end of the file.

package L4::Image::Raw;

use warnings;
use strict;
use Exporter;
use Fcntl qw(SEEK_SET SEEK_END);
use L4::Image::Utils qw/error check_sysread check_syswrite filepos_set/;

use vars qw(@ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw();

sub new
{
  my $class = shift;
  my $fn = shift;
  my $start_of_binary = shift;

  open(my $fd, "<", $fn) || error("Could not open '$fn': $!");
  binmode($fd);

  return bless {
    start_of_binary => $start_of_binary,
    fd => $fd,
  }, $class;
}

sub dispose
{
  my $self = shift;
  close($self->{'fd'});
}

sub vaddr_to_file_offset
{
  my $self = shift;
  my $vaddr = shift;

  return $vaddr - $self->{'start_of_binary'};
}

sub write_image
{
  my $self = shift;
  my $vaddr = shift;
  my $ofn = shift;
  my $write_cb = shift;

  my $offset = $self->vaddr_to_file_offset($vaddr);
  open(my $ofd, "+>$ofn") || error("Could not open '$ofn': $!");
  binmode $ofd;

  my $ifd = $self->{'fd'};

  # copy initial part
  my $buf;
  filepos_set($ifd, 0);
  check_sysread(sysread($ifd, $buf, $offset), $offset);
  check_syswrite(syswrite($ofd, $buf), length($buf));

  # write module data
  $write_cb->($ofd);

  # Adjust vmlinuz header if available
  patch_vmlinuz_header($ofd);

  close($ofd);
}

sub patch_vmlinuz_header
{
  my ($fd) = @_;

  my $image_size = sysseek($fd, 0, SEEK_END);

  # try arm32
  {
    sysseek($fd, 0, SEEK_SET);
    sysread($fd, my $buf, 14*4);

    my ($nop0, $nop1, $nop2, $nop3, $nop4, $nop5, $nop6, $nop7,
        $b_insn, $magic1, $start, $end, $magic2, $magic3)
      = unpack("(L14)<", substr($buf, 0, 14 * 4));

    if (   $nop0 == $nop1
        && $nop0 == $nop2
        && $nop0 == $nop3
        && $nop0 == $nop4
        && $nop0 == $nop5
        && $nop0 == $nop6
        && $nop0 == $nop7
        && $magic1 == 0x016f2818
        && $magic2 == 0x04030201
        && $magic3 == 0x45454545)
      {
        # Found vmlinuz signature, patch end of binary
        sysseek($fd, 11 * 4, SEEK_SET);
        my $r = syswrite($fd, pack("L<", $start + $image_size), 4);
        die "Could not patch binary" if not defined $r or $r != 4;

        return;
      }
  }

  # try arm64
  {
    sysseek($fd, 0, SEEK_SET);
    sysread($fd, my $buf, 8 * 8);

    my ($two_insns, $start, $old_size, $flags, $res1, $res2, $res3, $magic)
      = unpack("(Q8)<", substr($buf, 0, 8 * 8));

    if ( $magic == 0x644d5241 )
      {
        sysseek($fd, 2 * 8, SEEK_SET);
        my $r = syswrite($fd, pack("Q<", $image_size), 8);
        die "Could not patch binary" if not defined $r or $r != 8;

        return;
      }
  }
}

1;
