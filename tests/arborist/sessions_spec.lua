local sessions = require("arborist.sessions")

-- Helper: create a real buffer so nvim_buf_is_valid works
local function make_buf()
  return vim.api.nvim_create_buf(false, true)
end

describe("sessions", function()
  before_each(function()
    sessions._sessions = {}
  end)

  describe("add", function()
    it("adds a session with default state", function()
      local buf = make_buf()
      sessions.add({ name = "claude:test", bufnr = buf, worktree_path = "/tmp/test" })
      assert.equals(1, #sessions._sessions)
      assert.equals("running", sessions._sessions[1].state)
      assert.is_not_nil(sessions._sessions[1].last_updated)
    end)

    it("preserves provided state", function()
      local buf = make_buf()
      sessions.add({ name = "claude:test", bufnr = buf, worktree_path = "/tmp", state = "waiting" })
      assert.equals("waiting", sessions._sessions[1].state)
    end)

    it("adds multiple sessions", function()
      sessions.add({ name = "claude:a", bufnr = make_buf(), worktree_path = "/tmp/a" })
      sessions.add({ name = "claude:b", bufnr = make_buf(), worktree_path = "/tmp/b" })
      assert.equals(2, #sessions._sessions)
    end)
  end)

  describe("remove_by_bufnr", function()
    it("removes the matching session", function()
      local buf = make_buf()
      sessions.add({ name = "claude:test", bufnr = buf, worktree_path = "/tmp" })
      assert.equals(1, #sessions._sessions)
      sessions.remove_by_bufnr(buf)
      assert.equals(0, #sessions._sessions)
    end)

    it("does nothing if bufnr not found", function()
      sessions.add({ name = "claude:test", bufnr = make_buf(), worktree_path = "/tmp" })
      sessions.remove_by_bufnr(99999)
      assert.equals(1, #sessions._sessions)
    end)

    it("only removes the matching session", function()
      local buf1 = make_buf()
      local buf2 = make_buf()
      sessions.add({ name = "claude:a", bufnr = buf1, worktree_path = "/tmp/a" })
      sessions.add({ name = "claude:b", bufnr = buf2, worktree_path = "/tmp/b" })
      sessions.remove_by_bufnr(buf1)
      assert.equals(1, #sessions._sessions)
      assert.equals("claude:b", sessions._sessions[1].name)
    end)
  end)

  describe("remove_by_session_id", function()
    it("removes matching session", function()
      local buf = make_buf()
      sessions.add({ name = "claude:test", bufnr = buf, worktree_path = "/tmp", session_id = "abc" })
      sessions.remove_by_session_id("abc")
      assert.equals(0, #sessions._sessions)
    end)

    it("does nothing if session_id not found", function()
      sessions.add({ name = "claude:test", bufnr = make_buf(), worktree_path = "/tmp", session_id = "abc" })
      sessions.remove_by_session_id("xyz")
      assert.equals(1, #sessions._sessions)
    end)
  end)

  describe("find_by_cwd", function()
    it("finds by exact worktree_path", function()
      local buf = make_buf()
      sessions.add({ name = "claude:test", bufnr = buf, worktree_path = "/tmp/test" })
      local found = sessions.find_by_cwd("/tmp/test")
      assert.is_not_nil(found)
      assert.equals("claude:test", found.name)
    end)

    it("falls back to dirname match", function()
      local buf = make_buf()
      sessions.add({ name = "claude:mydir", bufnr = buf, worktree_path = "/some/other/path" })
      local found = sessions.find_by_cwd("/different/mydir")
      assert.is_not_nil(found)
      assert.equals("claude:mydir", found.name)
    end)

    it("returns nil when not found", function()
      sessions.add({ name = "claude:test", bufnr = make_buf(), worktree_path = "/tmp/test" })
      assert.is_nil(sessions.find_by_cwd("/no/match"))
    end)
  end)

  describe("find_by_session_id", function()
    it("finds matching session", function()
      sessions.add({ name = "claude:test", bufnr = make_buf(), worktree_path = "/tmp", session_id = "abc123" })
      local found = sessions.find_by_session_id("abc123")
      assert.is_not_nil(found)
      assert.equals("claude:test", found.name)
    end)

    it("returns nil for empty string", function()
      sessions.add({ name = "claude:test", bufnr = make_buf(), worktree_path = "/tmp", session_id = "abc" })
      assert.is_nil(sessions.find_by_session_id(""))
    end)

    it("returns nil for nil", function()
      sessions.add({ name = "claude:test", bufnr = make_buf(), worktree_path = "/tmp", session_id = "abc" })
      assert.is_nil(sessions.find_by_session_id(nil))
    end)
  end)

  describe("set_state", function()
    it("updates state by session_id", function()
      sessions.add({ name = "claude:test", bufnr = make_buf(), worktree_path = "/tmp", session_id = "abc" })
      sessions.set_state("/tmp", "abc", "waiting")
      assert.equals("waiting", sessions._sessions[1].state)
    end)

    it("updates state by cwd when no session_id match", function()
      sessions.add({ name = "claude:test", bufnr = make_buf(), worktree_path = "/tmp/test" })
      sessions.set_state("/tmp/test", "new-sid", "waiting")
      assert.equals("waiting", sessions._sessions[1].state)
    end)

    it("binds session_id on first callback", function()
      sessions.add({ name = "claude:test", bufnr = make_buf(), worktree_path = "/tmp/test" })
      assert.is_nil(sessions._sessions[1].session_id)
      sessions.set_state("/tmp/test", "new-sid", "running")
      assert.equals("new-sid", sessions._sessions[1].session_id)
    end)

    it("does nothing if session not found", function()
      sessions.add({ name = "claude:test", bufnr = make_buf(), worktree_path = "/tmp" })
      sessions.set_state("/no/match", "unknown", "waiting")
      assert.equals("running", sessions._sessions[1].state)
    end)

    it("updates last_updated timestamp", function()
      sessions.add({ name = "claude:test", bufnr = make_buf(), worktree_path = "/tmp", session_id = "abc" })
      local old_time = sessions._sessions[1].last_updated
      sessions.set_state("/tmp", "abc", "waiting")
      assert.is_true(sessions._sessions[1].last_updated >= old_time)
    end)
  end)

  describe("get_all", function()
    it("returns all sessions with valid buffers", function()
      sessions.add({ name = "claude:a", bufnr = make_buf(), worktree_path = "/tmp/a" })
      sessions.add({ name = "claude:b", bufnr = make_buf(), worktree_path = "/tmp/b" })
      assert.equals(2, #sessions.get_all())
    end)

    it("prunes sessions with deleted buffers and keeps them as detached if they have session_id", function()
      local buf = make_buf()
      sessions.add({ name = "claude:test", bufnr = buf, worktree_path = "/tmp", session_id = "abc" })
      vim.api.nvim_buf_delete(buf, { force = true })
      local all = sessions.get_all()
      assert.equals(1, #all)
      assert.equals("detached", all[1].state)
      assert.is_nil(all[1].bufnr)
    end)

    it("removes sessions with deleted buffers and no session_id", function()
      local buf = make_buf()
      sessions.add({ name = "claude:test", bufnr = buf, worktree_path = "/tmp" })
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals(0, #sessions.get_all())
    end)
  end)

  describe("get_active_count", function()
    it("returns count", function()
      sessions.add({ name = "claude:a", bufnr = make_buf(), worktree_path = "/tmp/a" })
      sessions.add({ name = "claude:b", bufnr = make_buf(), worktree_path = "/tmp/b" })
      assert.equals(2, sessions.get_active_count())
    end)

    it("returns 0 when empty", function()
      assert.equals(0, sessions.get_active_count())
    end)
  end)

  describe("persistence", function()
    it("persists and loads sessions", function()
      -- Set up config for persistence
      require("arborist.config").setup({ persist_sessions = true, session_timeout = 86400 })

      sessions.add({
        name = "claude:persist",
        bufnr = make_buf(),
        worktree_path = "/tmp/persist",
        session_id = "persist-123",
      })
      sessions._persist()

      -- Clear in-memory state
      sessions._sessions = {}
      assert.equals(0, #sessions._sessions)

      -- Load from disk
      sessions.load_persisted()
      assert.equals(1, #sessions._sessions)
      assert.equals("persist-123", sessions._sessions[1].session_id)
      assert.equals("detached", sessions._sessions[1].state)
      assert.is_nil(sessions._sessions[1].bufnr)
    end)

    it("does not persist sessions without session_id", function()
      require("arborist.config").setup({ persist_sessions = true, session_timeout = 86400 })

      sessions.add({ name = "claude:no-id", bufnr = make_buf(), worktree_path = "/tmp/no-id" })
      sessions._persist()

      sessions._sessions = {}
      sessions.load_persisted()
      assert.equals(0, #sessions._sessions)
    end)

    it("skips loading duplicate session_ids", function()
      require("arborist.config").setup({ persist_sessions = true, session_timeout = 86400 })

      sessions.add({
        name = "claude:dup",
        bufnr = make_buf(),
        worktree_path = "/tmp/dup",
        session_id = "dup-id",
      })
      sessions._persist()

      -- Don't clear — load_persisted should skip the duplicate
      sessions.load_persisted()
      assert.equals(1, #sessions._sessions)
    end)

    it("does not persist when persist_sessions is false", function()
      require("arborist.config").setup({ persist_sessions = false, session_timeout = 86400 })

      -- Clean any existing persisted file
      local path = vim.fn.stdpath("data") .. "/arborist/sessions.json"
      pcall(os.remove, path)

      sessions.add({
        name = "claude:no-persist",
        bufnr = make_buf(),
        worktree_path = "/tmp/np",
        session_id = "np-123",
      })
      -- _persist runs inside add but should be a no-op
      sessions._sessions = {}
      sessions.load_persisted()
      assert.equals(0, #sessions._sessions)
    end)
  end)

  describe("cleanup", function()
    it("removes stale detached sessions", function()
      require("arborist.config").setup({ persist_sessions = true, session_timeout = 10 })

      -- Add a detached session with old timestamp
      table.insert(sessions._sessions, {
        name = "claude:old",
        worktree_path = "/tmp/old",
        session_id = "old-id",
        state = "detached",
        last_updated = os.time() - 100, -- well past timeout of 10s
        bufnr = nil,
      })

      sessions.cleanup()
      assert.equals(0, #sessions._sessions)
    end)

    it("keeps sessions with valid buffers regardless of age", function()
      require("arborist.config").setup({ persist_sessions = true, session_timeout = 10 })

      local buf = make_buf()
      table.insert(sessions._sessions, {
        name = "claude:live",
        worktree_path = "/tmp/live",
        bufnr = buf,
        state = "running",
        last_updated = os.time() - 100,
      })

      sessions.cleanup()
      assert.equals(1, #sessions._sessions)
    end)

    it("keeps recent detached sessions", function()
      require("arborist.config").setup({ persist_sessions = true, session_timeout = 86400 })

      table.insert(sessions._sessions, {
        name = "claude:recent",
        worktree_path = "/tmp/recent",
        session_id = "recent-id",
        state = "detached",
        last_updated = os.time() - 10,
        bufnr = nil,
      })

      sessions.cleanup()
      assert.equals(1, #sessions._sessions)
    end)
  end)
end)
