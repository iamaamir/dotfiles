# argoq

a weekend project to make ArgoCD more accessible across enviroments

## Requirements

**Required** :

- [argocd](https://argo-cd.readthedocs.io/en/stable/cli_installation/) — ArgoCD CLI
- [fzf](https://github.com/junegunn/fzf) — fuzzy finder for interactive selection
- [jq](https://jqlang.github.io/jq/) — JSON processing

**Optional** (auto-detected, graceful fallbacks):

| Tool | Used for | Fallback |
|------|----------|----------|
| [bat](https://github.com/sharkdp/bat) | YAML syntax highlighting | `cat` |
| [nvim](https://neovim.io/) / vim | Side-by-side diff viewer | `$EDITOR` / `code` / `diff` |
| [code](https://code.visualstudio.com/) / [cursor](https://cursor.sh/) | GUI diff viewer | `diff + bat` / `diff + cat` |

## Installation

### 1. Symlink into PATH

```bash
ln -sf ~/dotfiles/argoq/argoq.sh ~/.local/bin/argoq
```

### 2. Ensure `~/.local/bin` is in your PATH

Add this to `~/.zshrc` if not already present:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then reload: `source ~/.zshrc`

### 3. Verify

```bash
argoq --help
```

## Usage

### Getting started

```bash
# Login to an environment (SSO)
argoq login

# Check who you're logged in as
argoq whoami
```

### Browsing apps

```bash
# List all apps (default command, cached)
argoq

# Force a fresh fetch
argoq apps --live

# Show only unhealthy/unsynced/errored apps
argoq apps --unhealthy

# Combine flags
argoq apps --unhealthy --live
```

Selecting an app opens an **action menu**
- `detail` — app summary (sync, health, resources, conditions)
- `open` — open in ArgoCD UI (browser)
- `logs` — stream/view logs
- `manifests` — view live or git manifests
- `resources` — drill into resources (live/git/diff)
- `history` — deployment history

### Logs

```bash
argoq logs
```

The logs command has a 3-step picker:

1. **Scope** — app-wide (all pods), by namespace, or by specific resource
2. **Container** — all containers or a specific one
3. **Mode** — choose from:

| Mode | Description |
|------|-------------|
| `last-100` | Last 100 lines |
| `last-500` | Last 500 lines |
| `last-1000` | Last 1000 lines |
| `since-1h` | Logs from the last hour |
| `since-6h` | Logs from the last 6 hours |
| `since-24h` | Logs from the last 24 hours |
| `follow` | Stream live |
| `follow-filter` | Stream live with keyword filter |
| `search` | Grep last 5000 lines for a keyword |
| `previous` | Previous container logs (crashed/restarted) |

### Manifests and resources

```bash
# View live or git manifests
argoq manifests

# Drill into resources — view live/git YAML or diff them
argoq resources
```

### Cross-environment comparison

```bash
# Diff manifests for the same app across two environments
argoq compare
```

Requires at least two logged-in environments.

### Re-using previous selections

Every command supports `--continue` to skip the selection steps and re-use your last picks:

```bash
argoq logs --continue
argoq manifests --continue
argoq resources --continue
```

### Session management

```bash
# Login (or switch to already-logged-in env)
argoq login

# Logout current environment
argoq logout

# Logout all environments
argoq logout --all


## Configuration

### Environments

Edit the `ENVS` array at the top of `argoq.sh` to add or modify environments:

```bash
ENVS=(
  "Alpha  (EU)|argo-mng.eu.postman-alpha.com"
  "Beta   (US)|argo-mng.us.postman-beta.com"
  "Stage  (US)|argo-mng.stage.us.ia.postmanlabs.com"
  "Prod   (US)|argo-mng.prod.us.ia.postmanlabs.com"
)
```

Format: `"Label|ArgoCD Server URL"`

### Diff viewer

The diff viewer is auto-detected with this priority:

```
$ARGOQ_DIFF → nvim → $EDITOR → code/cursor → diff+bat → diff+cat
```

Override for a single invocation:

```bash
ARGOQ_DIFF=code argoq compare
```

Or set permanently in your shell profile:

```bash
export ARGOQ_DIFF=code
```

## State and cache

argoq stores state in `~/.local/state/argoq/`:

| File | Purpose |
|------|---------|
| `current-env` | Selected environment |
| `cache-*.json` | Cached app list per environment (auto-refreshes) |
| `last-*` | Previous selections for `--continue` |

Cache auto-refreshes every 5 minutes. Use `--live` to force a fresh fetch.
