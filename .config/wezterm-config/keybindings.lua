-- keybindings.lua - Centralized keybinding definitions
-- All keybindings are defined here with descriptions for auto-generated cheatsheet

local wezterm = require("wezterm")
local act = wezterm.action
local callbacks = require("callbacks")
local quickselect = require("quickselect")

local M = {}

-- ============================================================================
-- KEYBINDING DEFINITIONS
-- ============================================================================
-- Each entry: { key, mods, action, description, category }
-- Categories: "pane", "tab", "workspace", "utility", "session", "other"

M.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 2000 }

M.bindings = {
	-- ========================================================================
	-- PANE MANAGEMENT
	-- ========================================================================
	{
		key = "|",
		mods = "LEADER|SHIFT",
		action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }),
		desc = "Split vertical",
		cat = "pane",
	},
	{
		key = "-",
		mods = "LEADER",
		action = act.SplitVertical({ domain = "CurrentPaneDomain" }),
		desc = "Split horizontal",
		cat = "pane",
	},
	{
		key = "h",
		mods = "LEADER",
		action = act.ActivatePaneDirection("Left"),
		desc = "Navigate left",
		cat = "pane",
	},
	{
		key = "j",
		mods = "LEADER",
		action = act.ActivatePaneDirection("Down"),
		desc = "Navigate down",
		cat = "pane",
	},
	{
		key = "k",
		mods = "LEADER",
		action = act.ActivatePaneDirection("Up"),
		desc = "Navigate up",
		cat = "pane",
	},
	-- Note: 'l' is used for "Last tab", use arrow key for right pane
	{
		key = "LeftArrow",
		mods = "LEADER",
		action = act.ActivatePaneDirection("Left"),
		desc = "Navigate left",
		cat = "pane",
		hidden = true, -- Don't show in cheatsheet (duplicate)
	},
	{
		key = "DownArrow",
		mods = "LEADER",
		action = act.ActivatePaneDirection("Down"),
		desc = "Navigate down",
		cat = "pane",
		hidden = true,
	},
	{
		key = "UpArrow",
		mods = "LEADER",
		action = act.ActivatePaneDirection("Up"),
		desc = "Navigate up",
		cat = "pane",
		hidden = true,
	},
	{
		key = "RightArrow",
		mods = "LEADER",
		action = act.ActivatePaneDirection("Right"),
		desc = "Navigate right",
		cat = "pane",
		hidden = true,
	},
	{
		key = "h",
		mods = "LEADER|ALT",
		action = act.AdjustPaneSize({ "Left", 5 }),
		desc = "Resize left",
		cat = "pane",
	},
	{
		key = "j",
		mods = "LEADER|ALT",
		action = act.AdjustPaneSize({ "Down", 5 }),
		desc = "Resize down",
		cat = "pane",
	},
	{
		key = "k",
		mods = "LEADER|ALT",
		action = act.AdjustPaneSize({ "Up", 5 }),
		desc = "Resize up",
		cat = "pane",
	},
	{
		key = "l",
		mods = "LEADER|ALT",
		action = act.AdjustPaneSize({ "Right", 5 }),
		desc = "Resize right",
		cat = "pane",
	},
	{
		key = "z",
		mods = "LEADER",
		action = act.TogglePaneZoomState,
		desc = "Zoom pane",
		cat = "pane",
	},
	{
		key = "x",
		mods = "LEADER",
		action = act.CloseCurrentPane({ confirm = true }),
		desc = "Close pane",
		cat = "pane",
	},
	{
		key = "o",
		mods = "LEADER",
		action = act.ActivatePaneDirection("Next"),
		desc = "Next pane",
		cat = "pane",
	},
	{
		key = ";",
		mods = "LEADER",
		action = "callback:last_pane", -- Special marker for callback
		desc = "Last pane",
		cat = "pane",
	},
	{
		key = "!",
		mods = "LEADER|SHIFT",
		action = "callback:pane_to_tab",
		desc = "Pane → new tab",
		cat = "pane",
	},

	-- ========================================================================
	-- TAB MANAGEMENT
	-- ========================================================================
	{
		key = "c",
		mods = "LEADER",
		action = act.SpawnTab("CurrentPaneDomain"),
		desc = "New tab",
		cat = "tab",
	},
	{
		key = "n",
		mods = "LEADER",
		action = act.ActivateTabRelative(1),
		desc = "Next tab",
		cat = "tab",
	},
	{
		key = "p",
		mods = "LEADER",
		action = act.ActivateTabRelative(-1),
		desc = "Previous tab",
		cat = "tab",
	},
	{
		key = "l",
		mods = "LEADER",
		action = act.ActivateLastTab,
		desc = "Last tab",
		cat = "tab",
	},
	{
		key = "&",
		mods = "LEADER|SHIFT",
		action = act.CloseCurrentTab({ confirm = true }),
		desc = "Close tab",
		cat = "tab",
	},
	{
		key = ",",
		mods = "LEADER",
		action = "callback:rename_tab",
		desc = "Rename tab",
		cat = "tab",
	},
	{
		key = "w",
		mods = "LEADER",
		action = act.ShowTabNavigator,
		desc = "Tab navigator",
		cat = "tab",
	},

	-- ========================================================================
	-- WORKSPACE MANAGEMENT
	-- ========================================================================
	{
		key = "s",
		mods = "LEADER",
		action = "callback:workspace_switcher",
		desc = "Switch workspace",
		cat = "workspace",
	},
	{
		key = "N",
		mods = "LEADER|SHIFT",
		action = "callback:new_workspace",
		desc = "New workspace",
		cat = "workspace",
	},
	{
		key = "$",
		mods = "LEADER|SHIFT",
		action = "callback:rename_workspace",
		desc = "Rename workspace",
		cat = "workspace",
	},
	{
		key = "L",
		mods = "LEADER|SHIFT",
		action = "callback:last_workspace",
		desc = "Last workspace",
		cat = "workspace",
	},
	{
		key = "(",
		mods = "LEADER|SHIFT",
		action = act.SwitchWorkspaceRelative(-1),
		desc = "Prev workspace",
		cat = "workspace",
	},
	{
		key = ")",
		mods = "LEADER|SHIFT",
		action = act.SwitchWorkspaceRelative(1),
		desc = "Next workspace",
		cat = "workspace",
	},
	{
		key = "X",
		mods = "LEADER|SHIFT",
		action = "callback:kill_workspace",
		desc = "Kill workspace",
		cat = "workspace",
	},

	-- ========================================================================
	-- UTILITIES
	-- ========================================================================
	{
		key = "[",
		mods = "LEADER",
		action = act.ActivateCopyMode,
		desc = "Copy mode",
		cat = "utility",
	},
	{
		key = "]",
		mods = "LEADER",
		action = act.PasteFrom("Clipboard"),
		desc = "Paste",
		cat = "utility",
	},
	{
		key = "/",
		mods = "LEADER",
		action = act.Search({ CaseInSensitiveString = "" }),
		desc = "Search",
		cat = "utility",
	},
	{
		key = ":",
		mods = "LEADER|SHIFT",
		action = act.ActivateCommandPalette,
		desc = "Command palette",
		cat = "utility",
	},
	{
		key = "Space",
		mods = "LEADER",
		action = act.QuickSelect,
		desc = "Quick select (default)",
		cat = "utility",
	},
	-- QuickSelectArgs are defined in quickselect.lua and merged in get_keys()
	{
		key = "i",
		mods = "LEADER",
		action = "callback:pane_info",
		desc = "Pane info",
		cat = "utility",
	},
	{
		key = "?",
		mods = "LEADER",
		action = "callback:cheatsheet",
		desc = "Keybinding help",
		cat = "utility",
	},
	-- ========================================================================
	-- SESSION PERSISTENCE
	-- ========================================================================
	{
		key = "s",
		mods = "LEADER|CTRL",
		action = "callback:save_session",
		desc = "Save session",
		cat = "session",
	},
	{
		key = "r",
		mods = "LEADER|CTRL",
		action = "callback:restore_session",
		desc = "Restore session",
		cat = "session",
	},
	{
		key = "d",
		mods = "LEADER|CTRL",
		action = "callback:delete_session",
		desc = "Delete saved session",
		cat = "session",
	},

	-- ========================================================================
	-- OTHER
	-- ========================================================================
	{
		key = "r",
		mods = "LEADER",
		action = act.ReloadConfiguration,
		desc = "Reload config",
		cat = "other",
	},
	{
		key = "d",
		mods = "LEADER",
		action = act.QuitApplication,
		desc = "Quit",
		cat = "other",
	},
	{
		key = "g",
		mods = "LEADER",
		action = "callback:git_status",
		desc = "Git status",
		cat = "other",
	},
	{
		key = "j",
		mods = "LEADER",
		action = "callback:project_jump",
		desc = "Jump to project",
		cat = "other",
	},
}

