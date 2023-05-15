
package L4::ModList;
use Exporter;
use File::Basename;
use warnings;
use vars qw(@ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw(get_module_entry search_file get_entries merge_entries);

my @internal_searchpaths;

sub quoted { shift =~ s/"/\\"/gr; }
sub trim { shift =~ s/^\s+|\s+$//gr; }

sub get_command_and_cmdline
{
  my $cmd_and_args = shift;
  my %opts = @_;

  my ($file, $args) = split /\s+/, $cmd_and_args, 2;
  $file = trim($file);
  $args = trim($args) if defined($args);

  my $command = basename($file);
  $command = trim($opts{fname}) if exists $opts{fname};

  my $cmdline = $command;
  $cmdline .= ' ' . $args if defined($args);

  $args = '' unless defined($args);

  # $mod structure
  (
    # File name or absolute file path of file on host
    file => $file,
    # File name in L4Re environment: fname if specified otherwise basename($file)
    command => $command,
    # $command and $args separated by a space (no trailing space if no args)
    cmdline => $cmdline,
    # Arguments only
    args => $args,
    # $cmdline but " replaced with \"
    cmdline_quoted => quoted($cmdline),
    # $args but " replaced with \"
    args_quoted => quoted($args),
    # Module type. Default: 0 (generic). 1: kernel, 2: root pager, 3: root task
    opts => { %opts },
  );
}

sub error($)
{
  print STDERR shift;
  exit(1);
}

sub parse_options
{
  my $optstring = shift;
  my %opts;

  foreach (split /\s*,\s*/, $optstring)
    {
      if (/(\S+)\s*=\s*(.+)/)
        {
          $opts{$1} = $2;
        }
      else
        {
          $opts{$_} = undef;
        }
    }

  print STDERR "Options: ",
        join(", ", map { $opts{$_} ? "$_=$opts{$_}" : $_ } keys %opts), "\n"
   if %opts && 0;

  return %opts;
}

sub handle_line
{
  my $r = shift;
  my %opts = @_;

  $r =~ s/\s+$//;

  if (exists $opts{arch})
    {
      my @a = split /\|+/, $opts{arch};
      return () unless grep /^$ENV{ARCH}$/, @a;
    }

  if (exists $opts{perl})
    {
      my @m = eval $r;
      die "perl: ".$@ if $@;
      return @m;
    }

  if (exists $opts{shell})
    {
      my @m = split /\n/, `$r`;
      error "$mod_file:$.: Shell command failed\n" if $?;
      return @m;
    }

  return ( glob $r ) if exists $opts{glob};

  return ( $r );
}

sub readin_config($)
{
  my ($mod_file) = @_;

  my @fs_fds;
  my @fs_filenames;
  my @mod_files_for_include;
  my $fd;
  my @contents;
  my %file_to_id;
  my %id_to_file;
  my $file_id_cur = 0;

  push @mod_files_for_include, $mod_file;

  while (1)
    {
      if (@mod_files_for_include)
        {
          my $f = shift @mod_files_for_include;

          if (grep { /^$f$/ } @fs_filenames)
            {
              print STDERR "$mod_file:$.: Warning: $f already included, skipping.\n";
              next;
            }

          push @fs_filenames, $mod_file;
          push @fs_fds, $fd;

          undef $fd;
          $mod_file = $f;
          open($fd, $f) || error "Cannot open '$f': $!\n";

          $id_to_file{$file_id_cur} = $f;
          $file_to_id{$f} = $file_id_cur++;
        }

      while (<$fd>)
        {
          chomp;
          s/#.*$//;
          s/^\s*//;
          next if /^$/;

          my ($cmd, $remaining) = split /\s+/, $_, 2;
          $cmd = lc($cmd);

          if ($cmd eq 'include')
            {
              my @f = handle_line($remaining);
              foreach my $f (@f)
                {
                  my $abs;
                  if ($f =~ /^\//)
                    {
                      $abs = $f;
                    }
                  else
                    {
                      my @tmp = split /\/+/, $mod_file;
                      $tmp[@tmp - 1] = $f;
                      $abs = join('/', @tmp);
                    }
                  unshift @mod_files_for_include, glob $abs;
                }

              last;
            }

          push @contents, [ $file_to_id{$mod_file}, $., $_ ];
        }

      unless (defined $_)
        {
          close $fd;

          $fd       = pop @fs_fds;
          $mod_file = pop @fs_filenames;

          last unless defined $fd;
        }
    }


  if (0)
    {
      print STDERR "$id_to_file{$$_[0]}($$_[0]):$$_[1]: $$_[2]\n" foreach (@contents);
    }

  return (
           contents => [ @contents ],
           file_to_id => { %file_to_id },
           id_to_file => { %id_to_file },
         );
}

sub disassemble_line
{
  $_[0] =~ /^([^\s\[]+)(?:\[\s*(.*)\s*\])?(?:\s+(.*))?/;
  ($1, $2, $3);
}

sub check_env_var
{
  my ($envvar, $type) = @_;

  if ($type eq 'path')
    {
      $ENV{$envvar} = "/env-var/$envvar/is/not/set" unless defined $ENV{$envvar};
    }
  elsif ($type eq 'word')
    {
      $ENV{$envvar} = "env-var-$envvar-not-set" unless defined $ENV{$envvar};
    }
  else
    {
      die "Unknown type '$type'";
    }
};

## Extract an entry with modules from a modules.list file
sub get_module_entry($$)
{
  my ($mod_file, $entry_to_pick) = @_;
  my @mods;
  my %type_num = ( kernel => 1, sigma0 => 2, roottask => 3 );
  my %base_mods = (
    kernel   => { get_command_and_cmdline("fiasco"), default => 1 },
    sigma0   => { get_command_and_cmdline("sigma0"), default => 1 },
    roottask => { get_command_and_cmdline("moe"), default => 1 },
  );
  my %groups;

  check_env_var('L4DIR', 'path');
  check_env_var('PLATFORM_TYPE', 'word');
  check_env_var('ARCH', 'word');
  check_env_var('SRC_BASE_ABS', 'path');

  my $process_mode = undef;
  my $found_entry = 0;
  my %entry_opts;
  my $global = 1;
  my $modaddr_title;
  my $modaddr_global;
  my %bootstrap = (
    get_command_and_cmdline("bootstrap"),
  );
  my $linux_initrd;
  my $is_mode_linux;

  my %mod_file_db = readin_config($mod_file);

  foreach my $fileentry (@{$mod_file_db{contents}})
    {
      $_ = $$fileentry[2];
      $. = $$fileentry[1];

      chomp;
      s/#.*$//;
      s/^\s*//;
      next if /^$/;

      if (/^modaddr\s+(\S+)/) {
        $modaddr_global = $1 if  $global;
        $modaddr_title  = $1 if !$global and $process_mode;
        next;
      }

      my ($type, $opts, $remaining) = disassemble_line($_);

      my %opts;
      %opts = parse_options($opts) if defined $opts;

      $type = lc($type);

      $type = 'bin'   if $type eq 'module';

      if ($type =~ /^(entry|title)$/) {
        last if $found_entry; # If we already have an entry do not process more
        ($remaining) = handle_line($remaining, %opts);
        if (defined $remaining && lc($entry_to_pick) eq lc($remaining)) {
          $process_mode = 'entry';
          $found_entry = 1;
          %entry_opts = %opts;
        } else {
          $process_mode = undef;
        }
        $global = 0;
        next;
      }

      if ($type eq 'searchpath') {
        push @internal_searchpaths, handle_line($remaining, %opts);
        next;
      } elsif ($type eq 'group') {
        $process_mode = 'group';
        $current_group_name = (split /\s+/, (handle_line($remaining, %opts))[0])[0];
        next;
      } elsif ($type eq 'default-bootstrap') {
        my $s = (handle_line($remaining, %opts))[0];
        next unless defined $s;
        %bootstrap = (%bootstrap, get_command_and_cmdline($s, %opts) );
        next;
      } elsif ($type =~ /default-(kernel|sigma0|roottask)/) {
        my $s = (handle_line($remaining, %opts))[0];
        $base_mods{$1} = { get_command_and_cmdline($s, %opts), default => 1 }
          if defined $s;
        next;
      }

      next unless $process_mode;

      my @params = handle_line($remaining, %opts);

      my @valid_types = ( 'bin', 'data', 'bin-nostrip', 'data-nostrip',
                          'bootstrap', 'roottask', 'kernel', 'sigma0',
                          'module-group', 'moe', 'initrd', 'set');
      error "$mod_file_db{id_to_file}{$$fileentry[0]}:$$fileentry[1]: Invalid type \"$type\"\n"
        unless grep(/^$type$/, @valid_types);

      # foo-nostrip is deprecated, use 'nostrip' option now. Added 2020-07.
      if ($type =~ /(.+)-nostrip$/) {
        print STDERR "Warning: Using '$type' is deprecated, use '$1"."[nostrip]' now\n";
        $type = $1;
        $opts{nostrip} = undef;
      }

      if ($type eq 'set') {
        my ($varname, $value) = split /\s+/, $params[0], 2;
        $is_mode_linux = 1 if $varname eq 'mode' and lc($value) eq 'linux';
      }

      if ($type eq 'moe') {
        my $bn = (reverse split(/\/+/, $params[0]))[0];
        $base_mods{roottask} = { get_command_and_cmdline("moe rom/$bn", %opts) };
      }
      next if not defined $params[0] or $params[0] eq '';

      if ($process_mode eq 'entry') {
        foreach my $m (@params) {

          my %modinfo = get_command_and_cmdline($m, %opts);

          # special cases
          if ($type eq 'bootstrap') {
            %bootstrap = (%bootstrap, %modinfo);
          } elsif ($type =~ /(roottask|kernel|sigma0)/) {
            $base_mods{$1} = { %modinfo };
          } elsif ($type eq 'initrd') {
            $linux_initrd      = $modinfo{file};
            $is_mode_linux     = 1;
          } elsif ($type eq 'module-group') {
            foreach (split /\s+/, join(' ', @params)) {
              error "$mod_file_db{id_to_file}{$$fileentry[0]}:$$fileentry[1]: Unknown group '$_'\n" unless defined $groups{$_};
              push @mods, @{$groups{$_}};
            }
          } else {
            push @mods, { %modinfo, type => 0 };
          }
        }
      } elsif ($process_mode eq 'group') {
        foreach my $m (@params) {
          my %modinfo = get_command_and_cmdline($m, %opts);
          push @{$groups{$current_group_name}}, { %modinfo, type => 0 };
        }
      } else {
        error "$mod_file_db{id_to_file}{$$fileentry[0]}:$$fileentry[1]: Invalid mode '$process_mode'\n";
      }
    }

  error "$mod_file: Unknown entry \"$entry_to_pick\"!\n".
        "Available entries: ".join(' ', sort &get_entries($mod_file))."\n"
    unless $found_entry;

  # For backwards compatibility add these modules in the classic order:
  # first the kernel, then sigma0, then roottask. At some point in the future
  # this will change when all users have been adapted to respect the type
  foreach ( qw( roottask sigma0 kernel ) )
    {
      my $mod = $base_mods{$_};
      unless (defined $mod->{default} and exists $entry_opts{"no-defaults"})
        {
          unshift @mods, { %{$mod}, type => $type_num{$_} };
        }
    }


  if (defined $is_mode_linux)
    {
      error "No Linux kernel image defined\n" unless defined $base_mods{kernel}{cmdline};
      print STDERR "Entry '$entry_to_pick' is a Linux type entry\n";
      my %r;
      %r = (
             # actually bootstrap is always the kernel in this
             # environment, for convenience we use $base_mods{kernel}
             # because that are the contents of 'kernel xxx' which sounds more
             # reasonable
             bootstrap => { %{$base_mods{kernel}} },
             type      => 'Linux',
           );
      $r{initrd} = { cmdline => $linux_initrd } if defined $linux_initrd;
      return %r;
    }

  # now some implicit stuff
  my $m = $modaddr_title || $modaddr_global;
  if (defined $m)
    {
      if ($bootstrap{cmdline} =~ /-modaddr\s+/)
        {
          $bootstrap{cmdline} =~ s/(-modaddr\s+)%modaddr%/$1$m/;
        }
      else
        {
          $bootstrap{cmdline} .= " -modaddr $m";
        }
    }

  return (
           bootstrap => \%bootstrap,
           mods    => [ @mods ],
           modaddr => $modaddr_title || $modaddr_global,
           type    => 'MB',
           entry   => $entry_to_pick,
         );
}

sub entry_is_linux(%)
{
  my %e = @_;
  return defined $e{type} && $e{type} eq 'Linux';
}

sub entry_is_mb(%)
{
  my %e = @_;
  return defined $e{type} && $e{type} eq 'MB';
}

sub get_entries($)
{
  my ($mod_file) = @_;
  my @entry_list;

  my %mod_file_db = readin_config($mod_file);

  foreach my $fileentry (@{$mod_file_db{contents}})
    {
      my ($t, $o, $n) = disassemble_line($$fileentry[2]);
      if ($t eq "entry" or $t eq "title")
        {
          my %opts;
          %opts = parse_options($o) if defined $o;
          ($n) = handle_line($n, %opts);

          push @entry_list, $n if defined $n and $n ne '';
        }
    }

  return @entry_list;
}

# internal function
sub handle_remote_file_get_file_in_dir
{
  my $lpath = shift;
  my $lfile = "__unknown_yet__";
  if (opendir(my $dh, $lpath))
    {
      my @entries = readdir $dh;
      die "Too many/few files in $lpath" if @entries != 3;
      foreach (@entries)
        {
          $lfile = $_ if $_ ne '.' and $_ ne '..';
        }
      closedir $dh;
    }

  return "$lpath/$lfile";
}

sub handle_remote_file
{
  my $file = shift;
  my $fetch_file = shift;
  my $output_dir = $ENV{OUTPUT_DIR} || $ENV{TMPDIR} || '/tmp';

  if ($file =~ /^s(sh|cp):\/\/([^\/]+)\/(.+)/)
    {
      my $rhost = $2;
      my $rpath = $3;

      (my $lpath = $file) =~ s,[\s/:~],_,g;
      $lpath = "$output_dir/$lpath";

      if ($fetch_file)
        {
          print STDERR "Retrieving $file...\n";

          mkdir $lpath || die "Cannot create directory '$lpath'";
          system("rsync -azS $rhost:$rpath $lpath 1>&2");
          die "rsync failed" if $?;
        }

      return handle_remote_file_get_file_in_dir($lpath);
    }

  if ($file =~ /^(https?:\/\/.+)/)
    {
      my $url = $1;

      (my $lpath = $url) =~ s,[\s/:~],_,g;
      $lpath = "$output_dir/$lpath";

      if ($fetch_file)
        {
          print STDERR "Retrieving $file...\n";

          # So we do not know the on-disk filename of the URL we're downloading
          # and since we want to use -N and as -N and -O don't play together,
          # we're doing the following:

          mkdir $lpath || die "Cannot create directory '$lpath'";
          system("wget -Nq -P $lpath $url");
          die "wget failed" if $?;
        }

      return handle_remote_file_get_file_in_dir($lpath);
    }

  if ($file =~ /^((ssh\+)?git:\/\/.+)/)
    {
      # git archive --format=tar --remote=$1 HEAD path | tar -xO
    }

  return undef;
}

# Search for a file by using a path list (single string, split with colons
# or spaces, see the split)
# return undef if it could not be found, the complete path otherwise
sub search_file($$)
{
  my $file = shift;
  my $paths = shift;

  return $file if $file =~ /^\// && -e $file && ! -d "$file";

  my $r = handle_remote_file($file, 0);
  return $r if $r;

  foreach my $p (split(/[:\s]+/, $paths), @internal_searchpaths) {
    return "$p/$file" if $p ne '' and -e "$p/$file" and ! -d "$p/$file";
  }

  undef;
}

sub search_file_or_die($$)
{
  my $file = shift;
  my $paths = shift;
  my $f = search_file($file, $paths);
  error "Could not find\n  '$file'\n\nwithin paths\n  " .
        join("\n  ", split(/[:\s]+/, $paths)) . "\n" unless defined $f;
  $f;
}

sub fetch_remote_file
{
  handle_remote_file(shift, 1);
}

sub is_gzipped_file
{
  my $file = shift;

  open(my $f, $file) || error "Cannot open '$file': $!\n";
  my $buf;
  read $f, $buf, 2;
  close $f;

  return length($buf) >= 2 && unpack("n", $buf) == 0x1f8b;
}

sub get_or_copy_file_uncompressed_or_die($$$$$)
{
  my ($command, $paths, $targetdir, $targetfilename, $copy) = @_;

  my $fp = L4::ModList::search_file_or_die($command, $paths);

  my $tf;
  if ($targetfilename) {
    $tf = $targetdir.'/'.$targetfilename;
  } else {
    (my $f = $fp) =~ s|.*/||;
    $tf = $targetdir.'/'.$f;
  }

  if (is_gzipped_file($fp)) {
    print STDERR "'$fp' is a zipped file, uncompressing to '$tf'\n";
    system("zcat $fp >$tf");
    $fp = $tf;
  } elsif ($copy) {
    system("cmp -s $fp $tf");
    if ($?)
      {
        print STDERR "cp $fp $tf\n";
        system("cp $fp $tf");
      }
    $fp = $tf;
  }

  $fp;
}

sub get_file_uncompressed_or_die($$$)
{
  return get_or_copy_file_uncompressed_or_die(shift, shift, shift, undef, 0);
}

sub copy_file_uncompressed_or_die($$$$)
{
  my ($command, $searchpaths, $targetdir, $targetfilename) = @_;
  return get_or_copy_file_uncompressed_or_die($command, $searchpaths,
                                              $targetdir, $targetfilename, 1);
}


sub generate_grub1_entry($$%)
{
  my $entryname = shift;
  my $prefix = shift;
  $prefix = '' unless defined $prefix;
  $prefix = "/$prefix" if $prefix ne '' and $prefix !~ /^[\/(]/;
  my %entry = @_;
  my $s = "title $entryname\n";
  my $c = $entry{bootstrap}{cmdline};
  $s .= "kernel $prefix/$c\n";

  if (entry_is_linux(%entry) and defined $entry{initrd})
    {
      $c = $entry{initrd}{cmdline};
      $s .= "initrd $prefix/$c\n";
      return $s;
    }

  foreach my $m (@{$entry{mods}})
    {
      $c = $m->{unique_short_filepath} . ' ' . $m->{args};
      $s .= "module $prefix/$c\n";
    }
  $s;
}

sub generate_grub2_entry($$%)
{
  my $entryname = shift;
  my $prefix = shift;
  $prefix = '' unless defined $prefix;
  $prefix = "/$prefix" if $prefix ne '' and $prefix !~ /^[\/(]/;
  my %entry = @_;
  # basename of first path
  my $args = $entry{bootstrap}{args};
  my $bn = $entry{bootstrap}{unique_short_filepath};
  my $s = "menuentry \"$entryname\" {\n";

  if (entry_is_linux(%entry))
    {
      $s .= "  echo Loading '$prefix/$bn $args'\n";
      $s .= "  linux $prefix/$bn $args\n";
      if (defined $entry{initrd})
        {
          my $c = $entry{initrd}{unique_short_filepath} . ' ' . $entry{initrd}{args};
          $s .= "  initrd $prefix/$c\n";
        }
    }
  else
    {
      $s .= "  echo Loading '$prefix/$bn $prefix/$bn $args'\n";
      $s .= "  multiboot2 $prefix/$bn $prefix/$bn $args\n";
      foreach my $m (@{$entry{mods}})
        {
          my $moduleline = "$prefix/" . $m->{unique_short_filepath} . " " . $m->{cmdline};
          $s .= "  echo Loading '$moduleline'\n";
          $s .= "  module2 $moduleline\n";
        }
    }
  $s .= "  echo Done, booting...\n";
  $s .= "}\n";
}

# Merge multiple entries such that we only need to copy a file
# once to a boot medium (e.g. ISO file, target, etc.)
# For that, the entries will be augmented with additional entries 'file' and
# 'unique_short_filepath'.
sub merge_entries
{
  my $module_path = shift;
  my $uncompressdir = shift;
  my @entries = @_;

  my %f;
  foreach my $e (@entries)
    {
      foreach my $mod (@{$e->{mods}}, $e->{bootstrap})
        {
          my $file = $mod->{file};
          fetch_remote_file($file);
          my $filepath;
          if (defined $uncompressdir)
            {
              # generate a file-path for the uncompressed file that is as
              # unique as the other file-path (same path -> same content)
              (my $ufn = $file) =~ s,/,_,g;
              $filepath = copy_file_uncompressed_or_die($file, $module_path,
                                                        $uncompressdir, $ufn);
            }
          else
            {
              $filepath = search_file_or_die($file, $module_path);
            }
          my $bn = $mod->{command};
          push @{$f{$bn}}, { fp => $filepath, entry => $e->{entry} };
          $mod->{file} = $filepath;
        }
    }

  my %r;
  foreach my $bn (keys %f)
    {
      my %tmp;
      foreach my $e (@{$f{$bn}})
        {
          push @{$tmp{$e->{fp}}}, $e->{entry};
        }

      if (keys %tmp == 1)
        {
          $r{$_} = $bn foreach keys %tmp;
        }
      else
        {
          my $subdir = 1;
          foreach my $fp (keys %tmp)
            {
              $r{$fp} = "$subdir/$bn";
              $subdir++;
            }
        }
    }

  foreach my $e (@entries)
    {
      foreach my $mod (@{$e->{mods}}, $e->{bootstrap})
        {
          $mod->{unique_short_filepath} = $r{$mod->{file}};
        }
    }
}

return 1;
