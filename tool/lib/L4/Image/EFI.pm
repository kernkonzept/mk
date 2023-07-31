# Rudementary implementation of PE header with the necessities for EFI files
# Assumes module data sits at the end of any PE section

package L4::Image::EFI;

use warnings;
use strict;
use Exporter;
use L4::Image::Utils qw/error check_sysread check_syswrite checked_sysseek filepos_set filepos_get/;
use L4::Image::Struct;

# Set to 1 to print debug information
$L4::Image::Struct::DEBUG = 0;

my $make_mz_header = L4::Image::Struct->define(
  "MZ header", 64, "Z2x58L",
  "magic",
  "pe_offset",
);

my $make_pe_header = L4::Image::Struct->define(
  "PE header", 24, "Z4SSLLLSS",
  "magic",
  "target",
  "num_sections",
  "timestamp",
  "ptr_symbol_table",
  "num_symbols",
  "size_optional_header",
  "characteristics",
);

my $make_oh_magic = L4::Image::Struct->define(
  "Optional Header Magic", 2, "S",
  "magic",
);

my $make_pe32p_header = L4::Image::Struct->define(
  "PE32+ Header (standard + win)", 112 - 2, "CCLLLLLQLLSSSSSSLLLLSSQQQQLL",
  "linker_version_major",
  "linker_version_minor",
  "size_code",
  "size_data",
  "size_bss",
  "entrypoint",
  "base_of_code",
  "imagebase",
  "alignment_section",
  "alignment_file",
  "os_version_major",
  "os_version_minor",
  "image_version_major",
  "image_version_minor",
  "subsystem_version_major",
  "subsystem_version_minor",
  "win32_version",
  "image_size",
  "header_size",
  "checksum",
  "subsystem",
  "dll_characteristics",
  "stack_reserve",
  "stack_commit",
  "heap_reserve",
  "heap_commit",
  "loader_flags",
  "num_datadirs",
);

my $make_pe32_header = L4::Image::Struct->define(
  "PE32 Header (standard + win)", 96 - 2, "CCLLLLLLLLLSSSSSSLLLLSSLLLLLL",
  "linker_version_major",
  "linker_version_minor",
  "size_code",
  "size_data",
  "size_bss",
  "entrypoint",
  "base_of_code",
  "base_of_data",
  "imagebase",
  "alignment_section",
  "alignment_file",
  "os_version_major",
  "os_version_minor",
  "image_version_major",
  "image_version_minor",
  "subsystem_version_major",
  "subsystem_version_minor",
  "win32_version",
  "image_size",
  "header_size",
  "checksum",
  "subsystem",
  "dll_characteristics",
  "stack_reserve",
  "stack_commit",
  "heap_reserve",
  "heap_commit",
  "loader_flags",
  "num_datadirs",
);

my $make_pe_data_dir = L4::Image::Struct->define(
  "PE data dir", 8, "LL",
  "addr",
  "size",
);

my $make_section_entry = L4::Image::Struct->define(
  "Section entry", 40, "Z8LLLLLLSSL",
  "name",
  "virt_size",
  "virt_addr",
  "raw_size",
  "raw_addr",
  "ptr_reloc",
  "ptr_linum",
  "num_reloc",
  "num_linum",
  "flags"
);

use constant {
  MZ_MAGIC => "MZ",
  PE_MAGIC => "PE",
  OH_MAGIC_PE32P => 0x20b,
  OH_MAGIC_PE32 => 0x10b,
  SUBSYSTEM_EFI_APPLICATION => 0xA,
  SECTION_FLAG_CODE => 0x20,
  SECTION_FLAG_DATA => 0x40,
  SECTION_FLAG_BSS => 0x80,
};

my @datadir_names = qw(Export Import Resource Exception Certificate BaseRelocation Debug Arch GlobalPtr TLS LoadConfig BoundImport IAT DelayImport CLRRuntimeHeader ReservedZ);

# Helper
sub align
{
  my ($size, $alignment) = @_;
  return (($size - 1) & ~($alignment - 1)) + $alignment;
}


