local M = {}

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
    local sessions = require("arborist.sessions")
    local launcher = require("arborist.launcher")

    local match = sessions.find_by_cwd(entry.cwd)
    if match then
      launcher.open_task_float(match)
    else
      vim.notify("No matching Claude session found for " .. entry.dirname, vim.log.levels.WARN)
    end
  end)
end

function M.clear_for_cwd(cwd)
  M._queue = vim.tbl_filter(function(n)
    return n.cwd ~= cwd
  end, M._queue)
end

return M