-- Tab activation by number (0-9)
for i = 0, 9 do
	table.insert(M.bindings, {
		key = tostring(i),
		mods = "LEADER",
		action = act.ActivateTab(i == 0 and -1 or i - 1),
		desc = "Go to tab " .. i,
		cat = "tab",
		hidden = true, -- Don't clutter cheatsheet
	})
end

-- ============================================================================
-- GENERATE CHEATSHEET
-- ============================================================================
function M.generate_cheatsheet()
	local categories = {
		{ id = "pane", title = "PANE MANAGEMENT" },
		{ id = "tab", title = "TAB MANAGEMENT" },
		{ id = "workspace", title = "WORKSPACE MANAGEMENT" },
		{ id = "utility", title = "UTILITIES" },
		{ id = "quickselect", title = "QUICK SELECT" },
		{ id = "session", title = "SESSION PERSISTENCE" },
		{ id = "other", title = "OTHER" },
	}

	-- Merge main bindings with quickselect bindings for cheatsheet
	local all_bindings = {}
	for _, b in ipairs(M.bindings) do
		table.insert(all_bindings, b)
	end
	for _, qs in ipairs(quickselect.selectors) do
		table.insert(all_bindings, qs)
	end

	local lines = {}
	table.insert(lines, "╔══════════════════════════════════════════════════════════════╗")
	table.insert(lines, "║               WEZTERM KEYBINDINGS (Ctrl+b)                   ║")
	table.insert(lines, "╠══════════════════════════════════════════════════════════════╣")

	for _, cat in ipairs(categories) do
		local bindings_in_cat = {}
		for _, b in ipairs(all_bindings) do
			if b.cat == cat.id and not b.hidden then
				table.insert(bindings_in_cat, b)
			end
		end

		-- Skip empty categories
		if #bindings_in_cat > 0 then
			table.insert(lines, "║  " .. cat.title .. string.rep(" ", 60 - #cat.title - 2) .. "║")

			-- Format in two columns
			for i = 1, #bindings_in_cat, 2 do
				local b1 = bindings_in_cat[i]
				local b2 = bindings_in_cat[i + 1]

				local key1 = M.format_key(b1)
				local col1 = string.format("  %-8s %-18s", key1, b1.desc)

				local col2 = ""
				if b2 then
					local key2 = M.format_key(b2)
					col2 = string.format("%-8s %-16s", key2, b2.desc)
				end

				local line = "║" .. col1 .. col2 .. string.rep(" ", 62 - #col1 - #col2) .. "║"
				table.insert(lines, line)
			end

			table.insert(lines, "╠══════════════════════════════════════════════════════════════╣")
		end
	end

	-- Remove last separator and add footer
	table.remove(lines)
	table.insert(lines, "╚══════════════════════════════════════════════════════════════╝")
	table.insert(lines, "")
	table.insert(lines, "                    Press Enter to close")

	return table.concat(lines, "\n")
end

function M.format_key(binding)
	local key = binding.key
	local mods = binding.mods or ""

	-- Simplify display
	if key == "Space" then
		key = "Spc"
	end
	if key == "LeftArrow" then
		key = "←"
	end
	if key == "RightArrow" then
		key = "→"
	end
	if key == "UpArrow" then
		key = "↑"
	end
	if key == "DownArrow" then
		key = "↓"
	end

	-- Show modifier shortcuts
	if mods:find("SHIFT") and #key == 1 then
		key = key:upper()
	elseif mods:find("ALT") then
		key = "M-" .. key
	elseif mods:find("CTRL") and mods:find("LEADER") then
		key = "C-" .. key
	end

	return key
end
-- ============================================================================
-- BUILD CONFIG KEYS
-- ============================================================================
-- Returns the keys table for wezterm config (resolves all callbacks)
function M.get_keys()
	local keys = {}

	-- Add Ctrl+b pass-through (send literal Ctrl+b when pressing Ctrl+b twice)
	table.insert(keys, {
		key = "b",
		mods = "LEADER|CTRL",
		action = act.SendKey({ key = "b", mods = "CTRL" }),
	})

	-- Add main bindings
	for _, b in ipairs(M.bindings) do
		local action = b.action

		-- Resolve callback actions
		if type(action) == "string" and action:match("^callback:") then
			local callback_name = action:gsub("^callback:", "")
			action = callbacks.get_action(callback_name)
		end

		if action then
			table.insert(keys, {
				key = b.key,
				mods = b.mods,
				action = action,
			})
		end
	end

	-- Add QuickSelect bindings from quickselect module
	for _, qs in ipairs(quickselect.get_bindings()) do
		table.insert(keys, {
			key = qs.key,
			mods = qs.mods,
			action = qs.action,
		})
	end

	return keys
end

return M

