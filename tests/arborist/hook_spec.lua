describe("hook", function()
  local hook_path = vim.fn.getcwd() .. "/lua/arborist/hook.lua"

  -- Helper: run hook.lua with JSON input, return exit code
  local function run_hook(json_input)
    local result = vim.system(
      { "nvim", "-l", hook_path },
      { stdin = json_input, text = true }
    ):wait()
    return result.code
  end

  describe("event routing", function()
    it("exits 0 on empty input", function()
      assert.equals(0, run_hook(""))
    end)

    it("exits 0 on invalid JSON", function()
      assert.equals(0, run_hook("not json"))
    end)

    it("exits 0 on Stop event with stop_hook_active", function()
      local input = vim.json.encode({
        hook_event_name = "Stop",
        cwd = "/tmp",
        session_id = "abc",
        stop_hook_active = true,
      })
      assert.equals(0, run_hook(input))
    end)

    it("exits 0 on Stop event", function()
      local input = vim.json.encode({
        hook_event_name = "Stop",
        cwd = "/tmp",
        session_id = "abc",
        stop_hook_active = false,
      })
      -- Will fail to connect to nvim sockets but should still exit 0
      assert.equals(0, run_hook(input))
    end)

    it("exits 0 on PostToolUse event", function()
      local input = vim.json.encode({
        hook_event_name = "PostToolUse",
        cwd = "/tmp",
        session_id = "abc",
        tool_name = "Edit",
      })
      assert.equals(0, run_hook(input))
    end)

    it("exits 0 on SessionStart event", function()
      local input = vim.json.encode({
        hook_event_name = "SessionStart",
        cwd = "/tmp",
        session_id = "abc",
        source = "startup",
      })
      assert.equals(0, run_hook(input))
    end)

    it("exits 0 on SessionEnd event", function()
      local input = vim.json.encode({
        hook_event_name = "SessionEnd",
        cwd = "/tmp",
        session_id = "abc",
      })
      assert.equals(0, run_hook(input))
    end)

    it("exits 0 on Notification event", function()
      local input = vim.json.encode({
        hook_event_name = "Notification",
        cwd = "/tmp",
        session_id = "abc",
        message = "test message",
        title = "test title",
      })
      assert.equals(0, run_hook(input))
    end)

    it("exits 0 on unknown event", function()
      local input = vim.json.encode({
        hook_event_name = "UnknownEvent",
        cwd = "/tmp",
        session_id = "abc",
      })
      assert.equals(0, run_hook(input))
    end)
  end)

  describe("global function integration", function()
    -- Test that the global functions registered by sessions.setup_globals work correctly
    -- when called directly (simulating what the hook handler triggers via --remote-expr)

    local sessions

    before_each(function()
      sessions = require("arborist.sessions")
      sessions._sessions = {}
      require("arborist.config").setup({})
      sessions.setup_globals()
    end)

    it("_arborist_hook_stop sets state to idle", function()
      sessions.add({ name = "claude:test", bufnr = vim.api.nvim_create_buf(false, true), worktree_path = "/tmp/test" })
      _G._arborist_hook_stop("/tmp/test", "sid-1")
      vim.wait(100, function() return sessions._sessions[1].state == "idle" end)
      assert.equals("idle", sessions._sessions[1].state)
    end)

    it("_arborist_hook_permission_request sets state to waiting", function()
      sessions.add({ name = "claude:test", bufnr = vim.api.nvim_create_buf(false, true), worktree_path = "/tmp/test" })
      _G._arborist_hook_permission_request("/tmp/test", "sid-1")
      vim.wait(100, function() return sessions._sessions[1].state == "waiting" end)
      assert.equals("waiting", sessions._sessions[1].state)
    end)

    it("_arborist_hook_post_tool_use sets state to running", function()
      sessions.add({
        name = "claude:test",
        bufnr = vim.api.nvim_create_buf(false, true),
        worktree_path = "/tmp/test",
        session_id = "sid-1",
      })
      sessions.set_state("/tmp/test", "sid-1", "waiting")
      _G._arborist_hook_post_tool_use("/tmp/test", "sid-1", "Edit")
      vim.wait(100, function() return sessions._sessions[1].state == "running" end)
      assert.equals("running", sessions._sessions[1].state)
    end)

    it("_arborist_hook_session_start binds session_id", function()
      sessions.add({
        name = "claude:test",
        bufnr = vim.api.nvim_create_buf(false, true),
        worktree_path = "/tmp/test",
      })
      assert.is_nil(sessions._sessions[1].session_id)
      _G._arborist_hook_session_start("/tmp/test", "new-sid", "startup")
      vim.wait(100, function() return sessions._sessions[1].session_id == "new-sid" end)
      assert.equals("new-sid", sessions._sessions[1].session_id)
    end)

    it("_arborist_hook_session_end removes session", function()
      local buf = vim.api.nvim_create_buf(false, true)
      sessions.add({
        name = "claude:test",
        bufnr = buf,
        worktree_path = "/tmp/test",
        session_id = "sid-end",
      })
      _G._arborist_hook_session_end("/tmp/test", "sid-end")
      vim.wait(100, function() return #sessions._sessions == 0 end)
      assert.equals(0, #sessions._sessions)
    end)
  end)
end)
