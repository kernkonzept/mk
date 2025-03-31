#!/usr/bin/env lua
-- SPDX-License-Identifier: GPL-2.0-only or License-Ref-kk-custom
--
-- Copyright (C) 2023 Kernkonzept GmbH.
-- Author(s): Marius Melzer <marius.melzer@kernkonzept.com>

lfs     = require('lfs')     -- luarocks install luafilesystem
zlib    = require('zlib')    -- luarocks install lua-zlib
tap     = require('tap')

local function sanitize(str)
  return str:gsub('%s+$', '')
            :gsub('\r\n', '\n')
end

---@param plugin string
---@param dir string
---@return ids table
---@return input table
local function load_snippets(plugin, dir)
  local input = {}
  local ids = {}
  for file in lfs.dir(dir) do
    if file ~= '.' and file ~= '..' then
      local i, tag, info = file:match('^(%d+)_(%w+)_(%w+).snippet$')
      if not i then
        i, tag = file:match('^(%d+)_(%w+).snippet$')
        info = nil
      end
      if not i then
        tap:abort(plugin, 'input filename "' .. tostring(file) ..
              '" does not adhere to the plugin interface')
      end

      local f = io.open(dir .. '/' .. file, 'r')
      if not f then
          tap:abort(plugin, 'failed to open file ' .. dir .. '/' .. file)
      end
      local text = sanitize(f:read('a'))
      f:close()

      if input[i] ~= nil then
        tap:abort(plugin, 'duplicate file id '.. i)
      end

      input[i] = {filename = file, tag = tag, info = info, text = text}
      ids[#ids+1] = i
    end
  end

  table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
  return ids, input
end

---@param str string
---@return string?
local function gunzip(str)
  local inflated, eof = zlib.inflate()(str)
  if not eof then
    return nil
  end
  return inflated
end


---@param str string
---@return string
local function uudecode(str)
  -- We assume '`' is always used to encode a 0.
  local decoded = ''

  for line in str:gmatch('[^\n]+') do
    if not (line:find('^begin ') or line == '`' or line == 'end') then
      local len = line:byte(1) - 32
      local decoded_line = ''
      line = line:sub(2)
      repeat
        local enc1 = (line:byte(1) - 32) & 63
        local enc2 = (line:byte(2) - 32) & 63
        local enc3 = (line:byte(3) - 32) & 63
        local enc4 = (line:byte(4) - 32) & 63

        local dec1 = (enc1 << 2) + (enc2 >> 4)
        local dec2 = ((enc2 & 15) << 4) + (enc3 >> 2)
        local dec3 = ((enc3 & 3) << 6) + enc4

        decoded_line = decoded_line .. string.char(dec1, dec2, dec3)

        line = line:sub(5)
      until(line == '')
      decoded = decoded .. string.sub(decoded_line, 1, len)
    end
  end

  return decoded
end

---@param plugin string
---@param objects string
---@return string
local function decode_kernel_objects(plugin, objects)
  local two_lines = '^[^\n]+\n[^\n]+\n'

  -- Heuristically check if object list is compressed and encoded (see kernel
  -- config option CONFIG_JDB_GZIP). If so, then decode and decompress.
  if objects:find(two_lines .. 'begin ') then
    local headers = objects:match(two_lines)
    if not headers then tap:abort(plugin, 'extract object dump headers') end

    local body = gunzip(uudecode(objects:gsub(two_lines, '')))
    if not body then tap:abort(plugin, 'decode object dump body') end
    objects = headers .. body
  end

  return sanitize(objects):gsub('\27%[[^m]*m', '')  -- remove color escape codes
end


helper = {
  sanitize      = sanitize,
  load_snippets = load_snippets,
  uudecode      = uudecode,
  gunzip        = gunzip,
  decode_kernel_objects = decode_kernel_objects
}

return helper
