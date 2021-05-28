package L4::Image::Regions;

use warnings;
use Exporter;

use vars qw(@ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw();

sub cmp_region($$)
{
  return $_[0]->{start} <=> $_[1]->{start};
}

sub new
{
  my $class = shift;
  my $page_size = shift;

  my @regions = ();
  return bless {
    regions => \@regions,
    page_size => $page_size,
  }, $class;
}

sub is_free
{
  my ($self, $start, $end) = @_;

  foreach(@{$self->{regions}})
    {
      if ($_->{start} < $end and $_->{end} > $start)
        {
          return 0;
        }
    }

  return 1;
}

sub trunc_page
{
  my ($self, $addr) = @_;
  return $addr & ~($self->{page_size} - 1);
}

sub round_page
{
  my ($self, $addr) = @_;
  my $ps = $self->{page_size};
  return ($addr + $ps - 1) & ~($ps - 1);
}

sub add
{
  my ($self, $start, $end) = @_;
  $start = $self->trunc_page($start);
  $end = $self->round_page($end);

  if (not $self->is_free($start, $end))
    {
      return 0;
    }

  $elem = {
    start => $start,
    end => $end
  };
  push(@{$self->{regions}}, $elem);

  @r = sort cmp_region @{$self->{regions}};
  $self->{regions} = \@r;

  return 1;
}

sub alloc
{
  my ($self, $size) = @_;
  $size = $self->round_page($size);

  my $i = 0;
  foreach(@{$self->{regions}})
    {
      if ($i+$size <= $_->{start})
        {
          last;
        }
      $i = $_->{end};
    }

  $self->add($i, $i+$size) || die "wtf";
  return $i;
}



sub dump
{
  $self = shift;

  foreach(@{$self->{regions}})
    {
      my $start = $_->{start};
      my $end = $_->{end};
      print STDERR "[$start .. $end) ";
    }
  print STDERR "\n";
}

1;
