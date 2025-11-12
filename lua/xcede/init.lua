local config = require("xcede.config")

local M = {
  terminal_buf = nil,
  terminal_win = nil,
  job_id = nil,
  parsed_config = {},
}

vim.g.xcede_status = "Idle"

--- Parse .xcrc config file
--- @return table config with scheme, platform, device fields
local function parse_xcrc()
  local xcrc_config = {}
  local config_paths = { ".xcrc", ".zed/xcrc" }
  local config_content = nil

  for _, path in ipairs(config_paths) do
    local file = io.open(path, "r")
    if file then
      config_content = file:read("*all")
      file:close()
      break
    end
  end

  if not config_content then
    return xcrc_config
  end

  for line in config_content:gmatch("[^\r\n]+") do
    line = line:gsub("#.*$", "")
    line = vim.trim(line)

    if line ~= "" then
      for setting in line:gmatch("[^;]+") do
        setting = vim.trim(setting)
        local key, value = setting:match("^%s*([%w_]+)%s*=%s*(.+)%s*$")
        if key and value then
          value = value:gsub("^['\"](.+)['\"]$", "%1")
          xcrc_config[key] = vim.trim(value)
        end
      end
    end
  end

  return xcrc_config
end

--- Check if a command exists
--- @param cmd string
--- @return boolean
local function command_exists(cmd)
  local handle = io.popen("which " .. cmd .. " 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    return result and result ~= ""
  end
  return false
end

--- Build xcede command with config options
--- @param cmd string
--- @return string
local function build_command(cmd)
  local parts = { "xcede", cmd }

  if M.parsed_config.scheme then
    table.insert(parts, "--scheme")
    table.insert(parts, string.format('"%s"', M.parsed_config.scheme))
  end

  if M.parsed_config.platform then
    table.insert(parts, "--platform")
    table.insert(parts, M.parsed_config.platform)
  end

  if M.parsed_config.device and M.parsed_config.platform ~= "mac" then
    table.insert(parts, "--device")
    table.insert(parts, string.format('"%s"', M.parsed_config.device))
  end

  local command = table.concat(parts, " ")

  if config.options.xcbeautify and command_exists("xcbeautify") then
    command = command .. " | xcbeautify"
  end

  return command
end

--- Get or create terminal buffer
--- @return number
local function get_or_create_terminal()
  if M.terminal_buf and vim.api.nvim_buf_is_valid(M.terminal_buf) then
    return M.terminal_buf
  end

  M.terminal_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(M.terminal_buf, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(M.terminal_buf, "filetype", "xcede")

  return M.terminal_buf
end

--- Show terminal in split window
--- @param buf number
local function show_terminal(buf)
  if M.terminal_win and vim.api.nvim_win_is_valid(M.terminal_win) then
    vim.api.nvim_set_current_win(M.terminal_win)
    return
  end

  local pos = config.options.terminal_position
  local height = config.options.terminal_height

  if pos == "vertical" then
    vim.cmd("vertical botright split")
  else
    vim.cmd(pos .. " " .. height .. "split")
  end

  M.terminal_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.terminal_win, buf)

  vim.api.nvim_win_set_option(M.terminal_win, "number", false)
  vim.api.nvim_win_set_option(M.terminal_win, "relativenumber", false)
  vim.api.nvim_win_set_option(M.terminal_win, "signcolumn", "no")

  vim.cmd("wincmd p")
end

--- Hide terminal window
local function hide_terminal()
  if M.terminal_win and vim.api.nvim_win_is_valid(M.terminal_win) then
    vim.api.nvim_win_close(M.terminal_win, true)
    M.terminal_win = nil
  end
end

--- Notify user
--- @param message string
--- @param level number
local function notify(message, level)
  if config.options.use_fidget and pcall(require, "fidget") then
    require("fidget").notify(message, level)
  else
    vim.notify(message, level)
  end
end

--- Run xcede command
--- @param cmd string
--- @param status_text string
local function run_xcede(cmd, status_text)
  if not command_exists("xcede") then
    notify("xcede is not installed. Install it from: https://github.com/XcodeClub/xcede", vim.log.levels.ERROR)
    return
  end

  M.parsed_config = parse_xcrc()

  if config.options.auto_save then
    vim.cmd("silent! wall")
  end

  local command = build_command(cmd)
  vim.g.xcede_status = status_text

  local buf = get_or_create_terminal()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

  -- Debug: show the command being run
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
    "Running: " .. command,
    "Working directory: " .. vim.fn.getcwd(),
    "Config: scheme=" .. (M.parsed_config.scheme or "none") ..
           ", platform=" .. (M.parsed_config.platform or "none") ..
           ", device=" .. (M.parsed_config.device or "none"),
    "----------------------------------------",
    ""
  })

  show_terminal(buf)

  if M.job_id then
    vim.fn.jobstop(M.job_id)
  end

  -- Use shell to execute command (needed for pipes like xcbeautify)
  M.job_id = vim.fn.jobstart({ "sh", "-c", command }, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      if data then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            local last_line = vim.api.nvim_buf_line_count(buf)
            vim.api.nvim_buf_set_lines(buf, last_line, last_line, false, data)

            if M.terminal_win and vim.api.nvim_win_is_valid(M.terminal_win) then
              vim.api.nvim_win_set_cursor(M.terminal_win, { vim.api.nvim_buf_line_count(buf), 0 })
            end
          end
        end)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            local last_line = vim.api.nvim_buf_line_count(buf)
            vim.api.nvim_buf_set_lines(buf, last_line, last_line, false, data)
          end
        end)
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code == 0 then
          vim.g.xcede_status = "Success"
          if config.options.notify_on_success then
            notify("Build succeeded", vim.log.levels.INFO)
          end
          if config.options.auto_close_terminal then
            hide_terminal()
          end
        else
          vim.g.xcede_status = "Failed"
          if config.options.notify_on_failure then
            notify("Build failed with exit code " .. exit_code, vim.log.levels.ERROR)
          end
        end

        vim.defer_fn(function()
          vim.g.xcede_status = "Idle"
        end, 3000)

        M.job_id = nil
      end)
    end,
  })

  if M.job_id <= 0 then
    vim.g.xcede_status = "Failed"
    notify("Failed to start xcede", vim.log.levels.ERROR)
  end
