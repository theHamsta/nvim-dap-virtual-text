# nvim-dap-virtual-text

This plugin adds virtual text support to [nvim-dap](https://github.com/mfussenegger/nvim-dap).
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) is used to find variable definitions.

```vim
    Plug 'mfussenegger/nvim-dap'
    Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
    Plug 'theHamsta/nvim-dap-virtual-text'
```

The hlgroup for the virtual text is `NvimDapVirtualText` (linked to `Comment`).
Exceptions that caused the debugger to stop are displayed as `NvimDapVirtualTextError`
(linked to `LspDiagnosticsVirtualTextError`).

The behavior of this can be controlled by a global variable (`g:dap_virtual_text` in viml)

```lua
    -- virtual text deactivated (default)
    vim.g.dap_virtual_text = false
    -- show virtual text for current frame (recommended)
    vim.g.dap_virtual_text = true
    -- request variable values for all frames (experimental)
    vim.g.dap_virtual_text = 'all frames'
```

So you could activate the plugin by pasting this into your `init.vim`
```viml
let g:dap_virtual_text = v:true
```

With `vim.g.dap_virtual_text = true`

![current_frame](https://user-images.githubusercontent.com/7189118/81495691-5d937400-92b2-11ea-8995-17daeda593cc.gif)

With `vim.g.dap_virtual_text = 'all frames'`

![all_scopes](https://user-images.githubusercontent.com/7189118/81495701-6b48f980-92b2-11ea-8df4-dd476dc825bc.gif)

It works for all languages with `locals.scm` in nvim-treesitter (`@definition.var` is required for variable definitions).
This should include C/C++, Python, Rust, Go, Java...

![image](https://user-images.githubusercontent.com/7189118/82733259-f4304e00-9d12-11ea-90da-addebada2e18.png)

![image](https://user-images.githubusercontent.com/7189118/91160889-485c1d00-e6ca-11ea-9c70-e329c50ed1e1.png)

## Exceptions

![image](https://user-images.githubusercontent.com/7189118/115946315-b3136180-a4c0-11eb-8d8b-980b11464448.png)
![image](https://user-images.githubusercontent.com/7189118/115946346-db9b5b80-a4c0-11eb-8582-6075d818d869.png)
