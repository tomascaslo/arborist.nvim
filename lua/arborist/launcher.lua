local M = {}
local api = vim.api

--- Open a task's terminal buffer in a float window using arborist's float config.
local function open_task_float(task)
  local config = require("arborist.config").get()
  local bufnr = task:get_bufnr()
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ui = api.nvim_list_uis()[1] or {}
  local width = math.floor((ui.width or 80) * (config.float.width or 0.6))
  local height = math.floor((ui.height or 24) * (config.float.height or 0.4))

  local win = api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor(((ui.width or 80) - width) / 2),
    row = math.floor(((ui.height or 24) - height) / 2),
    style = "minimal",
    border = config.float.border or "rounded",
  })

  -- Signal the terminal to redraw at the new size
  api.nvim_win_call(win, function()
    vim.cmd("startinsert")
  end)

  for _, mode in ipairs({ "n", "t" }) do
    vim.keymap.set(mode, config.keys.close_float, function()
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
      end
    end, { buffer = bufnr, desc = "Close Claude float" })
  end
end

M.open_task_float = open_task_float

function M.launch(branch, worktree_path, prompt)
  local overseer = require("overseer")

  overseer.run_template({
    name = "Claude Code",
    params = {
      prompt = prompt,
      worktree = worktree_path,
      branch = branch,
    },
  }, function(task)
    if not task then
      vim.notify("Failed to start Claude task", vim.log.levels.ERROR)
      return
    end

    vim.defer_fn(function()
      open_task_float(task)
    end, 300)
  end)
end

function M.pick_instance()
  local overseer = require("overseer")
  local tasks = overseer.list_tasks({ status = "RUNNING" })
  local claude_tasks = vim.tbl_filter(function(t)
    return t.name:match("^claude:")
  end, tasks)

  if #claude_tasks == 0 then
    vim.notify("No running Claude instances", vim.log.levels.INFO)
    return
  end

  vim.ui.select(claude_tasks, {
    prompt = "Claude instances:",
    format_item = function(t)
      return t.name .. "  [" .. t.status .. "]"
    end,
  }, function(task)
    if not task then
      return
    end
    open_task_float(task)
  end)
end

return M
