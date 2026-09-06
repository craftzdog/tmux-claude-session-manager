# tmux-codex-session-manager

Run multiple [Codex CLI](https://developers.openai.com/codex/cli/) sessions
across your projects, each in tmux, then see which agents need attention and
jump to any of them from one popup.

If you keep one Codex session open per project, checking every pane quickly
becomes tedious. This plugin provides:

- A central picker (`prefix` + `u`) for every Codex process running in tmux,
  including sessions launched outside the plugin.
- Live `working`, `waiting`, and `idle` status from Codex's terminal title.
- A live `capture-pane` preview for the highlighted agent.
- Smart navigation back to dedicated popup sessions or ordinary tmux panes.
- A launcher (`prefix` + `y`) that restores the managed conversation for the
  current pane's directory after its tmux session exits.
- Quick process termination with `ctrl-x` inside the picker.

Managed sessions configure Codex's documented `status` and `project` terminal
title fields for reliable status detection. No hooks or app-server daemon are
required.

## Prerequisites

- tmux 3.2 or newer, for `display-popup`
- [fzf](https://github.com/junegunn/fzf), for the picker UI
- [Codex CLI](https://developers.openai.com/codex/cli/), available as `codex`
- Bash, plus standard `ps`, `awk`, `sort`, and `stat` utilities
- macOS or Linux

`lsof` is optional. When available, the picker uses the mtimes of open Codex
rollout files for the activity-age column. Without it, agents still appear and
their age is shown as `-`.

## Install with tpm

Add this plugin to `~/.tmux.conf` or `~/.config/tmux/tmux.conf`:

```tmux
set -g @plugin 'GiladTrachtenberg/codex-session-manager'
```

Press `prefix` + <kbd>I</kbd> to install it.

The plugin binds `prefix` + `y` and `prefix` + `u` by default. If those keys are
already in use, change the options below or load this plugin in the order that
should win.

### Manual installation

```sh
git clone https://github.com/GiladTrachtenberg/codex-session-manager.git ~/clone/path
```

Load the entrypoint from your tmux configuration, then reload tmux:

```tmux
run-shell ~/clone/path/codex_session_manager.tmux
```

## Usage

| Key | Action |
| --- | --- |
| `prefix` + `y` | Launch, reattach, or resume the managed Codex session for the current directory |
| `prefix` + `u` | Open the agent picker |

Inside the picker:

| Key | Action |
| --- | --- |
| `enter` | Jump to the highlighted agent |
| `ctrl-x` | Terminate the highlighted Codex process and reload the list |
| `↑` / `↓` | Move through agents |
| Any text | Fuzzy-filter the list |

Agents that are waiting or idle sort above agents that are still working. Each
native Codex process gets its own row, so several agents in one project remain
independently selectable.

## Options

Set options before the plugin is loaded. Defaults are shown below:

```tmux
# Configure the two plugin key bindings.
set -g @codex_launch_key      'y'
set -g @codex_list_key        'u'

# Configure the launched command and any additional Codex CLI arguments.
set -g @codex_command         'codex'
set -g @codex_args            ''

# Resume the last saved Codex conversation after a managed tmux session exits.
set -g @codex_resume          'on'

# Configure managed tmux session names and popup dimensions.
set -g @codex_session_prefix  'codex-'
set -g @codex_popup_width     '90%'
set -g @codex_popup_height    '90%'

# Append custom options to the fzf invocation.
set -g @codex_fzf_options     ''
```

For example, to bypass Codex approvals and sandboxing in an environment that is
already externally isolated:

```tmux
set -g @codex_args '--dangerously-bypass-approvals-and-sandbox'
```

That flag is intentionally dangerous. See the
[official Codex command reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli)
before enabling it.

### Customizing fzf

`@codex_fzf_options` is passed to `fzf`. The picker exports its executable path
as `$CODEX_PICKER`, which custom reload bindings can use:

```tmux
set -g @codex_fzf_options "\
  --prompt 'nav> ' \
  --bind 'j:down' \
  --bind 'k:up' \
  --bind 'q:abort' \
  --bind 'x:execute-silent(kill {3})+reload(sleep 0.3; \$CODEX_PICKER --list)' \
  --bind 'i:unbind(j,k,q,i,a,x)+change-prompt(filter> )' \
  --bind 'a:unbind(j,k,q,i,a,x)+change-prompt(filter> )' \
  --bind 'esc:rebind(j,k,q,i,a,x)+change-prompt(nav> )'"
```

Write `\$CODEX_PICKER` inside a double-quoted tmux value so tmux stores the
literal variable reference.

## How it works

- The launcher creates `codex-<hash-of-directory>`, records its origin window in
  `@codex_origin`, and opens the session in a popup. Repeated launches for the
  same directory reattach to the existing tmux session. If that tmux session has
  ended, the next launch runs `codex resume --last`, which Codex scopes to the
  current working directory. Set `@codex_resume` to `off` to always start fresh.
- Resume markers live under
  `${XDG_STATE_HOME:-$HOME/.local/state}/tmux-codex-session-manager`. They store
  only the project-path hash; Codex remains responsible for conversation data.
- Managed launches pass `tui.terminal_title=["status","project"]` to Codex.
  `agents.sh` interprets the attention label as `waiting`, Codex's spinner as
  `working`, and a plain project title as `idle`.
- Discovery finds native `codex` processes with `ps`, maps PID to TTY, and joins
  that TTY to `tmux list-panes`. It does not rely on `pane_current_command`,
  which commonly reports Codex's Node wrapper instead of the native process.
- When `lsof` is installed, one pass identifies rollout files held by each Codex
  process. Only file paths and mtimes are used; transcript contents are never
  read. The newest main or subagent rollout mtime becomes the activity age.
- Plugin-created sessions carry an explicit `@codex_managed` marker and reopen
  in a popup over their recorded origin. A normal session is never treated as
  managed merely because its name begins with `codex-`; loose Codex processes
  are focused in their existing tmux pane.
- Opening the picker from inside a managed popup first closes that popup and
  waits for tmux teardown, preventing a non-interactive popup-inside-popup race.

## Development

Run the fixture-based discovery regression test and syntax checks:

```sh
bash tests/agents_test.sh
bash tests/launch_test.sh
bash -n codex_session_manager.tmux scripts/*.sh tests/*.sh tests/fixtures/bin/* tests/fixtures/launch-bin/*
```

## License

[MIT](LICENSE) © Takuya Matsuyama
