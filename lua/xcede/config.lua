local M = {}

M.defaults = {
  -- Terminal settings
  terminal_height = 15,
  terminal_position = "botright", -- "botright", "topleft", "vertical"

  -- Behavior
  auto_save = true, -- Auto-save all buffers before building
  auto_close_terminal = false, -- Auto-close terminal on successful build

  -- Notifications
  notify_on_success = true,
  notify_on_failure = true,
  use_fidget = true, -- Use fidget.nvim for notifications if available

  -- xcede settings
  xcbeautify = true, -- Use xcbeautify if available

  -- Keymaps (set to false to disable, or customize)
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
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
