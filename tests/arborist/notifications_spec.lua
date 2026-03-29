local notifications = require("arborist.notifications")

describe("notifications", function()
  before_each(function()
    notifications._queue = {}
    -- Ensure config is set up for notification_timeout
    require("arborist.config").setup({})
  end)

  describe("push", function()
    it("adds entry to the queue", function()
      notifications.push("/tmp/test", "sid-123")
      assert.equals(1, #notifications._queue)
    end)

    it("stores cwd, dirname, session_id, and time", function()
      notifications.push("/tmp/my-branch", "sid-456")
      local entry = notifications._queue[1]
      assert.equals("/tmp/my-branch", entry.cwd)
      assert.equals("my-branch", entry.dirname)
      assert.equals("sid-456", entry.session_id)
      assert.is_not_nil(entry.time)
    end)

    it("increments count with multiple pushes", function()
      notifications.push("/tmp/a", "sid-1")
      notifications.push("/tmp/b", "sid-2")
      notifications.push("/tmp/c", "sid-3")
      assert.equals(3, #notifications._queue)
    end)
  end)

  describe("clear_for_cwd", function()
    it("removes all entries matching the cwd", function()
      notifications.push("/tmp/test", "sid-1")
      notifications.push("/tmp/test", "sid-2")
      notifications.push("/tmp/other", "sid-3")
      notifications.clear_for_cwd("/tmp/test")
      assert.equals(1, #notifications._queue)
      assert.equals("/tmp/other", notifications._queue[1].cwd)
    end)

    it("does nothing when cwd not in queue", function()
      notifications.push("/tmp/test", "sid-1")
      notifications.clear_for_cwd("/tmp/nonexistent")
      assert.equals(1, #notifications._queue)
    end)

    it("handles empty queue", function()
      notifications.clear_for_cwd("/tmp/test")
      assert.equals(0, #notifications._queue)
    end)
  end)

  describe("open_queue", function()
    it("notifies when queue is empty", function()
      -- Should not error
      notifications.open_queue()
      assert.equals(0, #notifications._queue)
    end)
  end)
end)
