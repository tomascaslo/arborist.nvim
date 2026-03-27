local M = {}
local api = vim.api

M._queue = {}

function M.push(cwd, session_id)
  local dirname = vim.fn.fnamemodify(cwd, ":t")
  table.insert(M._queue, {
    cwd = cwd,
    dirname = dirname,
    session_id = session_id,
    time = os.date("%H:%M:%S"),
  })
  local count = #M._queue
  local config = require("arborist.config").get()
  vim.notify(
    string.format("Claude waiting [%s] (%d pending)", dirname, count),
    vim.log.levels.INFO,
    { title = "arborist.nvim", timeout = config.notification_timeout }
  )
end

local function open_task_float(task)
  require("arborist.launcher").open_task_float(task)
end

function M.open_queue()
  if #M._queue == 0 then
    vim.notify("No pending Claude notifications", vim.log.levels.INFO)
    return
  end

  local items = {}
  for i, n in ipairs(M._queue) do
    items[i] = string.format("[%s] %s", n.time, n.dirname)
  end

  vim.ui.select(items, {
    prompt = "Claude notifications (" .. #M._queue .. " pending):",
  }, function(_, idx)
    if not idx then
      return
    end

    local entry = table.remove(M._queue, idx)
    local overseer = require("overseer")
    local tasks = overseer.list_tasks({ status = "RUNNING" })

    -- Match by worktree_path metadata
    local match = nil
    for _, t in ipairs(tasks) do
      if t.name:match("^claude:") and t.metadata and t.metadata.worktree_path == entry.cwd then
        match = t
        break
      end
    end

    -- Fallback: match by dirname in task name
    if not match then
      for _, t in ipairs(tasks) do
        if t.name == "claude:" .. entry.dirname then
          match = t
          break
        end
      end
    end

    if match then
      open_task_float(match)
    else
      vim.notify("No matching Claude task found for " .. entry.dirname, vim.log.levels.WARN)
    end
  end)
end

function M.setup_global()
  _G._claude_push_notification = function(cwd, session_id)
    vim.schedule(function()
      M.push(cwd, session_id)
    end)
  end
end

return M
