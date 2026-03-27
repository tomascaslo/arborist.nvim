local M = {}

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

  -- :ArboristInstall — install the Stop hook into ~/.claude/settings.json
  api.nvim_create_user_command("ArboristInstall", function()
    M.install_hook()
  end, { desc = "Install Claude Code Stop hook for notifications" })

  -- Keymaps
  vim.keymap.set("n", cfg.keys.worktrees, worktrees.fzf_picker, { desc = "Worktrees (fzf)" })
  vim.keymap.set("n", cfg.keys.new_worktree, ":ClaudeNew ", { desc = "New worktree + Claude" })
  vim.keymap.set("n", cfg.keys.pick_instance, launcher.pick_instance, { desc = "Pick Claude instance" })
  vim.keymap.set("n", cfg.keys.notifications, notifications.open_queue, { desc = "Claude notifications" })
end

--- Install the Stop hook into ~/.claude/settings.json and copy the hook script
function M.install_hook()
  -- Find the plugin's hooks directory
  local source = debug.getinfo(1, "S").source:sub(2)
  local plugin_root = vim.fn.fnamemodify(source, ":h:h:h")
  local hook_source = plugin_root .. "/hooks/notify-nvim-stop.sh"
  local hook_dest = vim.fn.expand("~/.claude/hooks/notify-nvim-stop.sh")

  -- Copy hook script
  vim.fn.mkdir(vim.fn.expand("~/.claude/hooks"), "p")
  vim.fn.system({ "cp", hook_source, hook_dest })
  vim.fn.system({ "chmod", "+x", hook_dest })

  -- Update settings.json
  local settings_path = vim.fn.expand("~/.claude/settings.json")
  local settings = {}
  local content = vim.fn.readfile(settings_path)
  if #content > 0 then
    local ok, parsed = pcall(vim.json.decode, table.concat(content, "\n"))
    if ok then
      settings = parsed
    end
  end

  settings.hooks = settings.hooks or {}
  settings.hooks.Stop = {
    {
      hooks = {
        {
          type = "command",
          command = hook_dest,
          timeout = 5,
          async = true,
        },
      },
    },
  }

  local json = vim.json.encode(settings)
  -- Pretty print
  local formatted = vim.fn.system("echo " .. vim.fn.shellescape(json) .. " | jq '.'")
  if vim.v.shell_error == 0 then
    vim.fn.writefile(vim.split(formatted, "\n"), settings_path)
  else
    vim.fn.writefile({ json }, settings_path)
  end

  vim.notify("Installed Stop hook at " .. hook_dest, vim.log.levels.INFO, { title = "arborist.nvim" })
end

return M
