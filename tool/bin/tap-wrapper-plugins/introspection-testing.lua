#!/usr/bin/env lua
-- SPDX-License-Identifier: GPL-2.0-only or License-Ref-kk-custom
--
-- Copyright (C) 2021 Kernkonzept GmbH.
-- Author(s): Marius Melzer <marius.melzer@kernkonzept.com>

--[[
The plugin handles four cases of labelled input and produces valid TAP output.
  1. Scope declarations:
       @@ IntrospectionTesting[RESETSCOPE]:<identifier>
     This opens a new scope/sandbox in which object dumps are available under
     their given tag for checks and in which execution statements take effect.
  2. Fiasco object/capability dumps:
       @@ IntrospectionTesting @< BLOCK DUMP
       dump format version number: <version>
       user space tag: <tag>
       <uuencoded gzipped object dump>
       @@ IntrospectionTesting BLOCK >@
     Parses the dump into a lua object and makes it available in the current
     scope under `d[<tag>]`.
  3. Lua checks on the dumps:
       @@ IntrospectionTesting[CHECK]:<lua code that returns true/false>
     The CHECK line is translated by the plugin to a TAP ok/not ok line.
  4. Lua code to evaluate without a check (e.g. to set variables for checks):
       @@ IntrospectionTesting[EXEC]:<lua code>
     The EXEC line is emitted as comments to the TAP output for documentation.
  5. Debug output:
       @@ IntrospectionTesting[DEBUGPRINT]:<lua code>
     The result is emitted as comments to the TAP output.
--]]

inspect = require('inspect') -- luarocks install inspect
lfs     = require('lfs')     -- luarocks install luafilesystem
zlib    = require('zlib')    -- luarocks install lua-zlib

---------------------
-- DATA STRUCTURES --
---------------------

-- helper function called by Dump:filter() and Caps:filter()
function filter(dict, func, res)
  for key, object in pairs(dict) do
    if func(object) then
      res[key] = object
    end
  end
  return res
end

-- helper function called by Dump:union() and Caps:union()
function union(dict1, dict2, res)
  for key, object in pairs(a) do
    res[key] = object
  end

  for key, object in pairs(b) do
    res[key] = object
  end

  return res
end

Dump = {}

function Dump.new()
  local o = {}
  setmetatable(o, {__index = Dump});
  return o;
end

function Dump:filter(func)
  return filter(self, func, Dump.new())
end

function Dump:union(dump)
  return union(self, dump, Dump.new())
end

function Dump:intersect(dump)
  return self:filter(function(obj) return dump[obj.obj_id] end)
end

function Dump:diff(dump)
  local diff_l = self:filter(function(obj) return not dump[obj.obj_id] end)
  local diff_r = dump:filter(function(obj) return not self[obj.obj_id] end)
  return diff_l:union(diff_r)
end

function Dump:by(key, value)
  return self:filter(function(obj) return obj[key] == value end)
end

function Dump:by_attr(key, value)
  return self:filter(function(obj) return obj.attrs[key] == value end)
end

function Dump:test_task()
  return unpack(self:by("proto", "Task")
                :filter(function(obj) return obj.name:find('^test_') end))
end

function Dump:test_thread()
  return unpack(self:by("proto", "Thread"):by("name", "gtest_main"))
end

function Dump:caps_to(space_id)
  if not self[space_id] then
    error(space_id .. ' is not an existing space', 2)
  end

  local caps = {}
  for _, object in pairs(self) do
    for _, cap in pairs(object.caps) do
      if cap.space_id == space_id then
        caps[cap.cap_id] = cap
      end
    end
  end
  return caps
end

function Dump:caps_to_name(space_name)
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
        caps[cap.cap_id] = cap
      end
    end
  end
  return caps
end

function Dump:cap(cap_id, task)
  if type(cap_id) ~= "string" then
    error('cap_id provided to cap(<cap_id>) must be a string', 2)
  end

  task = task or self:test_task()
  return self:caps_to(task.obj_id)[cap_id]
end

Caps = {}

function Caps.new()
  local o = {}
  setmetatable(o, {__index = Caps});
  return o;
end

function Caps:filter(func)
  return filter(self, func, Caps.new())
end

function Caps:union(caps)
  return union(self, caps, Caps.new())
end

function Caps:intersect(caps)
  return self:filter(function(cap) return caps[cap.cap_id] end)
end

function Caps:diff(caps)
  local diff_l = self:filter(function(cap) return not dump[cap.cap_id] end)
  local diff_r = caps:filter(function(cap) return not self[cap.cap_id] end)
  return diff_l:union(diff_r)
end

function Caps:by(key, value)
  return self:filter(function(cap) return cap[key] == value end)
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

