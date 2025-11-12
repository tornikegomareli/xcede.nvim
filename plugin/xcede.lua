-- xcede.nvim
-- Prevent loading twice
if vim.g.loaded_xcede_nvim then
  return
end
vim.g.loaded_xcede_nvim = true

-- The plugin will be configured via require('xcede').setup() in the user's config
