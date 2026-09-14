package L4::Image::ITB;

use warnings;
use strict;
use File::Temp qw/tempfile/;
use L4::Image::Raw;
use L4::Image::Utils::FDT;
use L4::Image::Utils qw/error checked_sysseek filepos_get filepos_set
                        alignto alignto_fd copy_data rtrim_zerobytes/;

# Alignment of every payload stored behind the FIT structure.
use constant EXT_DATA_ALIGN => 8;

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

sub prop_u32 { unpack("L>", substr(shift, 0, 4)) }

# Position and size of an image payload that is stored behind the FIT
# structure, undef if the image carries its data inline in the 'data'
# property.
#
# 'data-offset' is relative to the end of the FIT structure rounded up to 4
# bytes, 'data-position' is an absolute file offset.
sub external_data
{
  my ($self, $image) = @_;
  my $props = $image->{properties};

  return undef if exists $props->{data};
  return undef unless exists $props->{'data-size'};

  my $pos;
  if (exists $props->{'data-position'})
    {
      $pos = prop_u32($props->{'data-position'});
    }
  elsif (exists $props->{'data-offset'})
    {
      $pos = alignto($self->{fdt}{header}{totalsize}, 4)
             + prop_u32($props->{'data-offset'});
    }
  else
    {
      return undef;
    }

  return { pos => $pos, size => prop_u32($props->{'data-size'}) };
}

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
  $self->{selected_image_key} = $selected_image_key;

  die "Image is not a kernel" unless rtrim_zerobytes($selected_image->{properties}{type}) eq "kernel";
  die "Compression not yet supported in ITB images"
    unless rtrim_zerobytes($selected_image->{properties}{compression}) eq "none";

  my ($fd, $filename) = tempfile("l4image-itb-inner-XXXXXXXXX", TMPDIR => 1, UNLINK => 1);
  binmode($fd);

  my $ext = $self->external_data($selected_image);

  if ($ext)
    {
      copy_data($self->{fdt}{fd}, $fd, $ext->{pos}, $ext->{size});
    }
  else
    {
      print $fd $selected_image->{properties}{data};
    }

  close($fd);

  # Needs to exist but is unused.
  # Will be passed to write_image() as $vaddr;
  $self->{'inner-vaddr'} = 0;

  return $filename;
}

# Write a payload behind everything written so far and let the image
# properties point to it.
sub write_payload
{
  my ($ofd, $props, $write) = @_;

  alignto_fd($ofd, EXT_DATA_ALIGN);
  my $start = filepos_get($ofd);

  $write->();

  my $end = checked_sysseek($ofd, 0, 2);

  $props->{'data-position'} = pack("L>", $start);
  $props->{'data-size'} = pack("L>", $end - $start);
}

# Write an image whose payloads are stored behind the FIT structure.
#
# The structure is written twice: the positions of the payloads are only
# known after they have been written, and they in turn have to go behind the
# structure. The second pass overwrites the first one byte for byte because
# 'data-position' and 'data-size' have a fixed width, so only their values
# change.
sub write_external
{
  my ($self, $ofd, $write_cb, $data_locations) = @_;

  my $fdt = $self->{fdt};
  my $images = $fdt->{structure}{children}{images}{children};
  my $selected_props = $self->{selected_image}{properties};

  # The payload of the selected image is stored externally as well, even if
  # it was inline in the input image.
  delete $selected_props->{data};

  foreach my $props ($selected_props,
                     map { $images->{$_}{properties} } keys %$data_locations)
    {
      delete $props->{'data-offset'};
      $props->{'data-position'} = pack("L>", 0);
      $props->{'data-size'} = pack("L>", 0);
    }

  $fdt->write_file($ofd);
  my $struct_size = $fdt->{header}{totalsize};

  filepos_set($ofd, $struct_size);

  write_payload($ofd, $selected_props, sub { $write_cb->($ofd) });

  foreach my $key (sort keys %$data_locations)
    {
      my $loc = $data_locations->{$key};

      write_payload($ofd, $images->{$key}{properties},
                    sub { copy_data($fdt->{fd}, $ofd, $loc->{pos}, $loc->{size}) });
    }

  filepos_set($ofd, 0);
  $fdt->write_file($ofd);

  error("FIT structure changed size while writing the image")
    if $fdt->{header}{totalsize} != $struct_size;
}

sub write_image {
  my $self = shift;
  my $vaddr = shift; # Useless: ITB doesn't know the concept of a vaddr.
  my $ofn = shift;
  my $write_cb = shift;

  # Remove children (hash nodes)
  $self->{selected_image}{children} = {};

  # Payloads of all other images that are stored behind the FIT structure.
  # They have to be copied over from the input image.
  my $images = $self->{fdt}{structure}{children}{images}{children};
  my %data_locations;
  foreach my $key (keys %$images)
    {
      next if $key eq $self->{selected_image_key};

      my $ext = $self->external_data($images->{$key});
      $data_locations{$key} = $ext if $ext;
    }

  # Open new image
  open(my $ofd, '+>', $ofn) || error("Could not open '$ofn': $!");
  binmode $ofd;

  if (%data_locations || $self->external_data($self->{selected_image}))
    {
      $self->write_external($ofd, $write_cb, \%data_locations);
    }
  else
    {
      # Put write_cb into data property of selected image
      # Call will be handled by write_fdt_token
      $self->{selected_image}{properties}{data} = $write_cb;

      # Write everything
      $self->{fdt}->write_file($ofd);
    }

  # Close new image
  close($ofd);
}

1;
