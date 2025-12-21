-- callbacks.lua - Centralized callback functions for keybindings
-- All wezterm.action_callback functions are defined here

local wezterm = require("wezterm")
local act = wezterm.action
local cfg = require("config")
local utils = require("utils")

local M = {}

-- ============================================================================
-- STATE TRACKING (for last pane/workspace features)
-- ============================================================================
M.state = {
	last_workspace = nil,
	current_workspace = nil,
	last_pane_by_tab = {},
}

-- Update state tracking (call from update-right-status event)
function M.update_state(window, pane)
	local workspace = window:active_workspace()

	-- Track workspace changes
	if M.state.current_workspace ~= workspace then
		M.state.last_workspace = M.state.current_workspace
		M.state.current_workspace = workspace
	end

	-- Track pane changes per tab
	local tab = window:active_tab()
	local tab_id = tab:tab_id()
	local pane_id = pane:pane_id()

	if M.state.last_pane_by_tab[tab_id] == nil then
		M.state.last_pane_by_tab[tab_id] = { current = pane_id, last = nil }
	elseif M.state.last_pane_by_tab[tab_id].current ~= pane_id then
		M.state.last_pane_by_tab[tab_id].last = M.state.last_pane_by_tab[tab_id].current
		M.state.last_pane_by_tab[tab_id].current = pane_id
	end
end

-- ============================================================================
-- PANE CALLBACKS
-- ============================================================================

-- Switch to last active pane (like tmux prefix+;)
function M.last_pane(window, pane)
	local tab = window:active_tab()
	local tab_id = tab:tab_id()
	local pane_info = M.state.last_pane_by_tab[tab_id]

	if pane_info and pane_info.last then
		for _, p in ipairs(tab:panes()) do
			if p:pane_id() == pane_info.last then
				p:activate()
				break
			end
		end
	end
end

-- Move pane to new tab (like tmux break-pane)
function M.pane_to_tab(window, pane)
	pane:move_to_new_tab()
end

-- Show pane info popup
function M.pane_info(window, pane)
	local path = utils.collapse_home(utils.get_cwd(pane, "unknown"))

	local info = string.format(
		"Path: %s\nPane ID: %s\nWorkspace: %s\nTab: %d/%d\nZoomed: %s",
		path,
		pane:pane_id(),
		window:active_workspace(),
		window:active_tab():tab_index() + 1,
		#window:mux_window():tabs(),
		pane:is_zoomed() and "Yes" or "No"
	)

	window:copy_to_clipboard(info, "Clipboard")
	utils.spawn_popup(info .. "\n\n(Copied to clipboard. Press Enter to close)")
end

-- ============================================================================
-- TAB CALLBACKS
-- ============================================================================

-- Rename tab
function M.rename_tab(window, pane)
	window:perform_action(
		act.PromptInputLine({
			description = "Enter new tab title:",
			action = wezterm.action_callback(function(win, p, line)
				if line then
					win:active_tab():set_title(line)
				end
			end),
		}),
		pane
	)
end

-- ============================================================================
-- WORKSPACE CALLBACKS
-- ============================================================================

-- Workspace switcher with fuzzy finder
function M.workspace_switcher(window, pane)
	local workspaces = wezterm.mux.get_workspace_names()
	local current = window:active_workspace()

	local choices = {}
	for _, name in ipairs(workspaces) do
		local icon = "󰖯"
		if name == current then
			icon = "󰄬"
			table.insert(choices, { id = name, label = icon .. "  " .. name .. " (active)" })
		else
			table.insert(choices, { id = name, label = icon .. "  " .. name })
		end
	end
	table.insert(choices, { id = "__new__", label = "󰐕  Create new workspace" })

	window:perform_action(
		act.InputSelector({
			title = "󰖯  Switch Workspace",
			choices = choices,
			fuzzy = true,
			fuzzy_description = "󰍉  Type to search: ",
			action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
				if not id then
					return
				end
				if id == "__new__" then
					inner_window:perform_action(
						act.PromptInputLine({
							description = "Enter name for new workspace:",
							action = wezterm.action_callback(function(win, p, line)
								if line and line ~= "" then
									win:perform_action(act.SwitchToWorkspace({ name = line }), p)
								end
							end),
						}),
						inner_pane
					)
				else
					inner_window:perform_action(act.SwitchToWorkspace({ name = id }), inner_pane)
				end
			end),
		}),
		pane
	)
