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
  vim.notify(
    string.format("Claude waiting [%s] (%d pending)", dirname, count),
    vim.log.levels.INFO,
    { title = "arborist.nvim" }
  )
end

local function open_task_float(task)
  local config = require("arborist.config").get()
  local overseer = require("overseer")

  overseer.run_action(task, "open float")
  vim.defer_fn(function()
    local bufnr = task:get_bufnr()
    if bufnr and api.nvim_buf_is_valid(bufnr) then
      for _, mode in ipairs({ "n", "t" }) do
        vim.keymap.set(mode, config.keys.close_float, function()
          local win = vim.fn.bufwinid(bufnr)
          if win ~= -1 then
            api.nvim_win_close(win, true)
          end
        end, { buffer = bufnr, desc = "Close Claude float" })
      end
    end
    vim.cmd("startinsert")
  end, 100)
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
