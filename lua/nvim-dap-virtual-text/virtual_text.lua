--
-- virtual_text.lua
-- Copyright (C) 2020 Stephan Seitz <stephan.seitz@fau.de>
--
-- Distributed under terms of the GPLv3 license.
--

local M = {}

local api = vim.api

local require_ok, locals = pcall(require, 'nvim-treesitter.locals')
local _, tsrange = pcall(require, 'nvim-treesitter.tsrange')
local _, parsers = pcall(require, 'nvim-treesitter.parsers')
local _, queries = pcall(require, 'nvim-treesitter.query')

local hl_namespace = api.nvim_create_namespace 'nvim-dap-virtual-text'
local error_set
local info_set
local stopped_frame
local last_frames = {}

local function find_definition(node, bufnr, node_text)
  local def_lookup = locals.get_definitions_lookup_table(bufnr)

  for scope in locals.iter_scope_tree(node, bufnr) do
    local id = locals.get_definition_id(scope, node_text)

    if def_lookup[id] then
      local entry = def_lookup[id]

      return entry.node, scope, entry.kind
    end
  end
  return nil
end

function M.set_virtual_text(stackframe, options)
  if not stackframe then
    return
  end
  if not stackframe.scopes then
    return
  end
  if not require_ok then
    return
  end
  if not stackframe.source then
    return
  end
  if not stackframe.source.path then
    return
  end
  local buf = vim.uri_to_bufnr(vim.uri_from_fname(stackframe.source.path))
  local lang = parsers.get_buf_lang(buf)

  if not parsers.has_parser(lang) or not queries.has_locals(lang) then
    return
  end

  local variables = {}

  -- prefer "locals"
  local scopes = stackframe.scopes or {}
  scopes = vim.list_extend(
    scopes,
    vim.tbl_filter(function(s)
      return s.presentationHint == 'locals'
    end, scopes)
  )
  for _, s in ipairs(scopes) do
    if s.variables then
      for _, v in pairs(s.variables) do
        variables[v.name] = v
      end
    end
  end

  local last_variables = {}
  local last_scopes = last_frames[stackframe.id] and last_frames[stackframe.id].scopes or {}
  last_scopes = vim.list_extend(
    last_scopes,
    vim.tbl_filter(function(s)
      return s.presentationHint == 'locals'
    end, last_scopes)
  )

  for _, s in ipairs(last_scopes) do
    if s.variables then
      for _, v in pairs(s.variables) do
        last_variables[v.name] = v
      end
    end
  end
  local virt_lines = {}

  for name, evaluated in pairs(variables) do
    local range = tsrange.TSRange.new(
      buf,
      stackframe.line - 1,
      stackframe.column - 1,
      stackframe.line - 1,
      stackframe.column - 1
    )
    -- TODO: check for kind?
    local node, _ = find_definition(range, buf, name)

    if node and evaluated.value then
      local last_value = last_variables[name]

      local has_changed = options.highlight_changed_variables
        and (evaluated.value ~= (last_value and last_value.value))
        and (options.highlight_new_as_changed or last_value)
      local text = name .. ' = ' .. evaluated.value
      if options.commented then
        text = vim.o.commentstring:gsub('%%s', text)
      end
      text = options.text_prefix .. text

      if virt_lines[node:start()] then
        if options.virt_lines then
          text = ' ' .. options.separator .. text
        end
      else
        virt_lines[node:start()] = {}
      end
      table.insert(virt_lines[node:start()], {
        text,
        has_changed and 'NvimDapVirtualTextChanged' or 'NvimDapVirtualText',
        node = node,
      })
    end
  end

  for line, content in pairs(virt_lines) do
    if options.virt_lines then
      vim.api.nvim_buf_set_extmark(buf, hl_namespace, line, 0, {
        virt_lines = { content },
        virt_lines_above = options.virt_lines_above,
      })
    else
      local line_text = api.nvim_buf_get_lines(buf, line, line + 1, true)[1]
      local win_col = math.max(options.virt_text_win_col or 0, #line_text + 1)
      for i, virt_text in ipairs(content) do
        local node_range = { virt_text.node:range() }
        if i < #content then
          virt_text[1] = virt_text[1] .. options.separator
        end
        virt_text.node = nil
        vim.api.nvim_buf_set_extmark(buf, hl_namespace, node_range[1], node_range[2], {
          end_line = node_range[3],
          end_col = node_range[4],
          virt_text = { virt_text },
          virt_text_pos = options.virt_text_pos,
          virt_text_win_col = options.virt_text_win_col and win_col,
        })
        win_col = win_col + #virt_text[1] + 1
      end
    end
  end

  if stopped_frame and stopped_frame.line and stopped_frame.source and stopped_frame.source.path then
    local buf = vim.uri_to_bufnr(vim.uri_from_fname(stopped_frame.source.path))
    if error_set then
      local error_msg = error_set
      if options.commented then
        error_msg = vim.o.commentstring:gsub('%%s', error_set)
      end
      api.nvim_buf_set_extmark(buf, hl_namespace, stopped_frame.line - 1, 0, {
        virt_text = { { error_msg, 'NvimDapVirtualTextError' } },
        virt_text_pos = options.virt_text_pos,
      })
    end
    if info_set then
      local info_msg = info_set
      if options.commented then
        info_msg = vim.o.commentstring:gsub('%%s', info_set)
      end
      api.nvim_buf_set_extmark(buf, hl_namespace, stopped_frame.line - 1, 0, {
        virt_text = { { info_msg, 'NvimDapVirtualTextInfo' } },
        virt_text_pos = options.virt_text_pos,
      })
    end
  end
end

function M.set_info(message, options)
  info_set = options.info_prefix .. message
end

function M.set_stopped_frame(frame)
  stopped_frame = frame
end

function M.set_error(response, options)
  if response then
    local exception_type = response.details and response.details.typeName
    local message = options.error_prefix
      .. (exception_type or '')
      .. (response.description and ((exception_type and ': ' or '') .. response.description) or '')
    error_set = message
  end
end

function M._on_continue()
  error_set = nil
  info_set = nil
  stopped_frame = nil
  M.clear_virtual_text()
end

function M.clear_virtual_text(stackframe)
  if stackframe then
    local buf = vim.uri_to_bufnr(vim.uri_from_fname(stackframe.source.path))
    api.nvim_buf_clear_namespace(buf, hl_namespace, 0, -1)
  else
    for _, buf in ipairs(api.nvim_list_bufs()) do
      api.nvim_buf_clear_namespace(buf, hl_namespace, 0, -1)
    end
  end
end

function M.set_last_frames(threads)
  for _, t in pairs(threads or {}) do
    for _, f in pairs(t.frames or {}) do
      if f and f.id then
        last_frames[f.id] = f
      end
    end
  end
end

function M.clear_last_frames()
  last_frames = {}
end

return M
