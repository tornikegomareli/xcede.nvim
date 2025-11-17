local config = require("xcede.config")

local M = {
  terminal_buf = nil,
  terminal_win = nil,
  floating_buf = nil,
  floating_win = nil,
  job_id = nil,
  parsed_config = {},
}

vim.g.xcede_status = "Idle"

--- Find project root by searching upwards for Xcode project markers
--- @param start_path string|nil Starting path (defaults to cwd)
--- @return string|nil Project root path or nil if not found
local function find_project_root(start_path)
  start_path = start_path or vim.fn.getcwd()
  local path = start_path

  -- Search upwards for project markers (max 10 levels up)
  local max_depth = 10
  local depth = 0

  while path ~= "/" and depth < max_depth do
    -- Check for Package.swift
    if vim.fn.filereadable(path .. "/Package.swift") == 1 then
      return path
    end

    -- Check for *.xcodeproj
    local xcodeproj = vim.fn.glob(path .. "/*.xcodeproj")
    if xcodeproj ~= "" then
      return path
    end

    -- Check for *.xcworkspace
    local xcworkspace = vim.fn.glob(path .. "/*.xcworkspace")
    if xcworkspace ~= "" then
      return path
    end

    -- Move up one directory
    path = vim.fn.fnamemodify(path, ":h")
    depth = depth + 1
  end

  return nil
end

--- Parse .xcrc config file (searches in project root)
--- @return table config with scheme, platform, device fields
local function parse_xcrc()
  local xcrc_config = {}

  -- Find project root first
  local project_root = find_project_root()
  if not project_root then
    return xcrc_config
  end

  local config_paths = {
    project_root .. "/.xcrc",
    project_root .. "/.zed/xcrc",
  }
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
--- @param use_beautify boolean|nil - Whether to use xcbeautify (default: true)
--- @return string
local function build_command(cmd, use_beautify)
  if use_beautify == nil then
    use_beautify = true
  end

  -- Find project root
  local project_root = find_project_root()

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

  if use_beautify and config.options.xcbeautify and command_exists("xcbeautify") then
    command = "set -o pipefail; " .. command .. " | xcbeautify"
  end

  -- If project root is different from cwd, cd to it first
  if project_root and project_root ~= vim.fn.getcwd() then
    command = string.format("cd %s && %s", vim.fn.shellescape(project_root), command)
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

  -- Window appearance settings
  vim.api.nvim_win_set_option(M.terminal_win, "number", false)
  vim.api.nvim_win_set_option(M.terminal_win, "relativenumber", false)
  vim.api.nvim_win_set_option(M.terminal_win, "signcolumn", "no")
  vim.api.nvim_win_set_option(M.terminal_win, "cursorline", false)
  vim.api.nvim_win_set_option(M.terminal_win, "wrap", true)

  -- Add colorful border
  vim.api.nvim_win_set_option(M.terminal_win, "winhl", "Normal:XcedeTerminal,NormalNC:XcedeTerminal")

  -- Set border with title
  if vim.fn.has('nvim-0.9') == 1 then
    vim.api.nvim_win_set_config(M.terminal_win, {
      border = "rounded",
      title = " Xcode Output ",
      title_pos = "center",
    })
  end

  vim.cmd("wincmd p")
end

--- Hide terminal window
local function hide_terminal()
  if M.terminal_win and vim.api.nvim_win_is_valid(M.terminal_win) then
    vim.api.nvim_win_close(M.terminal_win, true)
    M.terminal_win = nil
  end
end

--- Close floating window
local function close_floating()
  if M.job_id then
    vim.fn.jobstop(M.job_id)
    M.job_id = nil
  end

  if M.floating_win and vim.api.nvim_win_is_valid(M.floating_win) then
    vim.api.nvim_win_close(M.floating_win, true)
  end

  if M.floating_buf and vim.api.nvim_buf_is_valid(M.floating_buf) then
    vim.api.nvim_buf_delete(M.floating_buf, { force = true })
  end

  M.floating_win = nil
  M.floating_buf = nil
end

