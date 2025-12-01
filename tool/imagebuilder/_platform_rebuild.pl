#!/usr/bin/env perl

# Abstract: This script checks if the present bootstrap image matches the
# selected platform, ram_base and efi support and rebuilds it if not. To avoid
# race conditions or multiple calls to the build system at once it uses a lock
# file in the build directory.

use strict;
use warnings;
use File::Basename;
use Fcntl qw(:flock);

BEGIN { unshift @INC, dirname($0).'/../lib'; }

use L4::Makeconf;
use L4::Image;

die "OBJ_BASE not set." unless $ENV{OBJ_BASE};
die "OBJ_BASE does not exist." unless -d $ENV{OBJ_BASE};

my $image = shift;

## Get lock. Lock is released automatically when the fd gets closed.
open(my $fd, ">", $ENV{OBJ_BASE} . "/.make.flock") or die "Cannot open lock file";
flock($fd, LOCK_EX) or die "Cannot acquire lock in lock file";

my $_platform_type_selected = L4::Makeconf::get($ENV{OBJ_BASE}, "PLATFORM_TYPE") // "invalid";
my $_ram_base_selected = L4::Makeconf::get($ENV{OBJ_BASE}, "RAM_BASE") // -1;
$_ram_base_selected = L4::Makeconf::get($ENV{OBJ_BASE}, "PLATFORM_RAM_BASE") unless $_ram_base_selected;
my $_uefi_selected = (defined($ENV{BOOTSTRAP_DO_UEFI}) && $ENV{BOOTSTRAP_DO_UEFI} eq "y") ? "y" : "n";
my $_platform_type_switch = L4::Makeconf::get($ENV{OBJ_BASE}, "RAM_BASE_SWITCH_PLATFORM_TYPE");

my $_ram_base_switch;
my $_ram_base_switch_ok;

if (defined($_platform_type_switch))
  {
    $_ram_base_switch = L4::Makeconf::get($ENV{OBJ_BASE}, "RAM_BASE_${_platform_type_switch}");
    $_ram_base_switch_ok = (L4::Makeconf::get($ENV{OBJ_BASE}, "RAM_BASE_SWITCH_OK") // "no") eq "yes";
  }
else
  {
    $_ram_base_switch = -1;
    $_ram_base_switch_ok = 0;
  }

my $makecmd = $ENV{MAKE} // "make";

my $rebuild = 1;

if ($_ram_base_switch_ok && -f $image)
  {
    my $image_attrs;
    eval {
      L4::Image::process_image($image, {}, sub {
        $image_attrs = shift->{attrs};
      });
      1;
    };

    if ($image_attrs)
      {
        my $_platform_type_built = $image_attrs->{"l4i:PT"};
        my $_ram_base_built = $image_attrs->{"l4i:rambase"};
        my $_uefi_built = ($image_attrs->{"l4i:uefi"} eq "y") ? "y" : "n";

        if (0)
          {
            print STDERR "$_platform_type_selected <> $_platform_type_built\n";
            print STDERR "$_ram_base_selected <> $_ram_base_built\n";
            print STDERR hex($_ram_base_selected)." <> ".hex($_ram_base_built)."\n";
            print STDERR "$_uefi_selected <> $_uefi_built\n";
          }

        $rebuild = 0 unless
          !defined($_platform_type_built) || !defined($_ram_base_built) ||
          $_platform_type_selected ne $_platform_type_built ||
          $_platform_type_switch ne $_platform_type_built ||
          hex($_ram_base_selected) != hex($_ram_base_built) ||
          hex($_ram_base_switch) != hex($_ram_base_built) ||
          $_uefi_selected ne $_uefi_built;
      }
  }

if ($rebuild)
  {
    delete @ENV{qw(E ENTRY MODULES_LIST MAKEFLAGS L4DIR PKGDIR)};

    # Updates rambase
    system($makecmd,"-C",$ENV{OBJ_BASE},"check_and_adjust_ram_base") == 0
      or die "check_and_adjust_ram_base failed";

    # Try bootstrap again, because check_and_adjust_ram_base might not have done it.
    system($makecmd,"-C",$ENV{OBJ_BASE} . "/pkg/bootstrap", "E=", "ENTRY=") == 0
        or die "bootstrap failed";
  }

__END__
