incdir      = %:set-var(incdir      %(l4obj)/include/contrib)
pc_file_dir = %:set-var(pc_file_dir %(l4obj)/pc)

# options that take an extra argument
link_arg_opts =
  %:arg-option(L m z o O h e -entry fini init -defsym Map)
  %:arg-option(b -format A -architecture y -trace-symbol MF)
  %:arg-option(-hash-style -version-script)
  %:arg-option(T Tbss Tdata Ttext Ttext-segment Trodata-segment Tldata-segment)
  %:arg-option(dT -image-base)

# options that are part of the output file list %o
link_output_args =
  %:output-option(l* -whole-archive -no-whole-archive
                  -start-group -end-group u)


l4libdir =
l4libdir_x = %:set-var(l4libdir
              %(l4system:%(l4api:%(l4obj)/lib/%(l4system)/%(l4api)))
              %(l4system:%(l4obj)/lib/%(l4system)) %(l4obj)/lib)

# compile a list of dirs from -L options
libdir    = %:set-var(libdir %{L*:%*} %(l4libdir))

# get dependency file name from -MF or from -o options
deps_file = %:strip(%{MF*:%*;:%{o*:.%*.d;:.pcs-deps}})

# generate dependency files for used spec/pc files
generate_deps =
  # main dependency
  %:echo-file(>%(deps_file) %{o*:%*}: %:all-specs())
  # empty deps for all spec/pc files for graceful removal
  %:foreach(%%:echo-file(>>%(deps_file) %%*:) %:all-specs())

# check whether the linker variable is set
check_linker = %(linker:;:%:error(linker variable not defined))


######### ld compatibility (pass through) mode for linking ##################
# options to pass to the linker (binutils GNU ld and LLVM ld)
link_pass_opts = %:set-var(link_pass_opts
  %{M} %{-print-map} %{-trace-symbol*} %{y} %{-verbose}
  %{-cref} %{-trace} %{r} %{O*}
  %{m} %{-error-*} %{-warn-*&-no-warn-*}
  %{-sort-*} %{-unique*}
  %{-define-common&-no-define-common} %{B*}
  %{-check-*&-no-check-*}
  %{-no-undefined} %{rpath*} %{-verbose*}
  %{-discard-*}
  %{x} %{X} %{S} %{s} %{t} %{z} %{Z} %{n} %{N} %{init*} %{fini*}
  %{soname*} %{h} %{E} %{-export-dynamic&-no-export-dynamic}
  %{e} %{-entry*} %{-defsym*} %{Map*} %{b} %{-format*} %{A} %{-architecture*}
  %{-gc-sections} %{gc-sections} %{-no-gc-sections} %{-hash-style*} %{-eh-frame-hdr}
  # we always set -nostlib below so drop it but use it to avoid an error
  %{nostdlib:} %{no-pie:} %{pie} %{-no-dynamic-linker} %{-version-script*})
  %{-wrap*}

# linker arguments part I
link_args_ld_part1 =
  %(link_arg_opts)%(link_output_args)
  %:read-pc-file(%(pc_file_dir) %{PC*:%*})
  %{nocrt|r:;:%:read-pc-file(%(pc_file_dir) ldscripts)}
  %{o} -nostdlib %{static:-static;:--eh-frame-hdr} %{shared}
  %{static-pie:-static -pie --no-dynamic-linker -z text}

# linker arguments part II -- specific to GNU ld
link_args_ld_part2_gnu_ld =
  %(link_pass_opts) %:foreach(%%{: -L%%*} %(l4libdir)) %{T*&L*}
  %{!r:%{!dT:-dT %:search(main_%{static:stat;static-pie:pie;shared:rel;:dyn}.ld
                          %(libdir));dT}}

# linker arguments part II -- specific to LLVM ld
# - use `-T <script>` rather than `-dT <script>`
# - use `--image-base=...` rather than `-Ttext-segment=...`
link_args_ld_part2_llvm_lld =
  %(link_pass_opts) %:foreach(%%{: -L%%*} %(l4libdir)) %{L*}
  %{-image-base*}
  %{!r:%{!T:-T %:search(main_%{static:stat;static-pie:pie;shared:rel;:dyn}.ld
                        %(libdir));T}}

