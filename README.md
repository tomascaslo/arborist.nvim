# arborist.nvim
<img width="2752" height="1536" alt="Gemini_Generated_Image_7okcp27okcp27okc" src="https://github.com/user-attachments/assets/78900244-1cf4-4f3d-b47e-0ce88325f4ab" />


Manage multiple [Claude Code](https://claude.ai/claude-code) sessions across git worktrees from inside Neovim.

An arborist tends to trees — this plugin tends to your git worktrees, launching and orchestrating Claude Code instances with an interactive fzf picker, floating prompt editor, live session dashboard, and a notification queue that tells you when Claude needs your attention.

## Features

- **Worktree picker** — fzf-lua powered picker with live preview showing git status and recent commits
- **Floating prompt editor** — write multi-line prompts with `@path` file/directory completion before launching Claude
- **Session dashboard** — vertical split view showing all active Claude sessions with live state (Running, Idle, Needs input, Detached)
- **Session persistence** — resume sessions across Neovim restarts via `claude --resume`
- **Hook system** — Lua-based hook handler (runs via `nvim -l`) handles Stop, PostToolUse, PermissionRequest, Notification, SessionStart, and SessionEnd events
- **Auto-reload buffers** — when Claude edits files, open buffers auto-reload via `checktime`
- **Notification queue** — pushes notifications when Claude finishes or needs permission
- **Lualine integration** — statusline component showing active session count (yellow when permission needed, green when idle)
- **Tool sandboxing** — configurable allowed/disallowed tools so Claude can't `rm -rf` or `git push` from worktree sessions
- **Branch slugification** — `:ClaudeNew hello world` creates a `hello-world` worktree automatically

## Dependencies

- [Neovim](https://neovim.io/) >= 0.10
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) — fuzzy picker
- [worktrunk (`wt`)](https://github.com/nicholasgasior/wt) — worktree CLI
- [Claude Code (`claude`)](https://claude.ai/claude-code) — AI coding assistant
- `jq` — JSON processing (used by the fzf preview)
- [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) — *(optional)* for statusline component

## Installation

### lazy.nvim

```lua
{
  "tomascaslo/arborist.nvim",
  dependencies = {
    "ibhagwan/fzf-lua",
  },
  config = function()
    require("arborist").setup({
      -- all options are optional, these are the defaults
      float = {
        width = 0.85,
        height = 0.8,
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
      persist_sessions = true,        -- persist sessions for resume across restarts
      session_timeout = 60 * 60 * 24, -- 24h — prune stale detached sessions
      notification_timeout = 3000,    -- ms
      keys = {
        worktrees = "<leader>rw",
        new_worktree = "<leader>rn",
        pick_instance = "<leader>ri",
        notifications = "<leader>rq",
        submit_prompt = "<leader>rs",
        session_view = "<leader>rv",
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

### Lualine

Add the `arborist` component to your lualine config:

```lua
require("lualine").setup({
  sections = {
    lualine_x = { "arborist" },
  },
})
```

Shows an icon + session count when Claude sessions are active. Yellow when a session needs permission, green when all are idle.

## Usage

| Keymap | Action |
|--------|--------|
| `<leader>rw` | Open worktree picker |
| `<leader>rn` | Create new worktree + launch Claude |
| `<leader>ri` | Pick a running Claude instance |
| `<leader>rq` | Open notification queue |
| `<leader>rv` | Toggle session dashboard |
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
| `<leader>rs` / `:w` | Submit prompt |
| `q` / `Esc` | Cancel |
| `@` | Trigger file/directory autocomplete |

### Session dashboard

| Key | Action |
|-----|--------|
| `enter` | Open session / resume detached session |
| `ctrl-n` / `ctrl-p` | Navigate between sessions |
| `x` | End session (keeps worktree) |
| `X` | Remove detached session (no confirmation) |
| `r` | Refresh |
| `q` | Close |
| `?` | Show help |

### Commands

| Command | Description |
|---------|-------------|
| `:ClaudeNew [name]` | Create worktree + launch Claude. Slugifies names: `hello world` → `hello-world` |
| `:ClaudeSessions` | Toggle the session dashboard |
| `:ClaudeCleanup` | Remove stale detached sessions |

## Session persistence

Sessions are persisted to disk (`stdpath("data")/arborist/sessions.json`) so you can resume them after restarting Neovim. When a session's `session_id` is captured (via the `SessionStart` hook), it becomes resumable.

Detached sessions appear in the session dashboard with a "Detached (resumable)" state. Press `enter` to resume with `claude --resume <session_id>`.

Stale sessions older than `session_timeout` (default 24h) are automatically pruned on startup. Run `:ClaudeCleanup` to manually clean up.

Disable with `persist_sessions = false` in setup.

## How it works

```
┌──────────────┐     ┌───────────┐     ┌──────────────┐
│  fzf picker  │────>│  prompt   │────>│  termopen()  │
│  (worktrees) │     │  (float)  │     │  (float)     │
└──────────────┘     └───────────┘     └──────┬───────┘
                                              │
                                    claude --model opus
                                    --settings arborist.json
                                              │
                                     ┌────────▼────────┐
                                     │  Claude Code    │
                                     │  (interactive)  │
                                     └────────┬────────┘
                                              │ hooks (nvim -l)
                    ┌─────────────┬───────────┼───────────┬──────────────┐
                    │             │           │           │              │
           ┌────────▼───────┐ ┌──▼────────┐ ┌▼────────┐ ┌▼───────────┐ ┌▼───────────┐
           │ SessionStart   │ │ Stop      │ │ PostTool│ │ Permission │ │ SessionEnd │
           │ → bind id      │ │ → "idle"  │ │ → "run" │ │ → "waiting"│ │ → cleanup  │
           └────────────────┘ │ → notify  │ │ → check │ │ → notify   │ └────────────┘
                              └─────┬─────┘ └─────────┘ └────────────┘
                                    │
                  ┌─────────────────┼─────────────────┐
                  │                                   │
         ┌────────▼────────┐                 ┌────────▼────┐
         │  session view   │                 │   lualine   │
         │  (live state)   │                 │  component  │
         └─────────────────┘                 └─────────────┘
```

## Tests

Requires [plenary.nvim](https://github.com/nvim-lua/plenary.nvim).

```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

## License

MIT