function table_merge(a, b)
  if type(a) == 'table' and type(b) == 'table' then
    for k,v in pairs(b) do
      if type(v)=='table' and type(a[k] or false)=='table' then
        table_merge(a[k],v)
      else
        a[k]=v
      end
    end
  end
  return a
end

function eq(a, b, quiet)
  function comment_not_equal()
    if not quiet then
      return "first: " .. inspect(a) .. "\n" .. "second: " .. inspect(b)
    end
    return nil
  end

  if a == b then return true end
  if type(a) ~= 'table' or type(b) ~= 'table' or
     table_len(a) ~= table_len(b) then
    return false, comment_not_equal()
  end

  for k, v in pairs(a) do
    if not eq(v, b[k], true) then
      return false, comment_not_equal()
    end
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

function parse_rights(rights)
  local r = tonumber(rights, 16)
  local parsed = {}
  if r & 0x4 ~= 0 then parsed["R"] = true end
  if r & 0x1 ~= 0 then parsed["W"] = true end
  if r & 0x2 ~= 0 then parsed["S"] = true end
  if r & 0x8 ~= 0 then parsed["D"] = true end
  return parsed
end

function parse_flags(flags)
  local f = tonumber(flags, 16)
  local parsed = {}
  if f & 0x08 ~= 0 then parsed["delete"] = true end
  if f & 0x10 ~= 0 then parsed["weakref"] = true end
  if f & 0x20 ~= 0 then parsed["server"] = true end
  return parsed
end

function parse_dump(dump)
  local objects = Dump.new()
  local lines = split(dump, '[^\n]+')
  local cur_obj_id

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

      objects[cur_obj_id].caps[cap_id] = {
        cap_addr = cap_addr,
        cap_id = cap_id,
        space_id = space_id,
        space_name = space_name,
        rights = parse_rights(rights),
        flags = parse_flags(flags),
        obj_addr = obj_addr
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

      cur_obj_id = obj_id
      objects[obj_id] = {
        obj_addr = obj_addr,
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

function Sandbox:safe_load(snip, env_ext)
  local fun, res = load(snip, snip, 't', table_merge(self.env, env_ext or {}))
  if not fun then
    return fun, res
  end
  return pcall(fun)
end

function Sandbox:exec(snip)
  local status, res = self:safe_load(snip)
  local s = 'IntrospectionTesting[EXEC] in ' .. self.scope
  snip = snip:gsub('\n', '\n#  ')
  if not status then
    tap_comment(s .. ' failed')
    tap_comment(snip, '   ')
    tap_comment('error: ' .. inspect(res))
    return
  end
  tap_comment(s)
  tap_comment(snip, '   ')
  return
end

function Sandbox:check(snip)
  if not snip:find("^return ") then
    snip = "return " .. snip
  end
  local status, res, errstr = self:safe_load(snip)
  local s = 'IntrospectionTesting[CHECK] in ' .. self.scope
  if not status or type(res) ~= 'boolean' then
    tap_not_ok(s)
    tap_comment(snip, '   ')
    tap_comment('result/error: ' .. inspect(res), '   ')
    return
  elseif res then
    tap_ok(s)
    tap_comment(snip, '   ')
    return true
  else
    tap_not_ok(s)
    tap_comment(snip, '   ')
    if errstr then tap_comment(errstr, '   ') end
    return
  end
end

function Sandbox:debug_print(snip)
  snip_ext = "return inspect(" .. snip .. ")"
  local status, res = self:safe_load(snip_ext, {inspect = inspect})
  tap_comment('IntrospectionTesting[DEBUGPRINT] in ' .. self.scope)
  if not status then
    tap_comment('error: ' .. inspect(res), '   ')
    return
  end
  tap_comment(snip .. ': ' .. res, '   ')
  return
end

sandbox = Sandbox.new('')
function process_input(id, input)
  local function fail_input()
    tap_not_ok('valid input')
    s = 'id: ' .. id .. ', tag: ' .. input.tag
    if input.info then
      s = s .. ', info: ' .. input.info
    end
    tap_comment(s)
  end

  if input.tag ~= 'IntrospectionTesting' then
    fail_input()
    return
  end
  if input.info == 'RESETSCOPE' then
    sandbox = Sandbox.new(input.text)
  elseif input.info == 'EXEC' then
    sandbox:exec(input.text)
  elseif input.info == 'CHECK' then
    sandbox:check(input.text)
  elseif input.info == 'DEBUGPRINT' then
    sandbox:debug_print(input.text)
  elseif input.info == "DUMP" then
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
    local i, tag, info = file:match('^(%d+)_(%w+)_(%w+).snippet$')

    if not i or not tag or not info then
      abort('input filename "' .. tostring(file) ..
            '" does not adhere to the plugin interface')
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