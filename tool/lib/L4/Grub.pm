package L4::Grub;

use Exporter;
use warnings;
use vars qw(@ISA @EXPORT);
@ISA    = qw(Exporter);

use Getopt::Long;

sub parse_gengrub_args()
{
  my %a = ( timeout => undef,
            serial  => undef,
            grubpathprefix => undef,
            grubentrytitle => undef,
	   );
  my @opts = ("timeout=i", \$a{timeout},
              "serial",    \$a{serial},
              "grubpathprefix:s", \$a{grubpathprefix},
              "grubentrytitle:s", \$a{grubentrytitle},
            );

  if (!GetOptions(@opts))
    {
      print "Command line parsing failed.\n";
    }

  if (0)
    {
      print "Options:\n";
      for (keys %a)
        {
          print "$_: $a{$_}\n" if defined $a{$_};
        }
    }

  %a;
}

sub prepare_grub1_dir($)
{
  my $dir = shift;

  return if -e "$dir/boot/grub/stage2_eltorito";

  my $copypath;
  my @grub_path = ("/usr/lib/grub/i386-pc", "/usr/share/grub/i386-pc",
                   "/boot/grub", "/usr/local/lib/grub/i386-pc",
                   "/usr/lib/grub/x86_64-pc");
  unshift @grub_path, $ENV{GRUB_PATH} if defined $ENV{GRUB_PATH};

  foreach my $p (@grub_path) {
    $copypath=$p if -e "$p/stage2_eltorito";
  }
  die "Cannot find a stage2_eltorito file..." unless defined $copypath;

  # copy files
  mkdir "$dir/boot";
  mkdir "$dir/boot/grub";
  system("cp $copypath/stage2_eltorito $dir/boot/grub");
  chmod 0644, "$dir/boot/grub/stage2_eltorito";
}

sub grub1_mkisofs($$@)
{
  my ($isofilename, $dir, @morefiles) = @_;
  system("cp -v ".join(' ', @morefiles)." $dir") if @morefiles;
  my $mkisofs = 'genisoimage';
  system("genisoimage -help >/dev/null 2>&1");
  $mkisofs = 'mkisofs' if $?;
  my $cmd = "$mkisofs -f -R -b boot/grub/stage2_eltorito".
            " -no-emul-boot -boot-load-size 4 -boot-info-table".
            " -hide-rr-moved -J -joliet-long -o \"$isofilename\" \"$dir\"";

  print "Generating GRUB1 image with cmd: $cmd\n";
  system("$cmd");
  die "Failed to create ISO" if $?;
}

sub prepare_grub2_dir($)
{
  my $dir = shift;
  mkdir "$dir/boot";
  mkdir "$dir/boot/grub";
}

sub check_for_program
{
  my $prog;
  for my $p (@_)
    {
      my $o = `sh -c "command -v \"$p\""`;
      if ($? == 0)
        {
          chomp $o;
          $prog = $o;
          last;
        }

    }

  die "\nDid not find ".join(' or ', map "'$_'", @_)
      ." program, required to proceed. Please install.\n\n"
    unless defined $prog;

  $prog;
}

sub grub2_mkisofs($$@)
{
  my ($isofilename, $dir, @morefiles) = @_;
  my $mkr = check_for_program("grub2-mkrescue", "grub-mkrescue");
  # grub-mkrescue returns without error if those are missing
  check_for_program('xorriso');
  check_for_program('mformat'); # EFI only?
  check_for_program('mcopy');   # EFI only?

  # Figure out grub-mkrescue variant as there are three different
  # versions of grub-mkrescue, where one is incompatible.
  # A pre-Grub-2.02 shell script, the incompatible binary-version
  # (2.02~beta2*) and the fixed binary-version (2.02~beta3*) with restored
  # behavior to the original shell script.
  # The incompatible version is actually unreleased but has been, for
  # example, shipped with Debian 8. It only works without the "-as mkisofs"
  # argument parts. We use the following to detect this version and act
  # accordingly.
  my $opt = '';
  system("$mkr --output=/dev/null /dev/null -f >/dev/null 2>&1");
  $opt = " -as mkisofs" unless $?;


  # Check whether the installed GRUB works for either PC or UEFI.
  my $is_pc;
  my $is_efi;
  my $is_hybrid;

  system("$mkr --install-modules=vbe --output=/dev/null /dev/null -f >/dev/null 2>&1");
  $is_pc = $? == 0;

  system("$mkr --install-modules=lsefi --output=/dev/null /dev/null -f >/dev/null 2>&1");
  $is_efi = $? == 0;

  if (not $is_pc and not $is_efi)
    {
      # As the last resort, check if GRUB is able to create a hybrid PC/UEFI image.
      system("$mkr --install-modules=acpi --output=/dev/null /dev/null -f >/dev/null 2>&1");
      $is_hybrid = $? == 0;
    }

  die "grub-mkrescue does not seem to work for either PC or UEFI targets. GRUB not (properly) installed?"
    if not $is_pc and not $is_efi and not $is_hybrid;

  if ($is_efi and $is_pc)
    {
      print "\nWarning: Unable to determine whether grub-mkrescue creates PC or UEFI images.\n";
      print "         Use your own discretion.\n\n";
    }

  my $cmd = "$mkr --output=\"$isofilename\" $dir ".
            join(' ', @morefiles)." --$opt -f";
  system("$cmd");
  die "Failed to create ISO" if $?;
  # grub-mkrescue does not propagate internal tool errors
  die "Failed to create ISO" unless -e $isofilename;

  if ($is_efi)
    {
      print "Note: Created UEFI ISO. Remember to add '-bios /usr/share/qemu/OVMF.fd'\n";
      print "      (or similar) to your QEMU call.\n\n";
    }

  if ($is_hybrid)
    {
      print "Note: Created hybrid PC/UEFI ISO. Remember to add '-bios /usr/share/qemu/OVMF.fd'\n";
      print "      (or similar) to your QEMU call to boot it in UEFI mode.\n\n";
    }
}


sub grub1_config_prolog(%)
{
  my %opts = @_;
  my $s = '';

  $s .= "color 23 52\n";
  $s .= "serial\nterminal serial\n" if $opts{serial};
  $s .= "timeout $opts{timeout}\n" if defined $opts{timeout};
  $s .= "\n";

  $s;
}

sub grub2_config_prolog(%)
{
  my %opts = @_;
  my $s = '';

  if ($opts{serial})
    {
      $s .= "serial\n";
      $s .= "terminal_output serial\n";
      $s .= "terminal_input serial\n";
    }
  $s .= "set timeout=$opts{timeout}\n" if defined $opts{timeout};

  $s;
}

