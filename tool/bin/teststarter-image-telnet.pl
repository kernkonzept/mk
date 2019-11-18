#!/usr/bin/env perl

# This tool is expected to work as EXTERNAL_TEST_STARTER for run_test.
#
# It expects to be pointed to your locally configured
# simulator start script in env var SIMULATOR_START.
#
# An example to call it looks like this
#
#  export EXTERNAL_TEST_STARTER=$L4RE_SRC/tool/bin/teststarter-image-telnet.pl
#  export SIMULATOR_START=/path/to/configured/simulator-exe
#  make test

use IO::Handle;
use Socket qw(PF_INET SOCK_STREAM sockaddr_in inet_aton);

my $simulator_start = $ENV{SIMULATOR_START};
my $simulator_start_sleeptime = $ENV{SIMULATOR_START_SLEEPTIME} || 1;
my $simulator_imagetype = $ENV{SIMULATOR_IMAGETYPE} || 'elfimage';
my $simulator_host = $ENV{SIMULATOR_HOST} || 'localhost';
my $simulator_port = $ENV{SIMULATOR_PORT} || 11111;

if (not $simulator_start)
  {
    die "Please provide SIMULATOR_START to your simulator start script.\n";
  }

# create image
my $retval = system("make $simulator_imagetype E=maketest");
die "Error creating image file\n" if $retval != 0;

# start simulator in background
my $simulator_pid = fork;
if ($simulator_pid == 0)
  {
    $ENV{SIMULATOR_PORT} = $simulator_port; # provide port to simulator
    exec $simulator_start;
  }
sleep $simulator_start_sleeptime;

# connect to simulator port and pass-through its output
socket(my $simulator, PF_INET, SOCK_STREAM, 0)
  or die "Could not create socket: $!";
connect($simulator, sockaddr_in($simulator_port, inet_aton($simulator_host)))
  or die "Could not connect: $!";
STDOUT->autoflush(1);
print while <$simulator>;
close $simulator;
