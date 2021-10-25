#!/usr/bin/env lua
-- SPDX-License-Identifier: GPL-2.0-only or License-Ref-kk-custom
--
-- Copyright (C) 2021 Kernkonzept GmbH.
-- Author(s): Marius Melzer <marius.melzer@kernkonzept.com>

--[[
The plugin handles four cases of labelled input and produces valid TAP output.
  1. Scope declarations:
       @@ ObjectSpaceDump[SCOPE]:<identifier>
     This opens a new scope/sandbox in which object dumps are available under
     their given tag for checks and in which execution statements take effect.
  2. Fiasco object/capability dumps:
       @@ ObjectSpaceDump @< BLOCK
       dump format version number: <version>
       user space tag: <tag>
       <uuencoded gzipped object dump>
       @@ ObjectSpaceDump BLOCK >@
     Parses the dump into a lua object and makes it available in the current
     scope under `d[<tag>]`.
  3. Lua checks on the dumps:
       @@ ObjectSpaceDump[CHECK]:<lua code that returns true/false>
     The CHECK line is translated by the plugin to a TAP ok/not ok line.
  4. Lua code to evaluate without a check (e.g. to set variables for checks):
       @@ ObjectSpaceDump[EXEC]:<lua code>
     The EXEC line is emitted as comments to the TAP output for documentation.
--]]

inspect = require('inspect') -- luarocks install inspect
lfs     = require('lfs')     -- luarocks install luafilesystem
zlib    = require('zlib')    -- luarocks install lua-zlib

---------------------
-- DATA STRUCTURES --
---------------------

Dump = {}

function Dump.new()
  local o = {}
  setmetatable(o, {__index = Dump});
  return o;
end

function Dump:caps_of(space_name)
  local spaces = self:filter(function(object)
    return object['name'] == space_name and
           (object['proto'] == 'Task' or object['proto'] == 'Vm')
  end)
  if next(spaces) == nil then
    error('name "' .. space_name .. '" does not name an existing space', 2)
  elseif table_len(spaces) > 1 then
    error('name "' .. space_name .. '" does not name a unique space:\n' ..
          inspect(spaces), 2)
  end
  local caps = {}
  for _, object in pairs(self) do
    for _, cap in pairs(object.caps) do
      if cap.space_name == space_name then
        caps[cap.cap_addr] = cap
      end
    end
  end
  return caps
end

function Dump:filter(func)
  local filtered = Dump.new()
  for key, object in pairs(self) do
    if func(object) then
      filtered[key] = object
    end
  end
  return filtered
end

function Dump:by(name, value)
  return self:filter(function(object) return object[name] == value end)
end

function Dump:by_attr(name, value)
  return self:filter(function(object) return object.attrs[name] == value end)
end

----------------------
-- HELPER FUNCTIONS --
----------------------

function abort(str)
  print('not ok ' .. str)
  print('1..1')
  os.exit(0)
end

function sanitize(str)
  return str:gsub('%s+$', '')
            :gsub('\r\n', '\n')
end

function split(str, regex)
  local parts = {}
  for part in str:gmatch(regex) do
    table.insert(parts, part)
  end
  return parts
end

function table_len(tab)
  local cnt = 0
  for _ in pairs(tab) do cnt = cnt + 1 end
  return cnt
end

function eq(a, b)
  if a == b                       then return true  end
  if type(a) ~= 'table'           then return false end
  if type(b) ~= 'table'           then return false end
  if table_len(a) ~= table_len(b) then return false end

  for k, v in pairs(a) do
    if not eq(v, b[k]) then return false end
  end
  return true
end

function unpack(o)
  if type(o) ~= 'table' then
    error('called unpack() not on a table', 2)
  end
  local k, v = next(o)
  if k == nil then
    error('called unpack() on empty table', 2)
  end
  if next(o, k) ~= nil then
    error('called unpack() on table with more than one item', 2)
  end
  return v
end

function gunzip(str)
  local inflated, eof = zlib.inflate()(str)
  if not eof then
    return nil
  end
  return inflated
end

function uudecode(str)
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

----------------
-- TAP OUTPUT --
----------------

num_checks = 0

function tap_ok(str)
  print('ok ' .. str)
  num_checks = num_checks + 1
end

function tap_not_ok(str)
  print('not ok ' .. str)
  num_checks = num_checks + 1
end

function tap_comment(comment, indent)
  indent = indent or ' '
  print('#' .. indent .. comment:gsub('\n', '\n#' .. indent))
end

-----------------
-- PARSE INPUT --
-----------------

