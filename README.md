# nvim-dap-virtual-text

This plugin adds virtual text support to [nvim-dap](https://github.com/mfussenegger/nvim-dap).
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) is used to find variable definitions.

```vim
Plug 'mfussenegger/nvim-dap'
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'theHamsta/nvim-dap-virtual-text'
```

> [!NOTE]
>
> With Neovim 0.9 and above, `nvim-treesitter` is not hard a dependency.
> This plugin only needs the parsers for the languages you want to use it with
> and `locals.scm` queries defining references and definitions of variables
> (typically provided by nvim-treesitter).

The hlgroup for the virtual text is `NvimDapVirtualText` (linked to `Comment`).
Exceptions that caused the debugger to stop are displayed as `NvimDapVirtualTextError`
(linked to `DiagnosticVirtualTextError`). Changed and new variables will be highlighted with
`NvimDapVirtualTextChanged` (default linked to `DiagnosticVirtualTextWarn`).

The behavior of this plugin can be activated and controlled via a `setup` call

```lua
require("nvim-dap-virtual-text").setup()
```

Wrap this call with `lua <<EOF` when you are using viml for your config:

```vim
lua <<EOF
require("nvim-dap-virtual-text").setup()
EOF
```

or with additional options:
```lua
require("nvim-dap-virtual-text").setup {
    enabled = true,                        -- enable this plugin (the default)
    enabled_commands = true,               -- create commands DapVirtualTextEnable, DapVirtualTextDisable, DapVirtualTextToggle, (DapVirtualTextForceRefresh for refreshing when debug adapter did not notify its termination)
    highlight_changed_variables = true,    -- highlight changed values with NvimDapVirtualTextChanged, else always NvimDapVirtualText
    highlight_new_as_changed = false,      -- highlight new variables in the same way as changed variables (if highlight_changed_variables)
    show_stop_reason = true,               -- show stop reason when stopped for exceptions
    commented = false,                     -- prefix virtual text with comment string
    only_first_definition = true,          -- only show virtual text at first definition (if there are multiple)
    all_references = false,                -- show virtual text on all all references of the variable (not only definitions)
    clear_on_continue = false,             -- clear virtual text on "continue" (might cause flickering when stepping)
    --- A callback that determines how a variable is displayed or whether it should be omitted
    --- @param variable Variable https://microsoft.github.io/debug-adapter-protocol/specification#Types_Variable
    --- @param buf number
    --- @param stackframe dap.StackFrame https://microsoft.github.io/debug-adapter-protocol/specification#Types_StackFrame
    --- @param node userdata tree-sitter node identified as variable definition of reference (see `:h tsnode`)
    --- @param options nvim_dap_virtual_text_options Current options for nvim-dap-virtual-text
    --- @return string|nil A text how the virtual text should be displayed or nil, if this variable shouldn't be displayed
    display_callback = function(variable, buf, stackframe, node, options)
    -- by default, strip out new line characters
      if options.virt_text_pos == 'inline' then
        return ' = ' .. variable.value:gsub("%s+", " ")
      else
        return variable.name .. ' = ' .. variable.value:gsub("%s+", " ")
      end
    end,
    -- position of virtual text, see `:h nvim_buf_set_extmark()`, default tries to inline the virtual text. Use 'eol' to set to end of line
    virt_text_pos = vim.fn.has 'nvim-0.10' == 1 and 'inline' or 'eol',

    -- experimental features:
    all_frames = false,                    -- show virtual text for all stack frames not only current. Only works for debugpy on my machine.
    virt_lines = false,                    -- show virtual lines instead of virtual text (will flicker!)
    virt_text_win_col = nil                -- position the virtual text at a fixed window column (starting from the first text column) ,
                                           -- e.g. 80 to position at column 80, see `:h nvim_buf_set_extmark()`
}
```

With support for inline virtual text (nvim 0.10), `virt_text_pos = 'inline'`

![image](https://user-images.githubusercontent.com/7189118/236633778-5e18c02c-4415-46a4-b903-6ee06764ef2a.png)


With `highlight_changed_variables = false, all_frames = false`

![current_frame](https://user-images.githubusercontent.com/7189118/81495691-5d937400-92b2-11ea-8995-17daeda593cc.gif)

With `highlight_changed_variables = false, all_frames = true`

![all_scopes](https://user-images.githubusercontent.com/7189118/81495701-6b48f980-92b2-11ea-8df4-dd476dc825bc.gif)

It works for all languages with `locals.scm` in nvim-treesitter (`@definition.var` is required for variable definitions).
This should include C/C++, Python, Rust, Go, Java...

![image](https://user-images.githubusercontent.com/7189118/82733259-f4304e00-9d12-11ea-90da-addebada2e18.png)

![image](https://user-images.githubusercontent.com/7189118/91160889-485c1d00-e6ca-11ea-9c70-e329c50ed1e1.png)

The virtual text can additionally use a comment-like syntax to further improve distinguishability between actual code and debugger info by setting the following option:
```lua
require("nvim-dap-virtual-text").setup {
  commented = true,
}
```

This will use the `commentstring` option to choose the appropriate comment-syntax for the current filetype

![image](https://user-images.githubusercontent.com/6146545/134688673-49c86368-ed51-4f16-82b4-fce05bcd9767.PNG)

With `virt_text_win_col = 80, highlight_changed_variables = true` (x has just changed its value)

![image](https://user-images.githubusercontent.com/7189118/139598856-d45e02ef-62f6-4f7e-a619-ed9b48d53cc1.png)


## Show Stop Reason on Exception

![image](https://user-images.githubusercontent.com/7189118/115946315-b3136180-a4c0-11eb-8d8b-980b11464448.png)
![image](https://user-images.githubusercontent.com/7189118/115946346-db9b5b80-a4c0-11eb-8582-6075d818d869.png)

Exception virtual text can be deactivated via

```lua
require("nvim-dap-virtual-text").setup {
  show_stop_reason = false,
}
```
