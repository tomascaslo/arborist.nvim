local M = {}

M._sessions = {}

function M.add(session)
  session.state = session.state or "running"
  session.last_updated = os.time()
  table.insert(M._sessions, session)
  M._notify_view()
end

function M.remove_by_bufnr(bufnr)
  for i, s in ipairs(M._sessions) do
    if s.bufnr == bufnr then
      table.remove(M._sessions, i)
      M._notify_view()
      return
    end
  end
end

function M.find_by_cwd(cwd)
  for _, s in ipairs(M._sessions) do
    if s.worktree_path == cwd then
      return s
    end
  end
  -- Fallback: match by dirname
  local dirname = vim.fn.fnamemodify(cwd, ":t")
  for _, s in ipairs(M._sessions) do
    if s.name == "claude:" .. dirname then
      return s
    end
  end
  return nil
end

function M.find_by_session_id(sid)
  for _, s in ipairs(M._sessions) do
    if s.session_id == sid then
      return s
    end
  end
  return nil
end

function M.set_state(cwd, session_id, state)
  local session = M.find_by_session_id(session_id) or M.find_by_cwd(cwd)
  if not session then
    return
  end
  -- Bind session_id on first hook callback
  if session_id and session_id ~= "" and not session.session_id then
    session.session_id = session_id
  end
  session.state = state
  session.last_updated = os.time()
  M._notify_view()
end

function M.get_all()
  -- Prune invalid buffers
  M._sessions = vim.tbl_filter(function(s)
    return s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr)
  end, M._sessions)
  return M._sessions
end

function M.get_active_count()
  return #M.get_all()
end

--- Trigger session view re-render if visible.
function M._notify_view()
  local ok, view = pcall(require, "arborist.session_view")
  if ok and view.render then
    view.render()
  end
end

--- Register global functions called by the hook handler via nvim --remote-expr.
function M.setup_globals()
  _G._arborist_hook_stop = function(cwd, session_id)
    vim.schedule(function()
      M.set_state(cwd, session_id, "waiting")
      require("arborist.notifications").push(cwd, session_id)
    end)
  end

  _G._arborist_hook_post_tool_use = function(cwd, session_id, tool_name)
    vim.schedule(function()
      M.set_state(cwd, session_id, "running")
      if tool_name == "Edit" or tool_name == "Write" or tool_name == "MultiEdit" then
        vim.cmd("checktime")
      end
    end)
  end

  _G._arborist_hook_notification = function(cwd, session_id, message, title)
    vim.schedule(function()
      local config = require("arborist.config").get()
      vim.notify(
        message or "Claude notification",
        vim.log.levels.INFO,
        { title = title or "arborist.nvim", timeout = config.notification_timeout }
      )
    end)
  end
end

return M
