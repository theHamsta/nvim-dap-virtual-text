--
-- virtual_text.lua
-- Copyright (C) 2020 Stephan Seitz <stephan.seitz@fau.de>
--
-- Distributed under terms of the GPLv3 license.
--

local M = {}

local api = vim.api

local require_ok, locals = pcall(require, 'nvim-treesitter.locals')
local _, ts_utils = pcall(require, 'nvim-treesitter.ts_utils')
local _, utils = pcall(require, 'nvim-treesitter.utils')
local _, parsers = pcall(require, 'nvim-treesitter.parsers')
local _, queries = pcall(require, 'nvim-treesitter.query')

local hl_namespace = api.nvim_create_namespace 'nvim-dap-virtual-text'
local error_set
local info_set
local stopped_frame
local last_frames = {}

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

  local scope_nodes = locals.get_scopes(buf)
  local definition_nodes = locals.get_definitions(buf)
  local variables = {}

  for _, s in ipairs(stackframe.scopes) do
    if s.variables then
      for _, v in pairs(s.variables) do
        variables[v.name] = v
      end
    end
  end
  last_variables = {}

  for _, s in ipairs(last_frames[stackframe.id] and last_frames[stackframe.id].scopes or {}) do
    if s.variables then
      for _, v in pairs(s.variables) do
        last_variables[v.name] = v
      end
    end
  end
  local virt_lines = {}

  local node_ids = {}
  for _, d in pairs(definition_nodes) do
    local node = utils.get_at_path(d, 'var.node') or utils.get_at_path(d, 'parameter.node')
    if node then
      local name = ts_utils.get_node_text(node, buf)[1]
      local var_line, var_col = node:start()

      local evaluated = variables[name]
      local last_value = last_variables[name]
      if evaluated then -- evaluated local with same name exists
        -- is this name really the local or is it in another scope?
        local in_scope = true
        for _, scope in ipairs(scope_nodes) do
          if
            ts_utils.is_in_node_range(scope, var_line, var_col)
            and not ts_utils.is_in_node_range(scope, stackframe.line - 1, 0)
          then
            in_scope = false
            break
          end
        end

        if in_scope then
          if not node_ids[node:id()] then
            node_ids[node:id()] = true
            local node_range = { node:range() }
            local has_changed = (evaluated.value ~= (last_value and last_value.value))
            local text = name .. ' = ' .. evaluated.value
            if options.commented then
              text = vim.o.commentstring:gsub('%%s', text)
            end
            text = options.text_prefix .. text

            local extmarks = vim.api.nvim_buf_get_extmarks(
              buf,
              hl_namespace,
              { node_range[1], 0 },
              { node_range[1], 0 },
              {}
            )
            if #extmarks > 0 then
              text = options.separator .. text
            end

            if options.virt_lines then
              if virt_lines[node:start()] then
                text = ' ' .. options.separator .. text
              else
                virt_lines[node:start()] = {}
              end
              table.insert(virt_lines[node:start()], {
                text,
                has_changed and 'NvimDapVirtualTextChanged' or 'NvimDapVirtualText',
              })
            else
              vim.api.nvim_buf_set_extmark(buf, hl_namespace, node_range[1], node_range[2], {
                end_line = node_range[3],
                end_col = node_range[4],
                virt_text = {
                  {
                    text,
                    has_changed and 'NvimDapVirtualTextChanged' or 'NvimDapVirtualText',
                  },
                },
                virt_text_pos = options.virt_text_pos,
              })
            end
          end
        end
      end
    end
  end

  for line, content in pairs(virt_lines) do
    vim.api.nvim_buf_set_extmark(buf, hl_namespace, line, 0, {
      virt_lines = { content },
      virt_lines_above = options.virt_lines_above,
    })
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
  last_frames = {}
  for _, t in pairs(threads or {}) do
    for _, f in pairs(t.frames or {}) do
      if f and f.id then
        last_frames[f.id] = f
      end
    end
  end
end

return M
