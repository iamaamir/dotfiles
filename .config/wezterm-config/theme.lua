-- theme.lua - Centralized theme and color configuration
-- All visual styling in one place for easy customization

local wezterm = require("wezterm")

local M = {}

-- ============================================================================
-- COLOR PALETTE (Tokyo Night inspired)
-- ============================================================================
M.colors = {
	-- Base colors
	bg = "#0a0a0f",
	bg_light = "#14141f",
	fg = "#c0caf5",
	fg_dim = "#565f89",

	-- Accent colors
	blue = "#7aa2f7",
	cyan = "#7dcfff",
	purple = "#bb9af7",
	green = "#9ece6a",
	yellow = "#e0af68",
	orange = "#ff9e64",
	red = "#f7768e",

	-- UI colors
	tab_bar_bg = "#1a1b26",
	tab_active_bg = "#1a1b26",
	tab_inactive_bg = "#16161e",
	tab_hover_bg = "#414868",
	status_bg = "#1a1b26",
}

-- ============================================================================
-- COLOR SCHEME
-- ============================================================================
M.color_scheme = "Tokyo Night"


-- ============================================================================
-- BACKGROUND CONFIGURATION
-- ============================================================================
-- Available styles: "gradient", "solid", "image", "parallax"
M.background_style = "gradient"

-- Parallax configuration (for background_style = "parallax")
-- Put images in your wezterm config dir and reference them here
M.parallax = {
	enabled = false,
	-- Layers are rendered back to front (first = deepest)
	-- Each layer can have: file, opacity, parallax_factor (0.0-1.0)
	-- Lower parallax = moves slower = appears further away
	layers = {
		-- Example configuration (uncomment and customize):
		-- { file = "bg_layer1.png", opacity = 0.3, parallax = 0.1 },
		-- { file = "bg_layer2.png", opacity = 0.4, parallax = 0.3 },
		-- { file = "bg_layer3.png", opacity = 0.5, parallax = 0.5 },
	},
	-- Dim factor for all parallax layers
	brightness = 0.15,
}

-- Get parallax background (can be called directly for overrides)
function M.get_parallax_background()
	return {
		-- Deep space base
		{ source = { Color = M.colors.bg }, width = "100%", height = "100%" },
		-- Slow-moving deep layer
		{
			source = {
				Gradient = {
					orientation = { Radial = { cx = 0.3, cy = 0.2, radius = 1.0 } },
					colors = { "#1e3a5f", "transparent" },
				},
			},
			width = "100%",
			height = "100%",
			opacity = 0.4,
			attachment = { Parallax = 0.1 },
		},
		-- Medium layer
		{
			source = {
				Gradient = {
					orientation = { Radial = { cx = 0.7, cy = 0.8, radius = 0.8 } },
					colors = { "#3d2963", "transparent" },
				},
			},
			width = "100%",
			height = "100%",
			opacity = 0.3,
			attachment = { Parallax = 0.3 },
		},
		-- Fast foreground glow
		{
			source = {
				Gradient = {
					orientation = { Radial = { cx = 0.5, cy = 1.2, radius = 0.6 } },
					colors = { "#1a2a4a", "transparent" },
				},
			},
			width = "100%",
			height = "100%",
			opacity = 0.5,
			attachment = { Parallax = 0.5 },
		},
	}
end

function M.get_background()
	if M.background_style == "solid" then
		return {
			{
				source = { Color = M.colors.bg },
				width = "100%",
				height = "100%",
			},
		}
	elseif M.background_style == "image" then
		local bg_image = wezterm.config_dir .. "/bg.jpg"
		return {
			{
				source = { File = bg_image },
				width = "Cover",
				height = "Cover",
				horizontal_align = "Center",
				vertical_align = "Middle",
				hsb = { brightness = 0.15, saturation = 0.8 },
			},
			{
				source = { Color = M.colors.bg },
				width = "100%",
				height = "100%",
				opacity = 0.6,
			},
		}
	elseif M.background_style == "parallax" then
		-- If custom layers configured, use them
		if #M.parallax.layers > 0 then
			local layers = {
				{ source = { Color = M.colors.bg }, width = "100%", height = "100%" },
			}
			for _, layer in ipairs(M.parallax.layers) do
				local layer_path = wezterm.config_dir .. "/" .. layer.file
				table.insert(layers, {
					source = { File = layer_path },
					width = "100%",
					repeat_x = "Mirror",
					hsb = { brightness = M.parallax.brightness },
					opacity = layer.opacity or 0.3,
					attachment = { Parallax = layer.parallax or 0.2 },
				})
			end
			return layers
		end
		-- Otherwise use default parallax gradient
		return M.get_parallax_background()
	else -- gradient (default)
		return {
			-- Base: deep dark
			{
				source = { Color = M.colors.bg },
				width = "100%",
				height = "100%",
			},
			-- Subtle vertical gradient
			{
				source = {
					Gradient = {
						orientation = "Vertical",
						colors = { M.colors.bg_light, M.colors.bg },
					},
				},
				width = "100%",
				height = "100%",
				opacity = 0.9,
			},
			-- Soft bottom glow
			{
				source = {
					Gradient = {
						orientation = { Radial = { cx = 0.5, cy = 1.1, radius = 0.7 } },
						colors = { "#1a2a4a", "transparent" },
					},
				},
				width = "100%",
				height = "100%",
				opacity = 0.5,
			},
		}
	end
end

