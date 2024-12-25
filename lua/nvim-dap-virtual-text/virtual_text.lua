--
-- virtual_text.lua
-- Copyright (C) 2020 Stephan Seitz <stephan.seitz@fau.de>
--
-- Distributed under terms of the GPLv3 license.
--

local M = {}

local api = vim.api

local ts = vim.treesitter
local tsq = ts.query

local is_in_node_range
if vim.treesitter.is_in_node_range then
  is_in_node_range = vim.treesitter.is_in_node_range
else
  local _, ts_utils = pcall(require, 'nvim-treesitter.ts_utils')
  is_in_node_range = ts_utils.is_in_node_range
end

local hl_namespace = api.nvim_create_namespace 'nvim-dap-virtual-text'
local error_set
local info_set
---@type dap.StackFrame|nil
local stopped_frame
---@type dap.StackFrame[]
local last_frames = {}

local function variables_from_scopes(scopes, lang)
  local variables = {}

  scopes = scopes or {}
  for _, s in ipairs(scopes) do
    if s.variables then
      for _, v in pairs(s.variables) do
        local key = lang == 'php' and v.name:gsub('^%$', '') or v.name
        -- prefer "locals"
        if not variables[key] or variables[key].presentationHint ~= 'locals' then
          variables[key] = { value = v, presentationHint = s.presentationHint }
        end
      end
    end
  end
  return variables
end

local function get_query(lang, query_name)
  return (tsq.get or tsq.get_query)(lang, query_name)
end

---@class Scope
---@field name string
---@field presentationHint 'arguments' | 'locals' | 'registers' | string | nil
---@field variablesReference number
---@field namedVariables number|nil
---@field indexedVariables number|nil
---@field expensive boolean
---@field source dap.Source|nil
---@field line number|nil
---@field column number|nil
---@field endLine number|nil
---@field endColumn number|nil
--- nvim-dap internal
---@field variables table<string,Variable>

---@class dap.StackFrame
--- nvim-dap internal
---@field scopes Scope[]

