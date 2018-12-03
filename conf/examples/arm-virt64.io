-- vi:ft=lua

Io.Dt.add_children(Io.system_bus(), function()
  pciec0 = Io.Hw.Ecam_pcie_bridge(function()
      Property.regs_base    =   0x10000000
      Property.regs_size    =   0x2eff0000
      Property.cfg_base     = 0x4010000000
      Property.cfg_size     = 0x0010000000 -- 256 buses x 256 devs x 4KB
      Property.ioport_base  =   0x3eff0000
      Property.ioport_size  =      0x10000 -- 64KB (for port I/O access)
      Property.mmio_base    =   0x10000000
      Property.mmio_size    =   0x2eff0000 -- ~750MB (for memory I/O access)
      Property.mmio_base_64 = 0x8000000000
      Property.mmio_size_64 = 0x8000000000 -- 512GB (for memory I/O access)
      Property.int_a        = 32 + 3
      Property.int_b        = 32 + 4
      Property.int_c        = 32 + 5
      Property.int_d        = 32 + 6
      Property.flags        = Io.Hw_device_DF_dma_supported
  end);
end);

local hw = Io.system_bus()
Io.add_vbusses
{
  vbus = Io.Vi.System_bus(function ()
    Property.num_msis = 26
    PCI = Io.Vi.PCI_bus(function ()
      pci_bus = wrap(hw:match("PCI/network", "PCI/storage", "PCI/media"));
    end)
  end);
}
