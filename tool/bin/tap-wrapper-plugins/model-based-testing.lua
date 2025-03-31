#!/usr/bin/env lua
-- SPDX-License-Identifier: GPL-2.0-only or License-Ref-kk-custom
--
-- Copyright (C) 2024 Kernkonzept GmbH.
-- Author(s): Sven Linker <sven.linker@kernkonzept.com>

-- This file contains LuaCATS (Lua Comment And Type System) annotations. They
-- are supported by the Lua Language Server (https://luals.github.io/). Usage is
-- highly recommended during development.

--[[
  The plugin handles two cases of labelled input in the following
  formats:
  1. Fiasco object printouts:
       @@ KernelObjects @< BLOCK
       dump format version number: <version>
       user space tag: <tag>
       <uuencoded gzipped object output>
       @@ KernelObjects BLOCK >@

     Unzips and decodes the labelled input and writes it into a file with the
     additional suffix `.decoded`.
  2. Names for corresponding abstract tests:
       @@ ModelBasedTest[Init]:<filename>

     Searches for this filename in the `SEARCHPATH` and passes the full path of
     the abstract test to the L4Re model.

  This plugin does not create any TAP output on its own, but calls the L4Re
  model with the path to the labelled input and the name of the abstract test
  file to be checked.

  **Attention** This plugin should not be used at the same time as other plugins
  that make use of the Fiasco object printouts, or the External Tapper plugin
  in general. It expects that all snippets contained in the temporary test
  directory should be used for model based testing.
--]]

-- adapt the package search path to access the local modules. L4DIR is set
-- by the TapperWrapper framework
local plugin_path = os.getenv("L4DIR") .. "/tool/bin/tap-wrapper-plugins/?.lua"
package.path = package.path .. ";" .. plugin_path

helper            = require('helper')
tap               = require('tap')

local plugin      = "ModelBasedTesting"

if #arg ~= 1 then
  tap:abort(plugin, 'number of command-line arguments')
end

local dir = arg[1]
if not lfs.attributes(dir) then
  tap:abort(plugin, 'no valid path as first argument')
end

local abstract = nil

-- decode all KernelObject files and get the filename of the abstract test
local ids, snippets = helper.load_snippets(plugin, dir)
for _, id in pairs(ids) do
  local input = snippets[id]
  if input.tag == 'KernelObjects' then
    local path = dir .. '/' .. input.filename .. '.decoded'
    local objects = helper.decode_kernel_objects(plugin, input.text)
    -- the current parser implementation for kernel objects requires a newline
    -- at the end of the last input
    objects = objects .. '\n'
    local f = io.open(path, 'w')
    if not f then tap:abort(plugin, 'opening ' .. path) end
    ---@cast f -nil
    f:write(objects)
    if not f then tap:abort(plugin, 'writing file ' .. path) end
    f:close()
  elseif input.tag == 'ModelBasedTest' and input.info == 'AbstractTestName' then
    abstract = input.text
  end
end

if not abstract then
  tap:abort(plugin, 'no name of abstract test file provided')
end
---@cast abstract -nil

-- SEARCHPATH is set by the TapperWrapper framework
local searchpath = os.getenv("SEARCHPATH")
if not searchpath then tap:abort(plugin, 'SEARCHPATH is not set') end
---@cast searchpath -nil

-- search for the abstract test file in the directories in SEARCHPATH
local testfile = nil
for path in string.gmatch(searchpath, '[^:]+') do
  local f =  path .. '/' .. abstract
  local _, err = lfs.attributes(f)
  if not err then
    if testfile then tap:abort(plugin, "test file " .. abstract
                               .. " is not unique in search path") end
    testfile = f
  end
end
if not testfile then tap:abort(plugin, "test file " .. abstract
                               .. " not found in search path") end
--@cast testfile -nil

-- TODO: document that user or framework is required to set this env variable
local model = os.getenv("L4RE_MODEL")
if not model then
  tap:abort(plugin, 'model executable not provided in L4RE_MODEL')
end
--@cast model -nil

os.execute(model .. ' compare ' .. testfile .. ' ' .. dir)