end

--- Toggle terminal visibility
local function toggle_terminal()
  if M.terminal_win and vim.api.nvim_win_is_valid(M.terminal_win) then
    hide_terminal()
  else
    local buf = get_or_create_terminal()
    show_terminal(buf)
  end
end

--- Stop running job
local function stop_job()
  if M.job_id then
    vim.fn.jobstop(M.job_id)
    M.job_id = nil
    vim.g.xcede_status = "Stopped"
    notify("Stopped xcede job", vim.log.levels.INFO)
  end
end

--- Setup commands
local function setup_commands()
  vim.api.nvim_create_user_command("XcedeBuild", function()
    run_xcede("build", "Building...")
  end, { desc = "Build project with xcede" })

  vim.api.nvim_create_user_command("XcedeRun", function()
    run_xcede("run", "Running...")
  end, { desc = "Run project with xcede" })

  vim.api.nvim_create_user_command("XcedeBuildRun", function()
    run_xcede("buildrun", "Building & Running...")
  end, { desc = "Build and run project with xcede" })

  vim.api.nvim_create_user_command("XcedeTest", function()
    run_xcede("test", "Testing...")
  end, { desc = "Run tests with xcede" })

  vim.api.nvim_create_user_command("XcedeToggleTerminal", function()
    toggle_terminal()
  end, { desc = "Toggle xcede terminal" })

  vim.api.nvim_create_user_command("XcedeStop", function()
    stop_job()
  end, { desc = "Stop running xcede job" })

  vim.api.nvim_create_user_command("XcedeDebug", function()
    M.parsed_config = parse_xcrc()
    local debug_info = {
      "=== xcede.nvim Debug Info ===",
      "",
      "xcede installed: " .. (command_exists("xcede") and "yes" or "NO"),
      "xcbeautify installed: " .. (command_exists("xcbeautify") and "yes" or "no"),
      "Working directory: " .. vim.fn.getcwd(),
      "",
      "Parsed .xcrc config:",
      "  scheme: " .. (M.parsed_config.scheme or "not set"),
      "  platform: " .. (M.parsed_config.platform or "not set"),
      "  device: " .. (M.parsed_config.device or "not set"),
      "",
      "Plugin config:",
      "  terminal_height: " .. tostring(config.options.terminal_height),
      "  auto_save: " .. tostring(config.options.auto_save),
      "  xcbeautify: " .. tostring(config.options.xcbeautify),
      "",
      "Test command would be:",
      "  " .. build_command("build"),
      "",
      "Current status: " .. (vim.g.xcede_status or "unknown"),
      "Job running: " .. (M.job_id and "yes (id: " .. M.job_id .. ")" or "no"),
    }
    print(table.concat(debug_info, "\n"))
  end, { desc = "Show xcede.nvim debug information" })
