# The uImage format assumes that _start is at the start of the payload and
# everything is in a continuous address space from there on. The module data is
# expected to be at the end of the file.

package L4::Image::UImage;

use warnings;
use strict;
use Exporter;
use Compress::Zlib qw/crc32/;
use L4::Image::Utils qw/error check_sysread check_syswrite filepos_set/;
use L4::Image::Raw;

use vars qw(@ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw();

use constant {
  UIMAGE_HEADER_SIZE => 64,
};


sub uimage_header_update
{
  my ($self, $fd) = @_;
  my $buf;

  filepos_set($fd, 0);
  check_sysread(sysread($fd, $buf, UIMAGE_HEADER_SIZE), UIMAGE_HEADER_SIZE);

  my $uimage_pattern = "L>L>L>L>L>L>L>CCCCZ32";

  my ($ih_magic,
      $ih_hcrc,
      $ih_time,
      $ih_size,
      $ih_load,
      $ih_ep,
      $ih_dcrc,
      $ih_os,
      $ih_arch,
      $ih_type,
      $ih_comp,
      $ih_name) = unpack($uimage_pattern, $buf);

  printf("uimage: size=%d ih_ep=0x%x name='%s'\n", $ih_size, $ih_ep, $ih_name);

  $ih_size = (stat($fd))[7] - UIMAGE_HEADER_SIZE;

  my $dcrc = 0;
  my $chunk;
  while (my $len = sysread($fd, $chunk, 64 * 1024))
    {
      $dcrc = crc32($chunk, $dcrc);
    }

  $ih_dcrc = $dcrc;

  my $uimage_header = pack($uimage_pattern,
                           $ih_magic,
                           0,
                           $ih_time,
                           $ih_size,
                           $ih_load,
                           $ih_ep,
                           $ih_dcrc,
                           $ih_os,
                           $ih_arch,
                           $ih_type,
                           $ih_comp,
                           $ih_name);

  $ih_hcrc = crc32($uimage_header);

  $uimage_header = pack($uimage_pattern,
                        $ih_magic,
                        $ih_hcrc,
                        $ih_time,
                        $ih_size,
                        $ih_load,
                        $ih_ep,
                        $ih_dcrc,
                        $ih_os,
                        $ih_arch,
                        $ih_type,
                        $ih_comp,
                        $ih_name);

  filepos_set($fd, 0);
  check_syswrite(syswrite($fd, $uimage_header, length($uimage_header)),
                 UIMAGE_HEADER_SIZE);
}

#------------------------------------------------------------------------------

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

  return $vaddr - $self->{'start_of_binary'} + UIMAGE_HEADER_SIZE;
}

sub write_image
{
  my $self = shift;
  my $until_vaddr = shift;
  my $ofn = shift;
  my $write_cb = shift;

  my $offset = $self->vaddr_to_file_offset($until_vaddr);
  open(my $ofd, "+>$ofn") || error("Could not open '$ofn': $!");
  binmode $ofd;

  my $ifd = $self->{'fd'};

  # copy initial part
  my $buf;
  filepos_set($ifd, 0);
  check_sysread(sysread($ifd, $buf, $offset), $offset);
  check_syswrite(syswrite($ofd, $buf), length($buf));

  # Write new module data
  $write_cb->($ofd);

  # Patch vmlinuz header if necessary which sits right behind the uimage header
  # Must be done before updating the uimage header, because that contains a
  # crc32 of the image including the vmlinuz header
  L4::Image::Raw::patch_vmlinuz_header($ofd, UIMAGE_HEADER_SIZE);

  $self->uimage_header_update($ofd);

  close($ofd);
}

1;
