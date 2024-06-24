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
  $self->{args}{literal} //= 0;
  $self->{args}{raw} //= 0;
  $self->{args}{no_boot} //= 0;
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
  $self->{num_res} = 0;
  $self->{had_block} = 0;
  $self->{features}{shuffling_support} = 0;
  $self->{wait_until} = time + 2 * $L4::TapWrapper::timeout;
  $self->{number_of_runs} = $ENV{TEST_EXPECTED_REPEAT}; #TODO: Make robust for bundle?
  $self->{number_of_runs} = 1 unless looks_like_number($self->{number_of_runs});

  $self = bless $self, $type;

  if ($self->{args}{no_boot})
    {
      $self->{in_block} = 1;
      $self->{had_block} = 1;
      $self->{next_line} = $self->get_next_line();
    }
  $L4::TapWrapper::print_to_tap_fd = 1; # OutputMatching always prints

  return $self;
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
  $L4::TapWrapper::expline =~ s/\r*\n$//g unless $self->{args}{raw}; # simplify line endings
  return $L4::TapWrapper::expline if $self->{args}{literal};
  return extract_expected($L4::TapWrapper::expline);
}

sub check_start {
  my $self = shift;
  return if $self->{had_block}; # Only ever start matching once
  my $data = shift;
  $data =~ s/\e\[[\d,;\s]*[A-Za-z]//gi; # strip color escapes
  if ($data =~ m@^(L4 Bootstrapper|Welcome to L4/Fiasco.OC!)@)
    {
      $self->{in_block} = 1;
      $self->{had_block} = 1;
      $self->{next_line} = $self->get_next_line();
    }
}

sub process_mine {
  my $self = shift;
  (my $data = shift) =~ s/\e\[[\d,;\s]*[A-Za-z]//gi; #Strip color escapes
  $data =~ s/\r+$//g unless $self->{args}{raw}; # lines from tap-wrapper do not contain final newline

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
  my $expect_message;
  my $ok = not defined($self->{next_line});

  # Ok or not ok?
  if ($ok and $self->{had_block})
    {
      $expect_message =  "A total of $self->{num_res} line(s) of output matched.";
    }
  else
    {
      $self->{num_res}++;
      $expect_message = "expected output not found in line $self->{num_res} : $self->{next_line}";
    }

  # Have extra tap description or not ?
  my $tap_description = $self->{args}{tap_description};
  if ($tap_description)
    {
      $self->add_tap_line($ok, $tap_description);
      $self->add_raw_tap_line("# ${expect_message}\n");
    }
  else
    {
      $self->add_tap_line($ok, $expect_message);
    }

  # UUID if present
  $self->add_raw_tap_line("#  Test-uuid: $self->{args}{uuid}\n")
    if defined($self->{args}{uuid});

  # TAP plan
  $self->add_raw_tap_line("1..1\n");

  $self->SUPER::finalize();
}

1;

__END__

=head1 Plugin for matching output lines

Match all output lines agains the given output expectation.
As a simplification carriage returns are removed from line endings, both in the
test output and in the file containing the expected lines. Further, escape
sequences are automatically removed from the test output but not from the
expected output.

=head1 Options

The following options are defined

=over

=item C<file>

The file that contains the expected output lines. Must be found using the
module search path.

=item C<literal>

The contents of the file that is matched are to be matched literally and not as
a regular expression.

=item C<raw>

The contents of the file are matched without stripping carriage returns.

=item C<uuid>

The globally unique identifier of the test.

=item C<tap_description>

The tap description to be used in the ok/not ok line. If not specified a generic
one will be used, which changes depending on the test outcome.

=back

=head1 Usage

Specify for a particular testrun using the TEST_TAP_PLUGINS variable.
Example:

  TEST_TAP_PLUGINS=OutputMatching:file=foo.txt,uuid=<`uuidgen -r`>

=cut
