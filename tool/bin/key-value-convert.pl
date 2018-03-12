#! /usr/bin/perl

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
use Getopt::Long;
use Scalar::Util "looks_like_number";

my $targetformat = "shell";
my $prefix = "";

GetOptions(
  "to=s", \$targetformat,
  "prefix=s", \$prefix,
);

# key/value syntax
my $kv_regex = qr/^\s*(\w+)\s*=\s*(.*?)(\s*)$/;

my %config =
  map { my @ret;
        $_ =~ $kv_regex;
        my ($key, $val) = ($1, $2);
        # keep existing outer quotes
        if ($val =~ /^'[^']*'$/ || $val =~ /^"[^"]*"$/)
          {
            @ret = ($key => $val);
          }
        # numbers
        elsif (looks_like_number($val))
          {
            @ret = ($key => $val);
          }
        # quote unquoted non-number strings;
        # ignore strange inner quoted strings
        elsif ($val !~ /['"]/)
          {
            @ret = ($key => "'$val'");
          }
        # ignore everything else
        else
          {
            @ret = ();
          }
        @ret;
      }
  grep { /^\s*\w+\s*=/ } # looks like key=value at all
  grep { $_ !~ /^\s*#/ } # ignore comment lines
  <>;

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
