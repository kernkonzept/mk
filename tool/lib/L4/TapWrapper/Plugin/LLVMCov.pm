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
  $self->{intermittent_fails} = 0;

  $L4::TapWrapper::wait_for_more = 1;
  bless $self, $type;

  my $tmpdir = $self->tmpdir();
  L4::TapWrapper::fail_test("Workdir not set. Coverage requires this")
    unless defined $tmpdir;
  print("Workdir: $tmpdir\n");
  $self->{coverage_dir} = "$tmpdir";
  return $self;
}

sub process_mine
{
  my $self = shift;
  my $check_data = shift;
  $check_data =~ s/\e\[[\d,;\s]+[A-Za-z]//gi; # strip color escapes
  my ($path, $data) = $check_data =~ /PATH '(.*)' ZDATA '(.*)'/;
  if ($data)
    {
      print("Plain data dumped.\n");
      push(@{$self->{sources}}, $path);
      my $exe_name = $self->__get_name($path);
      $self->__dump_plain($path, $data, $exe_name);
      return;
    }

  ($path, $data) = $check_data =~ /PATH '(.*)' ZSTD '(.*)'/;
  if ($data)
    {
      print("Compressed data dumped.\n");
      push(@{$self->{sources}}, $path);
      my $exe_name = $self->__get_name($path);
      $self->__dump_zstd($path, $data, $exe_name);
      return;
    }

  if ($self->{keep_going})
    {
      $self->{intermittent_fails} += 1;
    }
  else
    {
      L4::TapWrapper::fail_test("Broken Data?: '$check_data'");
    }
  return;
}

sub start_block {}
sub end_block {}

sub finalize
{
  my $self = shift;

  open (my $sources_file, '>', "$self->{coverage_dir}/sources")
    or die "Could not open file: $!";

  foreach my $ln (@{$self->{sources}})
    {
      print $sources_file $ln."\n";
    }

  L4::TapWrapper::fail_test("Broken data $self->{intermittent_fails} times")
    if ($self->{intermittent_fails} > 0);

  return ();
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
  system( ($llvm_profdata_cmd, "merge", "--instr",
      "$self->{coverage_dir}/$exe_name.profraw", "-o",
      "$self->{coverage_dir}/$exe_name.profdata") );

  my $output = `$llvm_cov_cmd export $path --format=lcov -instr-profile=$self->{coverage_dir}/$exe_name.profdata`;
  die "$!" if $?;

  open (my $file, '>', "$self->{coverage_dir}/$exe_name.lcov")
    or die "Could not open file: $!";

  for my $line ( split /\n/, $output )
    {
      if ($line =~ /^SF:(.*)$/)
        {
          print $file "SF:".realpath($1)."\n";
        }
      else
        {
          print $file $line . "\n";
        }
    }

  close $file;

  unlink "$self->{coverage_dir}/$exe_name.profraw";
  # unlink "$self->{coverage_dir}/$exe_name.profdata";
}


# This extracts zstd compressed coverage data into an lcov file
sub __dump_zstd
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
sub __dump_plain
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
