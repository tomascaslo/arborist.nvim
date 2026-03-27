local M = {}
local api = vim.api

--- Build the claude command args from config + params.
local function build_cmd(prompt, worktree)
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
local function create_float()
  local config = require("arborist.config").get()
  local ui = api.nvim_list_uis()[1] or {}
  local width = math.floor((ui.width or 80) * (config.float.width or 0.6))
  local height = math.floor((ui.height or 24) * (config.float.height or 0.4))

  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor(((ui.width or 80) - width) / 2),
    row = math.floor(((ui.height or 24) - height) / 2),
    style = "minimal",
    border = config.float.border or "rounded",
  })

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

-- Track running Claude sessions for pick_instance and notifications
M._sessions = {}

--- Open a tracked session's float. Used by pick_instance and notifications.
function M.open_task_float(session)
  if not session or not session.bufnr or not api.nvim_buf_is_valid(session.bufnr) then
    vim.notify("Session buffer no longer valid", vim.log.levels.WARN)
    return
  end

  local _, win = create_float()
  api.nvim_win_set_buf(win, session.bufnr)
  setup_close_key(session.bufnr, win)
  vim.cmd("startinsert")
end

function M.launch(branch, worktree_path, prompt)
  local buf, win = create_float()
  local cmd = build_cmd(prompt, worktree_path)

  local cwd = worktree_path or vim.fn.getcwd()

  vim.fn.termopen(cmd, {
    cwd = cwd,
    on_exit = function()
      -- Clean up session tracking
      for i, s in ipairs(M._sessions) do
        if s.bufnr == buf then
          table.remove(M._sessions, i)
          break
        end
      end
    end,
  })

  setup_close_key(buf, win)
  vim.cmd("startinsert")

  local session = {
    name = "claude:" .. (branch or vim.fn.fnamemodify(cwd, ":t")),
    bufnr = buf,
    worktree_path = cwd,
    branch = branch,
  }
  table.insert(M._sessions, session)
end

function M.pick_instance()
  -- Filter to sessions with valid buffers
  M._sessions = vim.tbl_filter(function(s)
    return s.bufnr and api.nvim_buf_is_valid(s.bufnr)
  end, M._sessions)

  if #M._sessions == 0 then
    vim.notify("No running Claude instances", vim.log.levels.INFO)
    return
  end

  vim.ui.select(M._sessions, {
    prompt = "Claude instances:",
    format_item = function(s)
      return s.name
    end,
  }, function(session)
    if not session then
      return
    end
    M.open_task_float(session)
  end)
end

return M
