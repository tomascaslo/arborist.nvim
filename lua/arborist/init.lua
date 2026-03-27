local M = {}

M.version = require("arborist.version")

function M.setup(opts)
  local config = require("arborist.config")
  config.setup(opts)

  local cfg = config.get()
  local api = vim.api
  local worktrees = require("arborist.worktrees")
  local launcher = require("arborist.launcher")
  local notifications = require("arborist.notifications")
  local prompt = require("arborist.prompt")

  -- Global hook receiver
  notifications.setup_global()

  -- :ClaudeNew [branch] — create worktree + float prompt + Claude
  api.nvim_create_user_command("ClaudeNew", function(cmd_opts)
    local branch = table.concat(cmd_opts.fargs, " ")
    if branch == "" then
      branch = vim.fn.input("Branch name: ")
      if branch == "" then
        return
      end
    end

    -- Slugify: "hello world" -> "hello-world"
    branch = branch:lower()
      :gsub("%s+", "-")
      :gsub("[^%w%-_/]", "")
      :gsub("%-%-+", "-")
      :gsub("^%-+", "")
      :gsub("%-+$", "")

    local result = vim.fn.system("wt switch --create " .. vim.fn.shellescape(branch) .. " --no-cd --yes")
    if vim.v.shell_error ~= 0 then
      vim.notify("wt switch --create failed:\n" .. result, vim.log.levels.ERROR)
      return
    end

    local path = worktrees.resolve_path(branch)
    if not path then
      vim.notify("Worktree created but path not found", vim.log.levels.WARN)
      return
    end

    prompt.open("Claude @ " .. branch, path, function(p)
      launcher.launch(branch, path, p)
    end)
  end, { nargs = "*", desc = "Create worktree via wt + launch Claude" })

  -- Generate settings file with Stop hook for --settings flag
  M._write_settings()

  -- Keymaps
  vim.keymap.set("n", cfg.keys.worktrees, worktrees.fzf_picker, { desc = "Worktrees (fzf)" })
  vim.keymap.set("n", cfg.keys.new_worktree, ":ClaudeNew ", { desc = "New worktree + Claude" })
  vim.keymap.set("n", cfg.keys.pick_instance, launcher.pick_instance, { desc = "Pick Claude instance" })
  vim.keymap.set("n", cfg.keys.notifications, notifications.open_queue, { desc = "Claude notifications" })
end

--- Write a settings JSON file with the Stop hook for use with --settings flag.
--- Called during setup() so the file is always up to date.
function M._write_settings()
  local source = debug.getinfo(1, "S").source:sub(2)
  local plugin_root = vim.fn.fnamemodify(source, ":h:h:h")
  local hook_script = plugin_root .. "/hooks/notify-nvim-stop.sh"

  -- Ensure hook script is executable
  vim.fn.system({ "chmod", "+x", hook_script })

  local settings = {
    hooks = {
      Stop = {
        {
          hooks = {
            {
              type = "command",
              command = hook_script,
              timeout = 5,
              async = true,
            },
          },
        },
      },
    },
  }

  local dir = vim.fn.stdpath("data") .. "/arborist"
  vim.fn.mkdir(dir, "p")

  M.settings_path = dir .. "/settings.json"
  vim.fn.writefile({ vim.json.encode(settings) }, M.settings_path)
end

return M
