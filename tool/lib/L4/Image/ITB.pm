package L4::Image::ITB;

use warnings;
use strict;
use File::Temp qw/tempfile/;
use L4::Image::Raw;
use L4::Image::Utils::FDT;
use L4::Image::Utils qw/rtrim_zerobytes/;

sub new
{
  my $class = shift;
  my $fn = shift;
  my $itbkey = shift;

  open(my $fd, "<", $fn) || error("Could not open '$fn': $!");
  binmode($fd);

  my $obj = bless {
    fdt => L4::Image::Utils::FDT->new_fd($fd),
    itbkey => $itbkey,
  }, $class;

  return $obj;
}

sub dispose
{
  my $self = shift;
  $self->{fdt}->dispose();
}

sub is_kernel { rtrim_zerobytes(shift->{properties}{type}) eq "kernel" }

sub unpack_inner
{
  my $self = shift;
  my $images = $self->{fdt}->{structure}{children}{images}{children};
  my @kernels = grep { is_kernel($images->{$_}) } keys %$images;

  my $selected_image_key;
  if (defined($self->{itbkey}))
    {
      $selected_image_key = $self->{itbkey};
    }
  elsif (@kernels == 1)
    {
      ($selected_image_key) = @kernels;
    }
  elsif (@kernels > 1)
    {
      print STDERR "This ITB file contains multiple kernels:\n\n";

      foreach my $k (@kernels)
        {
          my $image = $images->{$k};

          printf STDERR "  - %s: %s\n",
            $k,
            ($image->{properties}{description} // "<No description>");
        }

      print STDERR "\nPlease select one via the --itbkey flag\n";

      die "\n";
    }
  else
    {
      die "ITB file does not contain any kernels\n";
    }

  die "Image $selected_image_key not found" unless exists $images->{$selected_image_key};

  my $selected_image = $self->{selected_image} = $images->{$selected_image_key};

  die "Image is not a kernel" unless rtrim_zerobytes($selected_image->{properties}{type}) eq "kernel";
  die "Compression not yet supported in ITB images"
    unless rtrim_zerobytes($selected_image->{properties}{compression}) eq "none";

  my $loadbytes = $selected_image->{properties}{load};
  my $loadaddr = unpack("L>",$loadbytes);

  my ($fd, $filename) = tempfile("l4image-itb-inner-XXXXXXXXX", TMPDIR => 1, UNLINK => 1);
  binmode($fd);

  print $fd $selected_image->{properties}{data};

  close($fd);

  $self->{'inner-vaddr'} = $loadaddr;

  return ($filename, $loadaddr);
}

sub write_image {
  my $self = shift;
  my $vaddr = shift; # Useless: ITB doesn't know the concept of a vaddr.
  my $ofn = shift;
  my $write_cb = shift;

  # Put write_cb into data property of selected image
  # Call will be handled by write_fdt_token
  $self->{selected_image}{properties}{data} = $write_cb;

  # Remove children (hash nodes)
  $self->{selected_image}{children} = {};

  # Open new image
  open(my $ofd, '>', $ofn);
  binmode $ofd;

  # Write everything
  $self->{fdt}->write_file($ofd);

  # Close new image
  close($ofd);
}

1;