# linker arguments part III
link_args_ld_part3 =
  %{r|shared|static|static-pie|-dynamic-linker*:;:
    --dynamic-linker=%(Link_DynLinker)
    %(Link_DynLinker:;:
      %:error(Link_DynLinker not specified, cannot link with shared libs.))}
  %{-dynamic-linker*}
  %(Link_Start) %o %{OBJ*:%*} %{pie:%(Libs_pic);:%(Libs)}
  %{static|static-pie:--start-group} %{pie:%(Link_Libs_pic);:%(Link_Libs)}
  %{static|static-pie:--end-group} %(Link_End)
  %{EL&EB}
  %{MD:%(generate_deps)} %:error-unused-options()

# executed when called with '-t ld' (L4 linker with ld)
ld = %(check_linker) %:exec(%(linker) %(link_args_ld_part1)
     %(link_args_ld_part2_gnu_ld) %(link_args_ld_part3))

# executed when called with '-t lld' (L4 linker with ld)
lld = %(check_linker) %:exec(%(linker) %(link_args_ld_part1)
      %(link_args_ld_part2_llvm_lld) %(link_args_ld_part3))


######### gcc command line compatibility mode for linker ###################
# maps GCC command line options directly to gnu-ld options
# specify command line compatible to linking with GCC
gcc_arg_opts =
  %:arg-option(aux-info param x idirafter include imacro iprefix
               iwithprefix iwithprefixbefore isystem imultilib
               isysroot Xpreprocessor Xassembler T
               Xlinker u z G o U D I MF)

link_output_args_gcc = %:output-option(l*)

# pass all -Wl, and -Xlinker flags as output to the linker, preserving the order
# with all -l and non-option args
link_pass_opts_gcc   = %:set-var(link_pass_opts_gcc %{Wl,*&Xlinker*})

link_args_gcc =
  %(gcc_arg_opts)%(link_output_args_gcc)
  %{pie:}%{no-pie:}%{nostdlib:}%{static:}%{static-pie:}%{shared:}%{nostdinc:}
  %{std*:} %{m*:}
  %:read-pc-file(%(pc_file_dir) %{PC*:%*})
  %{r}
  %{r|nocrt|nostartfiles|nostdlib:;:%:read-pc-file(%(pc_file_dir) ldscripts)}
  %{o} -nostdlib %{static:-static;:-Wl,--eh-frame-hdr} %{shared}
  %{static-pie:-static -pie --no-dynamic-linker -z text}
  %(link_pass_opts_gcc) %{W*:} %{f*:} %{u*} %{O*} %{g*} %{T*&L*}
  %{!r:%{!dT:-Wl,-dT,%:search(main_%{static:stat;static-pie:pie;shared:rel;:dyn}.ld
                              %(libdir))}}
  %{r|shared|static|static-pie|-dynamic-linker*:;:
    -Wl,--dynamic-linker=%(Link_DynLinker)
    %(Link_DynLinker:;:
      %:error(Link_DynLinker not specified, cannot link with shared libs.))}
  %{r|nostartfiles|nostdlib:;:%(Link_Start)} %o %(Libs)
  %{r|nodefaultlibs|nostdlib:;:%{static|static-pie:-Wl,--start-group}
                               %(Link_Libs)
                               %{static|static-pie:-Wl,--end-group}}
  %{r|nostartfiles|nostdlib:;:%(Link_End)}
  %{EL&EB}
  %{MD:%(generate_deps)} %:error-unused-options()

# executed when called with '-t gcc-ld' (L4 linker with gcc)
gcc-ld = %(check_linker) %:exec(%(linker) %(link_args_gcc))


################## GCC pass through for linking host / l4linux mode ###########
# implementation for modes 'host' and 'l4linux' that use GCC/G++ as linker
# (we use gcc as linker in that case)
link_host_mode_args =
  %(gcc_arg_opts)
  %:read-pc-file(%(pc_file_dir) %{PC*:%*})
  %{o} %{z} %{pie&no-pie} %{v} %{g*} %{-coverage} %{undef}
  %{static} %o
  %{I*&D*&U*} %{L*&l*&Wl,*&Xlinker*} %<Wl,*
  %{!static:-Wl,-Bstatic} -Wl,--start-group %(Libs) %(Link_Libs) -Wl,--end-group
  %{!static:-Wl,-Bdynamic}
  %{EL&EB} %{m*} %{W*} %{f*}
  %{MD:%(generate_deps)} %:error-unused-options()

# executed when called with '-t host-ld', host linker.
host-ld = %(check_linker) %:exec(%(linker) %(link_host_mode_args))

