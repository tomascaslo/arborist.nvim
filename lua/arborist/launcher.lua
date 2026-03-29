local M = {}
local api = vim.api

--- Build the claude command args from config + params.
local function build_cmd(prompt)
  local ok, config_mod = pcall(require, "arborist.config")
  local cfg = ok and config_mod.get() or {}
  local claude = cfg.claude or {}

  local cmd = { "claude" }
  if claude.model then
    table.insert(cmd, "--model")
    table.insert(cmd, claude.model)
  end
  if claude.effort then
    table.insert(cmd, "--effort")
    table.insert(cmd, claude.effort)
  end
  for _, tool in ipairs(claude.allowed_tools or {}) do
    table.insert(cmd, "--allowedTools")
    table.insert(cmd, tool)
  end
  for _, tool in ipairs(claude.disallowed_tools or {}) do
    table.insert(cmd, "--disallowedTools")
    table.insert(cmd, tool)
  end

  local arborist = require("arborist")
  if arborist.settings_path then
    table.insert(cmd, "--settings")
    table.insert(cmd, arborist.settings_path)
  end

  if prompt and prompt ~= "" then
    table.insert(cmd, prompt)
  end

  return cmd
end

--- Create a centered float window with a new buffer.
local function create_float(title)
  local config = require("arborist.config").get()
  local ui = api.nvim_list_uis()[1] or {}
  local width = math.floor((ui.width or 80) * (config.float.width or 0.85))
  local height = math.floor((ui.height or 24) * (config.float.height or 0.8))

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor(((ui.width or 80) - width) / 2),
    row = math.floor(((ui.height or 24) - height) / 2),
    style = "minimal",
    border = config.float.border or "rounded",
  }
  if title then
    win_opts.title = " " .. title .. " "
    win_opts.title_pos = "center"
  end

  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, win_opts)

  return buf, win
end

--- Set up close keybinding on a float buffer/window.
local function setup_close_key(bufnr, win)
  local config = require("arborist.config").get()
  for _, mode in ipairs({ "n", "t" }) do
    vim.keymap.set(mode, config.keys.close_float, function()
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
      end
    end, { buffer = bufnr, desc = "Close Claude float" })
  end
end

--- Open a tracked session's float. Used by pick_instance and notifications.
function M.open_task_float(session)
  if not session or not session.bufnr or not api.nvim_buf_is_valid(session.bufnr) then
    vim.notify("Session buffer no longer valid", vim.log.levels.WARN)
    return
  end

  local title = session.branch or session.name
  local _, win = create_float(title)
  api.nvim_win_set_buf(win, session.bufnr)
  setup_close_key(session.bufnr, win)
  vim.cmd("startinsert")
end

function M.launch(branch, worktree_path, prompt)
  local sessions = require("arborist.sessions")
  local title = branch or vim.fn.fnamemodify(worktree_path or vim.fn.getcwd(), ":t")
  local buf, win = create_float(title)
  local cmd = build_cmd(prompt)
  local cwd = worktree_path or vim.fn.getcwd()

  vim.fn.termopen(cmd, {
    cwd = cwd,
    on_exit = function()
      sessions.remove_by_bufnr(buf)
    end,
  })

  setup_close_key(buf, win)
  vim.cmd("startinsert")

  sessions.add({
    name = "claude:" .. (branch or vim.fn.fnamemodify(cwd, ":t")),
    bufnr = buf,
    worktree_path = cwd,
    branch = branch,
    state = "running",
  })
end

--- Resume a detached session by launching claude --resume <session_id>.
function M.resume(session)
  if not session or not session.session_id then
    vim.notify("No session ID to resume", vim.log.levels.WARN)
    return
  end

  local sessions_mod = require("arborist.sessions")
  local title = session.branch or session.name
  local buf, win = create_float(title)
  local cwd = session.worktree_path or vim.fn.getcwd()

  -- Build resume command with settings
  local cmd = { "claude", "--resume", session.session_id }
  local arborist = require("arborist")
  if arborist.settings_path then
    table.insert(cmd, "--settings")
    table.insert(cmd, arborist.settings_path)
  end

  vim.fn.termopen(cmd, {
    cwd = cwd,
    on_exit = function()
      sessions_mod.remove_by_bufnr(buf)
    end,
  })

  setup_close_key(buf, win)
  vim.cmd("startinsert")

  -- Update the existing session entry with the new buffer
  session.bufnr = buf
  session.state = "running"
  session.last_updated = os.time()
  sessions_mod._persist()
  sessions_mod._notify_view()
end

function M.pick_instance()
  local sessions = require("arborist.sessions")
  local all = sessions.get_all()

  if #all == 0 then
    vim.notify("No running Claude instances", vim.log.levels.INFO)
    return
  end

  vim.ui.select(all, {
    prompt = "Claude instances:",
    format_item = function(s)
      local state = s.state or "idle"
      return s.name .. "  [" .. state .. "]"
    end,
  }, function(session)
    if not session then
      return
    end
    M.open_task_float(session)
  end)
end

return M
