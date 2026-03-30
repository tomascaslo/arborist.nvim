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
  local sessions = require("arborist.sessions")
  local session_view = require("arborist.session_view")

  -- Register global hook receivers
  sessions.setup_globals()

  -- Load persisted sessions if enabled
  if cfg.persist_sessions then
    sessions.load_persisted()
  end

  -- Generate settings file with hooks for --settings flag
  M._write_settings()

  -- :ClaudeNew [branch] — create worktree + float prompt + Claude
  api.nvim_create_user_command("ClaudeNew", function(cmd_opts)
    local branch = table.concat(cmd_opts.fargs, " ")
    if branch == "" then
      branch = vim.fn.input("Branch name: ")
      if branch == "" then
        return
      end
    end

    -- Slugify: "hello world" -> "hello-world" (preserves casing)
    branch = branch
      :gsub("%s+", "-")
      :gsub("[^%w%-_/]", "")
      :gsub("%-%-+", "-")
      :gsub("^%-+", "")
      :gsub("%-+$", "")

    -- Resolve or create worktree
    local path = worktrees.resolve_path(branch)
    if not path then
      local root = worktrees.repo_root()
      local opts = { text = true }
      if root then opts.cwd = root end

      -- Prune stale worktree registrations before switching
      vim.system({ "git", "worktree", "prune" }, opts):wait()

      -- Try switching to existing branch (creates worktree if needed)
      local r = vim.system({ "wt", "switch", branch, "--no-cd", "--yes", "--clobber" }, opts):wait()
      if r.code ~= 0 then
        -- Branch doesn't exist — create it
        r = vim.system({ "wt", "switch", "--create", branch, "--no-cd", "--yes" }, opts):wait()
        if r.code ~= 0 then
          local err = vim.trim((r.stdout or "") .. (r.stderr or ""))
          vim.notify("wt switch failed:\n" .. err, vim.log.levels.ERROR)
          return
        end
      end
      path = worktrees.resolve_path(branch)
      if not path then
        vim.notify("Worktree created but path not found", vim.log.levels.WARN)
        return
      end
    end

    -- Always open prompt editor for a fresh session
    prompt.open("Claude @ " .. branch, path, function(p)
      launcher.launch(branch, path, p)
    end)
  end, { nargs = "*", desc = "Create worktree via wt + launch Claude" })

  -- :ClaudeSessions — toggle session view
  api.nvim_create_user_command("ClaudeSessions", function()
    session_view.toggle()
  end, { desc = "Toggle Claude sessions view" })

  -- :ClaudeCleanup — remove stale detached sessions
  api.nvim_create_user_command("ClaudeCleanup", function()
    sessions.cleanup()
  end, { desc = "Clean up stale detached sessions" })

  -- Keymaps
  vim.keymap.set("n", cfg.keys.worktrees, worktrees.fzf_picker, { desc = "Worktrees (fzf)" })
  vim.keymap.set("n", cfg.keys.new_worktree, ":ClaudeNew ", { desc = "New worktree + Claude" })
  vim.keymap.set("n", cfg.keys.pick_instance, launcher.pick_instance, { desc = "Pick Claude instance" })
  vim.keymap.set("n", cfg.keys.notifications, notifications.open_queue, { desc = "Claude notifications" })
  vim.keymap.set("n", cfg.keys.session_view, session_view.toggle, { desc = "Claude sessions" })
end

--- Write a settings JSON file with hooks for use with claude --settings flag.
--- Called during setup() so the file is always up to date.
function M._write_settings()
  local source = debug.getinfo(1, "S").source:sub(2)
  local plugin_root = vim.fn.fnamemodify(source, ":h:h:h")
  local hook_script = plugin_root .. "/lua/arborist/hook.lua"

  local hook_cmd = "nvim -l " .. hook_script

  local hook_entry = {
    {
      hooks = {
        {
          type = "command",
          command = hook_cmd,
          timeout = 10,
        },
      },
    },
  }

  local settings = {
    hooks = {
      Stop = hook_entry,
      PostToolUse = hook_entry,
      Notification = hook_entry,
      PermissionRequest = hook_entry,
      SessionStart = hook_entry,
      SessionEnd = hook_entry,
    },
  }

  local dir = vim.fn.stdpath("data") .. "/arborist"
  vim.fn.mkdir(dir, "p")

  M.settings_path = dir .. "/settings.json"
  vim.fn.writefile({ vim.json.encode(settings) }, M.settings_path)
end

return M
