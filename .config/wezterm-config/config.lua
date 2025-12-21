-- config.lua - User-configurable constants
-- All user-specific settings in one place for easy customization
-- Edit this file to personalize your WezTerm setup

local M = {}

-- ============================================================================
-- FONT SETTINGS
-- ============================================================================
M.font = {
	family = "FiraCode Nerd Font Mono",
	weight = "Medium",
	size = 16.0,
	line_height = 1.2,
}

-- ============================================================================
-- WINDOW SETTINGS
-- ============================================================================
M.window = {
	initial_rows = 35,
	initial_cols = 120,
}

-- ============================================================================
-- TAB SETTINGS
-- ============================================================================
M.tab = {
	max_width = 32,
	show_index = true,
}

-- ============================================================================
-- EDITOR
-- ============================================================================
-- Used as fallback when $EDITOR is not set
M.default_editor = "nvim"

-- ============================================================================
-- URLS & INTEGRATIONS
-- ============================================================================
M.urls = {
	-- Jira instance URL (for clickable PROJ-1234 tickets)
	-- Set to your company's Jira URL, e.g., "https://mycompany.atlassian.net/browse/$1"
	jira = "https://jira.atlassian.com/browse/$1",

	-- GitHub base URL (for clickable owner/repo#123 issues)
	github = "https://github.com/$1/issues/$2",
}

-- ============================================================================
-- SHELL CONFIGURATION
-- ============================================================================

-- Detect user's default shell from $SHELL (e.g., /bin/zsh → zsh)
local user_shell_path = os.getenv("SHELL") or "/bin/sh"
M.user_shell = user_shell_path:match("([^/]+)$") or "sh"

-- Shell to use for spawning commands (auto-detected, with fallbacks)
-- Order: user's shell → bash → sh
M.default_shell = M.user_shell

-- Fallback shells if user's shell is not available
M.fallback_shells = { "bash", "sh" }

-- Shells to recognize for tab title icon logic (O(1) hash lookup)
-- Add your custom shells here!
M.shell_names = {
	-- Common shells (auto-included)
	zsh = true,
	bash = true,
	fish = true,
	sh = true,
	dash = true,
	ksh = true,
	tcsh = true,
	csh = true,
	-- Add custom shells below:
	-- nu = true,      -- Nushell
	-- pwsh = true,    -- PowerShell
	-- elvish = true,  -- Elvish
}

-- ============================================================================
-- SESSION PERSISTENCE (resurrect plugin)
-- ============================================================================
M.session = {
	auto_save_interval = 300, -- seconds (5 minutes)
	-- Custom directory for saved sessions (cleaner than default plugin directory)
	-- Uses ~/.local/share/wezterm/sessions/ by default
	-- Note: Must end with trailing slash for resurrect plugin
	state_dir = (os.getenv("HOME") or "") .. "/.local/share/wezterm/sessions/",
}

return M
