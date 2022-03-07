package L4::TapWrapper::Plugin::OutputMatching;

use strict;
use warnings;

use File::Basename;
use Scalar::Util qw(looks_like_number);

use parent 'L4::TapWrapper::Plugin';
use L4::TapWrapper;

sub new {
  my $type = shift;
  my $self = L4::TapWrapper::Plugin->new( () );
  $self->{args} = shift;
  $self->{args}{literal} = 0 unless defined $self->{args}{literal};
  my $file = $self->{args}{file};
  if (! -e $file or -d $file)
    {
      foreach my $p (split(/:/, $ENV{SEARCHPATH}))
        {
          if (-e "$p/$file" and ! -d "$p/$file")
            {
              $file = "$p/$file";
              last;
            }
        }
    }

  open($self->{expect_fd}, '<', $file)
    or L4::TapWrapper::fail_test("Can't open expected output ('$file')");

  $self->inhibit_exit();
  $self->{num_res} = 1;
  $self->{had_block} = 0;
  $self->{wait_until} = time + 2 * $L4::TapWrapper::timeout;
  $self->{number_of_runs} = $ENV{TEST_EXPECTED_REPEAT};
  $self->{number_of_runs} = 1 unless looks_like_number($self->{number_of_runs});
  $L4::TapWrapper::print_to_tap_fd = 1; # OutputMatching always prints

  return bless $self, $type;
}

sub get_next_line {
  my $self = shift;
  my $fd = $self->{expect_fd};
  if (!($L4::TapWrapper::expline = <$fd>))
    {
      if ($self->{number_of_runs} == 1) # End of file and we only had one run
        {
          $self->{in_block} = 0;
          $self->permit_exit();
          return undef;
        }
      $self->{number_of_runs}-- if ($self->{number_of_runs} > 0);
      seek($fd, 0, 0); # Rewind
      $L4::TapWrapper::expline = <$fd>;
    }
  chomp $L4::TapWrapper::expline;
  return $L4::TapWrapper::expline if $self->{args}{literal};
  return extract_expected($L4::TapWrapper::expline);
}

sub check_start {
  my $self = shift;
  return if $self->{had_block}; # Only ever start matching once
  my $data = shift;
  $data =~ s/\e\[[\d,;\s]+[A-Za-z]//gi; # strip color escapes
  if ($data =~ m@^(L4 Bootstrapper|Welcome to L4/Fiasco.OC!)@)
    {
      $self->{in_block} = 1;
      $self->{had_block} = 1;
      $self->{next_line} = $self->get_next_line();
    }
}

sub process_mine {
  my $self = shift;
  (my $data = shift) =~ s/\e\[[\d,;\s]+[A-Za-z]//gi; #Strip color escapes
  if ((!$self->{args}{literal} && $data =~ m/$self->{next_line}/) ||
      ($data =~ m/^\Q$self->{next_line}\E$/))
    {
      $self->{num_res}++;
      $self->{next_line} = $self->get_next_line();
      $self->{wait_until} = time + 2 * $L4::TapWrapper::timeout;
    }
  else #Wait for more output?
    {
      $self->permit_exit() if (time > $self->{wait_until})
    }
}

sub extract_expected
{
  my $exp = shift;

  if ($exp =~ /^([^|]+)\s+\|\s+(.*)\s*$/)
    {
      return '^'.$1.'\\W+\\| '.$2;
    }
  else
    {
      return '^\\s*'.$exp.'\\s*$';
    }
}

sub finalize
{
  my $self = shift;
  if (defined($self->{next_line}))
    {
      $self->{num_res}++;
      $self->add_tap_line(0, "expected output not found in line $self->{num_res} : $self->{next_line}");
    }
  else
    {
      $self->add_tap_line(1, "A total of $self->{num_res} line(s) of output matched.");
    }
  $self->add_raw_tap_line("1..1\n");
  $self->SUPER::finalize();
}

1;
