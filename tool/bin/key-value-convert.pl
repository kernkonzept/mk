#! /usr/bin/env perl

# Read a file containing key=value entries and
# output them into other key/value formats.

# Its primary functionality is to be flexible about whitespace around
# assignment '=', consistently quote non-number strings, and ignore
# unrecognized lines.

# SYNOPSIS
#
# Use like typical unix tool, output always to stdout:
#
#   key-value-convert.pl < config_file
#   key-value-convert.pl   config_file
#   cat config_file | key-value-convert.pl
#
# Specify target format (lua, shell, perl, perlhash [default=shell]):
#
#    key-value-convert.pl --to=shell
#
# Prefix each line (examples):
#
#   key-value-convert.pl --to=lua      --prefix="myvariable."
#   key-value-convert.pl --to=shell    --prefix="MYPREFIX_"
#   key-value-convert.pl --to=perl     --prefix="my "
#   key-value-convert.pl --to=perlhash

use 5.008;
use strict;
use warnings;

BEGIN {
  use FindBin;
  unshift @INC, "$FindBin::Bin/../lib/";
}

use Getopt::Long;
use L4::KeyValueConfig;

my $targetformat = "shell";
my $prefix = "";

GetOptions(
  "to=s", \$targetformat,
  "prefix=s", \$prefix,
);

my @lines = <>;

my %config = L4::KeyValueConfig::parse(1, @lines);

my ($key, $val);
if ($targetformat eq 'shell')
  {
    print "$prefix$key=$val\n" while ($key, $val) = each %config;
  }
elsif ($targetformat eq 'lua')
  {
    print "$prefix$key = $val\n" while ($key, $val) = each %config;
  }
elsif ($targetformat eq 'perl')
  {
    print "$prefix\$$key = $val;\n" while ($key, $val) = each %config;
  }
elsif ($targetformat eq 'perlhash')
  {
    print "$prefix'$key' => $val,\n" while ($key, $val) = each %config;
  }
else
  {
    print STDERR "Unknown target format '$targetformat'.\n";
    exit 1;
  }
