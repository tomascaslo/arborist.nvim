local M = {}
local api = vim.api

M._bufnr = nil
M._render_timer = nil

local ns = api.nvim_create_namespace("arborist_session_view")

local function setup_highlights()
  api.nvim_set_hl(0, "ArboristRunning", { fg = "#a6e3a1", default = true })
  api.nvim_set_hl(0, "ArboristWaiting", { fg = "#f9e2af", default = true })
  api.nvim_set_hl(0, "ArboristIdle", { fg = "#6c7086", default = true })
  api.nvim_set_hl(0, "ArboristHeader", { fg = "#cdd6f4", bold = true, default = true })
  api.nvim_set_hl(0, "ArboristSeparator", { fg = "#45475a", default = true })
  api.nvim_set_hl(0, "ArboristDetached", { fg = "#89b4fa", default = true })
  api.nvim_set_hl(0, "ArboristHelp", { fg = "#6c7086", italic = true, default = true })
end

local state_display = {
  running = { text = "Running", icon = "●", hl = "ArboristRunning" },
  waiting = { text = "Waiting for input", icon = "◉", hl = "ArboristWaiting" },
  idle = { text = "Idle", icon = "○", hl = "ArboristIdle" },
  detached = { text = "Detached (resumable)", icon = "◌", hl = "ArboristDetached" },
}

local function get_state_info(state)
  return state_display[state] or state_display.idle
end

-- Header is 3 lines: title, separator, blank
local HEADER_LINES = 3
-- Each session block is 3 lines: icon+branch, state, separator
local BLOCK_LINES = 3

--- Get the session index from the current cursor line.
local function session_idx_at_cursor()
  local line = api.nvim_win_get_cursor(0)[1] -- 1-indexed
  if line <= HEADER_LINES then
    return nil
  end
  local idx = math.floor((line - HEADER_LINES - 1) / BLOCK_LINES) + 1
  local sessions = require("arborist.sessions")
  local all = sessions.get_all()
  if idx >= 1 and idx <= #all then
    return idx, all[idx]
  end
  return nil
end

--- Jump cursor to the first line of the given session index.
local function jump_to_session(idx)
  local line = HEADER_LINES + (idx - 1) * BLOCK_LINES + 1
  local buf_lines = api.nvim_buf_line_count(M._bufnr)
  if line > buf_lines then
    line = buf_lines
  end
  api.nvim_win_set_cursor(0, { line, 0 })
end

function M.render()
  if M._render_timer then
    vim.fn.timer_stop(M._render_timer)
  end
  M._render_timer = vim.fn.timer_start(100, function()
    M._render_timer = nil
    vim.schedule(function()
      M._do_render()
    end)
  end)
end

