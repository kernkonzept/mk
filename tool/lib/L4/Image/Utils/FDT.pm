package L4::Image::Utils::FDT;

# Based on
# https://devicetree-specification.readthedocs.io/en/stable/flattened-format.html

use warnings;
use strict;

use L4::Image::Struct;
use L4::Image::Utils qw/error check_sysread check_syswrite checked_sysseek
                        filepos_set filepos_get
                        sysreadz syswritez
                        rtrim_zerobytes
                        alignto alignto_fd/;

$L4::Image::Struct::DEBUG = 0;

my $make_fdt_header = L4::Image::Struct->define(
  "FDT header", 40, "L>L>L>L>L>L>L>L>L>L>",
  "magic",
  "totalsize",
  "off_dt_struct",
  "off_dt_strings",
  "off_mem_rsvmap",
  "version",
  "last_comp_version",
  "boot_cpuid_phys",
  "size_dt_strings",
  "size_dt_struct",
);

my $make_mem_rsvmap_entry = L4::Image::Struct->define(
  "Memory Reservation Block Entry", 16, "Q>Q>",
  "address",
  "size",
);

my $make_node_token = L4::Image::Struct->define(
  "Struct Node Token", 4, "L>",
  "id",
);

my $make_fdt_prop_info = L4::Image::Struct->define(
  "Prop info", 8, "L>L>",
  "len",
  "nameoff",
);

use constant {
  FDT_BEGIN_NODE => 1,
  FDT_END_NODE => 2,
  FDT_PROP => 3,
  FDT_NOP => 4,
  FDT_END => 9,
};

sub new
{
  my $class = shift;
  my $fn = shift;

  open(my $fd, "<", $fn) || error("Could not open '$fn': $!");
  binmode($fd);

  return $class->new_fd($fd);
}

sub new_fd {
  my $class = shift;
  my $fd = shift;
  my $self = bless {
    fd => $fd,
  }, $class;

  $self->read_file();

  return $self;
}

sub read_file
{
  my $self = shift;
  my $fd = $self->{fd};
  my $header = $self->{header} = $make_fdt_header->();

  filepos_set($fd,0);
  $header->read($fd);

  filepos_set($fd,$header->{off_mem_rsvmap});

  my @mem_rsvmap;

  while (1)
    {
      my $entry = $make_mem_rsvmap_entry->();
      $entry->read($fd);
      last unless $entry->{address} && $entry->{size};
      push @mem_rsvmap, $entry;
    }

  $self->{mem_rsvmap} = \@mem_rsvmap;

  filepos_set($fd, $header->{off_dt_strings});

  sysread($fd, my $strtab, $header->{size_dt_strings});

  $self->{strtab} = $strtab;

  filepos_set($fd, $header->{off_dt_struct});

  $self->{structure} = $self->read_fdt_structure();
}

# FDT is moderately free form. We choose this order:
# - header (must be at beginning of file)
# - mem_rsvmap (offset in header)
# - structure (offset & size in header)
# - string table (offset & size in header)
sub write_file
{
  my ($self, $fd) = @_;

  # Reset strtab. It is filled during write_fdt_structure
  $self->{strtab} = "";

  # Write incomplete header, update offsets & sizes later.
  $self->{header}->write($fd);


  # Write mem_rsvmap
  alignto_fd($fd, 8);
  $self->{header}->{off_mem_rsvmap} = filepos_get($fd);

  $_->write($fd) foreach @{$self->{mem_rsvmap}};

  my $end_rsv = $make_mem_rsvmap_entry->();
  $end_rsv->{address} = 0;
  $end_rsv->{size} = 0;
  $end_rsv->write($fd);

  # Write structure
  alignto_fd($fd, 4);
  my $struct_start = $self->{header}->{off_dt_struct} = filepos_get($fd);

  $self->write_fdt_structure($fd);

  my $struct_end = filepos_get($fd);

  # Write string table
  alignto_fd($fd, 4);
  my $strings_start = $self->{header}->{off_dt_strings} = filepos_get($fd);

  syswrite($fd, $self->{strtab});

  my $strings_end = filepos_get($fd);

  # Update header fields
  $self->{header}->{size_dt_struct} = $struct_end - $struct_start;
  $self->{header}->{size_dt_strings} = $strings_end - $struct_end;
  $self->{header}->{totalsize} = $strings_end;

  # Write header again
  filepos_set($fd,0);
  $self->{header}->write($fd);
}

