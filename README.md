# zsh-live-history-menu

Realtime history suggestions and current-directory path completion for Zsh.

`zsh-live-history-menu` is a small ZLE-based plugin that shows history candidates while you type, lets you pick candidates quickly, and keeps `Tab` focused on current-directory path completion in command argument position.

## Features

- Realtime list of matching history commands while typing.
- Ranking tuned for command prefixes and structured input such as `git "` or `git commit -m "`.
- Up and Down selection for visible history candidates.
- Number-based candidate selection.
- `Alt+number` direct selection from the current visible list.
- `Tab` completion for current-directory files and folders whenever the command line has input.
- Empty command-line `Tab` remains delegated to native Zsh completion.
- No external runtime dependency.
- Works as an Oh My Zsh custom plugin and can be sourced by other plugin managers.

## Demo Behavior

```text
git
   1  git status
   2  git branch
   3  git commit -m "fix: address PR review feedback"

git "
   1  git "fa7;"
   2  git commit -m "fix: address PR review feedback"
```

Selected candidates are marked with `▸` by default:

```text
▸  2  git branch
```

## Requirements

- Zsh
- Oh My Zsh, Antidote, Zinit, Sheldon, or any plugin manager that can source a `.plugin.zsh` file

## Installation

### Oh My Zsh

Clone the plugin:

```zsh
git clone https://github.com/xyseoer/zsh-live-history-menu.git \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-live-history-menu
```

Enable it in `~/.zshrc`:

```zsh
plugins=(zsh-live-history-menu)
```

If you also use `zsh-syntax-highlighting`, keep it after this plugin:

```zsh
plugins=(zsh-live-history-menu zsh-syntax-highlighting)
```

Reload Zsh:

```zsh
exec zsh
```

### Antidote

Add this to your plugin file:

```zsh
xyseoer/zsh-live-history-menu
zsh-users/zsh-syntax-highlighting
```

Load it with your usual Antidote setup.

### Zinit

```zsh
zinit light xyseoer/zsh-live-history-menu
zinit light zsh-users/zsh-syntax-highlighting
```

### Sheldon

```toml
[plugins.zsh-live-history-menu]
github = "xyseoer/zsh-live-history-menu"

[plugins.zsh-syntax-highlighting]
github = "zsh-users/zsh-syntax-highlighting"
```

### Manual

```zsh
source /path/to/zsh-live-history-menu.plugin.zsh
```

## Usage

| Key | Behavior |
| --- | --- |
| Type text | Show realtime history candidates |
| Up / Down | Select previous or next visible history candidate |
| 1-9 | Pick a visible candidate after selection mode is active |
| 0 | Pick the 10th visible candidate after selection mode is active |
| Alt+1 ... Alt+9 | Pick a visible candidate directly |
| Alt+0 | Pick the 10th visible candidate directly |
| Tab | Complete files and folders in command argument position |

Number keys still insert normal digits when history selection mode is not active.

## Tab Completion Rules

- `fr<Tab>` lists current-directory files and folders matching `fr`.
- `gi<Tab>` lists current-directory files and folders matching `gi`.
- `git <Tab>` lists current-directory files and folders.
- `git src/<Tab>` lists matching entries under `src/`.
- Empty command-line `Tab` is delegated to native Zsh completion.
- If exactly one path matches, it is inserted automatically.
- Directories are displayed with a trailing `/`.

## Configuration

Set these before loading the plugin:

```zsh
LHM_MAX_RESULTS=12
LHM_HISTORY_SCAN_LIMIT=1500
LHM_FUZZY_MIN_QUERY_LENGTH=4
LHM_ENABLE_FUZZY=1
LHM_PATH_MAX_RESULTS=200
LHM_SELECTED_MARKER='▸'
```

Example:

```zsh
LHM_MAX_RESULTS=8
LHM_HISTORY_SCAN_LIMIT=1500
LHM_FUZZY_MIN_QUERY_LENGTH=5
LHM_SELECTED_MARKER='▶'
plugins=(zsh-live-history-menu zsh-syntax-highlighting)
```

## Performance Tuning

The plugin keeps history matching synchronous so the visible list always matches the current command line. If your shell history is large, tune these values before loading the plugin:

| Variable | Default | Meaning |
| --- | ---: | --- |
| `LHM_HISTORY_SCAN_LIMIT` | `1500` | Maximum recent history events scanned when refreshing the cache |
| `LHM_MAX_RESULTS` | `12` | Maximum visible history candidates |
| `LHM_FUZZY_MIN_QUERY_LENGTH` | `4` | Minimum query length before loose fuzzy matching is used |
| `LHM_ENABLE_FUZZY` | `1` | Set to `0` to disable loose fuzzy matching |
| `LHM_PATH_MAX_RESULTS` | `200` | Maximum path candidates shown for `Tab` |

For the fastest setup:

```zsh
LHM_HISTORY_SCAN_LIMIT=1000
LHM_FUZZY_MIN_QUERY_LENGTH=6
LHM_ENABLE_FUZZY=0
LHM_MAX_RESULTS=8
```

## Compatibility Notes

- Keep `zsh-syntax-highlighting` after `zsh-live-history-menu`.
- The plugin uses ZLE widgets and `POSTDISPLAY`.
- It intentionally avoids external binaries and does not require `fzf`.

## Development

Run syntax checks:

```zsh
zsh -n zsh-live-history-menu.plugin.zsh
```

Create a local release tag:

```zsh
git tag vX.Y.Z
git push origin main vX.Y.Z
```

## License

MIT
