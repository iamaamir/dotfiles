-- plugins.lua - Centralized plugin management
-- All wezterm plugins are loaded and configured here

local wezterm = require("wezterm")
local cfg = require("config")
local utils = require("utils")

local M = {}

-- ============================================================================
-- PLUGIN REGISTRY
-- ============================================================================
-- Add new plugins here with their configuration

M.plugins = {
	-- Session persistence (like tmux-resurrect)
	resurrect = {
		enabled = true,
		url = "https://github.com/MLFlexer/resurrect.wezterm",
		config = {
			auto_save_interval = cfg.session.auto_save_interval,
			save_workspaces = true,
			save_windows = true,
			save_tabs = true,
		},
	},

	-- Add more plugins here as needed:
	-- example_plugin = {
	--     enabled = false,
	--     url = "https://github.com/user/plugin.wezterm",
	--     config = {},
	-- },
}

-- ============================================================================
-- LOADED PLUGINS (populated after init)
-- ============================================================================
M.loaded = {}

-- ============================================================================
-- INITIALIZE PLUGINS
-- ============================================================================
function M.init()
	if not M.plugins.resurrect.enabled then
		return
	end

	-- Load resurrect plugin
	local ok, resurrect = pcall(function()
		return wezterm.plugin.require(M.plugins.resurrect.url)
	end)

	if not ok or not resurrect then
		wezterm.log_error("Failed to load resurrect plugin: " .. tostring(resurrect))
		return
	end

	M.loaded.resurrect = resurrect

	-- Set custom state directory (cleaner location, easier to manage)
	resurrect.state_manager.change_state_save_dir(cfg.session.state_dir)

	-- SESSION PERSISTENCE STRATEGY:
	-- 1. Mux server (unix_domains) → seamless close/reopen during a session
	-- 2. Resurrect plugin → restore after system restart or crash
	--
	-- On mux-startup: restore saved workspaces (only runs when mux server starts fresh)
	-- This does NOT run when GUI reconnects to existing mux server

	wezterm.on("mux-startup", function()
		-- Check for saved workspace states
		local state_path = cfg.session.state_dir .. "workspace"
		local handle = io.popen('ls "' .. state_path .. '"/*.json 2>/dev/null')
		local saved_files = handle and handle:read("*a") or ""
		if handle then handle:close() end

		-- Parse workspace names from file paths
		local saved_workspaces = {}
		for file in saved_files:gmatch("[^\n]+") do
			local name = file:match("([^/]+)%.json$")
			if name then
				table.insert(saved_workspaces, name)
			end
		end

		if #saved_workspaces > 0 then
			wezterm.log_info("Restoring " .. #saved_workspaces .. " workspace(s) from backup...")

			for i, workspace_name in ipairs(saved_workspaces) do
				local state = resurrect.state_manager.load_state(workspace_name, "workspace")
				if state then
					if i == 1 then
						-- First workspace: create initial window
						local tab, pane, window = wezterm.mux.spawn_window({
							workspace = workspace_name,
							cwd = utils.home,
						})
						resurrect.workspace_state.restore_workspace(state, {
							relative = true,
							restore_text = true,
							on_pane_restore = resurrect.tab_state.default_on_pane_restore,
							window = window,
						})
					else
						-- Additional workspaces
						local new_tab, new_pane, new_window = wezterm.mux.spawn_window({
							workspace = workspace_name,
							cwd = utils.home,
						})
						resurrect.workspace_state.restore_workspace(state, {
							relative = true,
							restore_text = true,
							on_pane_restore = resurrect.tab_state.default_on_pane_restore,
							window = new_window,
						})
					end
				end
			end

			-- Switch to first workspace
			if saved_workspaces[1] then
				wezterm.mux.set_active_workspace(saved_workspaces[1])
			end
		end
	end)

	-- Periodic auto-save (backup for crash/restart recovery)
	resurrect.state_manager.periodic_save({
		interval_seconds = M.plugins.resurrect.config.auto_save_interval,
		save_workspaces = M.plugins.resurrect.config.save_workspaces,
		save_windows = M.plugins.resurrect.config.save_windows,
		save_tabs = M.plugins.resurrect.config.save_tabs,
	})
end

-- ============================================================================
-- PLUGIN ACTIONS (for keybindings)
-- ============================================================================

-- Save all workspaces (resurrect)
function M.save_session(window, pane)
	if not M.loaded.resurrect then
		utils.spawn_toast("ERROR: Resurrect plugin not loaded", 2)
		return
	end

	local resurrect = M.loaded.resurrect
	local saved_count = 0
	local errors = {}

	-- Get all workspace names
	local workspaces = wezterm.mux.get_workspace_names()
	local current_workspace = wezterm.mux.get_active_workspace()

	for _, workspace_name in ipairs(workspaces) do
		local ok, err = pcall(function()
			-- Switch to workspace temporarily to get its state
			wezterm.mux.set_active_workspace(workspace_name)

			-- Small delay to ensure workspace is active
			local state = resurrect.workspace_state.get_workspace_state()
			resurrect.state_manager.save_state(state)
			saved_count = saved_count + 1
		end)

		if not ok then
			table.insert(errors, workspace_name .. ": " .. tostring(err))
		end
	end

	-- Switch back to original workspace
	wezterm.mux.set_active_workspace(current_workspace)

	if #errors == 0 then
		utils.spawn_toast("✓ Saved " .. saved_count .. " workspace(s)!", 1)
	else
		utils.spawn_toast("Saved " .. saved_count .. ", errors: " .. #errors, 2)
	end
end

-- Restore session (resurrect)
function M.restore_session(window, pane)
	if not M.loaded.resurrect then
		utils.spawn_toast("ERROR: Resurrect plugin not loaded", 2)
		return
	end

	local resurrect = M.loaded.resurrect
	local act = wezterm.action

	resurrect.fuzzy_loader.fuzzy_load(window, pane, function(id, label)
		-- id format: "type/name.json" e.g., "workspace/UDS.json"
		local state_type = string.match(id, "^([^/]+)")
		local state_name = string.match(id, "/(.+)$")
		if state_name then
			state_name = string.match(state_name, "(.+)%.json$")
		end

		if not state_type or not state_name then
			return
		end

		local opts = {
			relative = true,
			restore_text = true,
			on_pane_restore = resurrect.tab_state.default_on_pane_restore,
		}

		if state_type == "workspace" then
			local state = resurrect.state_manager.load_state(state_name, "workspace")
			if state then
				window:perform_action(
					act.SwitchToWorkspace({
						name = state_name,
						spawn = { cwd = utils.home },
					}),
					pane
				)
				wezterm.time.call_after(0.1, function()
					local mux_win = wezterm.mux.get_active_window()
					if mux_win then
						opts.window = mux_win
						resurrect.workspace_state.restore_workspace(state, opts)
					end
				end)
			end
		elseif state_type == "window" then
			local state = resurrect.state_manager.load_state(state_name, "window")
			if state then
				opts.window = pane:window()
				resurrect.window_state.restore_window(pane:window(), state, opts)
			end
		elseif state_type == "tab" then
			local state = resurrect.state_manager.load_state(state_name, "tab")
			if state then
				resurrect.tab_state.restore_tab(pane:tab(), state, opts)
			end
		end
	end)
end

-- Delete session (resurrect) - uses fuzzy finder
function M.delete_session(window, pane)
	if not M.loaded.resurrect then
		utils.spawn_toast("ERROR: Resurrect plugin not loaded", 2)
		return
	end

	local resurrect = M.loaded.resurrect
	resurrect.fuzzy_loader.fuzzy_load(window, pane, function(id)
		resurrect.state_manager.delete_state(id)
		utils.spawn_toast("✓ Session deleted: " .. id, 1)
	end, {
		title = "󰆴 Delete Saved Session",
		description = "Select session to delete. Enter = delete, Esc = cancel",
		fuzzy_description = "Search: ",
		is_fuzzy = true,
	})
end

-- ============================================================================
-- STATUS / INFO
-- ============================================================================
function M.get_loaded_plugins()
	local loaded = {}
	for name, _ in pairs(M.loaded) do
		table.insert(loaded, name)
	end
	return loaded
end

function M.is_loaded(plugin_name)
	return M.loaded[plugin_name] ~= nil
end

return M

