package L4::TapWrapper::Plugin::External;

use strict;
use warnings;

use IPC::Open3;
use IO::Select;
use Symbol 'gensym';

use parent 'L4::TapWrapper::Plugin::TagPluginBase';
use L4::TapWrapper;

sub new {
  my $type = shift;
  my $self = L4::TapWrapper::Plugin::TagPluginBase->new(shift);
  $self->{idx} = 0;
  bless $self, $type;

  L4::TapWrapper::fail_test("Workdir not set. External plugins require this.")
    unless defined $self->tmpdir();
  L4::TapWrapper::fail_test("External tool not set. Use tool=path/to/tool.")
    unless defined $self->{args}{tool};
  $L4::TapWrapper::print_to_tap_fd = 1; # Externals always print
  return $self;
}

sub process_mine {
  my $self = shift;
  my $data = shift;
  my $info = shift;

  if ($self->{in_block})
    {
      print { $self->{cur_file} } $data;
    }
  else
    {
      my $fname = "$self->{idx}_$self->{cur_tag}";
      $fname .= "_$info" if $info ne "";
      open(my $fh, '>', $self->tmpdir() . "/$fname.snippet");
      print $fh $self->{clean_line};
      $self->{idx}++;
      close($fh) || L4::TapWrapper::fail_test("Failed writing snippet $fname.");
    }
}

sub start_block()
{
  my $self = shift;
  my $info = shift;
  my $fname = "$self->{idx}_$self->{cur_tag}";
  $fname .= "_$info" if $info ne "";
  open($self->{cur_file}, '>', $self->tmpdir() . "/$fname.snippet");
  $self->{idx}++;
}

sub end_block()
{
  my $self = shift;
  close($self->{cur_file})
    || L4::TapWrapper::fail_test("Failed writing snippet $self->{fname}.");
}

sub finalize()
{
  my $self = shift;

  my $tool = "$ENV{L4DIR}/$self->{args}{tool}";

  my $pid = open3(my $chld_stdin, my $chld_stdout, my $chld_stderr = gensym, $tool, $self->tmpdir());
  close($chld_stdin);
  my $select = IO::Select->new($chld_stdout, $chld_stderr);

  my $stdout_text = "";
  my $stderr_text = "";

  while (my @ready = $select->can_read())
    {
      for my $fh (@ready)
        {
          my $ret = sysread($fh, my $buf, 256);

          if ($ret == 0)
            {
              $select->remove($fh);
              close($fh);
              next;
            }

          if ($fh == $chld_stdout)
            {
              $stdout_text .= $buf;
            }
          else
            {
              $stderr_text .= $buf;
            }
        }
    }

  waitpid($pid, 0);
  my $ecode = $? >> 8;

  # /(?<=\n)/ means split after \n and keep the \n.
  my @stdout_lines = split /(?<=\n)/, $stdout_text;
  my @stderr_lines = split /(?<=\n)/, $stderr_text;

  $self->add_log_line(@stderr_lines);

  if ($ecode != 0)
    {
      $self->add_tap_line(0, "External ['$tool']: Exited with code $ecode");
      $self->add_raw_tap_line("1..1");

      $self->add_log_line("### External ['$tool']: Exited with code $ecode\n");
      $self->add_log_line("### STDOUT:\n");
      $self->add_log_line(@stdout_lines);
    }
  else
    {
      $self->add_raw_tap_line(@stdout_lines);
    }
  $self->SUPER::finalize();
}

1;

__END__

=head1 Plugin to invoke external too for tagged content

This is a plugin that writes the content of tagged blocks or lines as files to
a directory and at the end invokes an external tool to process these files. The
tool gets passed an argument that is the path to the directory containing the
snippet files.

Files are named

<seq>_<tag>_<info>.snippet

where C<seq> is a  non-padded number, numbered in sequence as found in the
output, tag is the specified C<tag> covered by the plugin instance and C<info>
is any additional info specified for the block or the line (see
C<TagPluginBase> documentation).

The _<info> part is optional.

If the invocation of the tool fails or the tool returns with an exit code that
is not equal to 0, then the plugin will add a C<no ok> line to the TAP lines
and not process any output from the external tool.

=head1 Options

The plugin inherits all options from the TagPluginBase and also defines an
additional C<tool> option that is the path to the tool to invoke. The path to
the tool is expected to be relative to the l4 source directory.

=head1 Tool convention

The tool is expected to output C<only> TAP lines, without any start or end
markers. Valid tool output, for example, can look like this

ok foo bar
1..1

The plugin can usually be specified as

TEST_TAP_PLUGINS=External:tag=foo,tool=tool/bin/my_post_processor

=cut