end

-- Create new workspace
function M.new_workspace(window, pane)
	window:perform_action(
		act.PromptInputLine({
			description = "Enter name for new workspace:",
			action = wezterm.action_callback(function(win, p, line)
				if line then
					win:perform_action(act.SwitchToWorkspace({ name = line }), p)
				end
			end),
		}),
		pane
	)
end

-- Rename current workspace
function M.rename_workspace(window, pane)
	window:perform_action(
		act.PromptInputLine({
			description = "Enter new workspace name:",
			action = wezterm.action_callback(function(win, p, line)
				if line then
					wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
				end
			end),
		}),
		pane
	)
end

-- Switch to last workspace
function M.last_workspace(window, pane)
	if M.state.last_workspace and M.state.last_workspace ~= window:active_workspace() then
		window:perform_action(act.SwitchToWorkspace({ name = M.state.last_workspace }), pane)
	else
		window:toast_notification("WezTerm", "No previous workspace to switch to", nil, 2000)
	end
end

-- Kill current workspace
function M.kill_workspace(window, pane)
	local current = window:active_workspace()
	local workspaces = wezterm.mux.get_workspace_names()

	local target = nil
	for _, name in ipairs(workspaces) do
		if name ~= current then
			target = name
			break
		end
	end

	if target then
		window:perform_action(act.SwitchToWorkspace({ name = target }), pane)
		for _, mux_win in ipairs(wezterm.mux.all_windows()) do
			if mux_win:get_workspace() == current then
				for _, tab in ipairs(mux_win:tabs()) do
					for _, p in ipairs(tab:panes()) do
						p:kill()
					end
				end
			end
		end
	else
		window:perform_action(act.QuitApplication, pane)
	end
end

-- ============================================================================
-- POPUP/UTILITY CALLBACKS
-- ============================================================================

-- Git status popup
function M.git_status(window, pane)
	local path = utils.get_cwd(pane)
	utils.spawn_cmd("git status; echo '\\n[Press Enter to close]'; read", { cwd = path })
end

-- Project jumper (autojump + fzf)
function M.project_jump(window, pane)
	local script = [[
		if command -v autojump &> /dev/null; then
			selected=$(autojump -s | grep -E '^\s*[0-9]' | sort -rn | awk '{print $2}' | fzf --prompt="Jump to: " --height=40% --reverse --border)
			if [ -n "$selected" ]; then
				echo "$selected"
			fi
		else
			echo "autojump not found"
			sleep 2
		fi
	]]

	utils.spawn_cmd(script .. " | tee /tmp/wezterm_jump_choice; sleep 0.3", { interactive = true })

	wezterm.time.call_after(2, function()
		local f = io.open("/tmp/wezterm_jump_choice", "r")
		if f then
			local choice = f:read("*l")
			f:close()
			os.remove("/tmp/wezterm_jump_choice")

			if choice and choice ~= "" and choice ~= "autojump not found" then
				local mux_win = wezterm.mux.get_active_window()
				if mux_win then
					mux_win:spawn_tab({ cwd = choice })
				end
			end
		end
	end)
end

-- Keybinding cheatsheet
function M.cheatsheet(window, pane)
	local keybindings = require("keybindings")
	local cheatsheet = keybindings.generate_cheatsheet()
	utils.spawn_popup(cheatsheet)
end

-- ============================================================================
-- SESSION CALLBACKS (uses plugins module)
-- ============================================================================

function M.save_session(window, pane)
	local plugins = require("plugins")
	plugins.save_session(window, pane)
end

function M.restore_session(window, pane)
	local plugins = require("plugins")
	plugins.restore_session(window, pane)
end

function M.delete_session(window, pane)
	local plugins = require("plugins")
	plugins.delete_session(window, pane)
end

-- ============================================================================
-- GET ACTION FOR CALLBACK NAME
-- ============================================================================
-- Returns a wezterm.action_callback for the given callback name
function M.get_action(callback_name)
	local fn = M[callback_name]
	if fn then
		return wezterm.action_callback(fn)
	end
	return nil
end

return M
