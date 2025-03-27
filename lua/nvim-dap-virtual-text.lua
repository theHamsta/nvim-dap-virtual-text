--
-- nvim-dap-virtual-text.lua
-- Copyright (C) 2020 Stephan Seitz <stephan.seitz@fau.de>
--
-- Distributed under terms of the GPLv3 license.
--
local M = {}

local dap = require 'dap'

local plugin_id = 'nvim-dap-virtual-text'

---@class VariablePresentationHint
---@field kind 'property' | 'method' | 'class' | 'data' | 'event' | 'baseClass' | 'innerClass' | 'interface'
--- | 'mostDerivedClass'
--- | 'virtual'
--- | 'dataBreakpoint'
--- | string
--- | nil
---@field attributes ('static' | 'constant' | 'readOnly' | 'rawString' | 'hasObjectId' | 'canHaveObjectId'
--- | 'hasSideEffects'
--- | 'hasDataBreakpoint'
--- | string)[] | nil
---@field visibility 'public' | 'private' | 'protected' | 'internal' | 'final' | string | nil
---@field lazy boolean|nil

--- @class Variable
--- @field name string
--- @field value string
--- @field type string|nil
--- @field presentationHint VariablePresentationHint|nil
--- @field evaluateName string|nil
--- @field variablesReference number
--- @field namedVariables number|nil
--- @field indexedVariables number|nil
--- @field memoryReference string|nil

---@class nvim_dap_virtual_text_options
local options = {
  -- enable this plugin (the default)
  enabled = true,
  -- create commands `DapVirtualTextEnable`, `DapVirtualTextDisable`, `DapVirtualTextToggle`,
  -- (`DapVirtualTextForceRefresh` for refreshing when debug adapter did not notify its termination)
  enable_commands = true,
  -- show virtual text for all stack frames not only current. Only works for debugpy on my machine.
  all_frames = false,
  -- prefix virtual text with comment string
  commented = false,
  -- highlight changed values with `NvimDapVirtualTextChanged`, else always `NvimDapVirtualText`
  highlight_changed_variables = true,
  -- highlight new variables in the same way as changed variables (if highlight_changed_variables)
  highlight_new_as_changed = false,
  -- show stop reason when stopped for exceptions
  show_stop_reason = true,
  -- only show virtual text at first definition (if there are multiple)
  only_first_definition = true,
  -- show virtual text on all all references of the variable (not only definitions)
  all_references = false,
  -- clear virtual text on "continue" (might cause flickering when stepping)
  clear_on_continue = false,
  text_prefix = '',
  separator = ',',
  error_prefix = '  ',
  info_prefix = '  ',
  -- position of virtual text, see `:h nvim_buf_set_extmark()`
  virt_text_pos = vim.fn.has 'nvim-0.10' == 1 and 'inline' or 'eol',
  -- show virtual lines instead of virtual text (will flicker!)
  virt_lines = false,
  virt_lines_above = true,
  -- position the virtual text at a fixed window column (starting from the first text column) ,
  -- e.g. `80` to position at column `80`, see `:h nvim_buf_set_extmark()`
  virt_text_win_col = nil,
  -- filter references (not definitions) pattern when `all_references` is activated
  -- (Lua gmatch pattern, default filters out Python modules)
  --- @deprecated Use display_callback instead with nil return value instead!
  filter_references_pattern = '<module',
  --- A callback that determines how a variable is displayed or whether it should be omitted
  --- @param variable Variable https://microsoft.github.io/debug-adapter-protocol/specification#Types_Variable
  --- @param buf number
  --- @param stackframe dap.StackFrame https://microsoft.github.io/debug-adapter-protocol/specification#Types_StackFrame
  --- @param node userdata tree-sitter node identified as variable definition of reference (see `:h tsnode`)
  --- @param options nvim_dap_virtual_text_options Current options for nvim-dap-virtual-text
  --- @return string|nil text how the virtual text should be displayed or nil, if this variable shouldn't be displayed
  --- @diagnostic disable-next-line: unused-local
  display_callback = function(variable, buf, stackframe, node, options)
    -- by default, strip out new line characters
    if options.virt_text_pos == 'inline' then
      return ' = ' .. variable.value:gsub('%s+', ' ')
    else
      return variable.name .. ' = ' .. variable.value:gsub('%s+', ' ')
    end
  end,
}

