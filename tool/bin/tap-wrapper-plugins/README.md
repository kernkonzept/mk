# Lua requirements for running the Lua Tapper Wrapper Plugin

The script introspection-testing.lua requires a version of Lua >= 5.3 for
running.

In case of having multiple lua interpreters installed on the machine and using
luarocks for installing lua packages (e.g. inspect, luafilesystem, lua-zlib),
you may need to run the following command to correctly set the path for
installing packages for the lua interpreter.

`$ luarocks config lua_version <Version>`

On some Linux distributions, like Debian, it is possible to have multiple
versions of the lua interpreter installed. In such a case, you need to ensure
that luarocks installs the packages for the same version of the interpreter that
is set up for the user. On Debian the following command can be used to choose
among different versions of the lua interpreter installed on the system:

`$ sudo update-alternatives --config lua-interpreter`

Ensure that the version provided to `luarocks config lua_version` matches that
currently chosen in `update-alternatives` before installing the lua packages
using `sudo luarocks install <package-name>`.