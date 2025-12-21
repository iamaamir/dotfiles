# WezTerm Configuration

A modular, tmux-inspired WezTerm setup with persistent sessions, quick select, and a clean Tokyo Night theme.

## Features

- **Session Persistence** - Sessions survive window close AND system restarts
- **Tmux-style keybindings** - `Ctrl+b` leader key with familiar shortcuts
- **Built-in Multiplexer** - Close window, reopen, sessions are still there
- **Quick select** - Extract URLs, git hashes, file paths with keyboard
- **Workspaces** - Multiple session management with fuzzy switcher
- **Modular design** - Clean separation of concerns, easy to customize
- **Shell integration** - Git branch and project name in tabs

## File Structure

```
wezterm-config/
├── wezterm.lua          # Main config (orchestrator)
├── config.lua           # User settings (fonts, URLs, shells)
├── theme.lua            # Colors, backgrounds, visual styling
├── keybindings.lua      # All keybindings with descriptions
├── callbacks.lua        # Action callback functions
├── quickselect.lua      # Quick select patterns & actions
├── command_palette.lua  # Custom command palette entries
├── plugins.lua          # Plugin management (resurrect)
├── icons.lua            # Process/directory icon mappings
├── utils.lua            # Shared utility functions
└── shell-integration.zsh # Shell hooks for tab info
```

## Installation

1. **Symlink or copy to WezTerm config directory:**
   ```bash
   # Option A: Symlink (recommended)
   ln -sf ~/dotfiles/.config/wezterm-config ~/.config/wezterm

   # Option B: Copy
   cp -r ~/dotfiles/.config/wezterm-config ~/.config/wezterm
   ```

2. **Add shell integration** (optional, for git branch in tabs):
   ```bash
   # Add to ~/.zshrc
   source ~/.config/wezterm/shell-integration.zsh
   ```

3. **Restart WezTerm** or press `Ctrl+b r` to reload.

## Session Persistence

This config uses a **two-layer** approach for maximum reliability:

### Layer 1: Built-in Mux Server
- **Close window → reopen** = instant reconnect (sessions never left)
- Works like tmux: GUI is just a client, mux server runs in background
- Zero-latency restoration, scrollback preserved

### Layer 2: Resurrect Plugin (Backup)
- Auto-saves all workspaces every 5 minutes
- Restores automatically after **system restart** or **crash**
- Manual save/restore available via keybindings

| Scenario | What Happens |
|----------|--------------|
| Close window + reopen | Instant reconnect (mux server) |
| System restart | Auto-restore from backup |
| WezTerm crash | Auto-restore from backup |

## Keybindings

Leader key: `Ctrl+b` (2 second timeout)

### Panes
| Key | Action |
|-----|--------|
| `\|` | Split vertical |
| `-` | Split horizontal |
| `h/j/k` | Navigate left/down/up |
| `→` | Navigate right (arrow key) |
| `Alt+h/j/k/l` | Resize panes |
| `z` | Zoom pane |
| `x` | Close pane |
| `o` | Next pane |
| `;` | Last pane |
| `!` | Move pane to new tab |

### Tabs
| Key | Action |
|-----|--------|
| `c` | New tab |
| `n/p` | Next/previous tab |
| `l` | Last tab |
| `0-9` | Go to tab N |
| `,` | Rename tab |
| `&` | Close tab |
| `w` | Tab navigator |

### Workspaces
| Key | Action |
|-----|--------|
| `s` | Switch workspace (fuzzy) |
| `N` | New workspace |
| `$` | Rename workspace |
| `L` | Last workspace |
| `(/)` | Prev/next workspace |
| `X` | Kill workspace |

### Session
| Key | Action |
|-----|--------|
| `Ctrl+s` | Save all workspaces (backup) |
| `Ctrl+r` | Restore session picker |
| `Ctrl+d` | Delete saved session |

### Quick Select
| Key | Action |
|-----|--------|
| `Space` | Quick select (default) |
| `u` | Open URL in browser |
| `e` | Edit file in $EDITOR |
| `H` | Copy git hash |
| `I` | Copy IP address |
| `U` | Copy UUID |

### Utilities
| Key | Action |
|-----|--------|
| `[` | Copy mode |
| `]` | Paste |
| `/` | Search |
| `:` | Command palette |
| `?` | Keybinding help |
| `i` | Pane info |
| `g` | Git status popup |
| `j` | Jump to project (fuzzy) |
| `r` | Reload config |
| `d` | Quit WezTerm |

## Customization

### Edit `config.lua` for:
- **Font**: family, size, weight
- **Window**: initial size
- **URLs**: Jira/GitHub links for hyperlink rules
- **Shell**: recognized shell names for tab icons
- **Session**: auto-save interval (default: 5 min), state directory

### Edit `theme.lua` for:
- **Colors**: modify `M.colors` palette
- **Background**: change `M.background_style` to `"gradient"`, `"solid"`, `"image"`, or `"parallax"`
- **Color scheme**: change `M.color_scheme`

### Add keybindings in `keybindings.lua`:
```lua
{
    key = "x",
    mods = "LEADER",
    action = act.SomeAction,
    desc = "Description for cheatsheet",
    cat = "category",
},
```

### Add command palette entries in `command_palette.lua`:
```lua
{
    brief = "My Command",
    icon = "md_icon_name",
    action = wezterm.action_callback(function(win, pane)
        -- your code
    end),
},
```

## Mouse Bindings

- **Right click**: Paste
- **Select text**: Auto-copy to clipboard
- **Triple-click**: Select entire command output (semantic zone)
- **Cmd/Ctrl+click**: Open hyperlinks

## Hyperlink Rules

Clickable patterns (Cmd/Ctrl+click):
- `https://...` - URLs
- `PROJ-1234` - Jira tickets (configure URL in `config.lua`)
- `owner/repo#123` - GitHub issues
- `localhost:3000` - Local dev servers

## SSH Integration

SSH hosts from `~/.ssh/config` are automatically available:
```bash
# In WezTerm, press Ctrl+Shift+P → "Connect to domain" → select SSH host
```

Or add custom domains in `wezterm.lua`:
```lua
table.insert(config.ssh_domains, {
    name = "my-server",
    remote_address = "server.example.com",
    username = "myuser",
})
```

## Troubleshooting

**Config not loading?**
```bash
wezterm show-keys  # Check for errors
```

**Plugin issues?**
```bash
# Clear plugin cache
rm -rf ~/Library/Application\ Support/wezterm/plugins
```

**Clear saved sessions?**
```bash
rm -rf ~/.local/share/wezterm/sessions/
```

**Mux server issues?**
```bash
# Kill existing mux server and start fresh
pkill -f wezterm-mux-server
# Then restart WezTerm
```

**Check logs:**
```bash
# macOS
tail -f ~/Library/Logs/wezterm.log
```

## Credits

- [WezTerm](https://wezfurlong.org/wezterm/) by Wez Furlong
- [resurrect.wezterm](https://github.com/MLFlexer/resurrect.wezterm) for session persistence
- Theme inspired by [Tokyo Night](https://github.com/folke/tokyonight.nvim)