function M.refresh(session)
  session = session or dap.session()
  local virtual_text = require 'nvim-dap-virtual-text/virtual_text'

  virtual_text.clear_virtual_text()

  if not options.enabled then
    return
  end
  if not session then
    return
  end

  if options.all_frames and session.threads and session.threads[session.stopped_thread_id] then
    local frames = session.threads[session.stopped_thread_id].frames
    for _, f in pairs(frames or {}) do
      virtual_text.set_virtual_text(f, options)
    end
  else
    virtual_text.set_virtual_text(session.current_frame, options)
  end
end

function M.is_enabled()
  return options.enabled
end

function M.enable()
  options.enabled = true
  M.refresh()
end

function M.toggle()
  options.enabled = not options.enabled
  M.refresh()
end

function M.disable()
  options.enabled = false
  M.refresh()
end

---@param opts nvim_dap_virtual_text_options
function M.setup(opts)
  ---@type nvim_dap_virtual_text_options
  options = vim.tbl_deep_extend('force', options, opts or {})

  vim.cmd [[
  highlight default link NvimDapVirtualText Comment
  highlight default link NvimDapVirtualTextChanged DiagnosticVirtualTextWarn
  highlight default link NvimDapVirtualTextError DiagnosticVirtualTextError
  highlight default link NvimDapVirtualTextInfo DiagnosticVirtualTextInfo
  ]]

  if options.enable_commands then
    vim.cmd [[
    command! DapVirtualTextEnable :lua require'nvim-dap-virtual-text'.enable()
    command! DapVirtualTextDisable :lua require'nvim-dap-virtual-text'.disable()
    command! DapVirtualTextToggle :lua require'nvim-dap-virtual-text'.toggle()
    command! DapVirtualTextForceRefresh :lua require'nvim-dap-virtual-text'.refresh()
    ]]
  end

  local function on_continue()
    local virtual_text = require 'nvim-dap-virtual-text/virtual_text'
    virtual_text._on_continue(options)
  end

  local function on_exit()
    local virtual_text = require 'nvim-dap-virtual-text/virtual_text'
    virtual_text.clear_virtual_text()
    virtual_text.clear_last_frames()
  end

  dap.listeners.after.event_terminated[plugin_id] = on_exit
  dap.listeners.after.event_exited[plugin_id] = on_exit
  dap.listeners.before.event_continued[plugin_id] = on_continue
  dap.listeners.before.continue[plugin_id] = on_continue

  dap.listeners.before.event_stopped[plugin_id] = function(session)
    local virtual_text = require 'nvim-dap-virtual-text/virtual_text'
    virtual_text.set_last_frames(session.threads)
  end
  dap.listeners.after.event_stopped[plugin_id] = function(_, event)
    local virtual_text = require 'nvim-dap-virtual-text/virtual_text'
    if options.show_stop_reason then
      if event and event.reason == 'exception' then
        virtual_text.set_error('Stopped due to exception', options)
      elseif event and event.reason == 'data breakpoint' then
        virtual_text.set_info('Stopped due to ' .. event.reason, options)
      end
    end
  end

  dap.listeners.after.variables[plugin_id] = M.refresh

  dap.listeners.after.stackTrace[plugin_id] = function(session, body, _)
    if not options.enabled then
      return
    end

    local virtual_text = require 'nvim-dap-virtual-text/virtual_text'
    if
      session.stopped_thread_id
      and session.threads[session.stopped_thread_id]
      and session.threads[session.stopped_thread_id].frames
    then
      local frames_with_source = vim.tbl_filter(function(f)
        return f.source and f.source.path
      end, session.threads[session.stopped_thread_id].frames)
      virtual_text.set_stopped_frame(frames_with_source[1])
    end

    -- request additional stack frames for "all frames"
    if options.all_frames then
      local requested_functions = {}

      if body then
        for _, f in pairs(body.stackFrames) do
          -- Ensure to evaluate the same function only once to avoid race conditions
          -- since a function can be evaluated in multiple frames.
          if not requested_functions[f.name] then
            if not f.scopes or #f.scopes == 0 then
              pcall(session._request_scopes, session, f)
            end
            requested_functions[f.name] = true
          end
        end
      end
    end
  end

  dap.listeners.after.exceptionInfo[plugin_id] = function(_, _, response)
    local virtual_text = require 'nvim-dap-virtual-text/virtual_text'
    if not options.enabled then
      return
    end
    virtual_text.set_error(response, options)
  end
end

return M
