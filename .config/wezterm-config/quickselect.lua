-- quickselect.lua - Centralized QuickSelect patterns and actions
-- All QuickSelectArgs configurations in one place for easy customization

local wezterm = require("wezterm")
local act = wezterm.action
local cfg = require("config")
local utils = require("utils")

local M = {}

-- ============================================================================
-- PATTERN DEFINITIONS
-- ============================================================================
-- These patterns can be reused across QuickSelect and other features

-- Only patterns that are actually used in selectors or get_all_patterns()
M.patterns = {
	-- URLs
	url = "https?://\\S+",

	-- Git
	git_hash = "[0-9a-f]{7,40}",

	-- File paths (supports dotfiles like .config, .gitignore)
	file_path = "/?[\\w.-]*[/][\\w./-]+",
	dotfile = "\\.[\\w.-]+", -- .gitignore, .zshrc

	-- Network
	ip_address = "\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}",
	ip_with_port = "\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}:\\d+",

	-- Identifiers
	uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
}

-- ============================================================================
-- QUICK SELECT CONFIGURATIONS
-- ============================================================================
-- Each config defines: key, mods, label, patterns, action (optional), desc

M.selectors = {
	-- Open URL in browser
	{
		key = "u",
		mods = "LEADER",
		label = "open url",
		patterns = { M.patterns.url },
		action = function(window, pane)
			local url = window:get_selection_text_for_pane(pane)
			if url and url ~= "" then
				wezterm.log_info("Opening: " .. url)
				wezterm.open_with(url)
			end
		end,
		desc = "Open URL in browser",
		cat = "quickselect",
	},

	-- Copy git hash
	{
		key = "H",
		mods = "LEADER|SHIFT",
		label = "copy git hash",
		patterns = { M.patterns.git_hash },
		-- No action = copies to clipboard (default)
		desc = "Copy git hash",
		cat = "quickselect",
	},

	-- Edit file in $EDITOR (fallback defined in config.lua)
	{
		key = "e",
		mods = "LEADER",
		label = "edit file",
		patterns = { M.patterns.file_path, M.patterns.dotfile },
		action = function(window, pane)
			local path = window:get_selection_text_for_pane(pane)
			if utils.is_empty(path) then return end

			path = utils.expand_home(path)
			wezterm.log_info("Opening in editor: " .. path)

			utils.spawn_editor(path, { cwd = utils.get_cwd(pane) })
		end,
		desc = "Edit file in $EDITOR",
		cat = "quickselect",
	},

	-- Copy IP address
	{
		key = "I",
		mods = "LEADER|SHIFT",
		label = "copy IP address",
		patterns = { M.patterns.ip_with_port, M.patterns.ip_address },
		desc = "Copy IP address",
		cat = "quickselect",
	},

	-- Copy UUID
	{
		key = "U",
		mods = "LEADER|SHIFT",
		label = "copy UUID",
		patterns = { M.patterns.uuid },
		desc = "Copy UUID",
		cat = "quickselect",
	},
}

-- ============================================================================
-- BUILD KEYBINDINGS
-- ============================================================================
-- Converts selector configs into wezterm keybindings

function M.get_bindings()
	local bindings = {}

	for _, sel in ipairs(M.selectors) do
		local quick_select_args = {
			label = sel.label,
			patterns = sel.patterns,
		}

		-- Add custom action if defined
		if sel.action then
			quick_select_args.action = wezterm.action_callback(sel.action)
		end

		table.insert(bindings, {
			key = sel.key,
			mods = sel.mods,
			action = act.QuickSelectArgs(quick_select_args),
			desc = sel.desc,
			cat = sel.cat,
		})
	end

	return bindings
end

-- ============================================================================
-- GET ALL PATTERNS (for config.quick_select_patterns)
-- ============================================================================
-- Returns a flat list of common patterns for default QuickSelect mode

function M.get_all_patterns()
	return {
		M.patterns.git_hash,
		M.patterns.uuid,
		M.patterns.ip_address,
		M.patterns.file_path,
		"~/[\\w./-]+", -- Home-relative paths
	}
end

return M
