-- wezterm.lua - Main WezTerm configuration
-- Orchestrates all modules: theme, keybindings, plugins, icons, callbacks

local wezterm = require("wezterm")
local cfg = require("config")
local utils = require("utils")
local keybindings = require("keybindings")
local theme = require("theme")
local plugins = require("plugins")
local icons = require("icons")
local callbacks = require("callbacks")

local config = wezterm.config_builder()

-- ============================================================================
-- APPLY MODULES
-- ============================================================================

-- Apply theme (colors, background, visual settings)
theme.apply(config)

-- Initialize plugins (resurrect, etc.)
plugins.init()

-- Apply keybindings (leader key + all keys)
config.leader = keybindings.leader
config.keys = keybindings.get_keys()

-- ============================================================================
-- CONFIG RELOAD NOTIFICATION
-- ============================================================================
local config_reloaded_at = nil

wezterm.on("window-config-reloaded", function(window, pane)
	config_reloaded_at = os.time()
	window:toast_notification("WezTerm", "Configuration reloaded! ✓", nil, 3000)
end)

-- ============================================================================
-- STATUS BAR (like tmux status line)
-- ============================================================================
wezterm.on("update-right-status", function(window, pane)
	-- Update state tracking (for last pane/workspace features)
	callbacks.update_state(window, pane)

	local workspace = window:active_workspace()
	local date = wezterm.strftime("%H:%M %b %d")
	local leader_active = window:leader_is_active()
	local config_reloaded = config_reloaded_at and (os.time() - config_reloaded_at) < 3

	local status_elements = theme.format_status(workspace, date, leader_active, config_reloaded)
	window:set_right_status(wezterm.format(status_elements))
end)

-- ============================================================================
-- TAB TITLE FORMATTING (with Nerd Font icons + unseen output indicator)
-- ============================================================================
wezterm.on("format-tab-title", function(tab, tabs, panes, config_from_wezterm, hover, max_width)
	local pane_info = tab.active_pane
	local index = tab.tab_index + 1

	-- Check for unseen output in any pane of this tab
	local has_unseen_output = false
	for _, p in ipairs(tab.panes) do
		if p.has_unseen_output then
			has_unseen_output = true
			break
		end
	end

	-- Get the process name
	local process_name = pane_info.foreground_process_name or ""
	local process = process_name:match("([^/]+)$") or ""

	-- Check if it's a shell (O(1) lookup from config.lua hash table)
	local is_shell = process == "" or cfg.shell_names[process:lower()]

	-- Get current directory info
	local title = process
	local full_path = ""
	local cwd = pane_info.current_working_dir
	if cwd then
		full_path = cwd.file_path or cwd.path or ""
		local display_path = utils.collapse_home(full_path)
		local basename = display_path:match("([^/]+)/?$") or display_path
		if basename and basename ~= "" then
			title = basename
		end
	end

	-- Choose icon based on context
	local icon
	if is_shell then
		icon = icons.get_dir(full_path)
	else
		icon = icons.get(process)
		title = process
	end

	-- Read user variables (set by shell integration)
	-- Example user vars: WEZTERM_PROG, GIT_BRANCH, PROJECT_NAME
	local user_vars = pane_info.user_vars or {}
	local user_var_suffix = ""

	-- Show git branch if set
	if user_vars.GIT_BRANCH and user_vars.GIT_BRANCH ~= "" then
		user_var_suffix = " " .. wezterm.nerdfonts.dev_git_branch .. " " .. user_vars.GIT_BRANCH
	end

	-- Show project name if set (overrides title)
	if user_vars.PROJECT_NAME and user_vars.PROJECT_NAME ~= "" then
		title = user_vars.PROJECT_NAME
	end

	-- Truncate if too long
	local max_title = max_width - 6 - #user_var_suffix
	if #title > max_title then
		title = title:sub(1, max_title - 2) .. "…"
	end

	-- Add zoom indicator
	local zoom = ""
	if tab.active_pane.is_zoomed then
		zoom = wezterm.nerdfonts.md_magnify .. " "
	end

	-- Build tab title text
	local tab_text = string.format(" %d: %s%s %s%s ", index, zoom, icon, title, user_var_suffix)

	-- Delegate styling to theme module
	return theme.format_tab_title(tab_text, {
		is_active = tab.is_active,
		has_unseen_output = has_unseen_output,
		hover = hover,
	}, wezterm.nerdfonts.md_bell)
end)

