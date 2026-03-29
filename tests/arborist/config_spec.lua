local config = require("arborist.config")

describe("config", function()
  before_each(function()
    config.opts = nil
  end)

  describe("defaults", function()
    it("has float settings", function()
      assert.equals(0.85, config.defaults.float.width)
      assert.equals(0.8, config.defaults.float.height)
      assert.equals("rounded", config.defaults.float.border)
    end)

    it("has claude settings", function()
      assert.equals("opus", config.defaults.claude.model)
      assert.equals("medium", config.defaults.claude.effort)
      assert.is_table(config.defaults.claude.allowed_tools)
      assert.is_table(config.defaults.claude.disallowed_tools)
    end)

    it("has persistence settings", function()
      assert.is_true(config.defaults.persist_sessions)
      assert.equals(86400, config.defaults.session_timeout)
    end)

    it("has notification_timeout", function()
      assert.equals(3000, config.defaults.notification_timeout)
    end)

    it("has key bindings", function()
      local keys = config.defaults.keys
      assert.equals("<leader>rw", keys.worktrees)
      assert.equals("<leader>rn", keys.new_worktree)
      assert.equals("<leader>ri", keys.pick_instance)
      assert.equals("<leader>rq", keys.notifications)
      assert.equals("<leader>rs", keys.submit_prompt)
      assert.equals("<leader>rv", keys.session_view)
      assert.equals("<C-q>", keys.close_float)
    end)
  end)

  describe("setup", function()
    it("merges user options with defaults", function()
      config.setup({ float = { width = 0.5 } })
      local cfg = config.get()
      assert.equals(0.5, cfg.float.width)
      assert.equals(0.8, cfg.float.height) -- default preserved
    end)

    it("overrides nested claude settings", function()
      config.setup({ claude = { model = "sonnet" } })
      local cfg = config.get()
      assert.equals("sonnet", cfg.claude.model)
      assert.equals("medium", cfg.claude.effort) -- default preserved
    end)

    it("overrides key bindings", function()
      config.setup({ keys = { worktrees = "<leader>ww" } })
      local cfg = config.get()
      assert.equals("<leader>ww", cfg.keys.worktrees)
      assert.equals("<leader>rn", cfg.keys.new_worktree) -- default preserved
    end)

    it("can disable persistence", function()
      config.setup({ persist_sessions = false })
      assert.is_false(config.get().persist_sessions)
    end)

    it("can set custom session timeout", function()
      config.setup({ session_timeout = 3600 })
      assert.equals(3600, config.get().session_timeout)
    end)
  end)

  describe("get", function()
    it("returns defaults when setup not called", function()
      config.opts = nil
      local cfg = config.get()
      assert.equals(config.defaults.float.width, cfg.float.width)
    end)

    it("returns merged opts after setup", function()
      config.setup({ notification_timeout = 5000 })
      assert.equals(5000, config.get().notification_timeout)
    end)
  end)
end)