sub read_fdt_token {
  my $self = shift;
  my $fd = $self->{fd};

  my $token = $make_node_token->();
  $token->read($fd);

  if ($token->{id} == FDT_BEGIN_NODE)
    {
      my $name = $token->{name} = sysreadz($fd);
    }
  elsif ($token->{id} == FDT_PROP)
    {
      my $info = $make_fdt_prop_info->();
      $info->read($fd);

      check_sysread(sysread($fd, my $data, $info->{len}), $info->{len});
      $token->{data} = $data;

      # Read name from string table
      my $tabstr = substr($self->{strtab}, $info->{nameoff});
      my $nullidx = index($tabstr, "\0");
      $tabstr = substr($tabstr, 0, $nullidx) unless $nullidx == -1;

      $token->{name} = $tabstr;
    }
  elsif ($token->{id} == FDT_END_NODE ||
         $token->{id} == FDT_NOP ||
         $token->{id} == FDT_END)
    {
      # No further data
    }
  else
    {
      die "Invalid FDT token id " . $token->{id};
    }

  # Move to 4 bytes border
  alignto_fd($fd,4);

  return $token;
}

sub write_fdt_token {
  my ($self, $fd, $token) = @_;

  $token->write($fd);
  if ($token->{id} == FDT_BEGIN_NODE)
    {
      die unless exists $token->{name};
      syswritez($fd, $token->{name});
    }
  elsif ($token->{id} == FDT_PROP)
    {
      my $info = $make_fdt_prop_info->();
      my $is_cb = ref($token->{data}) eq "CODE";

      $info->{nameoff} = length($self->{strtab});
      $self->{strtab} .= $token->{name} . "\0";

      # We don't know the data length yet if it's a callback
      if ($is_cb)
        {
          $info->{len} = 0;
        }
      else
        {
          $info->{len} = length($token->{data});
        }

      my $info_offset = filepos_get($fd);
      $info->write($fd);

      if ($is_cb)
        {
          # Write data into file
          my $data_start = filepos_get($fd);
          $token->{data}->($fd);
          my $data_end = filepos_get($fd);

          # Update data length in prop info
          $info->{len} = $data_end - $data_start;

          # Go back and write info again
          filepos_set($fd, $info_offset);
          $info->write($fd);
          filepos_set($fd, $data_end);
        }
      else
        {
          check_syswrite(syswrite($fd, $token->{data}),length($token->{data}));
        }
    }
  elsif ($token->{id} == FDT_END_NODE ||
         $token->{id} == FDT_NOP ||
         $token->{id} == FDT_END)
    {
      # No further data
    }
  else
    {
      die "Invalid FDT token id " . $token->{id};
    }

  # Align to 4 bytes border (by adding padding)
  alignto_fd($fd, 4);
}

sub read_node {
  my $self = shift;

  my $node = {
    properties => {},
    children => {}
  };

  my $token;
  do {
    $token = $self->read_fdt_token();
    die if $token->{id} == FDT_END;

    if ($token->{id} == FDT_BEGIN_NODE)
      {
        my $subnode = $self->read_node($token);
        $node->{children}{$token->{name}} = $subnode;
      }
    elsif ($token->{id} == FDT_PROP)
      {
        $node->{properties}{$token->{name}} = $token->{data};
      }
  } until ($token->{id} == FDT_END_NODE);

  return $node;
}

sub write_node {
  my ($self, $fd, $node) = @_;

  foreach my $prop_name (keys %{$node->{properties}})
    {
      my $token = $make_node_token->();

      $token->{id} = FDT_PROP;
      $token->{name} = $prop_name;
      $token->{data} = $node->{properties}{$prop_name};

      $self->write_fdt_token($fd, $token);
    }

  foreach my $child_name (keys %{$node->{children}})
    {
      my $child_node = $node->{children}{$child_name};

      # Write FDT_BEGIN_NODE
      my $token = $make_node_token->();
      $token->{id} = FDT_BEGIN_NODE;
      $token->{name} = $child_name;
      $self->write_fdt_token($fd, $token);

      # Write content of node
      $self->write_node($fd, $child_node);

      # Write FDT_END_NODE
      $token = $make_node_token->();
      $token->{id} = FDT_END_NODE;
      $self->write_fdt_token($fd, $token);
    }
}

sub read_fdt_structure {
  my $self = shift;
  my $token = $self->read_fdt_token();
  die unless $token->{id} == FDT_BEGIN_NODE;
  my $structure = $self->read_node();
  $token = $self->read_fdt_token();
  die unless $token->{id} == FDT_END;
  return $structure;
}

sub write_fdt_structure {
  my $self = shift;
  my $fd = shift;

  # Write FDT_BEGIN_NODE for root node
  my $token = $make_node_token->();
  $token->{id} = FDT_BEGIN_NODE;
  $token->{name} = "";
  $self->write_fdt_token($fd, $token);

  # Write content of root node
  $self->write_node($fd, $self->{structure});

  # Write FDT_END_NODE for root node
  $token = $make_node_token->();
  $token->{id} = FDT_END_NODE;

  $self->write_fdt_token($fd, $token);

  # Write FDT_END as signal for end of structure
  $token = $make_node_token->();
  $token->{id} = FDT_END;

  $self->write_fdt_token($fd, $token);
}

sub dispose {
  my $self = shift;
  close($self->{fd});
}

1;
