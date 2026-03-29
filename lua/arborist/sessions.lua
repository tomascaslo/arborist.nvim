local M = {}

M._sessions = {}

local function persist_path()
  return vim.fn.stdpath("data") .. "/arborist/sessions.json"
end

local function should_persist()
  local ok, config = pcall(require, "arborist.config")
  if not ok then return false end
  local cfg = config.get()
  return cfg.persist_sessions
end

--- Write current sessions to disk (atomic write).
function M._persist()
  if not should_persist() then return end

  local entries = {}
  for _, s in ipairs(M._sessions) do
    if s.session_id and s.session_id ~= "" then
      table.insert(entries, {
        name = s.name,
        session_id = s.session_id,
        worktree_path = s.worktree_path,
        branch = s.branch,
        state = s.state,
        last_updated = s.last_updated,
      })
    end
  end

  local dir = vim.fn.stdpath("data") .. "/arborist"
  vim.fn.mkdir(dir, "p")

  local path = persist_path()
  local tmp = path .. ".tmp"
  local json = vim.json.encode(entries)
  vim.fn.writefile({ json }, tmp)
  vim.uv.fs_rename(tmp, path)
end

--- Load persisted sessions from disk. Marks them as "detached" (no bufnr).
function M.load_persisted()
  local path = persist_path()
  local ok_read, content = pcall(vim.fn.readfile, path)
  if not ok_read or #content == 0 then return end

  local ok, entries = pcall(vim.json.decode, table.concat(content, "\n"))
  if not ok or type(entries) ~= "table" then return end

  local config = require("arborist.config").get()
  local now = os.time()
  local timeout = config.session_timeout

  for _, e in ipairs(entries) do
    -- Skip if already tracked (same session_id)
    if e.session_id and not M.find_by_session_id(e.session_id) then
      -- Skip stale sessions
      local age = now - (e.last_updated or 0)
      if age < timeout then
        table.insert(M._sessions, {
          name = e.name,
          session_id = e.session_id,
          worktree_path = e.worktree_path,
          branch = e.branch,
          state = "detached",
          last_updated = e.last_updated,
          bufnr = nil, -- no terminal buffer
        })
      end
    end
  end

  M._notify_view()
end

--- Remove stale sessions older than timeout and persist.
function M.cleanup()
  local config = require("arborist.config").get()
  local now = os.time()
  local timeout = config.session_timeout
  local removed = 0

  M._sessions = vim.tbl_filter(function(s)
    -- Keep sessions with live buffers
    if s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) then
      return true
    end
    -- For detached sessions, check age
    local age = now - (s.last_updated or 0)
    if age >= timeout then
      removed = removed + 1
      return false
    end
    return true
  end, M._sessions)

  M._persist()
  M._notify_view()
  vim.notify(
    string.format("Cleaned up %d stale session(s)", removed),
    vim.log.levels.INFO,
    { title = "arborist.nvim" }
  )
end

function M.add(session)
  session.state = session.state or "running"
  session.last_updated = os.time()
  table.insert(M._sessions, session)
  M._persist()
  M._notify_view()
end

function M.remove_by_bufnr(bufnr)
  for i, s in ipairs(M._sessions) do
    if s.bufnr == bufnr then
      table.remove(M._sessions, i)
      M._persist()
      M._notify_view()
      return
    end
  end
end

function M.remove_by_session_id(sid)
  for i, s in ipairs(M._sessions) do
    if s.session_id == sid then
      table.remove(M._sessions, i)
      M._persist()
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
  local dirname = vim.fn.fnamemodify(cwd, ":t")
  for _, s in ipairs(M._sessions) do
    if s.name == "claude:" .. dirname then
      return s
    end
  end
  return nil
end

function M.find_by_session_id(sid)
  if not sid or sid == "" then return nil end
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
  if session_id and session_id ~= "" and not session.session_id then
    session.session_id = session_id
  end
  session.state = state
  session.last_updated = os.time()
  M._persist()
  M._notify_view()
end

function M.get_all()
  -- Prune live sessions with dead buffers (mark as detached if they have session_id)
  local pruned = {}
  for _, s in ipairs(M._sessions) do
    if s.bufnr and not vim.api.nvim_buf_is_valid(s.bufnr) then
      -- Buffer died — keep as detached if we have a session_id
      if s.session_id and s.session_id ~= "" then
        s.bufnr = nil
        s.state = "detached"
        table.insert(pruned, s)
      end
    else
      table.insert(pruned, s)
    end
  end
  M._sessions = pruned
  return M._sessions
end

function M.get_active_count()
  return #M.get_all()
end

function M._notify_view()
  local ok, view = pcall(require, "arborist.session_view")
  if ok and view.render then
    view.render()
  end
end

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

  _G._arborist_hook_session_start = function(cwd, session_id, source)
    vim.schedule(function()
      local session = M.find_by_session_id(session_id) or M.find_by_cwd(cwd)
      if session then
        -- Bind session_id and mark running
        if session_id and session_id ~= "" then
          session.session_id = session_id
        end
        session.state = "running"
        session.last_updated = os.time()
        M._persist()
        M._notify_view()
      end
    end)
  end

  _G._arborist_hook_session_end = function(cwd, session_id)
    vim.schedule(function()
      local session = M.find_by_session_id(session_id) or M.find_by_cwd(cwd)
      if session then
        -- If it has a live buffer, remove it fully (terminal is done)
        if session.bufnr and vim.api.nvim_buf_is_valid(session.bufnr) then
          M.remove_by_bufnr(session.bufnr)
        else
          M.remove_by_session_id(session_id)
        end
      end
    end)
  end
end

return M
