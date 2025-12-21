-- command_palette.lua - Custom command palette entries
-- Extend WezTerm's built-in command palette with custom actions

local wezterm = require("wezterm")
local act = wezterm.action
local cfg = require("config")
local theme = require("theme")
local utils = require("utils")

local M = {}

-- ============================================================================
-- COMMAND DEFINITIONS
-- ============================================================================
-- Each command has: brief (title), icon (nerdfonts key), action
M.commands = {
	-- ========================================================================
	-- TAB & WORKSPACE
	-- ========================================================================
	{
		brief = "Rename Tab",
		icon = "md_rename_box",
		-- Reuse callbacks.rename_tab instead of duplicating
		action = wezterm.action_callback(function(win, p)
			local callbacks = require("callbacks")
			callbacks.rename_tab(win, p)
		end),
	},
	{
		brief = "Create New Workspace",
		icon = "md_plus_box",
		action = act.PromptInputLine({
			description = "Enter name for new workspace",
			action = wezterm.action_callback(function(win, p, line)
				if line then
					win:perform_action(act.SwitchToWorkspace({ name = line }), p)
				end
			end),
		}),
	},
	{
		brief = "Switch Workspace",
		icon = "md_layers",
		action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }),
	},

	-- ========================================================================
	-- THEME & APPEARANCE
	-- ========================================================================
	{
		brief = "Theme: Switch to Parallax Background",
		icon = "md_image_multiple",
		action = wezterm.action_callback(function(win, p)
			local overrides = win:get_config_overrides() or {}
			-- Use theme's parallax background generator
			overrides.background = theme.get_parallax_background()
			win:set_config_overrides(overrides)
		end),
	},
	{
		brief = "Theme: Reset to Default Background",
		icon = "md_refresh",
		action = wezterm.action_callback(function(win, p)
			local overrides = win:get_config_overrides() or {}
			overrides.background = nil
			win:set_config_overrides(overrides)
		end),
	},
	{
		brief = "Theme: Toggle Transparency",
		icon = "md_circle_opacity",
		action = wezterm.action_callback(function(win, p)
			local overrides = win:get_config_overrides() or {}
			if overrides.window_background_opacity == 0.85 then
				overrides.window_background_opacity = 1.0
			else
				overrides.window_background_opacity = 0.85
			end
			win:set_config_overrides(overrides)
		end),
	},

	-- ========================================================================
	-- UTILITIES
	-- ========================================================================
	{
		brief = "Show Keybinding Help",
		icon = "md_keyboard",
		-- Reuse callbacks.cheatsheet instead of duplicating
		action = wezterm.action_callback(function(win, p)
			local callbacks = require("callbacks")
			callbacks.cheatsheet(win, p)
		end),
	},
	{
		brief = "Edit Scrollback in $EDITOR",
		icon = "dev_vim",
		action = wezterm.action_callback(function(win, p)
			local text = p:get_lines_as_text(p:get_dimensions().scrollback_rows)
			local name = os.tmpname()
			local f = io.open(name, "w+")
			if f then
				f:write(text)
				f:close()
				utils.spawn_editor(name)
			end
		end),
	},
	{
		brief = "Connect to SSH Host",
		icon = "md_console_network",
		action = act.ShowLauncherArgs({ flags = "FUZZY|DOMAINS" }),
	},
	{
		brief = "Clear Scrollback",
		icon = "md_delete_sweep",
		action = act.ClearScrollback("ScrollbackAndViewport"),
	},
	{
		brief = "Debug: Show Pane Info",
		icon = "md_bug",
		action = wezterm.action_callback(function(win, pane)
			local info = {
				"Pane ID: " .. pane:pane_id(),
				"Dimensions: " .. pane:get_dimensions().cols .. "x" .. pane:get_dimensions().viewport_rows,
				"CWD: " .. utils.get_cwd(pane, "unknown"),
				"Process: " .. (pane:get_foreground_process_name() or "unknown"),
			}
			local user_vars = pane:get_user_vars()
			if next(user_vars) then
				table.insert(info, "User Variables:")
				for k, v in pairs(user_vars) do
					table.insert(info, "  " .. k .. " = " .. v)
				end
			end
			utils.spawn_popup(table.concat(info, "\n"))
		end),
	},
}

-- ============================================================================
-- GET ALL COMMANDS
-- ============================================================================
function M.get_commands()
	return M.commands
end

-- ============================================================================
-- REGISTER EVENT HANDLER
-- ============================================================================
function M.setup()
	wezterm.on("augment-command-palette", function(window, pane)
		return M.get_commands()
	end)
end

return M

