-- utils.lua - Common utility functions
-- Eliminates repetitive patterns across the codebase

local wezterm = require("wezterm")
local cfg = require("config")

local M = {}

-- ============================================================================
-- PATH UTILITIES
-- ============================================================================

-- Cache home directory (called frequently)
M.home = os.getenv("HOME") or ""

-- Get current working directory from pane (handles nil safely)
-- @param pane: WezTerm pane object
-- @param fallback: Optional fallback path (defaults to home)
-- @return string: The current working directory path
function M.get_cwd(pane, fallback)
	local cwd = pane:get_current_working_dir()
	if cwd then
		return cwd.file_path or cwd.path or fallback or M.home
	end
	return fallback or M.home
end

-- Expand ~ to home directory in a path
-- @param path: Path string that may contain ~
-- @return string: Path with ~ expanded
function M.expand_home(path)
	if not path then return M.home end
	return path:gsub("^~", M.home)
end

-- Collapse home directory to ~ for display
-- @param path: Full path string
-- @return string: Path with home replaced by ~
function M.collapse_home(path)
	if not path then return "" end
	return path:gsub("^" .. M.home, "~")
end

-- ============================================================================
-- SHELL COMMAND UTILITIES
-- ============================================================================

-- Spawn a new window running a shell command
-- @param cmd: Command to run
-- @param opts: Optional table { cwd, login, interactive }
--   cwd: Working directory
--   login: Use login shell (-l flag)
--   interactive: Use interactive shell (-i flag)
function M.spawn_cmd(cmd, opts)
	opts = opts or {}
	local flags = ""
	if opts.login then flags = flags .. "l" end
	if opts.interactive then flags = flags .. "i" end
	if flags ~= "" then flags = "-" .. flags end

	local args
	if flags ~= "" then
		args = { cfg.default_shell, flags, "-c", cmd }
	else
		args = { cfg.default_shell, "-c", cmd }
	end

	return wezterm.mux.spawn_window({
		cwd = opts.cwd,
		args = args,
	})
end

-- Spawn a popup window that displays a message and waits for Enter
-- @param msg: Message to display
-- @param opts: Optional table { cwd, title }
function M.spawn_popup(msg, opts)
	opts = opts or {}
	-- Escape double quotes in message
	local escaped_msg = msg:gsub('"', '\\"')
	local cmd = string.format('echo "%s"; read', escaped_msg)
	return M.spawn_cmd(cmd, { cwd = opts.cwd })
end

-- Spawn a popup that shows message and auto-closes after delay
-- @param msg: Message to display
-- @param delay: Seconds to wait before closing (default: 1)
function M.spawn_toast(msg, delay)
	delay = delay or 1
	local escaped_msg = msg:gsub('"', '\\"')
	local cmd = string.format('echo "%s"; sleep %d', escaped_msg, delay)
	return M.spawn_cmd(cmd)
end

-- Spawn editor with a file
-- @param file: File path to edit
-- @param opts: Optional table { cwd, editor }
function M.spawn_editor(file, opts)
	opts = opts or {}
	local editor = opts.editor or os.getenv("EDITOR") or cfg.default_editor
	local cmd = string.format("exec %s %q", editor, file)
	return M.spawn_cmd(cmd, { cwd = opts.cwd, login = true })
end

-- ============================================================================
-- STRING UTILITIES
-- ============================================================================

-- Check if string is empty or nil
function M.is_empty(str)
	return str == nil or str == ""
end

return M

