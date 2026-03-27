# arborist.nvim

Manage multiple [Claude Code](https://claude.ai/claude-code) sessions across git worktrees from inside Neovim.

An arborist tends to trees — this plugin tends to your git worktrees, launching and orchestrating Claude Code instances via [Overseer](https://github.com/stevearc/overseer.nvim) with an interactive fzf picker, floating prompt editor, and a notification queue that tells you when Claude needs your attention.

## Features

- **Worktree picker** — fzf-lua powered picker with live preview showing git status and recent commits
- **Floating prompt editor** — write multi-line prompts with `@path` file/directory completion before launching Claude
- **Overseer integration** — each Claude session is an Overseer task with a real terminal you can interact with
- **Notification queue** — Claude Code's Stop hook pushes notifications to Neovim when Claude finishes and is waiting for input; select a notification to jump into that session
- **Tool sandboxing** — configurable allowed/disallowed tools so Claude can't `rm -rf` or `git push` from worktree sessions
- **Branch slugification** — `:ClaudeNew hello world` creates a `hello-world` worktree automatically

## Dependencies

- [Neovim](https://neovim.io/) >= 0.10
- [overseer.nvim](https://github.com/stevearc/overseer.nvim) — task runner
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) — fuzzy picker
- [worktrunk (`wt`)](https://github.com/nicholasgasior/wt) — worktree CLI
- [Claude Code (`claude`)](https://claude.ai/claude-code) — AI coding assistant
- `jq` — JSON processing (used by the fzf preview and hook script)

## Installation

### lazy.nvim

```lua
{
  "tomascaslo/arborist.nvim",
  dependencies = {
    "stevearc/overseer.nvim",
    "ibhagwan/fzf-lua",
  },
  config = function()
    require("arborist").setup({
      -- all options are optional, these are the defaults
      float = {
        width = 0.6,
        height = 0.4,
        border = "rounded",
      },
      claude = {
        model = "opus",
        effort = "medium",
        -- add/remove tools as needed for your stack
        allowed_tools = {
          "Read", "Glob", "Grep", "Edit", "MultiEdit",
          "Bash(go test *)", "Bash(git diff *)",
          -- ... see lua/arborist/config.lua for full defaults
        },
        disallowed_tools = {
          "Bash(rm -rf *)",
          "Bash(git push *)",
          "Bash(git rebase *)",
          "Bash(git reset --hard *)",
        },
      },
      keys = {
        worktrees = "<leader>rw",
        new_worktree = "<leader>rn",
        pick_instance = "<leader>ri",
        notifications = "<leader>rq",
        submit_prompt = "<leader>rs",
        close_float = "<C-q>",
      },
    })
  end,
}
```

For local development / testing:

```lua
{ dir = "~/projects/arborist.nvim" }
```

## Usage

| Keymap | Action |
|--------|--------|
| `<leader>rw` | Open worktree picker |
| `<leader>rn` | Create new worktree + launch Claude |
| `<leader>ri` | Pick a running Claude instance |
| `<leader>rq` | Open notification queue |
| `<C-q>` | Close Claude float (works in terminal mode) |

### Worktree picker actions

| Key | Action |
|-----|--------|
| `enter` | Switch to worktree |
| `ctrl-c` | Launch Claude on worktree |
| `ctrl-d` | Remove worktree (with force option) |
| `ctrl-n` / `ctrl-p` | Navigate list |
| `shift-up` / `shift-down` | Scroll preview |

### Prompt editor

| Key | Action |
|-----|--------|
| `<leader>rs` | Submit prompt |
| `q` / `Esc` | Cancel |
| `@` | Trigger file/directory autocomplete |

### Commands

| Command | Description |
|---------|-------------|
| `:ClaudeNew [name]` | Create worktree + launch Claude. Slugifies names: `hello world` → `hello-world` |
| `:OverseerRun Claude Code` | Launch Claude via Overseer directly (prompts for params) |

## How it works

```
┌──────────────┐     ┌───────────┐     ┌──────────────┐
│  fzf picker  │────>│  prompt   │────>│   overseer   │
│  (worktrees) │     │  (float)  │     │  (terminal)  │
└──────────────┘     └───────────┘     └──────┬───────┘
                                              │
                                    claude --model opus
                                    --effort medium
                                    --allowedTools ...
                                              │
                                     ┌────────▼────────┐
                                     │  Claude Code    │
                                     │  (interactive)  │
                                     └────────┬────────┘
                                              │ Stop hook
                                     ┌────────▼────────┐
                                     │  notification   │
                                     │  queue (nvim)   │
                                     └─────────────────┘
```

## License

MIT
