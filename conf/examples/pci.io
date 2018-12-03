-- vi:ft=lua

local hw = Io.system_bus()

Io.add_vbusses
{
  vbus = Io.Vi.System_bus(function ()
    Property.num_msis = 26
    PCI = Io.Vi.PCI_bus(function ()
      pci_bus = wrap(hw:match("PCI/network", "PCI/storage", "PCI/media"));
    end)
  end)
}
