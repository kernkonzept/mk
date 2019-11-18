#! /usr/bin/env perl


my %consts;

while (<>)
{
  chomp;
  if (/#define\s+([^\s_]+)_(\S+)\s+(\S+)/)
  {
    push @{$consts{$1}}, [ "$1_$2", $3 ];
#    print STDOUT "$1 _ $2 = $3,\n";
  }
}

print <<EOF
#pragma once

/*
 *
 *
 * Constants for L4Re events ...
 */

EOF
;

foreach my $key (keys %consts)
{
  my $wdith;
  $width = 0;
  foreach (@{$consts{$key}})
  {
    $width = length ${$_}[0] if length ${$_}[0] > $width;
    ${$_}[1] =~ s/^\D/L4RE_$&/;
  }

  print "\nenum L4Re_events_".lc($key)."\n{\n";
  foreach (@{$consts{$key}})
  {
    printf "  L4RE_%-*s = %s,\n", $width, ${$_}[0], ${$_}[1];
  }
  print "};\n";
}
