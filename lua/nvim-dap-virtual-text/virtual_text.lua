--
-- virtual_text.lua
-- Copyright (C) 2020 Stephan Seitz <stephan.seitz@fau.de>
--
-- Distributed under terms of the GPLv3 license.
--

local M = {}

local api = vim.api

local require_ok, locals = pcall(require, "nvim-treesitter.locals")
local _, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
local _, utils = pcall(require, "nvim-treesitter.utils")
local _, parsers = pcall(require, "nvim-treesitter.parsers")
local _, queries = pcall(require, "nvim-treesitter.query")

local hl_namespace = api.nvim_create_namespace("nvim-dap-virtual-text")
local error_set
local info_set
local stopped_frame

M.error_prefix = "  "
M.info_prefix = "  "
M.text_prefix = ""

function M.set_virtual_text(stackframe)
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

  local virtual_text = {}
  local node_ids = {}
  for _, d in pairs(definition_nodes) do
    local node = utils.get_at_path(d, "var.node") or utils.get_at_path(d, "parameter.node")
    if node then
      local name = ts_utils.get_node_text(node, buf)[1]
      local var_line, var_col = node:start()

      local evaluated = variables[name]
      if evaluated then -- evaluated local with same name exists
        -- is this name really the local or is it in another scope?
        local in_scope = true
        for _, scope in ipairs(scope_nodes) do
          if
            ts_utils.is_in_node_range(scope, var_line, var_col) and
              not ts_utils.is_in_node_range(scope, stackframe.line - 1, 0)
           then
            in_scope = false
            break
          end
        end

        if in_scope then
          if not node_ids[node:id()] then
            node_ids[node:id()] = true
            virtual_text[node:start()] =
              (virtual_text[node:start()] and virtual_text[node:start()] .. ", " or "") ..
              name .. " = " .. evaluated.value
          end
        end
      end
    end
  end

  for line, content in pairs(virtual_text) do
    content = M.text_prefix .. content
    api.nvim_buf_set_virtual_text(buf, hl_namespace, line, {{content, "NvimDapVirtualText"}}, {})
  end

  if stopped_frame and stopped_frame.line and stopped_frame.source and stopped_frame.source.path then
    local buf = vim.uri_to_bufnr(vim.uri_from_fname(stopped_frame.source.path))
    if error_set then
      api.nvim_buf_set_virtual_text(
        buf,
        hl_namespace,
        stopped_frame.line - 1,
        {{error_set, "NvimDapVirtualTextError"}},
        {}
      )
    end
    if info_set then
      api.nvim_buf_set_virtual_text(
        buf,
        hl_namespace,
        stopped_frame.line - 1,
        {{info_set, "NvimDapVirtualTextInfo"}},
        {}
      )
    end
  end
end

function M.set_info(message)
  info_set = M.info_prefix..message
end

function M.set_stopped_frame(frame)
  stopped_frame = frame
end

function M.set_error(response)
  if response then
    local exception_type = response.details and response.details.typeName
    local message =
      M.error_prefix ..
      (exception_type or "") ..
        (response.description and ((exception_type and ": " or "") .. response.description) or "")
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

return M
