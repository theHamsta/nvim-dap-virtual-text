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

local function variables_from_scopes(scopes, lang)
  local variables = {}

  local scopes = scopes or {}
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
  local definition_nodes = locals.get_locals(buf)
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

  local last_scopes = last_frames[stackframe.id] and last_frames[stackframe.id].scopes or {}
  local last_variables = variables_from_scopes(last_scopes)

  local virt_lines = {}

  local node_ids = {}
  for _, d in pairs(definition_nodes) do
    local node = (options.all_references and utils.get_at_path(d, 'reference.node'))
      or utils.get_at_path(d, 'definition.var.node')
      or utils.get_at_path(d, 'definition.parameter.node')
    if node then
      local name = vim.treesitter.query.get_node_text(node, buf)
      local var_line, var_col = node:start()

      local evaluated = variables[name]
      evaluated = evaluated and evaluated.value
      local last_value = last_variables[name]
      last_value = last_value and last_value.value
      if
        evaluated
        and not (options.filter_references_pattern and evaluated.value:find(options.filter_references_pattern))
      then -- evaluated local with same name exists
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
          if options.only_first_definition and not options.all_references then
            variables[name] = nil
          end
          if not node_ids[node:id()] then
            node_ids[node:id()] = true
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
        if i < #content then
          virt_text[1] = virt_text[1] .. options.separator
        end
        virt_text.node = nil
        vim.api.nvim_buf_set_extmark(buf, hl_namespace, node_range[1], node_range[2], {
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
        error_msg = vim.o.commentstring:gsub('%%s', error_set)
      end
      pcall(api.nvim_buf_set_extmark, buf, hl_namespace, stopped_frame.line - 1, 0, {
        hl_mode = 'combine',
        virt_text = { { error_msg, 'NvimDapVirtualTextError' } },
        virt_text_pos = options.virt_text_pos,
      })
    end
    if info_set then
      local info_msg = info_set
      if options.commented then
        info_msg = vim.o.commentstring:gsub('%%s', info_set)
      end
      pcall(api.nvim_buf_set_extmark, buf, hl_namespace, stopped_frame.line - 1, 0, {
        hl_mode = 'combine',
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
