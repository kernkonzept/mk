#!/usr/bin/env lua
-- SPDX-License-Identifier: GPL-2.0-only or License-Ref-kk-custom
--
-- Copyright (C) 2021 Kernkonzept GmbH.
-- Author(s): Marius Melzer <marius.melzer@kernkonzept.com>

----------------
-- TAP OUTPUT --
----------------

-- The singleton tap object buffers comments and only outputs them when a (not)
-- ok line is printed via flush_test(), ok(), etc. The comments are printed
-- after that (not) ok line. Besides the tap object counts how many (not) ok
-- lines were written. For valid test output, this count must finally be written
-- via flush_plan(); the comment buffer must be empty then.
tap = { _comment_header = nil, _comments = {}, _plan_number = 0 }


-- Prepend each line of `str` by `prefix. If `prefix` is a number, then each
-- line is prefixed by this number of spaces.
---@param prefix? string|number
---@param str string
---@return string
local function indent(prefix, str)
  if prefix == nil or prefix == 0 or prefix == '' then
    return str
  end
  if type(prefix) == 'number' then
    prefix = string.rep(' ', prefix)
  end
  return prefix .. str:gsub('\n', '\n' .. prefix)
end


-- Write and reset current comment buffer.
---@return boolean # `true` iff the comment buffer was not empty
function tap:_flush_comments(ok, description)
  local res = next(self._comments) ~= nil
  for _, c in ipairs(self._comments) do
    io.write('# ', c:gsub('\n', '\n# '), '\n')
  end
  self._comments = {}
  self._comment_header = nil
  return res
end

function tap:flush_plan()
  io.write('1..', self._plan_number, '\n')
  io.flush()
  self._plan_number = 0
  if self:_flush_comments() then
    io.flush()
    error('Non-empty comment buffer while flushing plan. Did you forget \z
           outputting a (not) ok line?', 2)
  end
end

-- Output a (not) ok line followed by the buffered comments.
---@param ok boolean
---@param description string
function tap:flush_test(ok, description)
  self._plan_number = self._plan_number + 1
  if not ok then
    io.write('not ')
  end
  io.write('ok ', description:gsub('\n', '\n# '), '\n')
  self:_flush_comments()
  io.flush()
end

-- Output an ok line followed by the buffered comments.
---@param description string
function tap:ok(description)
  self:flush_test(true, description)
end

-- Output a not ok line followed by the buffered comments.
---@param description string
function tap:not_ok(description)
  self:flush_test(false, description)
end

-- Prepare a comment that is is only written to the comment buffer before the
-- comment of the next comment() call. If no comment() call follows before the
-- next flush, the header is dropped.
--
-- There can only be one pending header at a time. Subsequent calls to this
-- funtion overwrite the current pending header. A call without arguments drops
-- a pending header.
---@param c? string
---@param prefix? string|number
function tap:comment_header(c, prefix)
  if c ~= nil then
    self._comment_header = indent(prefix, c)
  else
    self._comment_header = nil
  end
end

-- Append a comment to the comment buffer.
---@param c string
---@param prefix? string|number
function tap:comment(c, prefix)
  if self._comment_header ~= nil then
    table.insert(self._comments, self._comment_header)
    self._comment_header = nil
  end
  table.insert(self._comments, indent(prefix, c))
end

-- Prepend a comment to the comment buffer.
---@param c string
---@param prefix? string|number
function tap:prepend_comment(c, prefix)
  table.insert(self._comments, 1, indent(prefix, c))
end

-- Abort script with some “not ok” TAP output but with zero exit code. This is
-- intended for expected fatal errors. Errors that abort the script with
-- non-zero exit code are considered a bug in the script.
---@param plugin string
---@param comment string
function tap:abort(plugin, comment)
  tap:comment('FATAL ERROR:')
  tap:comment(comment, 2)
  tap:not_ok(plugin .. '::FatalError')
  tap:flush_plan()
  os.exit(0)
end


return tap
