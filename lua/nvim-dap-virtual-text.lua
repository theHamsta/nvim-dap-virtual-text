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
  local virtual_text= require'nvim-dap-virtual-text/virtual_text'
  virtual_text.set_virtual_text(session.current_frame)
end
