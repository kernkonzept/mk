entry[no-defaults] [% entryname %]
kernel [% kernel.name %] [% kernel.args %]
bootstrap [% bootstrap.name %] [% bootstrap.args %]
[% IF cpu_firmware.file -%]
[%# cpu_firmware.bin cannot be the first or second module,
    because when using a grubcfg they are special %]
sigma0 sigma0
roottask moe
module[fname=cpu_firmware.bin] [% cpu_firmware.file %]
[% END -%]