---@param stackframe dap.StackFrame
---@param options nvim_dap_virtual_text_options
function M.set_virtual_text(stackframe, options)
  if not stackframe then
    return
  end
  if not stackframe.scopes then
    return
  end
  if not stackframe.source then
    return
  end
  if not stackframe.source.path then
    return
  end
  local buf = vim.fn.bufnr(stackframe.source.path, false)
  if buf == -1 then
    buf = vim.uri_to_bufnr(vim.uri_from_fname(stackframe.source.path))
  end
  local parser
  local lang
  local ft = vim.bo[buf].ft
  if ft == '' then
    ft = vim.filetype.match { buf = buf } or ''
    if ft == '' then
      return
    end
  end
  if vim.treesitter.get_parser and vim.treesitter.language and vim.treesitter.language.get_lang then
    lang = vim.treesitter.language.get_lang(ft)
    if not lang then
      return
    end
    local ok
    ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
    if not ok then
      return
    end
  else
    local require_ok, parsers = pcall(require, 'nvim-treesitter.parsers')
    if not require_ok then
      return
    end
    lang = parsers.get_buf_lang(buf)
    if not lang then
      return
    end
    local ok
    ok, parser = pcall(parsers.get_parser, buf, lang)
    if not ok then
      return
    end
  end

  local scope_nodes = {}
  local definition_nodes = {}

  if not parser then
    return
  end
  parser:parse()
  parser:for_each_tree(function(tree, ltree)
    local query = get_query(ltree:lang(), 'locals')
    if query then
      for _, match, _ in query:iter_matches(tree:root(), buf, 0, -1) do
        for id, nodes in pairs(match) do
          if type(nodes) ~= 'table' then
            nodes = { nodes }
          end
          for _, node in ipairs(nodes) do
            local cap_id = query.captures[id]
            if cap_id:find('scope', 1, true) then
              table.insert(scope_nodes, node)
            elseif cap_id:find('definition', 1, true) then
              table.insert(definition_nodes, node)
            elseif options.all_references and cap_id:find('reference', 1, true) then
              table.insert(definition_nodes, node)
            end
          end
        end
      end
    end
  end)

  local variables = variables_from_scopes(stackframe.scopes)

  local scopes = stackframe.scopes or {}
  for _, s in ipairs(scopes) do
    if s.variables then
      for _, v in pairs(s.variables) do
        local key = lang == 'php' and v.name:gsub('^%$', '') or v.name
        -- prefer "locals"
        if not variables[key] or variables[key].presentationHint ~= 'locals' then
          variables[key] = { value = v, presentationHint = s.presentationHint }
        end
      end
    end
  end

  local inline = options.virt_text_pos == 'inline'
  local last_scopes = last_frames[stackframe.id] and last_frames[stackframe.id].scopes or {}
  local last_variables = variables_from_scopes(last_scopes)

  local virt_lines = {}

  local node_ids = {}
  for _, node in pairs(definition_nodes) do
    if node then
      local get_node_text = vim.treesitter.get_node_text or vim.treesitter.query.get_node_text
      local name = get_node_text(node, buf)
      local var_line, var_col = node:start()

      local evaluated = variables[name]
      evaluated = evaluated and evaluated.value
      local last_value = last_variables[name]
      last_value = last_value and last_value.value
      if
        evaluated
        ---@diagnostic disable-next-line: deprecated
        and not (options.filter_references_pattern and evaluated.value:find(options.filter_references_pattern))
      then -- evaluated local with same name exists
        -- is this name really the local or is it in another scope?
        local in_scope = true
        for _, scope in ipairs(scope_nodes) do
          if is_in_node_range(scope, var_line, var_col) and not is_in_node_range(scope, stackframe.line - 1, 0) then
            in_scope = false
            break
          end
        end

        if in_scope then
          if options.only_first_definition and not options.all_references then
            variables[name] = nil
          end
          if not node_ids[node:id()] then
            node_ids[node:id()] = true
            local has_changed = options.highlight_changed_variables
              and (evaluated.value ~= (last_value and last_value.value))
              and (options.highlight_new_as_changed or last_value)
            local text = options.display_callback(evaluated, buf, stackframe, node, options)
            if text then
              if options.commented then
                text = vim.o.commentstring:gsub('%%s', { ['%s'] = text })
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
        end
      end
    end
  end

  for line, content in pairs(virt_lines) do
    -- Filtering necessary with all_references: there can be more than on reference on one line
    if options.all_references then
      local avoid_duplicates = {}
      content = vim.tbl_filter(function(c)
        local text = c[1]
        local was_duplicate = avoid_duplicates[text]
        avoid_duplicates[text] = true
        return not was_duplicate
      end, content)
    end
    if options.virt_lines then
      for _, virt_text in ipairs(content) do
        virt_text.node = nil
      end
      vim.api.nvim_buf_set_extmark(
        buf,
        hl_namespace,
        line,
        0,
        { virt_lines = { content }, virt_lines_above = options.virt_lines_above }
      )
    else
      local line_text = api.nvim_buf_get_lines(buf, line, line + 1, true)[1]
      local win_col = math.max(options.virt_text_win_col or 0, #line_text + 1)
      for i, virt_text in ipairs(content) do
        local node_range = { virt_text.node:range() }
        if i < #content and not inline then
          virt_text[1] = virt_text[1] .. options.separator
        end
        virt_text.node = nil
        vim.api.nvim_buf_set_extmark(buf, hl_namespace, node_range[inline and 3 or 1], node_range[inline and 4 or 2], {
          end_line = node_range[3],
          end_col = node_range[4],
          hl_mode = 'combine',
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
        error_msg = vim.o.commentstring:gsub('%%s', { ['%s'] = error_set })
      end
      pcall(api.nvim_buf_set_extmark, buf, hl_namespace, stopped_frame.line - 1, 0, {
        hl_mode = 'combine',
        virt_text = { { error_msg, 'NvimDapVirtualTextError' } },
        virt_text_pos = inline and 'eos' or options.virt_text_pos,
      })
    end
    if info_set then
      local info_msg = info_set
      if options.commented then
        info_msg = vim.o.commentstring:gsub('%%s', { ['%s'] = info_set })
      end
      pcall(api.nvim_buf_set_extmark, buf, hl_namespace, stopped_frame.line - 1, 0, {
        hl_mode = 'combine',
        virt_text = { { info_msg, 'NvimDapVirtualTextInfo' } },
        virt_text_pos = inline and 'eos' or options.virt_text_pos,
      })
    end
  end
end

---@param options nvim_dap_virtual_text_options
function M.set_info(message, options)
  info_set = options.info_prefix .. message
end

---@param frame dap.StackFrame
function M.set_stopped_frame(frame)
  stopped_frame = frame
end

---@param options nvim_dap_virtual_text_options
function M.set_error(response, options)
  if response then
    local exception_type = response.details and response.details.typeName
    local message = options.error_prefix
      .. (exception_type or '')
      .. (response.description and ((exception_type and ': ' or '') .. response.description) or '')
    error_set = message
  end
end

function M._on_continue(options)
  error_set = nil
  info_set = nil
  stopped_frame = nil

  if type(options) == 'table' and options.clear_on_continue then
    M.clear_virtual_text()
  end
end

---@param stackframe dap.StackFrame|nil
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

---@param threads dap.Thread[]
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
