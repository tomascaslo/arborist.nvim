local M = {}
local api = vim.api

M._bufnr = nil
M._render_timer = nil

local ns = api.nvim_create_namespace("arborist_session_view")

-- Highlight groups
local function setup_highlights()
  api.nvim_set_hl(0, "ArboristRunning", { fg = "#a6e3a1", default = true })
  api.nvim_set_hl(0, "ArboristWaiting", { fg = "#f9e2af", default = true })
  api.nvim_set_hl(0, "ArboristIdle", { fg = "#6c7086", default = true })
  api.nvim_set_hl(0, "ArboristHeader", { fg = "#cdd6f4", bold = true, default = true })
  api.nvim_set_hl(0, "ArboristSeparator", { fg = "#45475a", default = true })
end

local state_display = {
  running = { text = "Running", icon = "●", hl = "ArboristRunning" },
  waiting = { text = "Waiting for input", icon = "◉", hl = "ArboristWaiting" },
  idle = { text = "Idle", icon = "○", hl = "ArboristIdle" },
}

local function get_state_info(state)
  return state_display[state] or state_display.idle
end

function M.render()
  -- Debounce: coalesce rapid state changes
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

  -- Check if the buffer is visible in any window
  local win = vim.fn.bufwinid(M._bufnr)
  if win == -1 then
    return
  end

  local sessions = require("arborist.sessions")
  local all = sessions.get_all()

  local lines = {}
  local highlights = {}

  table.insert(lines, " Arborist Sessions")
  table.insert(highlights, { line = 0, col = 0, end_col = #lines[1], hl = "ArboristHeader" })

  local sep = " " .. string.rep("─", 36)
  table.insert(lines, sep)
  table.insert(highlights, { line = 1, col = 0, end_col = #sep, hl = "ArboristSeparator" })

  if #all == 0 then
    table.insert(lines, "")
    table.insert(lines, "  No active sessions")
  else
    for i, s in ipairs(all) do
      local info = get_state_info(s.state)
      local branch = s.branch or vim.fn.fnamemodify(s.worktree_path, ":t")
      local line = string.format(" %s %-20s %s", info.icon, branch, info.text)
      table.insert(lines, line)
      -- Highlight the state portion
      local state_start = #line - #info.text
      table.insert(highlights, {
        line = i + 1, -- offset for header + separator
        col = state_start,
        end_col = #line,
        hl = info.hl,
      })
    end
  end

  api.nvim_set_option_value("modifiable", true, { buf = M._bufnr })
  api.nvim_buf_set_lines(M._bufnr, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = M._bufnr })

  -- Apply highlights
  api.nvim_buf_clear_namespace(M._bufnr, ns, 0, -1)
  for _, h in ipairs(highlights) do
    api.nvim_buf_set_extmark(M._bufnr, ns, h.line, h.col, {
      end_col = h.end_col,
      hl_group = h.hl,
    })
  end
end

function M._setup_buffer(bufnr)
  api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  api.nvim_set_option_value("filetype", "arborist-sessions", { buf = bufnr })
  api.nvim_buf_set_name(bufnr, "arborist://sessions")

  -- Keymaps
  vim.keymap.set("n", "<CR>", function()
    local line = api.nvim_win_get_cursor(0)[1]
    local sessions = require("arborist.sessions")
    local all = sessions.get_all()
    local idx = line - 2 -- offset for header + separator
    if idx >= 1 and idx <= #all then
      require("arborist.launcher").open_task_float(all[idx])
    end
  end, { buffer = bufnr, desc = "Open session float" })

  vim.keymap.set("n", "q", function()
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      api.nvim_win_close(win, true)
    end
  end, { buffer = bufnr, desc = "Close session view" })

  vim.keymap.set("n", "r", function()
    M._do_render()
  end, { buffer = bufnr, desc = "Refresh session view" })
end

function M.toggle()
  setup_highlights()

  -- If buffer exists and is visible, close it
  if M._bufnr and api.nvim_buf_is_valid(M._bufnr) then
    local win = vim.fn.bufwinid(M._bufnr)
    if win ~= -1 then
      api.nvim_win_close(win, true)
      return
    end
  end

  -- Create or reuse buffer
  if not M._bufnr or not api.nvim_buf_is_valid(M._bufnr) then
    M._bufnr = api.nvim_create_buf(false, true)
    M._setup_buffer(M._bufnr)
  end

  -- Open as a left vertical split
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
