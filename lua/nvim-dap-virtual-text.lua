#! /usr/bin/env lua
--
-- nvim-dap-virtual-text.lua
-- Copyright (C) 2020 Stephan Seitz <stephan.seitz@fau.de>
--
-- Distributed under terms of the GPLv3 license.
--

local require_ok, dap = pcall(require, "dap")
local plugin_id = "nvim-dap-virtual-text"

if not require_ok then return end
if not dap.custom_event_handlers then return end

dap.custom_event_handlers.event_exited[plugin_id] = function(_, _)
  local virtual_text= require'nvim-dap-virtual-text/virtual_text'
  virtual_text.clear_virtual_text()
end

dap.custom_event_handlers.event_continued[plugin_id] = function(_, _)
  local virtual_text= require'nvim-dap-virtual-text/virtual_text'
  virtual_text.clear_virtual_text()
end

-- update virtual text after "variables" request
dap.custom_response_handlers.variables[plugin_id] = function(session, _)
  if not vim.g.dap_virtual_text then return end

  local virtual_text= require'nvim-dap-virtual-text/virtual_text'
  virtual_text.clear_virtual_text()

  if vim.g.dap_virtual_text == 'all frames' then
    local frames = session.threads[session.stopped_thread_id].frames
    for _, f in pairs(frames) do
      virtual_text.set_virtual_text(f)
    end
  else
     virtual_text.set_virtual_text(session.current_frame)
  end
end

-- request additional stack frames for "all frames"
dap.custom_response_handlers.stackTrace[plugin_id] = function(session, body)
  if vim.g.dap_virtual_text == 'all frames' then
    local requested_functions = {}

    for _, f in pairs(body.stackFrames) do
      dap.repl.append(vim.inspect(f))
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
