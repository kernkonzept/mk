package L4::Image::Struct;
use strict;
use warnings;

our $DEBUG = 0;

sub define {
  my $class = shift;
  my $typename = shift;
  my $size = shift;
  my $format = shift;
  my @fields = @_;

  return sub {
    my $self = {
      _typename => $typename,
      _size => $size,
      _format => $format,
      _fields => \@fields,
    };

    return bless $self, $class;
  }
}

sub read {
  my ($self,$fd) = @_;

  printf "Reading %s...\n", $self->{_typename} if $DEBUG;

  die "Read error" unless sysread($fd, my $buf, $self->{_size}) == $self->{_size};
  my @values = CORE::unpack($self->{_format}, $buf);

  for my $field (@{$self->{_fields}}) {
    $self->{$field} = shift @values;
  }

  $self->dump() if $DEBUG;
}
;

sub write {
  my ($self,$fd) = @_;

  printf "Writing %s...\n", $self->{_typename} if $DEBUG;

  $self->dump() if $DEBUG;

  my @values = map { $self->{$_} } @{$self->{_fields}};

  my $buf = CORE::pack($self->{_format}, @values);

  die "Write error"
    unless syswrite($fd,$buf) == length $buf;

}

sub dump {
  my ($self) = @_;

  printf "%s:\n", $self->{_typename};
  for my $field (@{$self->{_fields}}) {
    my $v = $self->{$field};
    printf "  %-40s: ", $field;
    if (!defined($v))
      {
        print "<undef>";
      }
    elsif ($v =~ /^[0-9]+$/)
      {
        printf "%d (0x%x)", $v, $v
      }
    else
      {
        printf ("%s (%s)", $v, join(" ", map { sprintf "%x", ord($_) } split(//, $v)));
      }
    print "\n";
  }
  print "\n";
}

1;