-- ============================================================================
-- FONT CONFIGURATION (from config.lua)
-- ============================================================================
config.font = wezterm.font(cfg.font.family, { weight = cfg.font.weight })
config.font_size = cfg.font.size
config.line_height = cfg.font.line_height

-- ============================================================================
-- WINDOW SIZE (from config.lua)
-- ============================================================================
config.initial_rows = cfg.window.initial_rows
config.initial_cols = cfg.window.initial_cols

-- ============================================================================
-- TAB BAR SETTINGS (from config.lua)
-- ============================================================================
config.tab_max_width = cfg.tab.max_width
config.show_tab_index_in_tab_bar = cfg.tab.show_index

-- ============================================================================
-- MULTIPLEXING (like tmux - sessions persist if terminal closes)
-- ============================================================================

-- Unix domain for local multiplexing
-- Sessions persist even when GUI is closed!
config.unix_domains = {
	{
		name = "unix",
	},
}

-- Auto-connect to multiplexer on startup (like tmux attach)
-- This makes WezTerm behave like tmux - close window, reopen, sessions are there
config.default_gui_startup_args = { "connect", "unix" }

-- SSH domains - auto-parsed from ~/.ssh/config
-- Each host in your ssh config becomes a connectable domain
config.ssh_domains = wezterm.default_ssh_domains()

-- Add custom SSH domains here:
-- table.insert(config.ssh_domains, {
--     name = "my-server",
--     remote_address = "server.example.com",
--     username = "myuser",
--     multiplexing = "None",  -- Use "None" if wezterm not installed on remote
--     assume_shell = "Posix", -- Enables cwd tracking on remote
-- })

-- ============================================================================
-- PRODUCTIVITY FEATURES
-- ============================================================================

-- Quick select mode patterns (reused from quickselect.lua to avoid duplication)
local quickselect = require("quickselect")
config.quick_select_patterns = quickselect.get_all_patterns()

-- Hyperlink detection (Cmd/Ctrl+Click to open)
-- NOTE: For opening files in $EDITOR, use QuickSelect (Ctrl+b e) instead
--       Hyperlink rules can only open URLs, not run commands
config.hyperlink_rules = wezterm.default_hyperlink_rules()

-- GitHub issues/PRs: #123 or owner/repo#123
-- Example: myorg/myrepo#456 → https://github.com/myorg/myrepo/issues/456
table.insert(config.hyperlink_rules, {
	regex = [[\b([A-Za-z0-9_-]+/[A-Za-z0-9_-]+)#(\d+)\b]],
	format = cfg.urls.github,
})

-- JIRA tickets: PROJ-1234 (configure URL in config.lua)
table.insert(config.hyperlink_rules, {
	regex = [[\b([A-Z][A-Z0-9]+-\d+)\b]],
	format = cfg.urls.jira,
})

-- Localhost URLs with port: localhost:3000, 127.0.0.1:8080
table.insert(config.hyperlink_rules, {
	regex = [[\b(localhost|127\.0\.0\.1):(\d+)\b]],
	format = "http://$1:$2",
})

-- Generic URLs (fallback)
table.insert(config.hyperlink_rules, {
	regex = "\\b\\w+://[\\w.-]+\\.[a-z]{2,15}\\S*\\b",
	format = "$0",
})

-- Bell
config.audible_bell = "Disabled"

-- ============================================================================
-- COMMAND PALETTE CUSTOMIZATION (Ctrl+Shift+P or Leader + :)
-- ============================================================================
local command_palette = require("command_palette")
command_palette.setup()

-- ============================================================================
-- MOUSE BINDINGS (copy on select + semantic zones)
-- ============================================================================
config.selection_word_boundary = " \t\n{}[]()\"'`,;:@"
config.mouse_bindings = {
	-- Right click pastes
	{
		event = { Down = { streak = 1, button = "Right" } },
		mods = "NONE",
		action = wezterm.action.PasteFrom("Clipboard"),
	},
	-- Copy on select
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "NONE",
		action = wezterm.action.CompleteSelection("ClipboardAndPrimarySelection"),
	},
	-- Triple-click selects SEMANTIC ZONE (entire command output)
	-- Requires shell integration: https://wezfurlong.org/wezterm/shell-integration.html
	{
		event = { Down = { streak = 3, button = "Left" } },
		mods = "NONE",
		action = wezterm.action.SelectTextAtMouseCursor("SemanticZone"),
	},
	{
		event = { Up = { streak = 3, button = "Left" } },
		mods = "NONE",
		action = wezterm.action.CompleteSelection("ClipboardAndPrimarySelection"),
	},
}

return config
