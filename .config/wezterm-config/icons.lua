-- icons.lua - Process to icon mapping
-- Add or modify icons here without touching the main config
-- Uses wezterm.nerdfonts for semantic icon names
-- Reference: https://wezfurlong.org/wezterm/config/lua/wezterm/nerdfonts.html

local wezterm = require("wezterm")
local nf = wezterm.nerdfonts
local utils = require("utils")

local M = {}

-- Map process names to icons
-- You can find icon names at: https://www.nerdfonts.com/cheat-sheet
M.process_icons = {
  -- Shells
  zsh = nf.dev_terminal,
  bash = nf.dev_terminal,
  fish = nf.dev_terminal,
  sh = nf.dev_terminal,
  pwsh = nf.md_powershell,
  powershell = nf.md_powershell,

  -- Editors
  nvim = nf.custom_vim,
  vim = nf.custom_vim,
  vi = nf.custom_vim,
  nano = nf.md_file_document_edit,
  emacs = nf.custom_emacs,
  code = nf.md_microsoft_visual_studio_code,
  cursor = nf.md_microsoft_visual_studio_code,

  -- Node.js ecosystem
  node = nf.md_nodejs,
  npm = nf.md_npm,
  yarn = nf.seti_yarn,
  pnpm = nf.md_npm,
  bun = nf.md_rabbit,
  deno = nf.md_nodejs,

  -- Python
  python = nf.dev_python,
  python3 = nf.dev_python,
  pip = nf.dev_python,
  ipython = nf.dev_python,

  -- Ruby
  ruby = nf.dev_ruby,
  irb = nf.dev_ruby,
  gem = nf.dev_ruby,
  bundle = nf.dev_ruby,

  -- Go
  go = nf.md_language_go,

  -- Rust
  cargo = nf.dev_rust,
  rustc = nf.dev_rust,

  -- Java/JVM
  java = nf.dev_java,
  gradle = nf.seti_gradle,
  mvn = nf.dev_java,

  -- Other languages
  lua = nf.seti_lua,
  perl = nf.dev_perl,
  php = nf.dev_php,
  swift = nf.dev_swift,
  kotlin = nf.dev_kotlin,

  -- Git
  git = nf.dev_git,
  gh = nf.dev_github_badge,

  -- Containers & Cloud
  docker = nf.dev_docker,
  kubectl = nf.md_kubernetes,
  k9s = nf.md_kubernetes,
  terraform = nf.md_terraform,
  aws = nf.dev_aws,

  -- System monitoring
  htop = nf.md_chart_areaspline,
  btop = nf.md_chart_areaspline,
  top = nf.md_chart_areaspline,

  -- Build tools
  make = nf.seti_makefile,
  cmake = nf.seti_makefile,
  ninja = nf.seti_makefile,

  -- File managers
  ranger = nf.md_folder,
  yazi = nf.md_folder,
  lf = nf.md_folder,
  mc = nf.md_folder,
  nnn = nf.md_folder,

  -- Network
  ssh = nf.md_ssh,
  curl = nf.md_download,
  wget = nf.md_download,
  ping = nf.md_access_point_network,

  -- Database
  psql = nf.dev_postgresql,
  mysql = nf.dev_mysql,
  sqlite3 = nf.dev_sqllite,
  redis = nf.dev_redis,
  mongosh = nf.dev_mongodb,

  -- Search & Find
  fzf = nf.md_magnify,
  rg = nf.md_magnify,
  grep = nf.md_magnify,
  find = nf.md_magnify,
  fd = nf.md_magnify,

  -- Misc
  man = nf.md_book_open_variant,
  less = nf.md_file_document,
  cat = nf.md_file_document,
  bat = nf.md_file_document,
  tmux = nf.cod_terminal_tmux,
  brew = nf.dev_homebrew,
  sudo = nf.md_shield_account,
}

-- Default icon for unknown processes
M.default_icon = nf.dev_terminal

-- Get icon for a process (optimized: single pattern match)
function M.get(process_name)
  -- Extract basename and first word in one step, then lowercase
  local name = (process_name:match("([^/%s]+)$") or process_name):lower()
  return M.process_icons[name] or M.default_icon
end

-- ============================================================================
-- DIRECTORY ICONS
-- ============================================================================
-- Map directory names/paths to icons
-- Add your own directories here!

-- Special directory names (matched by folder name)
M.dir_icons = {
  -- Home and common dirs
  ["~"] = nf.md_home,
  ["home"] = nf.md_home,
  
  -- Development
  ["src"] = nf.md_code_braces,
  ["source"] = nf.md_code_braces,
  ["lib"] = nf.md_library,
  ["bin"] = nf.md_application_cog,
  ["build"] = nf.md_hammer,
  ["dist"] = nf.md_package_variant,
  ["target"] = nf.md_bullseye_arrow,
  
  -- Config
  ["config"] = nf.md_cog,
  [".config"] = nf.md_cog,
  ["dotfiles"] = nf.md_dots_horizontal,
  
  -- Git/Version control
  [".git"] = nf.dev_git,
  
  -- Node.js
  ["node_modules"] = nf.md_nodejs,
  
  -- Documentation
  ["docs"] = nf.md_book_open_variant,
  ["documentation"] = nf.md_book_open_variant,
  
  -- Tests
  ["test"] = nf.md_test_tube,
  ["tests"] = nf.md_test_tube,
  ["spec"] = nf.md_test_tube,
  ["__tests__"] = nf.md_test_tube,
  
  -- Assets
  ["assets"] = nf.md_image,
  ["images"] = nf.md_image,
  ["img"] = nf.md_image,
  ["static"] = nf.md_folder_star,
  ["public"] = nf.md_folder_account,
  
  -- Downloads/Desktop
  ["Downloads"] = nf.md_download,
  ["Desktop"] = nf.md_desktop_mac,
  ["Documents"] = nf.md_file_document_multiple,
  
  -- Cloud
  ["iCloud"] = nf.md_cloud,
  ["Dropbox"] = nf.md_dropbox,
  ["Google Drive"] = nf.md_google_drive,
}

-- Full path patterns to icons (for specific repos/projects)
-- Add your own project paths here!
M.path_icons = {
  -- Example: specific repos get specific icons
  -- ["/Users/aamir.khan/projects/my-go-project"] = nf.md_language_go,
  -- ["/Users/aamir.khan/work/frontend"] = nf.md_react,
  
  -- Common patterns (use string.match patterns)
  ["%.git$"] = nf.dev_git,
  ["nvim"] = nf.custom_vim,
  ["neovim"] = nf.custom_vim,
  ["wezterm"] = nf.dev_terminal,
}

-- Default icon for unknown directories
M.default_dir_icon = nf.md_folder

-- Get icon for a directory
function M.get_dir(path)
  if not path or path == "" then
    return M.default_dir_icon
  end
  
  -- Check if it's exactly home
  if path == utils.home or path == "~" then
    return M.dir_icons["~"]
  end
  
  -- Check full path patterns first
  for pattern, icon in pairs(M.path_icons) do
    if path:match(pattern) then
      return icon
    end
  end
  
  -- Get the directory basename
  local basename = path:match("([^/]+)/?$") or path
  
  -- Check directory name mapping
  if M.dir_icons[basename] then
    return M.dir_icons[basename]
  end
  
  -- Check lowercase version
  if M.dir_icons[basename:lower()] then
    return M.dir_icons[basename:lower()]
  end
  
  return M.default_dir_icon
end

return M