function parse_dump(dump)
  local objects = Dump.new()
  local lines = split(dump, '[^\n]+')
  local cur_obj_addr

  local function parse(line, pat)
    local res = {}
    if line ~= nil then
      res = {line:match(pat)}
    end
    if res[1] == nil then
      abort('object dump line: "' .. inspect(line) ..
            '" does not match pattern "' .. pat .. '"')
    end
    return table.unpack(res)
  end

  local version =
    parse(table.remove(lines, 1), '^dump format version number: (%d+)$')
  local tag = parse(table.remove(lines, 1), '^user space tag: (%w+)$')

  for _, line in ipairs(lines) do
    if line:sub(1, 1) == '\t' then -- this is a capability line
      local attrs_regex =
        'space=D:(%x+)%(([^)]+)%) rights=(%x+) flags=(%x+) obj=0x(%x+)'
      local cap_addr, cap_id, space_id, space_name, rights, flags, obj_addr =
        parse(line, '^\t(%x+)%[C:(%x+)%]: ' .. attrs_regex .. '$')

      objects[cur_obj_addr].caps[cap_addr] = {
        cap_addr = cap_addr,
        cap_id = cap_id,
        space_id = space_id,
        space_name = space_name,
        rights = rights,
        flags = flags,
        obj_addr = obj_addr,
      }
    else -- this is an object line
      local obj_id, obj_addr, proto, attrstrs =
        parse(line, '^(%x+) (%x+) %[([^]]+)%] (.*)$')
      local i, j, name = attrstrs:find('{(.*)}')
      if i then
        attrstrs = attrstrs:sub(j+1)
      end

      local attrs = {}
      for attr in attrstrs:gmatch('[^%s]+') do
        attr = split(attr, '[^=]+')
        if #attr > 2 then abort("Failed parsing attribute") end
        attrs[attr[1]] = attr[2] or true
      end

      cur_obj_addr = obj_addr
      objects[obj_addr] = {
        addr = obj_addr,
        obj_id = obj_id,
        proto = proto,
        name = name,
        attrs = attrs,
        caps = {}
      }
    end
  end

  return version, tag, objects
end

-----------------
-- SANDBOXING --
-----------------

Sandbox = {}

function Sandbox.new(scope)
  local env =
    {d = {}, eq = eq, unpack = unpack}
  local sandbox = {env = env, scope = scope}
  setmetatable(sandbox, {__index = Sandbox})
  return sandbox
end

function Sandbox:safe_load(snip)
  local fun, res = load(snip, snip, 't', self.env)
  if not fun then
    return fun, res
  end
  return pcall(fun)
end

function Sandbox:exec(snip)
  local status, res = self:safe_load(snip)
  local s = 'ObjectSpaceDump[EXEC] in ' .. self.scope
  snip = snip:gsub('\n', '\n#  ')
  if not status then
    tap_comment(s .. ' failed')
    tap_comment(snip, '   ')
    tap_comment('error: ' .. inspect(res))
    return false
  end
  tap_comment(s)
  tap_comment(snip, '   ')
  return true
end

function Sandbox:check(snip)
  local status, res = self:safe_load(snip)
  local s = 'ObjectSpaceDump[CHECK] in ' .. self.scope
  if not status or type(res) ~= 'boolean' then
    tap_not_ok(s)
    tap_comment(snip, '   ')
    tap_comment('result/error: ' .. inspect(res))
    return false
  elseif res then
    tap_ok(s)
    tap_comment(snip, '   ')
    return true
  else
    tap_not_ok(s)
    tap_comment(snip, '   ')
    return false
  end
end

sandbox = Sandbox.new('')
function process_input(id, input)
  local function fail_status()
    tap_comment('emitting current dumps for debugging:')
    tap_comment(inspect(sandbox.env.d))
  end
  local function fail_input()
    tap_not_ok('valid input')
    s = 'id: ' .. id .. ', tag: ' .. input.tag
    if input.info then
      s = s .. ', info: ' .. input.info
    end
    tap_comment(s)
  end

  if input.tag ~= 'ObjectSpaceDump' then
    fail_input()
    return
  end
  if input.info == 'SCOPE' then
    sandbox = Sandbox.new(input.text)
  elseif input.info == 'EXEC' then
    if not sandbox:exec(input.text) then
      fail_status()
    end
  elseif input.info == 'CHECK' then
    if not sandbox:check(input.text) then
      fail_status()
    end
  elseif input.info == nil then
    local two_lines = '^[^\n]+\n[^\n]+\n'
    local headers = input.text:match(two_lines)
    if not headers then abort('extract object dump headers') end

    local body = gunzip(uudecode(input.text:gsub(two_lines, '')))
    if not body then abort('decode object dump body') end
    body = sanitize(body):gsub('\27%[[^m]*m', '') -- escape color codes

    local version, tag, dump = parse_dump(headers .. body)
    if version then
      sandbox.env.d[tag] = dump
    end
  else
    fail_input()
  end
end

----------
-- MAIN --
----------

if #arg ~= 1 then
  abort('number of command-line arguments')
end

local dir = arg[1]
if not lfs.attributes(dir) then abort('valid path as first argument') end

local input = {}
local ids = {}
for file in lfs.dir(dir) do
  if file ~= '.' and file ~= '..' then
    local patterns = { '^(%d+)_(%w+).snippet$'
                     , '^(%d+)_(%w+)_(%w+).snippet$' }
    local i, tag, info
    for _, pattern in pairs(patterns) do
      i, tag, info = file:match(pattern)
      if i then break end
    end

    if not i then
      abort('input filename "' .. file ..
        '" does not adhere the plugin interface')
    end

    local f = io.open(dir .. '/' .. file, 'r')
    if not f then abort('failed to open file ' .. dir .. '/' .. file) end
    local text = sanitize(f:read('a'))
    f:close()

    if input[i] ~= nil then
      abort('duplicate file id '.. i)
    end

    input[i] = {tag = tag, info = info, text = text}
    ids[#ids+1] = i
  end
end

table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
for _, id in ipairs(ids) do
  process_input(id, input[id])
end
print('1..' .. num_checks)
