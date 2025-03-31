# This is a plugin for extracting coverage output

package L4::TapWrapper::Plugin::LLVMCov;

use strict;
use warnings;

use MIME::Base64 qw( decode_base64 );
use File::Copy;
use File::Temp;
use Cwd qw(realpath cwd);


use File::Basename;
use File::Path "make_path";

use IO::Handle;

use parent 'L4::TapWrapper::Plugin::TagPluginBase';
use L4::TapWrapper;
use L4::Makeconf;

my $cxx = L4::Makeconf::get("$ENV{OBJ_BASE}", "CXX");
my @cxx_parts = split ' ', $cxx;
my $llvm_profdata_cmd = $cxx_parts[0] =~ s/clang\+\+/llvm-profdata/gr;
my $llvm_cov_cmd = $cxx_parts[0] =~ s/clang\+\+/llvm-cov/gr;


sub new
{
  my $type = shift;
  my $args = shift;
  $args->{tag} = "llvmcov";

  my $self = L4::TapWrapper::Plugin::TagPluginBase->new($args);
  $self->{sources} = [];
  $self->{outputs} = {};
  $self->{keep_going} = defined $args->{keep_going};
  $self->{fail_if_no_data} = !!$args->{fail_if_no_data};
  $self->{has_data} = 0;
  $self->{intermittent_fails} = 0;

  bless $self, $type;


  my $tmpdir = $self->tmpdir();
  L4::TapWrapper::fail_test("Workdir not set. Coverage requires this")
    unless defined $tmpdir;
  print("Workdir: $tmpdir\n");
  $self->{coverage_dir} = "$tmpdir";
  $self->{memdump_file} = undef;

  if ($ENV{COVERAGE_MEMBUF})
    {
      # Expecting coverage data via a memory dump done by the simulator.

      $self->{memdump_file} = $ENV{COVERAGE_DUMP_FILE} // "${tmpdir}/_memdump";
      $ENV{COVERAGE_DUMP_FILE} = $self->{memdump_file};

      # Use a large time span, since we expect the simulator to shutdown anyway
      # after the memory dump.
      $self->wait_for_more(300);
    }
  else
    {
      # Expecting coverage data via serial output

      # Inhibit until first chunk of data
      $self->inhibit_exit();

      # Once we're not inhibiting anymore, we "wait for more" which means we use a
      # smaller timeout once all other plugins are finished.
      $self->wait_for_more(6);
    }

  return $self;
}

