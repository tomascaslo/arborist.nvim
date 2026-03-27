local M = {}

M.defaults = {
  float = {
    width = 0.6,
    height = 0.4,
    border = "rounded",
  },
  claude = {
    model = "opus",
    effort = "medium",
    allowed_tools = {
      -- Built-in tools
      "Read",
      "Glob",
      "Grep",
      "Edit",
      "MultiEdit",
      -- Go
      "Bash(go build *)",
      "Bash(go run *)",
      "Bash(go test *)",
      "Bash(go vet *)",
      "Bash(go mod *)",
      "Bash(go fmt *)",
      "Bash(gofmt *)",
      "Bash(golangci-lint *)",
      -- Git (safe operations)
      "Bash(git status)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git branch *)",
      "Bash(git checkout *)",
      "Bash(git stash *)",
      -- Shell basics
      "Bash(ls *)",
      "Bash(cat *)",
      "Bash(find *)",
      "Bash(grep *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(wc *)",
      "Bash(mkdir *)",
      -- Introspection
      "Bash(* --version)",
      "Bash(* --help)",
    },
    disallowed_tools = {
      "Bash(rm -rf *)",
      "Bash(git push *)",
      "Bash(git rebase *)",
      "Bash(git reset --hard *)",
    },
  },
  notification_timeout = 3000, -- ms
  keys = {
    worktrees = "<leader>rw",     -- a[r]borist [w]orktrees
    new_worktree = "<leader>rn",  -- a[r]borist [n]ew
    pick_instance = "<leader>ri", -- a[r]borist [i]nstance
    notifications = "<leader>rq", -- a[r]borist [q]ueue
    submit_prompt = "<leader>rs", -- a[r]borist [s]ubmit
    close_float = "<C-q>",
  },
}

M.opts = nil

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

function M.get()
  return M.opts or M.defaults
end

return M
