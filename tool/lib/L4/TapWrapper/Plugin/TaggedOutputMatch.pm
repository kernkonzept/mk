# This is a plugin for matching tagged test output

package L4::TapWrapper::Plugin::TaggedOutputMatch;

use strict;
use warnings;

use File::Basename;

use parent 'L4::TapWrapper::Plugin::TagPluginBase';
use L4::TapWrapper;
use L4::TapWrapper::Plugin::OutputMatching;

sub new {
  my $type = shift;
  my $args = shift;
  my $self = L4::TapWrapper::Plugin::TagPluginBase->new($args);

  L4::TapWrapper::fail_test("No matching file specified for plugin!")
    unless defined($self->{args}{file});

  # Also forces printing to tap fd!
  $self->{matcher} = L4::TapWrapper::Plugin::OutputMatching->new({ file => $self->{args}{file}, literal => $self->{args}{literal} });
  # We have tags, so we are always "in block"
  $self->{matcher}->check_start("L4 Bootstrapper");
  $self->{inhibit_exit} = $self->{matcher}{inhibit_exit}; # We must wait for the data

  return bless $self, $type;
}

sub process_mine {
  my $self = shift;
  my $check_data = shift;

  $check_data = $self->{raw_line} if $self->{args}{match_with_tag};
  chomp($check_data);

  my $cur_res = $self->{matcher}{num_res};
  $self->{matcher}->process_mine($check_data);
  L4::TapWrapper::fail_test("Unexpected line: '$check_data'")
    if $cur_res == $self->{matcher}{num_res} and $self->{args}{nounexpected};

  $self->{inhibit_exit} = $self->{matcher}{inhibit_exit}; # We must wait for the data
}

sub finalize {
  return shift->{matcher}->finalize(@_);
}

1;

__END__

=head1 Plugin for matching tagged lines

This uses the standard tag format. All lines within tagged blocks are checked
against a specified expected output file. All line must be matched. This uses
the OutputMatching plugin underneath, so features such as repeated matching are
available in principle.

=head1 Options

The following options are defined

=over

=item C<tag>

The tag for which the output should be matched. Only lines matching this tag
(See TagPluginBase.pm) are matched. Others are silently ignored.

=item C<file>

The file that contains the expected output lines. Must be found using the
module search path.

=item C<literal>

The contents of the file that is matched are to be matched literally and not as
a regular expression.

=item C<nounexpected>

The default is to just ignore lines that are not matched, continuing to wait
for the next line to match. This tag changes the behaviour to require all lines
to match until the last expected line is matched.

=item C<match_with_tag>

The default is to strip the tag before trying to match against the lines in the
file. Enabling this option matches the whole line, including the tag. This is
especially usefull if the expected output is long and should be easily
generated from a known good run.

=back

=head1 Usage

Specify for a particular testrun using the TEST_TAP_PLUGINS variable.
Example:

  TEST_TAP_PLUGINS=TaggedOutputMatch:tag=mapdb,file=foo.txt,match_with_tag=1

=cut
