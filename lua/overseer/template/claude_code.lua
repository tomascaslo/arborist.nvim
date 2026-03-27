-- Overseer template for Claude Code sessions.
-- Used by arborist.nvim and available via :OverseerRun Claude Code

local function tool_args()
  local ok, config = pcall(require, "arborist.config")
  if not ok then
    return {}
  end
  local cfg = config.get()
  if not cfg or not cfg.claude then
    return {}
  end

  local args = {}
  for _, tool in ipairs(cfg.claude.allowed_tools or {}) do
    table.insert(args, "--allowedTools")
    table.insert(args, tool)
  end
  for _, tool in ipairs(cfg.claude.disallowed_tools or {}) do
    table.insert(args, "--disallowedTools")
    table.insert(args, tool)
  end
  return args
end

return {
  name = "Claude Code",
  builder = function(params)
    local ok, config = pcall(require, "arborist.config")
    local cfg = ok and config.get() or {}
    local claude = cfg.claude or {}

    local args = {}
    if claude.model then
      table.insert(args, "--model")
      table.insert(args, claude.model)
    end
    if claude.effort then
      table.insert(args, "--effort")
      table.insert(args, claude.effort)
    end
    vim.list_extend(args, tool_args())

    -- Pass arborist settings (hooks) via --settings so we don't modify user config
    local arborist = require("arborist")
    if arborist.settings_path then
      table.insert(args, "--settings")
      table.insert(args, arborist.settings_path)
    end

    if params.prompt and params.prompt ~= "" then
      table.insert(args, params.prompt)
    end

    local cwd = params.worktree or vim.fn.getcwd()
    local branch = params.branch or vim.fn.fnamemodify(cwd, ":t")

    return {
      cmd = { "claude" },
      args = args,
      cwd = cwd,
      name = "claude:" .. branch,
      strategy = { "jobstart" },
      metadata = { worktree_path = cwd },
      components = {
        "default",
        { "on_complete_notify", system = "always" },
        { "on_complete_dispose", timeout = 600 },
      },
    }
  end,
  params = {
    prompt = { type = "string", optional = true, desc = "Prompt for Claude" },
    worktree = { type = "string", optional = true, desc = "Git worktree path" },
    branch = { type = "string", optional = true, desc = "Branch name for task label" },
  },
}
