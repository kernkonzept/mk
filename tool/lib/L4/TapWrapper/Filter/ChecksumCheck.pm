package L4::TapWrapper::Filter::ChecksumCheck;

use strict;
use warnings;

use parent 'L4::TapWrapper::Filter';
use L4::TapWrapper;

sub new {
  my $self = L4::TapWrapper::Filter->new();
  $self->{started} = 0;
  $self->{failed} = 0;
  $self->{crc32} = 0;

  # Compute polynomial table
  my $polynomial = 0xedb88320;
  $self->{lookup_table} = [];
  foreach my $x (0..255)
    {
      $x = ( $x >> 1 ) ^ ( $x & 1 ? $polynomial : 0) foreach (0..7);
      push @{$self->{lookup_table}}, $x;
    }

  $L4::TapWrapper::print_to_tap_fd = 1; # Always print the checksum result
  return bless $self, shift;
}

sub update_crc32 {
  my $self = shift;
  my $input = shift;

  my $crc = $self->{crc32} ^ 0xffffffff;

  foreach my $x (unpack ('C*', $input)) {
    $crc = ($crc >> 8) ^ $self->{lookup_table}->[ ($crc ^ $x) & 0xff ];
  }

  $self->{crc32} = $crc ^ 0xffffffff;
}

sub finalize {
  my $self = shift;
  $self->add_tap_line(1, "Checksums checked out.") unless $self->{failed};
  $self->add_raw_tap_line("1..1");
  $self->SUPER::finalize();
}

sub process_any {
  my $self = shift;
  my $line = shift;

  if (!$self->{started})
    {
      return [ $line ] unless $line =~ m/^\{00000000\} (.*)$/;
      $self->{started} = 1;
    }

  L4::TapWrapper::fail_test("Line without checksum: '$line'\n")
    unless defined $line =~ /^\{(?<chksum>[0-9a-f]{8})\} (?<text>.*)/ms;

  return [ $+{text} ] if $self->{failed};
  my $string_checksum = sprintf("%08x", $self->{crc32});
  if ($string_checksum ne $+{chksum})
    {
      $self->{failed} = 1;
      $self->add_tap_line(0, "Invalid checksum. Expected: '$string_checksum', got '$+{chksum}'!");
    }

  $self->update_crc32($+{text});
  return ( $+{text} );
}

1;
