#!/usr/bin/env -S nvim -l
-- Hook handler for Claude Code events.
-- Invoked via: nvim -l <this_file>
-- Reads JSON from stdin, routes to the appropriate global function
-- on all running Neovim instances.

--- Escape a string for embedding in a Lua string literal.
local function lua_escape(s)
  if not s then return "" end
  return s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
end

--- Find all running Neovim server sockets.
local function find_nvim_sockets()
  local sockets = {}
  local patterns = {}

  local is_mac = (vim.uv.os_uname().sysname == "Darwin")
  if is_mac then
    local tmpdir = os.getenv("TMPDIR") or "/tmp/"
    table.insert(patterns, tmpdir .. "nvim.*/*/nvim.*.0")
  else
    table.insert(patterns, "/run/user/*/nvim.*/0")
    table.insert(patterns, "/tmp/nvim.*/0")
  end

  for _, pattern in ipairs(patterns) do
    local found = vim.fn.glob(pattern, false, true)
    for _, path in ipairs(found) do
      local stat = vim.uv.fs_stat(path)
      if stat and stat.type == "socket" then
        table.insert(sockets, path)
      end
    end
  end

  return sockets
end

--- Send a luaeval expression to a Neovim instance via --remote-expr.
local function send_to_nvim(sock, lua_expr)
  local stdout = vim.uv.new_pipe()
  local stderr = vim.uv.new_pipe()
  local handle
  handle = vim.uv.spawn("nvim", {
    args = { "--server", sock, "--remote-expr", "luaeval('" .. lua_expr .. "')" },
    stdio = { nil, stdout, stderr },
  }, function()
    stdout:close()
    stderr:close()
    if handle then handle:close() end
  end)
end

--- Broadcast a lua expression to all running Neovim instances.
local function broadcast(lua_expr)
  local sockets = find_nvim_sockets()
  for _, sock in ipairs(sockets) do
    send_to_nvim(sock, lua_expr)
  end
end

-- Main: read stdin, parse, route
local input = io.read("*a")
if not input or input == "" then
  os.exit(0)
end

local ok, data = pcall(vim.json.decode, input)
if not ok or not data then
  os.exit(0)
end

local event = data.hook_event_name or ""
local cwd = lua_escape(data.cwd or "")
local session_id = lua_escape(data.session_id or "")

if event == "Stop" then
  -- Guard against infinite loops
  if data.stop_hook_active then
    os.exit(0)
  end
  broadcast('_arborist_hook_stop("' .. cwd .. '", "' .. session_id .. '")')

elseif event == "PostToolUse" then
  local tool_name = lua_escape(data.tool_name or "")
  broadcast('_arborist_hook_post_tool_use("' .. cwd .. '", "' .. session_id .. '", "' .. tool_name .. '")')

elseif event == "Notification" then
  local message = lua_escape(data.message or "")
  local title = lua_escape(data.title or "")
  broadcast('_arborist_hook_notification("' .. cwd .. '", "' .. session_id .. '", "' .. message .. '", "' .. title .. '")')

elseif event == "SessionStart" then
  local source = lua_escape(data.source or "")
  broadcast('_arborist_hook_session_start("' .. cwd .. '", "' .. session_id .. '", "' .. source .. '")')

elseif event == "SessionEnd" then
  broadcast('_arborist_hook_session_end("' .. cwd .. '", "' .. session_id .. '")')
end

os.exit(0)
