# xcede.nvim

Neovim plugin for building, running, and testing Xcode projects using [xcede](https://codeberg.org/luxmentis/xcede).

This plugin brings the power of `xcede` to Neovim, allowing you to build and run iOS/macOS apps without leaving your editor.

## Features

- Build Xcode projects and Swift packages
- Run apps on simulator, devices, and macOS
- Run tests
- Async execution with live output
- Status line integration
- Syntax highlighting for build output
- Fully configurable keybindings
- Auto-save before building
- Support for `.xcrc` configuration files (compatible with Zed editor)
- Floating window for builds with auto-close on success
- Progress notifications with fidget.nvim integration
- Colorful terminal output with borders

## Requirements

- Neovim >= 0.8.0
- [xcede](https://codeberg.org/luxmentis/xcede) CLI tool
- [xcode-build-server](https://github.com/SolaWing/xcode-build-server) - Required for LSP support (autocompletion, navigation) in Xcode projects
- Optional: [xcbeautify](https://github.com/cpisciotta/xcbeautify) for prettier output
- Optional: [fidget.nvim](https://github.com/j-hui/fidget.nvim) for progress notifications

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "yourusername/xcede.nvim",
  config = function()
    require("xcede").setup({
      -- your configuration here (optional)
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "yourusername/xcede.nvim",
  config = function()
    require("xcede").setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'yourusername/xcede.nvim'

lua << EOF
require("xcede").setup()
EOF
```

## Configuration

### Default Configuration

```lua
require("xcede").setup({
  -- Terminal settings
  terminal_height = 15,
  terminal_position = "vertical", -- "botright", "topleft", "vertical"
  use_floating_for_build = true, -- Use floating window for build (auto-close on success)

  -- Behavior
  auto_save = true, -- Auto-save all buffers before building
  auto_close_terminal = false, -- Auto-close terminal on successful build

  -- Notifications
  notify_on_success = true,
  notify_on_failure = true,
  use_fidget = true, -- Use fidget.nvim for notifications if available

  -- xcede settings
  xcbeautify = true, -- Use xcbeautify if available

  -- Keymaps (set to false or customize)
  keymaps = {
    build = "<leader>xb",
    run = "<leader>xr",
    buildrun = "<leader>xR",
    test = "<leader>xt",
    toggle_terminal = "<leader>xl",
    stop = "<leader>xs",
  },

  -- Filetype to enable keymaps (set to false to disable auto-keymaps)
  filetypes = { "swift", "objc", "objcpp" },
})
```

### Custom Keybindings Example

```lua
require("xcede").setup({
  keymaps = {
    build = "<F5>",
    buildrun = "<F6>",
    test = "<F7>",
    toggle_terminal = "<F8>",
    stop = "<F9>",
    run = false, -- Disable this keybinding
  },
})
```

### Disable Auto-Keybindings

If you want to set keybindings manually:

```lua
require("xcede").setup({
  keymaps = false, -- Disable all auto-keybindings
})

-- Then set your own keybindings
vim.keymap.set("n", "<leader>bb", "<cmd>XcedeBuild<cr>", { desc = "Build" })
vim.keymap.set("n", "<leader>br", "<cmd>XcedeBuildRun<cr>", { desc = "Build & Run" })
```

## Usage

### Project Configuration

Create a `.xcrc` file in your project root:

```
scheme=MyApp
platform=sim
device=iPhone 16 Pro
```

**Platform options:**
- `device` - Physical iOS device
- `sim` - iOS Simulator
- `mac` - macOS app

**Multiple Configurations** (comment/uncomment as needed):

```
# Active config
platform=sim; device=iPhone 16 Pro

# Commented configs
# platform=device; device=My iPhone
# platform=mac
```

### Commands

The plugin provides the following commands:

- `:XcedeBuild` - Build project
- `:XcedeRun` - Run project (assumes already built)
- `:XcedeBuildRun` - Build and run in one step
- `:XcedeTest` - Run tests
- `:XcedeToggleTerminal` - Show/hide build output terminal
- `:XcedeStop` - Stop running build/run job

### Status Line Integration

The plugin sets `vim.g.xcede_status` which you can display in your statusline:

**Possible values:**
- `"Idle"`
- `"Building..."`
- `"Running..."`
- `"Testing..."`
- `"Success"`
- `"Failed"`
- `"Stopped"`

**Example for lualine:**

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      function()
        return vim.g.xcede_status or "Idle"
      end,
    },
  },
})
```

## Examples

### Minimal Configuration

```lua
{
  "yourusername/xcede.nvim",
  config = function()
    require("xcede").setup()
  end,
}
```

### Custom Configuration

```lua
{
  "yourusername/xcede.nvim",
  ft = { "swift" }, -- Lazy load on Swift files only
  config = function()
    require("xcede").setup({
      terminal_height = 20,
      terminal_position = "vertical",
      auto_close_terminal = true,
      notify_on_success = false, -- Only notify on failures
      keymaps = {
        build = "<D-b>", -- Cmd+B (Mac-style)
        buildrun = "<D-r>", -- Cmd+R
        test = "<D-u>", -- Cmd+U
        toggle_terminal = "<leader>xl",
        stop = "<leader>xs",
      },
    })
  end,
}
```

### Without Keybindings

```lua
{
  "yourusername/xcede.nvim",
  config = function()
    require("xcede").setup({
      keymaps = false, -- I'll set my own keybindings
    })

    -- Custom keybindings
    local keymap = vim.keymap.set
    keymap("n", "<F9>", "<cmd>XcedeBuild<cr>", { desc = "Build Project" })
    keymap("n", "<F10>", "<cmd>XcedeBuildRun<cr>", { desc = "Build & Run" })
  end,
}
```

## Swift Package Support

The plugin works with Swift packages (SPM) as well! If there's no `.xcrc` file, `xcede` will default to building/running the Swift package in the current directory.

## Comparison with xcodebuild.nvim

| Feature | xcede.nvim | xcodebuild.nvim |
|---------|-----------|-----------------|
| Build & Run | ✅ | ✅ |
| Testing | ✅ | ✅ |
| Debugging | ❌ | ✅ |
| Code Coverage | ❌ | ✅ |
| Test Explorer | ❌ | ✅ |
| Project Management | ❌ | ✅ |
| Simpler Setup | ✅ | ❌ |
| Swift Packages | ✅ | ✅ |

**xcede.nvim** is perfect if you want a lightweight, simple build/run workflow.
**xcodebuild.nvim** is better if you need advanced features like debugging and test management.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT

## Credits

- [xcede](https://codeberg.org/luxmentis/xcede) - The underlying CLI tool
- Inspired by the [Zed editor's Xcode integration](https://www.artificialworlds.net/blog/2025/08/04/build-run-and-debug-ios-and-mac-apps-in-zed-instead-of-xcode/)

## Troubleshooting

### xcede not found

Make sure `xcede` is installed and in your PATH. Follow installation instructions from https://codeberg.org/luxmentis/xcede

### No autocompletion or LSP support in Xcode projects

You need to install and configure [xcode-build-server](https://github.com/SolaWing/xcode-build-server):

1. Install xcode-build-server:
   ```bash
   brew install xcode-build-server
   ```

2. Generate buildServer.json in your project:
   ```bash
   cd /path/to/your/project
   xcode-build-server config -project YourProject.xcodeproj -scheme YourScheme
   ```

3. Configure sourcekit-lsp in your Neovim LSP config to recognize buildServer.json

See the [xcode-build-server documentation](https://github.com/SolaWing/xcode-build-server) for detailed setup instructions.

### Build output is hard to read

Install `xcbeautify` for prettier output:

```bash
brew install xcbeautify
```

The plugin will automatically detect and use it.

### Keybindings not working

Make sure you're in a Swift/Objective-C file, or configure the `filetypes` option in setup.

### Terminal not showing

Check your terminal configuration:

```lua
require("xcede").setup({
  terminal_height = 15,
  terminal_position = "botright", -- try different positions
})
```
