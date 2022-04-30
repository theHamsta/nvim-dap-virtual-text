--
-- nvim-dap-virtual-text.lua
-- Copyright (C) 2020 Stephan Seitz <stephan.seitz@fau.de>
--
-- Distributed under terms of the GPLv3 license.
--
local M = {}

local dap = require 'dap'

local plugin_id = 'nvim-dap-virtual-text'
local options = {
  enabled = true,
  enable_commands = true,
  all_frames = false,
  commented = false,
  highlight_changed_variables = true,
  highlight_new_as_changed = false,
  show_stop_reason = true,
  only_first_definition = true, -- only show virtual text at first definition (if there are multiple)
  all_references = false, -- show virtual text on all all references of the variable (not only definitions)
  text_prefix = '',
  separator = ',',
  error_prefix = '  ',
  info_prefix = '  ',
  virt_text_pos = 'eol',
  virt_lines = false,
  virt_lines_above = true,
  virt_text_win_col = nil,
  filter_references_pattern = '<module', -- filter references pattern (Lua gmatch pattern)
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
    for _, f in pairs(frames) do
      virtual_text.set_virtual_text(f, options)
    end
  else
    virtual_text.set_virtual_text(session.current_frame, options)
  end
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

function M.setup(opts)
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
    virtual_text._on_continue()
  end

  local function on_exit()
    local virtual_text = require 'nvim-dap-virtual-text/virtual_text'
    virtual_text._on_continue()
    virtual_text.clear_last_frames()
  end

  dap.listeners.after.event_terminated[plugin_id] = on_exit
  dap.listeners.after.event_exited[plugin_id] = on_exit
  dap.listeners.before.event_continued[plugin_id] = on_continue

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
              session:_request_scopes(f)
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
