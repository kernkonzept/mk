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
#include <vector>
#include <algorithm>

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

class Elf_file
{
public:
  Elf_file(const char * const filename);

  ~Elf_file() { close(_fd); }

protected:
  int _fd;
  void *_elf_addr;
  const char * const _filename;
};

Elf_file::Elf_file(const char * const filename)
: _filename(filename)
{
  _fd = open(filename, O_RDONLY);
  if (_fd < 0)
    {
      fprintf(stderr, "%s: Could not open '%s': ", prog, filename);
      perror("");
      throw(errno);
    }

  struct stat statbuf;
  if (fstat(_fd, &statbuf) == -1)
    {
      fprintf(stderr, "%s: Could not get size of '%s': ", prog, filename);
      close(_fd);
      perror("");
      throw(errno);
    }

  _elf_addr = mmap(NULL, statbuf.st_size, PROT_READ, MAP_SHARED, _fd, 0);
  if (_elf_addr == MAP_FAILED)
    {
      fprintf(stderr, "%s: Could not mmap '%s': ", prog, filename);
      close(_fd);
      perror("");
      throw(errno);
    }

  Elf64_Ehdr *elf = (Elf64_Ehdr *)_elf_addr;
  if (memcmp(elf->e_ident, ELFMAG, sizeof(ELFMAG) - 1) != 0)
    {
      fprintf(stderr, "%s: '%s' is not an ELF binary\n", prog, filename);
      throw(-1);
    }
}

class Show_infos_shell : public Elf_file
{
public:
  Show_infos_shell(const char * const filename)
  : Elf_file(filename)
  {}

  int handle(int idx, unsigned long base_addr);

private:
  template<typename ELF_EHDR, typename ELF_PHDR>
  int _handle(int idx, addr_t base_addr)
  {
    ELF_EHDR *elf = (ELF_EHDR *)_elf_addr;
    ELF_PHDR *phdr = (ELF_PHDR *)((char *)_elf_addr + elf->e_phoff);
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

        if (phdr->p_flags & PF_X && phdr->p_align > align)
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

    printf("FILEPATH_%d=\"%s\"\n", idx, _filename);
    printf("BASE_ADDR_%d=0x%llx\n", idx, base_addr);
    printf("LOAD_ADDR_MIN_%d=0x%llx\n", idx, trunc_align(min_addr, align) - base_addr);
    printf("LOAD_ADDR_MAX_%d=0x%llx\n", idx, round_align(max_addr, align) - base_addr);
    printf("LOAD_SIZE_%d=0x%llx\n", idx, round_align(max_addr, align) - trunc_align(min_addr, align));
    printf("ALIGNMENT_%d=0x%llx\n", idx, align);

    return 0;
  }
};

int Show_infos_shell::handle(int idx, unsigned long base_addr)
{
  Elf64_Ehdr *elf = (Elf64_Ehdr *)_elf_addr;
  int r;
  if (elf->e_ident[EI_CLASS] == ELFCLASS32)
    r = _handle<Elf32_Ehdr, Elf32_Phdr>(idx, base_addr);
  else if (elf->e_ident[EI_CLASS] == ELFCLASS64)
    r = _handle<Elf64_Ehdr, Elf64_Phdr>(idx, base_addr);
  else
    {
      fprintf(stderr, "%s: Invalid ELF class\n", prog);
      r = -1;
    }

  return r;
}

class Check_overlap_state
{
public:
  void add(unsigned long long start, unsigned long long end,
           const char *name)
  {
    Region r = { .start = start, .end = end, .name = name };
    _regions.push_back(r);
  }

  void print_state()
  {
    if (_regions.empty())
      return;

    std::sort(_regions.begin(), _regions.end(), region_cmp);

    Region_list::const_iterator i = _regions.begin();
    Region_list::const_iterator n = i + 1;
    for (; n != _regions.end(); ++i, ++n)
      {
        if (n->start < i->end)
          printf("overlap %s %llx-%llx vs. %s %llx-%llx\n",
                 i->name, i->start, i->end, n->name, n->start, n->end);
      }
  }

private:
  struct Region {
    unsigned long long start, end;
    const char *name;
  };
  typedef std::vector<Region> Region_list;
  Region_list _regions;

  static bool region_cmp(Region &a, Region &b)
  {
    return a.start < b.start;
  }
};

class Check_overlap_file : public Elf_file
{
public:
  Check_overlap_file(const char * const filename)
  : Elf_file(filename)
  {}

  int handle(Check_overlap_state *state);

private:
  template<typename ELF_EHDR, typename ELF_PHDR>
  int _handle(Check_overlap_state *state)
  {
    ELF_EHDR *elf = (ELF_EHDR *)_elf_addr;
    ELF_PHDR *phdr = (ELF_PHDR *)((char *)_elf_addr + elf->e_phoff);
    int phnum  = elf->e_phnum;
    int phsz   = elf->e_phentsize;

    for (; phnum > 0; --phnum, phdr = (ELF_PHDR * )((char *)phdr + phsz))
      {
        unsigned long e = phdr->p_paddr + phdr->p_memsz;
        if (0)
          printf("type = %x  p_paddr=%llx end = %lx flags=%x align=%x\n",
                 phdr->p_type, (addr_t)phdr->p_paddr,
                 e, phdr->p_flags, (unsigned)phdr->p_align);

        if (phdr->p_type != PT_LOAD)
          continue;

        if (phdr->p_memsz == 0)
          continue;

        state->add(phdr->p_paddr, phdr->p_paddr + phdr->p_memsz, _filename);
      }


    return 0;
  }

};

int Check_overlap_file::handle(Check_overlap_state *state)
{
  Elf64_Ehdr *elf = (Elf64_Ehdr *)_elf_addr;
  int r;
  if (elf->e_ident[EI_CLASS] == ELFCLASS32)
    r = _handle<Elf32_Ehdr, Elf32_Phdr>(state);
  else if (elf->e_ident[EI_CLASS] == ELFCLASS64)
    r = _handle<Elf64_Ehdr, Elf64_Phdr>(state);
  else
    {
      fprintf(stderr, "%s: Invalid ELF class\n", prog);
      r = -1;
    }

  return r;
}

enum
{
  Opt_show_infos,
  Opt_check_overlap,
  Opt_base_addr,
};

static struct option lopts[] = {
  { "show-infos",    no_argument,       NULL, Opt_show_infos },
  { "check-overlap", no_argument,       NULL, Opt_check_overlap },
  { "base-addr",     required_argument, NULL, Opt_base_addr },
  { 0, 0, 0, 0}
};

int main(int argc, char **argv)
{
  bool show_infos = false;
  bool check_overlap = false;
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
        case Opt_check_overlap:
          check_overlap = true;
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


  Check_overlap_state overlap_state;


  int idx = 1;
  while (optind < argc)
    {
      if (show_infos)
        {
          Show_infos_shell o(argv[optind]);
          o.handle(idx, base_addr);
        }
      if (check_overlap)
        {
          Check_overlap_file o(argv[optind]);
          o.handle(&overlap_state);
        }

      ++optind;
      ++idx;
    }

  if (check_overlap)
    overlap_state.print_state();

  return 0;
}