-- ============================================================================
-- WINDOW SETTINGS
-- ============================================================================
M.window = {
	opacity = 1.0,
	blur = 40, -- macOS only
	decorations = "RESIZE",
	padding = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- ============================================================================
-- TAB BAR SETTINGS
-- ============================================================================
M.tab_bar = {
	position = "top", -- "top" or "bottom"
	hide_when_single = false,
}

-- ============================================================================
-- CURSOR SETTINGS
-- ============================================================================
M.cursor = {
	style = "SteadyBar", -- SteadyBlock, BlinkingBlock, SteadyUnderline, etc.
	blink_rate = 500,
}


-- ============================================================================
-- INACTIVE PANE DIMMING
-- ============================================================================
M.inactive_pane = {
	saturation = 0.8,
	brightness = 0.7,
}

-- ============================================================================
-- STATUS BAR FORMATTING
-- ============================================================================
function M.format_status(workspace, date, leader_active, config_reloaded)
	local elements = {}

	-- Config reload indicator (green)
	if config_reloaded then
		table.insert(elements, { Foreground = { Color = M.colors.bg } })
		table.insert(elements, { Background = { Color = M.colors.green } })
		table.insert(elements, { Attribute = { Intensity = "Bold" } })
		table.insert(elements, { Text = " 󰑓 Reloaded! " })
	end

	-- Leader indicator (yellow)
	if leader_active then
		table.insert(elements, { Foreground = { Color = M.colors.bg } })
		table.insert(elements, { Background = { Color = M.colors.yellow } })
		table.insert(elements, { Attribute = { Intensity = "Bold" } })
		table.insert(elements, { Text = "  LEADER " })
	end

	-- Reset background
	table.insert(elements, { Background = { Color = M.colors.tab_bar_bg } })
	table.insert(elements, { Attribute = { Intensity = "Normal" } })

	-- Workspace
	table.insert(elements, { Foreground = { Color = M.colors.blue } })
	table.insert(elements, { Text = " 󰖯 " .. workspace .. " " })

	-- Date/time
	table.insert(elements, { Foreground = { Color = M.colors.green } })
	table.insert(elements, { Text = " " .. date .. " " })

	return elements
end

-- ============================================================================
-- TAB TITLE STYLING
-- ============================================================================
-- Returns styled elements for tab title based on state
-- @param tab_text: The text content to display
-- @param state: { is_active, has_unseen_output, hover }
-- @param bell_icon: Icon for unseen output (optional)
function M.format_tab_title(tab_text, state, bell_icon)
	-- Active tab (blue, bold)
	if state.is_active then
		return {
			{ Background = { Color = M.colors.blue } },
			{ Foreground = { Color = M.colors.bg } },
			{ Attribute = { Intensity = "Bold" } },
			{ Text = tab_text },
		}
	end

	-- Tab with unseen output (orange, with bell icon)
	if state.has_unseen_output then
		return {
			{ Background = { Color = M.colors.orange } },
			{ Foreground = { Color = M.colors.bg } },
			{ Attribute = { Intensity = "Bold" } },
			{ Text = (bell_icon or "") .. tab_text },
		}
	end

	-- Hovered tab (slightly lighter)
	if state.hover then
		return {
			{ Background = { Color = M.colors.tab_hover_bg } },
			{ Foreground = { Color = M.colors.fg } },
			{ Text = tab_text },
		}
	end

	-- Inactive tab (dim)
	return {
		{ Background = { Color = M.colors.tab_inactive_bg } },
		{ Foreground = { Color = M.colors.fg_dim } },
		{ Text = tab_text },
	}
end

-- ============================================================================
-- APPLY THEME TO CONFIG
-- ============================================================================
function M.apply(config)
	-- Color scheme
	config.color_scheme = M.color_scheme

	-- Background
	config.window_background_opacity = M.window.opacity
	config.macos_window_background_blur = M.window.blur
	config.background = M.get_background()

	-- Window
	config.window_decorations = M.window.decorations
	config.window_padding = M.window.padding

	-- Tab bar
	config.tab_bar_at_bottom = (M.tab_bar.position == "bottom")
	config.hide_tab_bar_if_only_one_tab = M.tab_bar.hide_when_single
	config.use_fancy_tab_bar = false
	config.show_new_tab_button_in_tab_bar = true

	-- Tab bar colors
	config.colors = {
		tab_bar = {
			background = M.colors.tab_bar_bg,
			active_tab = {
				bg_color = M.colors.blue,
				fg_color = M.colors.bg,
				intensity = "Bold",
			},
			inactive_tab = {
				bg_color = M.colors.tab_inactive_bg,
				fg_color = M.colors.fg_dim,
			},
			inactive_tab_hover = {
				bg_color = M.colors.tab_hover_bg,
				fg_color = M.colors.fg,
			},
			new_tab = {
				bg_color = M.colors.tab_bar_bg,
				fg_color = M.colors.blue,
			},
			new_tab_hover = {
				bg_color = M.colors.blue,
				fg_color = M.colors.bg,
			},
		},
	}

	-- Cursor
	config.default_cursor_style = M.cursor.style
	config.cursor_blink_rate = M.cursor.blink_rate

	-- Inactive pane
	config.inactive_pane_hsb = M.inactive_pane

	-- Visual bell
	config.visual_bell = {
		fade_in_function = "EaseIn",
		fade_out_function = "EaseOut",
		fade_in_duration_ms = 75,
		fade_out_duration_ms = 75,
	}

	-- Scrollback
	config.scrollback_lines = 10000

	return config
end

return M

