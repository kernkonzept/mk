#!/usr/bin/env perl

=pod

=head1 lua2dox converter

Extracts single line comments beginning with "--!" or multiline comments
beginning with "--[[!" and ending in "]]" and presents these as C-esque comments
in a format that doxygen understands. Futhermore this turns lua function
definitions into C function declarations for doxygen.

=cut

use strict;
use warnings;

binmode(STDOUT, ":encoding(UTF-8)");

my $in_block_comment = 0;

# C/C++ have a data type in their function declaration while lua does not. To
# make the documentation look more lua-ly we use a non-standard whitespace
# character as the "data type".
my $generic_datatype = "\x{200B}";

while(<>) {
  # Remove newline
  chomp;

  my $info_line = "";

  # If not in block comment
  unless ($in_block_comment) {
    if (s/--(\[\[)?!(.*)$//) {
      # Found start of single line comment or block comment
      # We're in a block comment if there are square brackets
      $in_block_comment = $1;

      # Add C-esque comment to output for doxygen to parse
      $info_line = "//!$2";
    }

    if (/^\s*function\s+([a-zA-Z0-9_]+)\s*\((.*)\)/) {
      # A C function definition needs a data type, add that "data type" here
      my $paramlist =
        join ", ",
        map { "$generic_datatype $_" }
        map { s/^\s+|\s+$//gr }
        split(/,/, $2);

      # Add C-esque function declaration to output for the lua function we just
      # found Prepend because there might be a comment in the same line. See
      # above.
      $info_line = "$1($paramlist);" . $info_line;
    }
  } else {
    # If block comment ends in this line
    if (/^(.*)\]\]/) {
      # then print only the comment part
      $info_line = "//!$1";
      # End of block comment
      $in_block_comment = 0;
    } else {
      # else print whole line as comment
      $info_line = "//!$_";
    }
  }

  # Print a line for every read line so that the lines match with the original
  # file and the "defined in line XX" links in the documentation work.
  print("$info_line\n");
}
