local M = {}

function M.resolve_path(branch)
  local json = vim.fn.system("wt list --format=json")
  local ok, trees = pcall(vim.json.decode, json)
  if not ok or type(trees) ~= "table" then
    return nil
  end
  for _, t in ipairs(trees) do
    if t.branch == branch and t.path then
      return t.path
    end
  end
  return nil
end

local function dispose_claude_task(branch)
  local ok, overseer = pcall(require, "overseer")
  if not ok then
    return
  end
  local tasks = overseer.list_tasks()
  for _, t in ipairs(tasks) do
    if t.name == "claude:" .. branch then
      t:stop()
      vim.defer_fn(function()
        t:dispose()
      end, 500)
    end
  end
end

function M.fzf_picker()
  local fzf = require("fzf-lua")
  local prompt = require("arborist.prompt")
  local launcher = require("arborist.launcher")

  fzf.fzf_exec(
    'wt list --format=json | jq -r \'.[] | "\\(.branch // "detached")\\t\\(.path // "-")\\t\\(.symbols // "")"\'',
    {
      prompt = false,
      winopts = {
        height = 0.5,
        width = 0.7,
        row = 0.35,
        title = " Worktrees ",
        title_pos = "center",
        preview = {
          layout = "vertical",
          vertical = "down:50%",
        },
      },
      fzf_opts = {
        ["--delimiter"] = "\t",
        ["--with-nth"] = "1,3",
        ["--header"] = "enter:switch  ctrl-c:claude  ctrl-d:remove  shift-up/down:scroll preview",
        ["--bind"] = "ctrl-n:down,ctrl-p:up,shift-up:preview-up,shift-down:preview-down",
        ["--preview"] = [[sh -c '
          path={2}
          printf "\033[1;34m%-12s\033[0m %s\n" "Branch:" {1}
          printf "\033[1;34m%-12s\033[0m %s\n" "Path:" "$path"
          echo ""
          echo "\033[1;33m--- Modified ---\033[0m"
          git -C "$path" status --short 2>/dev/null || echo "  (clean)"
          echo ""
          echo "\033[1;33m--- Recent Commits ---\033[0m"
          git -C "$path" log --oneline --decorate -15 2>/dev/null
        ']],
        ["--preview-window"] = "down:50%:wrap",
      },
      previewer = false,
      actions = {
        ["default"] = function(selected)
          local branch = selected[1]:match("^([^\t]+)")
          if not branch then
            return
          end
          vim.fn.system("wt switch " .. vim.fn.shellescape(branch) .. " --no-cd")
          local path = M.resolve_path(branch)
          if path then
            vim.cmd("cd " .. vim.fn.fnameescape(path))
          end
        end,
        ["ctrl-d"] = function(selected)
          local branch = selected[1]:match("^([^\t]+)")
          local esc_branch = vim.fn.shellescape(branch)

          local out = vim.fn.system("wt remove " .. esc_branch)
          if vim.v.shell_error == 0 then
            dispose_claude_task(branch)
            vim.notify("Removed: " .. branch, vim.log.levels.INFO)
            return
          end

          local err = vim.trim(out)
          vim.notify(err, vim.log.levels.WARN, { title = "wt remove " .. branch })
          vim.ui.select({ "Yes, force remove", "No, keep it" }, {
            prompt = "Force remove " .. branch .. "?",
          }, function(choice)
            if choice and choice:match("^Yes") then
              local force_out = vim.fn.system("wt remove " .. esc_branch .. " --force")
              if vim.v.shell_error == 0 then
                dispose_claude_task(branch)
                vim.notify("Force removed: " .. branch, vim.log.levels.INFO)
              else
                vim.notify("Failed to remove:\n" .. vim.trim(force_out), vim.log.levels.ERROR)
              end
            end
          end)
        end,
        ["ctrl-c"] = function(selected)
          local branch = selected[1]:match("^([^\t]+)")
          local path = M.resolve_path(branch)
          if not path then
            vim.notify("No worktree for " .. branch, vim.log.levels.WARN)
            return
          end
          prompt.open("Claude @ " .. branch, path, function(p)
            launcher.launch(branch, path, p)
          end)
        end,
      },
    }
  )
end

return M