--- Create floating window
--- @param title string
--- @return number buffer number
local function create_floating_window(title)
  close_floating()

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })

  M.floating_buf = buf
  M.floating_win = win

  vim.api.nvim_buf_set_option(buf, "filetype", "xcede")
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_win_set_option(win, "winblend", 0)
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)
  vim.api.nvim_win_set_option(win, "cursorline", false)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

  -- Keybindings to close floating window
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
    callback = function()
      close_floating()
    end,
    noremap = true,
    silent = true,
  })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "", {
    callback = function()
      close_floating()
    end,
    noremap = true,
    silent = true,
  })

  return buf
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

--- Show progress notification
--- @param key string - Unique key for this progress
--- @param message string - Progress message
--- @return table|nil - Progress handle (fidget) or nil
local function show_progress(key, message)
  if config.options.use_fidget and pcall(require, "fidget") then
    local fidget = require("fidget")
    return fidget.progress.handle.create({
      title = "Xcode",
      message = message,
      lsp_client = { name = "xcede" },
    })
  else
    vim.notify(message, vim.log.levels.INFO)
    return nil
  end
end

--- Update progress notification
--- @param handle table|nil - Progress handle
--- @param message string - New message
local function update_progress(handle, message)
  if handle and handle.message then
    handle.message = message
  end
end

--- Finish progress notification
--- @param handle table|nil - Progress handle
--- @param message string|nil - Final message
local function finish_progress(handle, message)
  if handle and handle.finish then
    handle:finish()
  end
  if message then
    notify(message, vim.log.levels.INFO)
  end
end

--- Run xcede command in floating window
--- @param cmd string
--- @param status_text string
--- @param title string
local function run_xcede_floating(cmd, status_text, title)
  if not command_exists("xcede") then
    notify("xcede is not installed. Install it from: https://github.com/XcodeClub/xcede", vim.log.levels.ERROR)
    return
  end

  M.parsed_config = parse_xcrc()

  if config.options.auto_save then
    vim.cmd("silent! wall")
  end

  -- Disable xcbeautify for floating window to show full error details
  local command = build_command(cmd, false)
  vim.g.xcede_status = status_text

  -- Show progress indicator
  local progress = show_progress("xcede_build", "Building project...")

  local buf = create_floating_window(title)

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
    "Command: " .. command,
    "Working directory: " .. vim.fn.getcwd(),
    "Config: scheme=" .. (M.parsed_config.scheme or "none") ..
           ", platform=" .. (M.parsed_config.platform or "none") ..
           ", device=" .. (M.parsed_config.device or "none"),
    "────────────────────────────────────────────────────────",
    "",
  })

  local start_time = vim.loop.hrtime()

  M.job_id = vim.fn.jobstart({ "sh", "-c", command }, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      if data then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            local last_line = vim.api.nvim_buf_line_count(buf)
            vim.api.nvim_buf_set_lines(buf, last_line, last_line, false, data)

            if M.floating_win and vim.api.nvim_win_is_valid(M.floating_win) then
              vim.api.nvim_win_set_cursor(M.floating_win, { vim.api.nvim_buf_line_count(buf), 0 })
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
        local end_time = vim.loop.hrtime()
        local elapsed = (end_time - start_time) / 1e9

        vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
          "",
          "────────────────────────────────────────────────────────",
        })

        if exit_code == 0 then
          vim.g.xcede_status = "Success"
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
            "✓ " .. title .. " completed successfully",
            "Time: " .. string.format("%.3fs", elapsed),
            "────────────────────────────────────────────────────────",
          })
          finish_progress(progress, "Build succeeded in " .. string.format("%.1fs", elapsed))
          if config.options.notify_on_success then
            notify(title .. " succeeded in " .. string.format("%.3fs", elapsed), vim.log.levels.INFO)
          end
          -- Auto-close on success
          vim.defer_fn(function()
            close_floating()
          end, 1500)
        else
          vim.g.xcede_status = "Failed"
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
            "✗ " .. title .. " failed with exit code: " .. exit_code,
            "Time: " .. string.format("%.3fs", elapsed),
            "────────────────────────────────────────────────────────",
            "",
            "Press 'q' or <Esc> to close this window",
          })
          finish_progress(progress, nil)
          if config.options.notify_on_failure then
            notify(title .. " failed with exit code: " .. exit_code, vim.log.levels.ERROR)
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
    close_floating()
  end