use vars qw(@ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw();

sub new
{
  my $class = shift;
  my $fn = shift;

  open(my $fd, "<", $fn) || error("Could not open '$fn': $!");
  binmode($fd);

  my $obj = bless {
    fd => $fd,
  }, $class;

  $obj->init();

  return $obj;
}

sub dispose
{
  my $self = shift;
  close($self->{fd});
}

sub init
{
  my $self = shift;
  my $fd = $self->{fd};
  my $buf;
  my $mz_header = $self->{mz_header} = $make_mz_header->();
  my $pe_header = $self->{pe_header} = $make_pe_header->();
  my $oh_magic = $self->{oh_magic} = $make_oh_magic->();

  $self->{file_size} = checked_sysseek($fd,0,2);

  # Read MZ header
  filepos_set($fd,0);
  $mz_header->read($fd);

  die "Not an EFI binary (MZ magic missing)" unless $mz_header->{magic} eq MZ_MAGIC;

  # Read PE header
  filepos_set($fd,$mz_header->{pe_offset});
  $pe_header->read($fd);

  die "Not an EFI binary (PE magic missing)" unless $pe_header->{magic} eq PE_MAGIC;

  # Read optional header magic
  $oh_magic->read($fd);

  # Save position of optional header for later rewriting
  $self->{oh_offset} = filepos_get($fd);
  my $remaining_oh_size = $pe_header->{size_optional_header} - $oh_magic->{_size};

  my $oh_header;
  if ($oh_magic->{magic} == OH_MAGIC_PE32P)
    {
      $oh_header = $make_pe32p_header->();
    }
  elsif ($oh_magic->{magic} == OH_MAGIC_PE32)
    {
      $oh_header = $make_pe32_header->();
    }
  else
    {
      die sprintf("Unsupported PE optional header type (0x%04x)", $oh_magic->{magic});
    }

  die "Optional header too small" unless $remaining_oh_size >= $oh_header->{_size};
  $remaining_oh_size -= $oh_header->{_size};

  $self->{oh_header} = $oh_header;
  $oh_header->read($fd);

  die "Not an EFI binary (wrong subsystem)"
    unless $oh_header->{subsystem} == SUBSYSTEM_EFI_APPLICATION;

  # Read data directories
  $self->{datadir_offset} = filepos_get($fd);
  my @datadirs;
  for(my $i = 0; $i < $oh_header->{num_datadirs}; $i++)
    {
      my $datadir = $make_pe_data_dir->();
      $datadir->{_typename} = $datadir_names[$i] // "Unknown";

      $datadir->read($fd);
      push @datadirs, $datadir;

      die "Unexpected end of optional header"
        unless $remaining_oh_size >= $datadir->{_size};
      $remaining_oh_size -= $datadir->{_size};
    }
  $self->{datadirs} = \@datadirs;

  # Find and read section table
  $self->{section_table_offset} =
    filepos_set(
      $fd,
      $mz_header->{pe_offset} + $pe_header->{_size} + $pe_header->{size_optional_header}
    );

  my @sections;
  for(my $i = 0; $i < $pe_header->{num_sections}; $i++)
    {
      my $section = $make_section_entry->();
      $section->read($fd);
      push @sections, $section;
    }

  $self->{sections} = \@sections;
}

sub calculate_size_from_sections
{
  my ($self) = @_;

  my $size_code = 0;
  my $size_data = 0;
  my $size_bss = 0;

  for my $section (@{$self->{sections}})
    {
      # Note: It's not quite clear if these size fields contain the cumulative
      # raw size or virt size. From what objcopy generates it seems to be the
      # virt size from each section aligned by the file alignment
      my $size = align($section->{virt_size}, $self->{oh_header}{alignment_file});

      if ($section->{flags} & SECTION_FLAG_CODE)
        {
          $size_code += $size;
        }
      elsif ($section->{flags} & SECTION_FLAG_DATA)
        {
          $size_data += $size;
        }
      elsif ($section->{flags} & SECTION_FLAG_BSS)
        {
          $size_bss += $size;
        }
    }
  return ($size_code, $size_data, $size_bss);
}

sub _find_section_by_vaddr
{
  my $self = shift;
  my $vaddr = shift;

  for my $section (@{$self->{sections}})
    {
      if ($vaddr >= $section->{virt_addr} &&
          $vaddr < $section->{virt_addr} + $section->{virt_size})
        {
          return $section;
        }
    }

  die "Virtual address " . sprintf("0x%08x", $vaddr) . " not present in PE image";
}

sub vaddr_to_file_offset
{
  my $self = shift;
  my $vaddr = shift;
  my $section = $self->_find_section_by_vaddr($vaddr);

  return $vaddr - $section->{virt_addr} + $section->{raw_addr};
}

sub objcpy_start
{
  my $self = shift;
  my $until_vaddr = shift;
  my $ofn = shift;
  my $ifd = $self->{fd};

  open(my $ofd, "+>$ofn") || error("Could not open '$ofn': $!");
  binmode $ofd;
  $self->{ofd} = $ofd;

  # Find module section and file offset of vaddr
  my $module_section = $self->_find_section_by_vaddr($until_vaddr);
  my $offset = $until_vaddr - $module_section->{virt_addr} + $module_section->{raw_addr};
  $self->{_module_section} = $module_section;

  # just copy everything until vaddr first, alter header later
  my $buf;
  filepos_set($ifd, 0);
  check_sysread(sysread($ifd, $buf, $offset), $offset);
  check_syswrite(syswrite($ofd, $buf), length($buf));

  return $ofd;
}

sub objcpy_finalize
{
  my $self = shift;
  my $ofd = $self->{ofd};
  my $ifd = $self->{fd};

  my $buf;

  my $module_section = $self->{_module_section};
  my $end_of_modules = checked_sysseek($ofd,0,2);

  # Calculate new section size of current section
  my $new_section_size_virt = $end_of_modules - $module_section->{raw_addr};
  my $file_alignment = $self->{oh_header}{alignment_file} // 0x200;
  my $new_section_size_raw = align($new_section_size_virt, $file_alignment);

  die "Internal error" unless $new_section_size_raw >= $new_section_size_virt;

  # Calculate how much we moved subsequent sections
  my $addr_delta = $new_section_size_raw - $module_section->{raw_size};

  # Insert padding after module_section
  syswrite($ofd, "\0" x ($new_section_size_raw - $new_section_size_virt));

  die "Internal error" unless filepos_get($ofd) == $module_section->{raw_addr} + $new_section_size_raw;

  # Copy everything after the module data section from the old image to the new image
  my $taildata_start = $module_section->{raw_addr} + $module_section->{raw_size};
  my $taildata_end = $self->{file_size};
  my $taildata_size = $taildata_end - $taildata_start;
  filepos_set($ifd, $taildata_start);
  check_sysread(sysread($ifd, $buf, $taildata_size), $taildata_size);
  check_syswrite(syswrite($ofd, $buf), $taildata_size);

  my $end_of_image = checked_sysseek($ofd,0,2);

  # Update current section size
  $module_section->{raw_size} = $new_section_size_raw;
  $module_section->{virt_size} = $new_section_size_virt;

  # Update subsequent section raw addr
  for my $section (@{$self->{sections}})
    {
      if ($section->{raw_addr} > $module_section->{raw_addr})
        {
          $section->{raw_addr} += $addr_delta;
        }
      die "Internal error" unless $section->{raw_addr} <= $end_of_image;
      die "Internal error" unless $section->{raw_addr} + $section->{raw_size} <= $end_of_image;
    }

  ## Write PE header
  # As per specification this should be zero
  $self->{pe_header}{ptr_symbol_table} = 0;
  $self->{pe_header}{num_symbols} = 0;

  filepos_set($ofd, $self->{mz_header}{pe_offset});
  $self->{pe_header}->write($ofd);

  ## Write optional header
  filepos_set($ofd, $self->{oh_offset});

  # checksum algorithm is not documented, apparently 0 is sufficient to deactivate the check.
  $self->{oh_header}{checksum}   = 0;

  # Calculate new size of code, data and bss
  my ($size_code,$size_data,$size_bss) = $self->calculate_size_from_sections();

  # Update sizes in optional header
  $self->{oh_header}{size_code}  = $size_code;
  $self->{oh_header}{size_data}  = $size_data;
  $self->{oh_header}{size_bss}   = $size_bss;
  $self->{oh_header}{image_size} += $addr_delta;
  $self->{oh_header}->write($ofd);

  filepos_set($ofd, $self->{datadir_offset});
  for my $datadir (@{$self->{datadirs}})
    {
      $datadir->write($ofd);
    }

  # Write section table
  filepos_set($ofd, $self->{section_table_offset});

  for my $section (@{$self->{sections}})
    {
      $section->write($ofd);
    }

  close($ofd);
}

1;
