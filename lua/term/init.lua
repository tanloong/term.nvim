#!/usr/bin/env lua

local fn = vim.fn
local api = vim.api
local vim_cmd = vim.cmd
local _str = require "term._str"

local M = { cmd = {} }

M.cmd.start = function()
  -- local orig_winid = api.nvim_get_current_win()
  vim_cmd "topleft split | setlocal winfixheight"
  local shell_bufnr = api.nvim_create_buf(true, true)
  local shell_winid = api.nvim_get_current_win()
  local p

  local GotOutput = function(channel, msg, name)
    -- go back to normal mode regardless whether is exiting
    api.nvim_input "<C-\\><C-N>"

    -- p is only set to non-nil by TextEntered(), p is nil means the msg is not a response to TextEntered, the shell is exiting, shell window has been closed, msg is empty string, don't pollute other windows
    if p == nil then return end
    local last_line = fn.line "$"
    while p[2] + 1 <= last_line and fn.getline(p[2] + 1) == "" do
      fn.deletebufline(shell_bufnr, p[2] + 1)
      last_line = last_line - 1
    end
    vim_cmd(("%dput =''"):format(p[2]))
    fn.append(p[2] + 1, msg)
    fn.setpos(".", p)
    p = nil
  end
  local JobExit = function()
    pcall(api.nvim_win_close, shell_winid, true)
    pcall(api.nvim_buf_delete, shell_bufnr, { force = true })
  end
  local shell_job = fn.jobstart({ "/usr/bin/sh" },
    { on_stdout = GotOutput, on_stderr = GotOutput, on_exit = JobExit })
  local TextEntered = function()
    p = fn.getcurpos()
    local text = api.nvim_get_current_line()
    fn.chansend(shell_job, { text, "" })
  end

  api.nvim_buf_set_name(shell_bufnr, ("shell"):format(tostring(shell_bufnr)))
  api.nvim_set_current_buf(shell_bufnr)
  vim.bo[shell_bufnr].bufhidden = "wipe"
  vim.bo[shell_bufnr].buftype = "nofile"
  vim.keymap.set({ "n", "i" }, "<c-g><c-g>", TextEntered, { buffer = true, silent = true, nowait = true })
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = shell_bufnr, callback = function() fn.jobstop(shell_job) end })
end

M.cmd.reload = function()
  local pkg_name = "term"
  for k, _ in pairs(package.loaded) do
    if k:sub(1, #pkg_name) == pkg_name then
      package.loaded[k] = nil
    end
  end
  require(pkg_name)
  vim.print(("%s restarted at %s"):format(pkg_name, os.date "%H:%M:%S"))
end

api.nvim_create_user_command("Term", function(a)
  -- :Term without any arguments fallbacks to :Term start
  if next(a.fargs) == nil then return M.cmd.start() end

  for _, provider in ipairs { M } do
    cmd = provider.cmd[a.fargs[1]]
    if cmd ~= nil then break end
  end
  if cmd ~= nil then
    a.args = vim.trim(_str.removeprefix(a.args, a.fargs[1]))
    table.remove(a.fargs, 1)
    return cmd(a)
  else
    vim.notify(("%s not found"):format(a.args), vim.log.levels.ERROR)
  end
end, {
  complete = function(_, line)
    local candidates = vim.iter { M.cmd }:map(vim.tbl_keys):flatten():totable()
    table.sort(candidates)
    local args = vim.split(vim.trim(line), "%s+")
    if vim.tbl_count(args) > 2 then return end
    table.remove(args, 1)
    ---@type string
    local prefix = table.remove(args, 1)
    if prefix and line:sub(-1) == " " then return end
    if not prefix then
      return candidates
    else
      return vim.fn.matchfuzzy(candidates, prefix)
    end
  end,
  nargs = "*",
})

return M
