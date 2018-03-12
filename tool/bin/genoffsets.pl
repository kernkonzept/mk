#! /usr/bin/perl

use strict;
use Getopt::Long;

my @include; # include files needed for data structures
my $generate_cxx;
my $output_file;
my $mode = '';
my %modes;
my $offsets;
my $prefix;

my $exit = 0;
my $output_data = '';
my $offset_entry_handler;

GetOptions(
  "include|i=s" => \@include,
  "cxx" => \$generate_cxx,
  "output|o=s" => \$output_file,
  "mode|m=s" => \$mode,
  "offsets|f=s" => \$offsets,
  "prefix=s" => \$prefix,
);

if ($output_file eq '')
{
  die "no output file specified\n";
}

sub handle_offsets()
{
  unshift(@ARGV,'-') unless @ARGV;
  while (my $file = shift @ARGV)
    {
      my $fh;
      open $fh, $file || die "could not open $file: $!\n";
      while(<$fh>)
	{
	  chomp;
	  if (/^#include\s+[<"](.*)[>"].*$/)
	    {
	      push @include, $1;
	    }
	  elsif (/^\s*$/ || /^#.*$/)
	    {
	    }
	  elsif (/^(\S+):\s*(.*)$/)
	  {
	    if (defined $offset_entry_handler->{$1})
	      {
		$offset_entry_handler->{$1}($2, "$file:$.");
	      }
	    else
	      {
		print stderr "$file:$.: no handler for type '$1'\n";
		$exit = 1;
	      }
	  }
	}
      close $fh;
    }
}

sub c_handle_member_offs($$)
{
  my ($v, $line) = @_;
  if ($v=~/^(\S*)\s+(\S*)\s+(\S*)\s*$/)
  {
    $output_data .= 
    "      ((unsigned long)(&((($2 *) 1)->$3)) - 1), /* $1 = offset($2.$3) */\n";
  }
  else
  {
    print stderr "$line: malformed entry\n";
    $exit = 1;
  }
}

sub c_handle_cast_offs($$)
{
  my ($v, $line) = @_;
  if ($v=~/^(\S*)\s+(\S*)\s+(\S*)\s*$/)
  {
    $output_data .=
      "      ((unsigned long)(($3 *)(($2 *)(&_t))) - (unsigned long)&_t), /* $1 = cast $2 to $3 */\n";
  }
  else
  {
    print stderr "$line: malformed entry\n";
    $exit = 1;
  }
}

sub c_handle_const($$)
{  
  my ($v, $line) = @_;
  if ($v=~/^(\S*)\s+(\S*)\s*$/)
  {
    $output_data .= "      (unsigned long)($2), /* $1 = $2 */\n";
  }
  else
  {
    print stderr "$line: malformed entry\n";
    $exit = 1;
  }

}

sub c_print_prolog()
{
  if ($generate_cxx == 1)
  {
    print OUT "#define class struct\n",
          "#define private public\n",
  	  "#define protected public\n",
	  "\n";
  }
  
  foreach my $inc (@include)
  {
    print OUT "#include \"$inc\"\n";
  }
  print OUT "\n".
    "void offsets_func(char **a, unsigned long **b);\n".
    "void offsets_func(char **a, unsigned long **b)\n".
    "{\n".
    "  static int _t;\n".
    "  (void)_t;\n".
    "  static char length[32] __attribute__((unused, section(\".e_length\")))\n".
    "    = { sizeof(unsigned long), };\n".
    "\n".
    "  static unsigned long offsets[] __attribute__((unused, section(\".offsets\"))) =\n".
    "    {\n";
}

sub c_print_epilog()
{
  print OUT
    "    };\n".
    "  *a = length;\n".
    "  *b = offsets;\n".
    "}\n";
}

$modes{c} = 
{
  'M' => \&c_handle_member_offs,
  'A' => \&c_handle_cast_offs,
  'C' => \&c_handle_const,
  'prolog' => \&c_print_prolog,
  'epilog' => \&c_print_epilog
};


my $bin_quantity_size = 0;
my $bin_offs;
sub bin_read_value()
{
  if (!$bin_quantity_size)
  {
    open $bin_offs, '<', $offsets || die "could not open $offsets: $!\n";
    read $bin_offs, $bin_quantity_size, 1 
      || die "could not read long_length from $offsets: $!\n";
      
    $bin_quantity_size = unpack ("c", $bin_quantity_size);
    seek ($bin_offs,32,0) || die "could not seek $offsets file: $!\n";
  }

  my $data;
  read $bin_offs, $data, $bin_quantity_size || die "could not read $offsets: $!\n";
  if ($bin_quantity_size == 4)
  {
    $data = sprintf("0x%08x", unpack("L",$data));
  } elsif ($bin_quantity_size == 8)
  {
    my @v = unpack("LL", $data);
    $data = sprintf("0x%08x%08x",$v[1], $v[0]);
  } else
  {
    die "unsupported offset size: $bin_quantity_size\n";
  }

  return $data;
}

sub bin_handle_x($$)
{
  my ($v, $line) = @_;
  my $data = bin_read_value();
  if ($v=~/^(\S*)\s+\S*.*$/)
  {
    $output_data .= "#define $prefix$1 $data\n";
  }
  else
  {
    print stderr "$line: malformed entry\n";
    $exit = 1;
  }
}


$modes{d} = 
{
  'M' => \&bin_handle_x,
  'A' => \&bin_handle_x,
  'C' => \&bin_handle_x,
};


$offset_entry_handler = $modes{$mode};

if (!defined $offset_entry_handler)
{
  print stderr "undefined mode '$mode'\n";
  exit 1;
}

handle_offsets();
close $bin_offs if $bin_offs;

exit $exit if $exit;

open OUT, '>', $output_file || die "could not open $output_file: $!\n";

$offset_entry_handler->{prolog}() if (defined $offset_entry_handler->{prolog});
print OUT $output_data;
$offset_entry_handler->{epilog}() if (defined $offset_entry_handler->{epilog});

close OUT;

exit $exit;