end

--- Check if current directory is an Xcode/Swift project
--- @return boolean
local function is_xcode_project()
  local cwd = vim.fn.getcwd()

  -- Check for Package.swift
  if vim.fn.filereadable(cwd .. "/Package.swift") == 1 then
    return true
  end

  -- Check for *.xcodeproj
  local xcodeproj = vim.fn.glob(cwd .. "/*.xcodeproj")
  if xcodeproj ~= "" then
    return true
  end

  -- Check for *.xcworkspace
  local xcworkspace = vim.fn.glob(cwd .. "/*.xcworkspace")
  if xcworkspace ~= "" then
    return true
  end

  return false
end

--- Setup keymaps
local function setup_keymaps()
  if not config.options.keymaps then
    return
  end

  -- Only set keymaps if we're in an Xcode/Swift project
  if not is_xcode_project() then
    return
  end

  -- Set global keymaps so they work from any buffer
  local opts = { silent = true, noremap = true }
  local keymaps = config.options.keymaps

  if keymaps.build then
    vim.keymap.set("n", keymaps.build, "<cmd>XcedeBuild<cr>", vim.tbl_extend("force", opts, { desc = "Build Project" }))
  end

  if keymaps.run then
    vim.keymap.set("n", keymaps.run, "<cmd>XcedeRun<cr>", vim.tbl_extend("force", opts, { desc = "Run Project" }))
  end

  if keymaps.buildrun then
    vim.keymap.set("n", keymaps.buildrun, "<cmd>XcedeBuildRun<cr>", vim.tbl_extend("force", opts, { desc = "Build & Run Project" }))
  end

  if keymaps.test then
    vim.keymap.set("n", keymaps.test, "<cmd>XcedeTest<cr>", vim.tbl_extend("force", opts, { desc = "Run Tests" }))
  end

  if keymaps.toggle_terminal then
    vim.keymap.set("n", keymaps.toggle_terminal, "<cmd>XcedeToggleTerminal<cr>", vim.tbl_extend("force", opts, { desc = "Toggle Terminal" }))
  end

  if keymaps.stop then
    vim.keymap.set("n", keymaps.stop, "<cmd>XcedeStop<cr>", vim.tbl_extend("force", opts, { desc = "Stop Build/Run" }))
  end
end

--- Setup syntax highlighting
local function setup_syntax()
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "xcede",
    callback = function()
      vim.cmd([[
        syntax match XcedeError /error:.*/
        syntax match XcedeWarning /warning:.*/
        syntax match XcedeSuccess /Build Succeeded\|BUILD SUCCEEDED\|Test Succeeded/
        syntax match XcedeFailed /Build Failed\|BUILD FAILED\|Test Failed/
        syntax match XcedeInfo /^==.*$/

        highlight default link XcedeError ErrorMsg
        highlight default link XcedeWarning WarningMsg
        highlight default link XcedeSuccess DiffAdd
        highlight default link XcedeFailed DiffDelete
        highlight default link XcedeInfo Comment
      ]])
    end,
  })
end

--- Setup autocmds
local function setup_autocmds()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if M.job_id then
        vim.fn.jobstop(M.job_id)
      end
    end,
  })
end

--- Main setup function
--- @param opts table|nil
function M.setup(opts)
  config.setup(opts)
  setup_commands()
  setup_keymaps()
  setup_syntax()
  setup_autocmds()
end

return M
