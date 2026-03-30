local lualine_require = require("lualine_require")
local component = lualine_require.require("lualine.component"):extend()

function component:init(options)
	component.super.init(self, options)
	local icon = ""
	local ok_icons, mini_icons = pcall(require, "mini.icons")
	if ok_icons then
		icon = mini_icons.get("filetype", "robots")
	end
	self.options.icon = self.options.icon or icon
	self.options.waiting_color = self.options.waiting_color or { fg = "#f9e2af" }
	self.options.idle_color = self.options.idle_color or { fg = "#a6e3a1" }
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
	local idle = 0
	for _, s in ipairs(all) do
		if s.state == "waiting" then
			waiting = waiting + 1
		elseif s.state == "idle" then
			idle = idle + 1
		end
	end

	if waiting > 0 then
		self.options.color = self.options.waiting_color
		return tostring(#all) .. " (" .. waiting .. "!)"
	end

	if idle > 0 then
		self.options.color = self.options.idle_color
		return tostring(#all)
	end

	self.options.color = nil
	return tostring(#all)
end

return component
