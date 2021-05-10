#include <sys/mman.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <elf.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <getopt.h>

typedef unsigned long long addr_t;
const char *prog;

template<typename T>
constexpr T round_align(T val, T alignment)
{
  return (val + alignment - T(1)) & ~(alignment - T(1));
}

template<typename T>
constexpr T trunc_align(T val, T alignment)
{
  return val & ~(alignment - T(1));
}

template<typename ELF_EHDR, typename ELF_PHDR>
int handle(void *elf_addr, const char * const filename, int idx,
           addr_t base_addr)
{
  ELF_EHDR *elf = (ELF_EHDR *)elf_addr;
  ELF_PHDR *phdr = (ELF_PHDR *)((char *)elf_addr + elf->e_phoff);
  int phnum  = elf->e_phnum;
  int phsz   = elf->e_phentsize;

  addr_t max_addr = 0;
  addr_t min_addr = ~0ull;
  addr_t align = 0;
  for (; phnum > 0; --phnum, phdr = (ELF_PHDR * )((char *)phdr + phsz))
    {
      unsigned long e = phdr->p_paddr + phdr->p_memsz;
      if (0)
        printf("type = %x  p_paddr=%llx end = %lx flags=%x align=%x\n",
               phdr->p_type, (addr_t)phdr->p_paddr,
               e, phdr->p_flags, (unsigned)phdr->p_align);

      if (phdr->p_memsz == 0)
        continue;

      if (!(phdr->p_flags & (PF_R | PF_W | PF_X)))
        continue;

      if (phdr->p_flags & PF_X)
        align = phdr->p_align;

      if (min_addr > phdr->p_paddr)
        min_addr = phdr->p_paddr;

      if (max_addr < e)
        max_addr = e;
    }

  if (max_addr == 0 || min_addr == ~0ull || align == 0)
    {
      fprintf(stderr, "%s: No valid PHDR found\n", prog);
      return 1;
    }

  printf("FILEPATH_%d=\"%s\"\n", idx, filename);
  printf("BASE_ADDR_%d=0x%llx\n", idx, base_addr);
  printf("LOAD_ADDR_MIN_%d=0x%llx\n", idx, trunc_align(min_addr, align) - base_addr);
  printf("LOAD_ADDR_MAX_%d=0x%llx\n", idx, round_align(max_addr, align) - base_addr);
  printf("LOAD_SIZE_%d=0x%llx\n", idx, round_align(max_addr, align) - trunc_align(min_addr, align));
  printf("ALIGNMENT_%d=0x%llx\n", idx, align);

  return 0;
}

static int do_file(const char * const filename, int idx, addr_t base_addr)
{
  int fd;

  fd = open(filename, O_RDONLY);
  if (fd < 0)
    {
      fprintf(stderr, "%s: Could not open '%s': ", prog, filename);
      perror("");
      return -1;
    }

  struct stat statbuf;
  if (fstat(fd, &statbuf) == -1)
    {
      fprintf(stderr, "%s: Could not get size of '%s': ", prog, filename);
      close(fd);
      perror("");
      return -1;
    }

  void *elf_addr = mmap(NULL, statbuf.st_size, PROT_READ,
                        MAP_SHARED, fd, 0);

  if (elf_addr == MAP_FAILED)
    {
      fprintf(stderr, "%s: Could not mmap '%s': ", prog, filename);
      close(fd);
      perror("");
      return -1;
    }

  Elf64_Ehdr *elf = (Elf64_Ehdr *)elf_addr;
  if (memcmp(elf->e_ident, ELFMAG, sizeof(ELFMAG) - 1) != 0)
    {
      fprintf(stderr, "%s: '%s' is not an ELF binary\n", prog, filename);
      return -1;
    }

  int r;
  if (elf->e_ident[EI_CLASS] == ELFCLASS32)
    r = handle<Elf32_Ehdr, Elf32_Phdr>(elf_addr, filename, idx, base_addr);
  else if (elf->e_ident[EI_CLASS] == ELFCLASS64)
    r = handle<Elf64_Ehdr, Elf64_Phdr>(elf_addr, filename, idx, base_addr);
  else
    {
      fprintf(stderr, "%s: Invalid ELF class\n", prog);
      r = -1;
    }

  close(fd);
  return r;
}

enum
{
  Opt_show_infos,
  Opt_base_addr,
};

static struct option lopts[] = {
  { "show-infos", no_argument,       NULL, Opt_show_infos },
  { "base-addr",  required_argument, NULL, Opt_base_addr },
  { 0, 0, 0, 0}
};

int main(int argc, char **argv)
{
  bool show_infos = false;
  addr_t base_addr = 0;

  prog = argv[0];

  int opt;
  while ((opt = getopt_long(argc, argv, "", lopts, NULL)) != -1)
    {
      switch (opt)
        {
        case Opt_show_infos:
          show_infos = true;
          break;
        case Opt_base_addr:
            {
              char *endptr;
              base_addr = strtoull(optarg, &endptr, 0);
              if (*endptr != '\0')
                {
                  fprintf(stderr, "%s: Invalid number given\n", prog);
                  exit(1);
                }
            }
          break;
        default:
          fprintf(stderr, "%s: Invalid option(s) given.\n", prog);
          exit(1);
        }
    }

  if (optind == argc)
    {
      fprintf(stderr, "%s: No ELF binary given.\n", prog);
      exit(1);
    }


  int idx = 1;
  while (optind < argc)
    {
      if (show_infos)
        {
          if (do_file(argv[optind], idx, base_addr))
            return 1;
        }

      ++optind;
      ++idx;
    }

  return 0;
}