function M._do_render()
  if not M._bufnr or not api.nvim_buf_is_valid(M._bufnr) then
    return
  end

  local win = vim.fn.bufwinid(M._bufnr)
  if win == -1 then
    return
  end

  local sessions = require("arborist.sessions")
  local all = sessions.get_all()

  local lines = {}
  local highlights = {}

  -- Header
  table.insert(lines, " Arborist Sessions")
  table.insert(highlights, { line = 0, col = 0, end_col = #lines[1], hl = "ArboristHeader" })
  local sep = " " .. string.rep("─", 36)
  table.insert(lines, sep)
  table.insert(highlights, { line = 1, col = 0, end_col = #sep, hl = "ArboristSeparator" })
  table.insert(lines, "")

  if #all == 0 then
    table.insert(lines, "  No active sessions")
  else
    for _, s in ipairs(all) do
      local info = get_state_info(s.state)
      local branch = s.branch or vim.fn.fnamemodify(s.worktree_path, ":t")

      -- Line 1: icon + branch
      local branch_line = " " .. info.icon .. " " .. branch
      table.insert(lines, branch_line)

      -- Line 2: state (indented)
      local state_line = "   " .. info.text
      table.insert(lines, state_line)
      local line_idx = #lines - 1
      table.insert(highlights, {
        line = line_idx,
        col = 0,
        end_col = #state_line,
        hl = info.hl,
      })

      -- Line 3: thin separator
      local thin_sep = " " .. string.rep("·", 36)
      table.insert(lines, thin_sep)
      table.insert(highlights, {
        line = #lines - 1,
        col = 0,
        end_col = #thin_sep,
        hl = "ArboristSeparator",
      })
    end
  end

  api.nvim_set_option_value("modifiable", true, { buf = M._bufnr })
  api.nvim_buf_set_lines(M._bufnr, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = M._bufnr })

  api.nvim_buf_clear_namespace(M._bufnr, ns, 0, -1)
  for _, h in ipairs(highlights) do
    api.nvim_buf_set_extmark(M._bufnr, ns, h.line, h.col, {
      end_col = h.end_col,
      hl_group = h.hl,
    })
  end
end

local function show_help()
  local help_lines = {
    " Arborist Sessions — Help",
    " " .. string.rep("─", 36),
    "",
    "  <CR>       Open / resume session",
    "  <C-n>      Next session",
    "  <C-p>      Previous session",
    "  x          End session",
    "  X          Remove detached session",
    "  r          Refresh",
    "  q          Close view",
    "  ?          Toggle help",
  }

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)
  api.nvim_set_option_value("modifiable", false, { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  local width = 40
  local height = #help_lines
  local ui = api.nvim_list_uis()[1] or {}
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor(((ui.width or 80) - width) / 2),
    row = math.floor(((ui.height or 24) - height) / 2),
    style = "minimal",
    border = "rounded",
  })

  -- Any key closes help
  vim.keymap.set("n", "?", function()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end, { buffer = buf })
  vim.keymap.set("n", "q", function()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end, { buffer = buf })
end

function M._setup_buffer(bufnr)
  api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  api.nvim_set_option_value("filetype", "arborist-sessions", { buf = bufnr })
  api.nvim_buf_set_name(bufnr, "arborist://sessions")

  -- Open session in float, or resume if detached
  vim.keymap.set("n", "<CR>", function()
    local _, session = session_idx_at_cursor()
    if not session then return end
    require("arborist.notifications").clear_for_cwd(session.worktree_path)
    if session.state == "detached" and session.session_id then
      require("arborist.launcher").resume(session)
    else
      require("arborist.launcher").open_task_float(session)
    end
  end, { buffer = bufnr, desc = "Open / resume session" })

  -- Navigate between sessions
  vim.keymap.set("n", "<C-n>", function()
    local sessions = require("arborist.sessions")
    local all = sessions.get_all()
    if #all == 0 then return end
    local idx = session_idx_at_cursor()
    local next_idx = (idx or 0) + 1
    if next_idx > #all then next_idx = 1 end
    jump_to_session(next_idx)
  end, { buffer = bufnr, desc = "Next session" })

  vim.keymap.set("n", "<C-p>", function()
    local sessions = require("arborist.sessions")
    local all = sessions.get_all()
    if #all == 0 then return end
    local idx = session_idx_at_cursor()
    local prev_idx = (idx or 2) - 1
    if prev_idx < 1 then prev_idx = #all end
    jump_to_session(prev_idx)
  end, { buffer = bufnr, desc = "Previous session" })

  -- End session (live or detached)
  vim.keymap.set("n", "x", function()
    local _, session = session_idx_at_cursor()
    if not session then return end
    vim.ui.select({ "Yes", "No" }, {
      prompt = "End session " .. session.name .. "?",
    }, function(choice)
      if choice ~= "Yes" then return end
      local sessions_mod = require("arborist.sessions")
      if session.bufnr and api.nvim_buf_is_valid(session.bufnr) then
        local chan = vim.bo[session.bufnr].channel
        if chan and chan > 0 then
          pcall(vim.fn.jobstop, chan)
        end
        pcall(api.nvim_buf_delete, session.bufnr, { force = true })
        sessions_mod.remove_by_bufnr(session.bufnr)
      elseif session.session_id then
        sessions_mod.remove_by_session_id(session.session_id)
      end
      require("arborist.notifications").clear_for_cwd(session.worktree_path)
    end)
  end, { buffer = bufnr, desc = "End session" })

  -- Remove detached session (no confirmation)
  vim.keymap.set("n", "X", function()
    local _, session = session_idx_at_cursor()
    if not session then return end
    if session.state ~= "detached" then
      vim.notify("Use 'x' to end live sessions", vim.log.levels.INFO)
      return
    end
    local sessions_mod = require("arborist.sessions")
    sessions_mod.remove_by_session_id(session.session_id)
    require("arborist.notifications").clear_for_cwd(session.worktree_path)
  end, { buffer = bufnr, desc = "Remove detached session" })

  -- Help
  vim.keymap.set("n", "?", show_help, { buffer = bufnr, desc = "Show help" })

  -- Close view
  vim.keymap.set("n", "q", function()
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      api.nvim_win_close(win, true)
    end
  end, { buffer = bufnr, desc = "Close session view" })

  -- Refresh
  vim.keymap.set("n", "r", function()
    M._do_render()
  end, { buffer = bufnr, desc = "Refresh session view" })
end

function M.toggle()
  setup_highlights()

  if M._bufnr and api.nvim_buf_is_valid(M._bufnr) then
    local win = vim.fn.bufwinid(M._bufnr)
    if win ~= -1 then
      api.nvim_win_close(win, true)
      return
    end
  end

  if not M._bufnr or not api.nvim_buf_is_valid(M._bufnr) then
    M._bufnr = api.nvim_create_buf(false, true)
    M._setup_buffer(M._bufnr)
  end

  vim.cmd("topleft 40vsplit")
  local win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, M._bufnr)
  api.nvim_set_option_value("winfixwidth", true, { win = win })
  api.nvim_set_option_value("number", false, { win = win })
  api.nvim_set_option_value("relativenumber", false, { win = win })
  api.nvim_set_option_value("signcolumn", "no", { win = win })

  M._do_render()
end

return M
