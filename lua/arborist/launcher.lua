local M = {}
local api = vim.api

function M.launch(branch, worktree_path, prompt)
  local config = require("arborist.config").get()
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
    end, 300)
  end)
end

function M.pick_instance()
  local config = require("arborist.config").get()
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
  end)
end

return M
