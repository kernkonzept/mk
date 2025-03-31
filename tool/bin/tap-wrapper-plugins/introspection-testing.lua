#!/usr/bin/env lua
-- SPDX-License-Identifier: GPL-2.0-only or License-Ref-kk-custom
--
-- Copyright (C) 2021 Kernkonzept GmbH.
-- Author(s): Marius Melzer <marius.melzer@kernkonzept.com>

-- This file contains LuaCATS (Lua Comment And Type System) annotations. They
-- are supported by the Lua Language Server (https://luals.github.io/). Usage is
-- highly recommended during development.

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

-- adapt the package search path to access the local modules
local plugin_path = os.getenv("L4DIR") .. "/tool/bin/tap-wrapper-plugins/?.lua"
package.path = package.path .. ";" .. plugin_path

inspect = require('inspect') -- luarocks install inspect
helper  = require('helper')
tap     = require('tap')

local plugin      = "Introspection"

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
  for key, object in pairs(dict1) do
    res[key] = object
  end

  for key, object in pairs(dict2) do
    res[key] = object
  end

  return res
end

---@class Dump
Dump = {}

---@return Dump
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

function Dump:caps_of(space_id)
  if not self[space_id] then
    error(space_id .. ' is not an existing space', 2)
  end

  local caps = Caps.new()
  for _, object in pairs(self) do
    for _, cap in pairs(object.caps) do
      if cap.space_id == space_id then
        if caps[cap.cap_idx] ~= nil then
          error('caps_of(): capability index '
                .. inspect(cap.cap_idx)
                .. ' is not unique in space '
                .. inspect(space_id)
                .. '.')
        end
        caps[cap.cap_idx] = cap
      end
    end
  end
  return caps
end

function Dump:caps_of_name(space_name)
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
  local caps = Caps.new()
  for _, object in pairs(self) do
    for _, cap in pairs(object.caps) do
      if cap.space_name == space_name then
        if caps[cap.cap_idx] ~= nil then
          error('caps_of(): capability index '
                .. inspect(cap.cap_idx)
                .. ' is not unique in space '
                .. inspect(space_name)
                .. '.')
        end
        caps[cap.cap_idx] = cap
      end
    end
  end
  return caps
end

function Dump:cap(cap_idx, task)
  if type(cap_idx) ~= "string" then
    error('cap_idx provided to cap(<cap_idx>) must be a string', 2)
  end

  task = task or self:test_task()
  return self:caps_of(task.obj_id)[cap_idx]
end

---@class Caps
Caps = {}

---@return Caps
function Caps.new()
  local o = {}
  setmetatable(o, {__index = Caps});
  return o;
end

---@return Caps
function Caps:filter(func)
  return filter(self, func, Caps.new())
end

---@return Caps
function Caps:union(caps)
  return union(self, caps, Caps.new())
end

---@return Caps
function Caps:intersect(caps)
  return self:filter(function(cap) return caps[cap.cap_idx] end)
end

---@return Caps
function Caps:diff(caps)
  local diff_l = self:filter(function(cap) return not caps[cap.cap_idx] end)
  local diff_r = caps:filter(function(cap) return not self[cap.cap_idx] end)
  return diff_l:union(diff_r)
end

---@return Caps
function Caps:by(key, value)
  return self:filter(function(cap) return cap[key] == value end)
end

----------------------
-- HELPER FUNCTIONS --
----------------------

---@param str string
---@param regex string
---@return string[]
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

-- Get all keys of a table.
function table_keys(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  return keys
end

-- Get a copy of `a` where all keys that are in `b` are removed.
function table_minus(a, b)
  local diff = {}
  for k, v in pairs(a) do
    if b[k] == nil then
      diff[k] = v
    end
  end
  return diff
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


-- Helper for eq(). Same as inspect() but truncates long results.
---@return string
local function eq_inspect(x)
  local maxlen = 20000
  local ret = inspect(x)
  if ret:len() > maxlen then
    return ret:sub(1, maxlen) .. '...<truncated>'
  end
  return ret
end

---@return boolean
---@return string? rationale # when not equal
local function eq_helper(a, b, path)
  -- fast return if equal values or identical table
  if a == b then return true end

  -- if type(a) ~= 'table' or type(b) ~= 'table' then
  --   return false, 'difference in ' .. path:sub(1, -2) .. ':'
  --     .. '\nfirst: ' .. inspect(a)
  --     .. '\nsecond: ' .. inspect(b)
  -- end
  if type(a) ~= 'table' or type(b) ~= 'table' then
    return false, 'Different values at ' .. path .. '.'
      .. '\n  first:  ' .. eq_inspect(a):gsub('\n', '\n  ')
      .. '\n  second: ' .. eq_inspect(b):gsub('\n', '\n  ')
  end

  -- from here on it is clear that both values are tables

  -- compare the key sets of both tables
  do  -- Scoped so table diffs vanish before recursive descent.
    local diff1 = table_minus(a, b)
    local diff2 = table_minus(b, a)
    if next(diff1) ~= nil or next(diff2) ~= nil then
      return false, 'Differing key sets at ' .. path .. '.'
        .. '\nKeys appearing only on one side:'
        .. '\n  first:  ' .. eq_inspect(table_keys(diff1))
        .. '\n  second: ' .. eq_inspect(table_keys(diff2))
        .. '\nValues of offending keys:'
        .. '\n  first:  ' .. eq_inspect(diff1):gsub('\n', '\n  ')
        .. '\n  second: ' .. eq_inspect(diff2):gsub('\n', '\n  ')
    end
  end

  -- compare corresponding values of both tables recursively
  for k, v in pairs(a) do
    res, err = eq_helper(v, b[k], path .. tostring(k) .. '/')
    if not res then
      return res, err
    end
  end
  return true
end

-- Compare two values and, in case of tables, compare their entries recursively.
-- Two `nil` values are considered unequal.
-- When the values are unequal, the second return value provides a rationale.
---@return boolean is_equal  # `true` iff equal (except `eq(nil, nil) == false`)
---@return string? rationale # when not equal
function eq(a, b)
  if a == nil and b == nil then
    return false, 'Both values are nil. This is considered not equal because \z
                   this often signals a problem.'
  end
  return eq_helper(a, b, '/')
end


---@generic V
---@param o table<any, V>
---@return V
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


-----------------
-- PARSE INPUT --
-----------------

---@param rights string hex string
---@return table
function parse_rights(rights)
  local r = tonumber(rights, 16)
  local parsed = {}
  if r & 0x4 ~= 0 then parsed["R"] = true end
  if r & 0x1 ~= 0 then parsed["W"] = true end
  if r & 0x2 ~= 0 then parsed["S"] = true end
  if r & 0x8 ~= 0 then parsed["D"] = true end
  return parsed
end

---@param flags string hex string
---@return table
function parse_flags(flags)
  local f = tonumber(flags, 16)
  local parsed = {}
  if f & 0x08 ~= 0 then parsed["delete"] = true end
  if f & 0x10 ~= 0 then parsed["weakref"] = true end
  if f & 0x20 ~= 0 then parsed["server"] = true end
  return parsed
end

---@param dump string
---@return string tag
---@return Dump
function parse_dump(dump)
  local objects = Dump.new()
  local lines = split(dump, '[^\n]+')
  local cur_obj_id

  ---@param line? string
  ---@param pat string
  ---@return string ...
  local function parse(line, pat)
    local res = {}
    if line ~= nil then
      res = {line:match(pat)}
    end
    if res[1] == nil then
      tap:abort(plugin, 'object dump line: "' .. inspect(line)
                .. '" does not match pattern "' .. pat .. '"')
    end
    return table.unpack(res)
  end

  local version =
    parse(table.remove(lines, 1), '^dump format version number: (%d+)$')
  if version ~= '0' then
    tap:abort(plugin, 'Expected kernel object dump version 0 but got '
              .. version .. '.')
  end

  local tag = parse(table.remove(lines, 1), '^user space tag: (%w+)$')

  for _, line in ipairs(lines) do
    if line:sub(1, 1) == '\t' then -- this is a capability line
      local cap_addr, cap_idx, space_id, space_name, rights, flags, obj_addr
      -- a space name is optionally given within parentheses, so we need to use
      -- slightly different patterns to parse this line
      if line:match("%b()") ~= nil then
        local attrs_regex =
           'space=D:(%x+)%(([^)]+)%) rights=(%x+) flags=(%x+) obj=0x(%x+)'
        cap_addr, cap_idx, space_id, space_name, rights, flags, obj_addr =
          parse(line, '^\t(%x+)%[C:(%x+)%]: ' .. attrs_regex .. '$')
      else
        space_name = nil
        local attrs_regex =
          'space=D:(%x+) rights=(%x+) flags=(%x+) obj=0x(%x+)'
        cap_addr, cap_idx, space_id, rights, flags, obj_addr =
          parse(line, '^\t(%x+)%[C:(%x+)%]: ' .. attrs_regex .. '$')
      end

      if objects[cur_obj_id].caps[cap_addr] ~= nil then
        tap:abort(plugin, 'object dump: ambiguous capability address '
                  .. inspect(cap_addr) .. '. Source line:\n' .. line)
      end
      objects[cur_obj_id].caps[cap_addr] = {
        cap_addr = cap_addr,
        cap_idx = cap_idx,
        space_id = space_id,
        space_name = space_name,
        rights = parse_rights(rights),
        flags = parse_flags(flags),
        obj_addr = obj_addr,
        obj_id = cur_obj_id
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
        local split_attr = split(attr, '[^=]+')
        if #split_attr > 2 then
          tap:abort(plugin, "Failed parsing attribute")
        end
        attrs[split_attr[1]] = split_attr[2] or true
      end

      if objects[obj_id] ~= nil then
        tap:abort(plugin, 'object dump: ambiguous object id ' .. inspect(obj_id)
              .. '. Source line:\n' .. line)
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

  return tag, objects
end

-----------------
-- SANDBOXING --
-----------------

---@class Sandbox
---@field public scope string
---@field private _env table
---@field private _ignored_kernel_object_attrs table<string, string[]>
---@field private _ignored_kernel_object_ids string[]
Sandbox = {}

---@return Sandbox
---@param scope string
function Sandbox.new(scope)
  local ignored_kernel_object_attrs =
    { ['Factory'] = {'c'}    -- remaining quota
    , ['IRQ ipc'] = {'F'}    -- flags
    , ['Thread']  = {'rdy'}  -- ignore scheduling decisions
    }

  local ignored_kernel_object_ids = {}

  local env_d = {}

  local env =
    { d = env_d
    , eq = eq
    , ignore_kernel_object_attr = function (proto, attr)
        if ignored_kernel_object_attrs[proto] == nil then
          ignored_kernel_object_attrs[proto] = {attr}
        else
          table.insert(ignored_kernel_object_attrs[proto], attr)
        end
        for _, dump in pairs(env_d) do
          for _, obj in pairs(dump) do
            if obj.proto == proto then
              obj.attrs[attr] = nil
            end
          end
        end
      end
    , ignore_kernel_object_id = function (id)
        if type(id) == 'number' then
          id = string.format('%x', id)
        end
        if type(id) ~= 'string' then
          error('ignore_kernel_object_id(): Argument must be number or string.',
                2)
        end
        table.insert(ignored_kernel_object_ids, id)
        for _, dump in pairs(env_d) do
          dump[id] = nil
        end
      end
    , inspect = inspect
    , print = function (...)
        local args = table.pack(...)
        for i = 1, args.n do
          args[i] = tostring(args[i])
        end
        tap:comment(table.concat(args, '\t'), '  Lua output: ')
      end
    , unpack = unpack
    }

  ---@type Sandbox
  local self =
    { scope = scope
    , succeeded = true
    , uuid = nil
    , _env = env
    , _ignored_kernel_object_attrs = ignored_kernel_object_attrs
    , _ignored_kernel_object_ids = ignored_kernel_object_ids
    }
  setmetatable(self, {__index = Sandbox})
  return self
end

function Sandbox:safe_load(snip, env_ext)
  local fun, res = load(snip, snip, 't', table_merge(self._env, env_ext or {}))
  if not fun then
    return fun, res
  end
  return pcall(fun)
end

function Sandbox:exec(snip)
  local status, res = self:safe_load(snip)
  if not status then
    tap:comment('EXEC not ok.', 2)
    tap:comment(snip, '  Lua source: ')
    tap:comment(tostring(res), '  Lua error: ')
  end
  self.succeeded = self.succeeded and status
end

function Sandbox:check(snip)
  if not snip:find("^return ") then
    snip = "return " .. snip
  end
  local status, res, errstr = self:safe_load(snip)
  if not status then
    tap:comment('CHECK not ok.', 2)
    tap:comment(snip, '  Lua source: ')
    tap:comment(tostring(res), '  Lua error: ')
    self.succeeded = false
  elseif type(res) ~= 'boolean' then
    tap:comment('CHECK not ok.', 2)
    tap:comment(snip, '  Lua source: ')
    tap:comment('Result has type ' .. type(res) .. '. Expected boolean.', 2)
    self.succeeded = false
  elseif not res then
    tap:comment('CHECK not ok.', 2)
    tap:comment(snip, '  Lua source: ')
    tap:comment('Result is ' .. tostring(res) .. '.', 2)
    if errstr then tap:comment(errstr, 2) end
    self.succeeded = false
  end
  self.succeeded = self.succeeded and status
end

-- Add dump under given tag to `d` in the sandbox environment.
-- The current ignore rules are applied to the dump in-place.
function Sandbox:insert_dump(tag, dump)
  for _, id in pairs(self._ignored_kernel_object_ids) do
    dump[id] = nil
  end
  for _, obj in pairs(dump) do
    local attrs = self._ignored_kernel_object_attrs[obj.proto]
    if attrs ~= nil then
      for _, a in pairs(attrs) do
        obj.attrs[a] = nil
      end
    end
  end
  self._env.d[tag] = dump
end

function Sandbox:print_test_result()
  -- if UUID of the last test was not set, print out a warning
  if self.uuid == nil then
    tap:prepend_comment('WARNING: UUID was not set!')
  else
    tap:prepend_comment('Test-uuid: ' .. self.uuid, 3)
  end
  tap:flush_test(self.succeeded, self.scope .. ':Introspection')
end

-- The invalid sandbox is no actual sandbox. It is unusable; indexing it aborts
-- the script. It is used instead of nil to get a clean error message in case it
-- is used.
invalid_sandbox = setmetatable({},
                    { __index = function ()
                                  tap:abort(plugin,
                                            'First action must be RESETSCOPE.')
                                end })
-- Start with invalid sandbox. The first actual sandox must be initialized with
-- RESETSCOPE because a sandbox needs a scope name.
sandbox = invalid_sandbox

function process_input(id, input)
  tap:comment_header(input.filename)

  if input.tag == 'IntrospectionTesting' then
    if input.info == 'RESETSCOPE' then
      if sandbox ~= invalid_sandbox then
        -- print current test output
        sandbox:print_test_result()
      end
      -- reset Lua sandbox and status of test output for next test
      sandbox = Sandbox.new(input.text)
    elseif input.info == 'EXEC' then
      sandbox:exec(input.text)
    elseif input.info == 'CHECK' then
      sandbox:check(input.text)
    elseif input.info == "UUID" then
      if sandbox.uuid ~= nil then
        tap:comment('WARNING: Overwriting already set UUID; was '
                    .. sandbox.uuid, 2)
      end
      sandbox.uuid = input.text
    else
      tap:comment('WARNING: ' .. input.tag .. ' - Unsupported type of input: '
                  .. input.info, 2)
    end
  elseif input.tag == 'KernelObjects' then
    local tag, dump
      = parse_dump(helper.decode_kernel_objects(plugin, input.text))
    sandbox:insert_dump(tag, dump)
  else
    tap:comment('WARNING: Unsupported tag ' .. input.tag, 2)
  end

  tap:comment_header()
end

----------
-- MAIN --
----------

if #arg ~= 1 then
  tap:abort(plugin, 'number of command-line arguments')
end

local dir = arg[1]
if not lfs.attributes(dir) then
  tap:abort(plugin, 'valid path as first argument')
end

local ids, input = helper.load_snippets(plugin, dir)

for _, id in ipairs(ids) do
  process_input(id, input[id])
end

-- print output of last test
if sandbox ~= invalid_sandbox then
  sandbox:print_test_result()
end

tap:flush_plan()
