local M = {}

--- Find the repo root directory (works from any worktree).
local function repo_root()
  local common = vim.trim(vim.fn.system("git rev-parse --git-common-dir 2>/dev/null"))
  if common ~= "" and common ~= ".git" then
    return vim.fn.fnamemodify(common, ":h")
  end
  local toplevel = vim.trim(vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"))
  if toplevel ~= "" then
    return toplevel
  end
  return nil
end

--- Run a shell command from the repo root.
local function system_from_root(cmd)
  local root = repo_root()
  if root then
    return vim.fn.system("cd " .. vim.fn.shellescape(root) .. " && " .. cmd)
  end
  return vim.fn.system(cmd)
end

M.system_from_root = system_from_root

--- Run a command asynchronously via vim.system() and call on_done(ok, output).
local function async_cmd(cmd, on_done)
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      on_done(result.code == 0, vim.trim(result.stdout or result.stderr or ""))
    end)
  end)
end

function M.resolve_path(branch)
  local json = system_from_root("wt list --format=json")
  local ok, trees = pcall(vim.json.decode, json)
  if not ok or type(trees) ~= "table" then
    return nil
  end
  for _, t in ipairs(trees) do
    if t.path then
      -- Match by branch name
      if t.branch == branch then
        return t.path
      end
      -- Match by directory name (wt names worktree dirs after the branch)
      local dirname = vim.fn.fnamemodify(t.path, ":t")
      if dirname == branch then
        return t.path
      end
    end
  end
  return nil
end

local function end_claude_session(branch)
  local sessions = require("arborist.sessions")
  for _, s in ipairs(sessions.get_all()) do
    if s.name == "claude:" .. branch then
      if s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) then
        local chan = vim.bo[s.bufnr].channel
        if chan and chan > 0 then
          pcall(vim.fn.jobstop, chan)
        end
        pcall(vim.api.nvim_buf_delete, s.bufnr, { force = true })
      end
      sessions.remove_by_bufnr(s.bufnr)
      break
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
          async_cmd({ "wt", "switch", branch, "--no-cd" }, function(ok)
            if not ok then
              vim.notify("Failed to switch to " .. branch, vim.log.levels.ERROR)
              return
            end
            local path = M.resolve_path(branch)
            if path then
              vim.cmd("cd " .. vim.fn.fnameescape(path))
            end
          end)
        end,
        ["ctrl-d"] = function(selected)
          local branch = selected[1]:match("^([^\t]+)")

          async_cmd({ "wt", "remove", branch }, function(ok, output)
            if ok then
              end_claude_session(branch)
              vim.notify("Removed: " .. branch, vim.log.levels.INFO)
              return
            end

            vim.notify(output, vim.log.levels.WARN, { title = "wt remove " .. branch })
            vim.ui.select({ "Yes, force remove", "No, keep it" }, {
              prompt = "Force remove " .. branch .. "?",
            }, function(choice)
              if choice and choice:match("^Yes") then
                async_cmd({ "wt", "remove", branch, "--force" }, function(force_ok, force_output)
                  if force_ok then
                    end_claude_session(branch)
                    vim.notify("Force removed: " .. branch, vim.log.levels.INFO)
                  else
                    vim.notify("Failed to remove:\n" .. force_output, vim.log.levels.ERROR)
                  end
                end)
              end
            end)
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
