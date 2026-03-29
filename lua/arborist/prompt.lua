local M = {}
local api = vim.api

function M.open(title, worktree_path, on_submit)
  local config = require("arborist.config").get()
  local float = config.float

  local width = math.floor(vim.o.columns * float.width)
  local height = math.floor(vim.o.lines * float.height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = float.border,
    title = " " .. title .. " ",
    title_pos = "center",
    footer = " " .. config.keys.submit_prompt .. " or :w submit | q close | @<path> file ref ",
    footer_pos = "center",
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:FloatBorder"

  -- Placeholder text (virtual, disappears when you type)
  local ns = api.nvim_create_namespace("arborist_prompt_placeholder")
  api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  api.nvim_win_set_cursor(win, { 1, 0 })

  local function update_placeholder()
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local empty = #lines == 0 or (#lines == 1 and lines[1] == "")
    if empty then
      api.nvim_buf_set_extmark(buf, ns, 0, 0, {
        virt_text = { { "Write your prompt... (@path to reference files)", "Comment" } },
        virt_text_pos = "overlay",
      })
    end
  end

  update_placeholder()
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = update_placeholder,
  })

  ---------------------------------------------------------
  -- @file completion (omnifunc-based, scoped to this buffer)
  ---------------------------------------------------------
  local file_cache = nil

  local function omnifunc(findstart, base)
    if findstart == 1 then
      local line = api.nvim_get_current_line()
      local cursor_col = api.nvim_win_get_cursor(0)[2]
      local start = cursor_col
      while start > 0 and line:sub(start, start) ~= "@" do
        start = start - 1
      end
      if start > 0 and line:sub(start, start) == "@" then
        return start
      end
      return -3
    else
      if not file_cache then
        local escaped = vim.fn.shellescape(worktree_path)
        local cmd = string.format(
          "find %s \\( -type f -o -type d \\) -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.next/*' -not -path '*/vendor/*' -not -path '*/__pycache__/*' | head -5000",
          escaped
        )
        local entries = vim.fn.systemlist(cmd)
        file_cache = {}
        local escaped_root = vim.pesc(worktree_path)
        for _, f in ipairs(entries) do
          local rel = f:gsub("^" .. escaped_root .. "/?", "")
          if rel ~= "" then
            local is_dir = vim.fn.isdirectory(f) == 1
            table.insert(file_cache, {
              path = is_dir and (rel .. "/") or rel,
              is_dir = is_dir,
            })
          end
        end
        table.sort(file_cache, function(a, b)
          if a.is_dir ~= b.is_dir then
            return a.is_dir
          end
          return a.path < b.path
        end)
      end

      local matches = {}
      local lower_base = (base or ""):lower()
      for _, entry in ipairs(file_cache) do
        if entry.path:lower():find(lower_base, 1, true) then
          table.insert(matches, {
            word = entry.path,
            menu = entry.is_dir and "[dir]" or "[file]",
          })
        end
        if #matches >= 30 then
          break
        end
      end
      return matches
    end
  end

  local func_name = "_arborist_omnifunc_" .. buf
  _G[func_name] = omnifunc
  vim.bo[buf].omnifunc = "v:lua." .. func_name

  api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      _G[func_name] = nil
    end,
  })

  -- Auto-trigger completion when typing @
  api.nvim_create_autocmd("TextChangedI", {
    buffer = buf,
    callback = function()
      local line = api.nvim_get_current_line()
      local cursor_col = api.nvim_win_get_cursor(0)[2]
      local before = line:sub(1, cursor_col)
      if before:match("@[%w%._%-/]*$") then
        if vim.fn.pumvisible() == 0 then
          api.nvim_feedkeys(api.nvim_replace_termcodes("<C-x><C-o>", true, false, true), "n", false)
        end
      end
    end,
  })

  ---------------------------------------------------------
  -- Keymaps
  ---------------------------------------------------------
  local function submit()
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local p = vim.trim(table.concat(lines, "\n"))
    api.nvim_win_close(win, true)
    on_submit(p)
  end

  vim.keymap.set("n", config.keys.submit_prompt, submit, { buffer = buf, desc = "Submit prompt to Claude" })

  -- :w also submits the prompt
  api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = submit,
  })

  vim.keymap.set("n", "q", function()
    api.nvim_win_close(win, true)
  end, { buffer = buf, desc = "Cancel prompt" })

  vim.keymap.set("n", "<Esc>", function()
    api.nvim_win_close(win, true)
  end, { buffer = buf })

  vim.cmd("startinsert")
end

return M
