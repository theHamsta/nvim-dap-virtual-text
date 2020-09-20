# nvim-dap-virtual-text

This plugin adds virtual text support to [nvim-dap](https://github.com/mfussenegger/nvim-dap).
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) is used to find variable definitions.

```vim
    Plug 'mfussenegger/nvim-dap'
    Plug 'nvim-treesitter/nvim-treesitter'
    Plug 'theHamsta/nvim-dap-virtual-text'
```

The hlgroup for the virtual text is `NvimDapVirtualText` (linked to `Comment`).

The behavior of this can be controlled by a global variable (`g:dap_virtual_text` in viml)

```lua
    -- virtual text deactivated (default)
    vim.g.dap_virtual_text = false
    -- show virtual text for current frame (recommended)
    vim.g.dap_virtual_text = true
    -- request variable values for all frames (experimental)
    vim.g.dap_virtual_text = 'all frames'
```

With `vim.g.dap_virtual_text = true`

![current_frame](https://user-images.githubusercontent.com/7189118/81495691-5d937400-92b2-11ea-8995-17daeda593cc.gif)

With `vim.g.dap_virtual_text = 'all frames'`

![all_scopes](https://user-images.githubusercontent.com/7189118/81495701-6b48f980-92b2-11ea-8df4-dd476dc825bc.gif)

It works for all languages with `locals.scm` in nvim-treesitter (`@definition.var` is required for variable definitions).
This should include C/C++, Python, Rust, Go, Java...

![image](https://user-images.githubusercontent.com/7189118/82733259-f4304e00-9d12-11ea-90da-addebada2e18.png)

![image](https://user-images.githubusercontent.com/7189118/91160889-485c1d00-e6ca-11ea-9c70-e329c50ed1e1.png)


