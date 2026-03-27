local lualine_require = require("lualine_require")
local component = lualine_require.require("lualine.component"):extend()

function component:init(options)
  component.super.init(self, options)
  self.options.icon = self.options.icon or ""
  self.options.waiting_color = self.options.waiting_color or { fg = "#f9e2af" }
end

function component:update_status()
  local ok, sessions = pcall(require, "arborist.sessions")
  if not ok then
    return ""
  end

  local all = sessions.get_all()
  if #all == 0 then
    return ""
  end

  local waiting = 0
  for _, s in ipairs(all) do
    if s.state == "waiting" then
      waiting = waiting + 1
    end
  end

  if waiting > 0 then
    self.options.color = self.options.waiting_color
    return tostring(#all) .. " (" .. waiting .. "!)"
  end

  self.options.color = nil
  return tostring(#all)
end

return component