end

--- Clean carriage returns from output lines
--- @param data table
--- @return table
local function clean_output(data)
  if not data then return data end
  local cleaned = {}
  for _, line in ipairs(data) do
    if line and line ~= "" then
      -- Remove carriage return characters
      local cleaned_line = line:gsub("\r", "")
      table.insert(cleaned, cleaned_line)
    end
  end
  return cleaned
end

--- Run xcede command
--- @param cmd string
--- @param status_text string
--- @param use_beautify boolean|nil - Whether to use xcbeautify (default: true)
local function run_xcede(cmd, status_text, use_beautify)
  if not command_exists("xcede") then
    notify("xcede is not installed. Install it from: https://github.com/XcodeClub/xcede", vim.log.levels.ERROR)
    return
  end

  M.parsed_config = parse_xcrc()

  if config.options.auto_save then
    vim.cmd("silent! wall")
  end

  local command = build_command(cmd, use_beautify)
  vim.g.xcede_status = status_text

  -- Show progress indicator based on command type
  local progress_msg = cmd == "run" and "Launching app..." or "Building & Running..."
  local progress = show_progress("xcede_run", progress_msg)

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

  -- Add keybindings to stop and close terminal
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
    callback = function()
      if M.job_id then
        vim.fn.jobstop(M.job_id)
        M.job_id = nil
        vim.g.xcede_status = "Stopped"
        notify("Stopped app", vim.log.levels.INFO)
      end
      hide_terminal()
    end,
    noremap = true,
    silent = true,
    desc = "Stop app and close terminal"
  })

  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "", {
    callback = function()
      if M.job_id then
        vim.fn.jobstop(M.job_id)
        M.job_id = nil
        vim.g.xcede_status = "Stopped"
        notify("Stopped app", vim.log.levels.INFO)
      end
      hide_terminal()
    end,
    noremap = true,
    silent = true,
    desc = "Stop app and close terminal"
  })

  if M.job_id then
    vim.fn.jobstop(M.job_id)
  end

  local app_launched = false

  -- Use shell to execute command (needed for pipes like xcbeautify)
  M.job_id = vim.fn.jobstart({ "sh", "-c", command }, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      if data then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            local cleaned_data = clean_output(data)
            if #cleaned_data > 0 then
              local last_line = vim.api.nvim_buf_line_count(buf)
              vim.api.nvim_buf_set_lines(buf, last_line, last_line, false, cleaned_data)

              -- Detect when app is launched (look for common launch indicators)
              if not app_launched and cmd == "run" or cmd == "buildrun" then
                for _, line in ipairs(cleaned_data) do
                  if line:match("Launched") or line:match("Running") or line:match("%[InstantDB%]") then
                    app_launched = true
                    update_progress(progress, "App is running...")
                    break
                  end
                end
              end

              if M.terminal_win and vim.api.nvim_win_is_valid(M.terminal_win) then
                vim.api.nvim_win_set_cursor(M.terminal_win, { vim.api.nvim_buf_line_count(buf), 0 })
              end
            end
          end
        end)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            local cleaned_data = clean_output(data)
            if #cleaned_data > 0 then
              local last_line = vim.api.nvim_buf_line_count(buf)
              vim.api.nvim_buf_set_lines(buf, last_line, last_line, false, cleaned_data)
            end
          end
        end)
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        -- Add final message to buffer
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
            "",
            "----------------------------------------",
          })
        end

        if exit_code == 0 then
          vim.g.xcede_status = "Success"

          -- Add completion message to buffer
          if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
              "App stopped (exit code: 0)",
              "",
              "Press 'q' or <Esc> to close this window",
            })
          end

          finish_progress(progress, "App stopped")

          -- For run commands, auto-close terminal after app stops
          if cmd == "run" or cmd == "buildrun" then
            notify("App stopped", vim.log.levels.INFO)
            -- Auto-close after 2 seconds
            vim.defer_fn(function()
              hide_terminal()
            end, 2000)
          else
            if config.options.notify_on_success then
              notify("Build succeeded", vim.log.levels.INFO)
            end
            if config.options.auto_close_terminal then
              hide_terminal()
            end
          end
        else
          vim.g.xcede_status = "Failed"

          -- Add error message to buffer
          if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
              "App crashed or failed (exit code: " .. exit_code .. ")",
              "",
              "Press 'q' or <Esc> to close this window",
            })
          end

          finish_progress(progress, nil)
          if config.options.notify_on_failure then
            notify("App failed with exit code " .. exit_code, vim.log.levels.ERROR)
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
    if config.options.use_floating_for_build then
      run_xcede_floating("build", "Building...", "Xcode Build")
    else
      run_xcede("build", "Building...")
    end
  end, { desc = "Build project with xcede" })

  vim.api.nvim_create_user_command("XcedeRun", function()
    -- Disable xcbeautify for run to see app logs (print statements, etc.)
    run_xcede("run", "Running...", false)
  end, { desc = "Run project with xcede" })

  vim.api.nvim_create_user_command("XcedeBuildRun", function()
    -- Disable xcbeautify for buildrun to see app logs
    run_xcede("buildrun", "Building & Running...", false)
  end, { desc = "Build and run project with xcede" })

  vim.api.nvim_create_user_command("XcedeTest", function()
    if config.options.use_floating_for_build then
      run_xcede_floating("test", "Testing...", "Xcode Test")
    else
      run_xcede("test", "Testing...")
    end
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
  return find_project_root() ~= nil
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
  -- Define highlight groups for terminal appearance
  vim.api.nvim_create_autocmd("ColorScheme", {
    pattern = "*",
    callback = function()
      -- Terminal background with subtle tint
      vim.api.nvim_set_hl(0, "XcedeTerminal", {
        bg = "#1a1f2e",  -- Slightly blue-tinted dark background
        fg = "#c0caf5",  -- Soft white for text
      })

      -- Border colors
      vim.api.nvim_set_hl(0, "XcedeBorder", {
        fg = "#7aa2f7",  -- Blue border
      })
    end,
  })

  -- Trigger once on setup
  vim.api.nvim_set_hl(0, "XcedeTerminal", {
    bg = "#1a1f2e",
    fg = "#c0caf5",
  })
  vim.api.nvim_set_hl(0, "XcedeBorder", {
    fg = "#7aa2f7",
  })

  -- Syntax highlighting for xcede filetype
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "xcede",
    callback = function()
      vim.cmd([[
        " Errors and warnings
        syntax match XcedeError /error:.*/
        syntax match XcedeWarning /warning:.*/

        " Build status
        syntax match XcedeSuccess /Build Succeeded\|BUILD SUCCEEDED\|Test Succeeded\|✓.*/
        syntax match XcedeFailed /Build Failed\|BUILD FAILED\|Test Failed\|✗.*/

        " Info and separators
        syntax match XcedeInfo /^==.*$/
        syntax match XcedeSeparator /^-\+$\|^─\+$/
        syntax match XcedeHeader /^Running:\|^Command:\|^Working directory:\|^Config:/

        " InstantDB logs
        syntax match XcedeInstantDB /\[InstantDB\].*/
        syntax match XcedeSuccess /\[InstantDB\] ✓.*/
        syntax match XcedeInfo /\[InstantDB\] ←.*/
        syntax match XcedeDebug /\[InstantDB\] DEBUG.*/

        " File paths
        syntax match XcedeFilePath /\/.*\.swift:\d\+:\d\+/

        " Highlights
        highlight default XcedeError guifg=#f7768e gui=bold
        highlight default XcedeWarning guifg=#e0af68 gui=bold
        highlight default XcedeSuccess guifg=#9ece6a gui=bold
        highlight default XcedeFailed guifg=#f7768e gui=bold
        highlight default XcedeInfo guifg=#7aa2f7
        highlight default XcedeSeparator guifg=#414868
        highlight default XcedeHeader guifg=#bb9af7 gui=bold
        highlight default XcedeInstantDB guifg=#7dcfff
        highlight default XcedeDebug guifg=#565f89
        highlight default XcedeFilePath guifg=#ff9e64 gui=underline
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