sub process_mine
{
  my $self = shift;
  my $check_data = shift;
  $check_data =~ s/\e\[[\d,;\s]+[A-Za-z]//gi; # strip color escapes

  if ($check_data =~ /PATH '(.*)' (ZSTD|ZDATA) '(.+)'/)
    {
      my ($path, $type, $data) = ($1, $2, $3);

      push @{$self->{sources}}, $path;

      my $exe_name = $self->__get_name($path);

      print("Processing $type data.\n");

      my $fn = "__process_$type";

      $self->$fn($path, $data, $exe_name);

      # First chunk received. Stop inhibiting. "wait_for_more" still let's us
      # wait a little while for more data
      $self->permit_exit();
    }
  elsif ($self->{keep_going})
    {
      $self->{intermittent_fails} += 1;
    }
  else
    {
      L4::TapWrapper::fail_test("Broken Data?: '$check_data'");
    }
}

sub start_block {}
sub end_block {}

sub process_memory_dump
{
  my ($self) = @_;

  my $file = $self->{memdump_file};
  return unless $file;

  print "Reading coverage memory dump from $file\n";

  open (my $fh, '<', $file)
    or die "Could not open memory dump at $file: $!";

  # Will be deleted once $fh is closed;
  unlink($file);

  my $last = 0;
  while (!$last && (my $line = <$fh>))
    {
      # Look for 0 byte which marks the end of the used part of the memory buffer
      if ((my $offset = index($line, "\0")) != -1)
        {
          $line = substr($line, 0, $offset);
          $last = 1;
        }

      $self->process_any($line);
    }

  close($fh);
}

sub finalize
{
  my $self = shift;

  $self->process_memory_dump();

  open (my $sources_file, '>', "$self->{coverage_dir}/sources")
    or die "Could not open file: $!";

  foreach my $ln (@{$self->{sources}})
    {
      print $sources_file $ln."\n";
    }

  if ($self->{intermittent_fails} > 0)
    {
      $self->add_tap_line(0, "Broken data $self->{intermittent_fails} times");
      $self->add_raw_tap_line("1..1");
    }
  elsif ($self->{fail_if_no_data} && !$self->{has_data})
    {
      $self->add_tap_line(0, __PACKAGE__ . ": No coverage data");
      $self->add_raw_tap_line("1..1");
    }

  return $self->SUPER::finalize();
}

sub __get_name
{
  my $self = shift;
  my $path = shift;
  my $name = (split("/",$path))[-1];

  if (exists $self->{outputs}{"$name"})
    {
      $self->{outputs}{"$name"} += 1;
      $name = $name."_".$self->{outputs}{"$name"}
    }
  else
    {
      $self->{outputs}{"$name"} = 1;
    }
  return $name;
}

# Add a newly created lcov file to the accumulated coverage output file (or
# create it if it does not yet exist)
sub __lcov_finish
{
  my $self = shift;
  my $path = shift;
  my $exe_name = shift;

  system($llvm_profdata_cmd, "merge", "--instr",
         "$self->{coverage_dir}/$exe_name.profraw", "-o",
         "$self->{coverage_dir}/$exe_name.profdata");

  open(my $lcov_data_in, "-|",
       qq($llvm_cov_cmd export $path --format=lcov -instr-profile=$self->{coverage_dir}/$exe_name.profdata))
    or die "$!";

  open (my $lcov_data_out, '>', "$self->{coverage_dir}/$exe_name.lcov")
    or die "Could not open file: $!";

  while (my $line = <$lcov_data_in>)
    {
      $line =~ s/^SF:(.*)$/"SF:".realpath($1)/e;
      print $lcov_data_out $line;
    }

  close($lcov_data_in)
    or die "$llvm_cov_cmd: $!";

  close($lcov_data_out);

  unlink "$self->{coverage_dir}/$exe_name.profraw";
  # unlink "$self->{coverage_dir}/$exe_name.profdata";

  $self->{has_data} = 1;
}


# This extracts zstd compressed coverage data into an lcov file
sub __process_ZSTD
{
  print("\ndecoding ZSTD... \n");
  require Compress::Zstd;
  my $self = shift;
  my $path = shift;
  my $indata = shift;
  my $exe_name = shift;

  L4::TapWrapper::fail_test("No indata") unless $indata;
  print "First Char: ", substr($indata, 0, 1), "\n";
  print "Last Char: ", substr($indata, -1), "\n";
  print "Data for $path\n";

  my $data = Compress::Zstd::decompress(decode_base64($indata))
    or L4::TapWrapper::fail_test("Decompression failed!");
  if (length($data))
    {
      printf("$path - Data: %.2f kB Decompressed: %.2f kB (%.1f%%)\n",
        length($indata)/1024, length($data)/1024,
        length($indata)*100.0/length($data));
    }

  open my $fh, '>', "$self->{coverage_dir}/$exe_name.profraw";
  print $fh $data;


  $self->__lcov_finish($path, $exe_name);
}

# This extracts a single plain base64 coverage data with runlength encoding
sub __process_ZDATA
{
  my $self = shift;
  my $path = shift;
  my $data = shift;
  my $exe_name = shift;
  print("processing plain dump from $path\n");

  # Unravel runlength encoding
  my $plain = "";
  my $cnt = 0;
  while ($data =~ /([^@]*)@(.)(.)(.*)/)
    {
      $plain .= $1 . ($2 x unpack('xxC',decode_base64("AAA".$3)));
      $data = $4;
      $cnt += 1;
    }
  $plain .= $data;

  open my $fh, '>', "$self->{coverage_dir}/$exe_name.profraw";
  print $fh decode_base64($plain);

  $self->__lcov_finish($path, $exe_name);
}

1;

__END__
