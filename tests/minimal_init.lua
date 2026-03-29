-- Minimal init for running plenary tests
local plenary_path = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:append(plenary_path)
end

-- Add the plugin itself to rtp
vim.opt.rtp:append(".")

-- Load plenary
vim.cmd("runtime plugin/plenary.vim")

-- Set up a temp data directory for test isolation
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
vim.env.XDG_DATA_HOME = tmp
