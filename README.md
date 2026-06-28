# tmux-opencode-session-manager

Run many [opencode](https://opencode.ai) sessions across your
projects, each in its own tmux session — then **list them, see which are done
vs. still working, and jump to one** from a single popup.

If you launch opencode per-directory (one nested session per project), you quickly
end up with a dozen of them and no way to tell which are finished without opening
each one. This plugin gives you:

- **A central picker** (`prefix` + `T`) listing every running opencode session.
- **Live status** per session — `busy` / `idle` — driven by opencode hooks,
  so you instantly see which need you.
- **A live preview** of each session's screen right in the picker.
- **Smart jump** — selecting a session switches your client to the window it
  was launched from, then resumes it in a popup over it.
- **A launcher** (`prefix` + `t`) that opens/attaches an opencode session for
  the current directory.
- **Quick kill** (`ctrl-x`) of finished sessions from the picker.

Status is optional: without the hooks the picker still lists, previews, jumps,
and kills — sessions just show `?` instead of a color.

## Prerequisites

- **tmux ≥ 3.2** (for `display-popup`)
- **[fzf](https://github.com/junegunn/fzf)** — the picker UI
- **[opencode](https://opencode.ai)** CLI (the `opencode` command)
- bash; macOS or Linux

## Install (tpm)

Add to `~/.tmux.conf` (or `~/.config/tmux/tmux.conf`):

```tmux
set -g @plugin 'githubcuaan/tmux-opencode-session-manager'
```

Then hit `prefix` + <kbd>I</kbd> to install.

> **Keybinding note:** by default the plugin binds `prefix` + `t` (launch) and
> `prefix` + `T` (list). If your config binds those elsewhere, either change the
> options below, or make sure the plugin loads **after** your own bindings (put
> `run '~/.tmux/plugins/tpm/tpm'` _after_ them) so the one you want wins.

### Manual install

```sh
git clone https://github.com/githubcuaan/tmux-opencode-session-manager ~/clone/path
```

Add to `~/.tmux.conf`, then reload (`prefix` + <kbd>r</kbd> or `tmux source ~/.tmux.conf`):

```tmux
run-shell ~/clone/path/tmux-opencode-session-manager.tmux
```

## Usage

| Key            | Action                                                                             |
| -------------- | ---------------------------------------------------------------------------------- |
| `prefix` + `t` | Launch (or re-attach to) an opencode session for the current directory, in a popup |
| `prefix` + `T` | Open the session picker                                                            |

Inside the picker:

| Key                       | Action                                                                    |
| ------------------------- | ------------------------------------------------------------------------- |
| `enter`                   | Jump to the session (switches to its origin window, resumes in the popup) |
| `ctrl-x`                  | Kill the highlighted session                                              |
| `↑` / `↓`, type to filter | fzf navigation                                                            |

Sessions needing your attention (`idle`) sort to the top.

## Status setup (optional, recommended)

Status comes from opencode hooks that stamp each session's state onto its tmux
session. Add the following to your opencode hooks configuration.

Copy `hooks.yaml` from this repo to `~/.config/opencode/hook/hooks.yaml`:

```yaml
hooks:
  - id: opencode-state-busy
    event: tool.before.*
    actions:
      - bash: "$HOME/.config/tmux/plugins/tmux-opencode-session-manager/scripts/state.sh busy"

  - id: opencode-state-idle
    event: session.idle
    actions:
      - bash: "$HOME/.config/tmux/plugins/tmux-opencode-session-manager/scripts/state.sh idle"
```

The state machine:

| Event           | State     | Meaning                   |
| --------------- | --------- | ------------------------- |
| `tool.before.*` | 🔴 `busy` | Working — leave it        |
| `session.idle`  | 🟢 `idle` | Turn finished — your move |
| _(no hook)_     | ⚪ `?`    | Unknown (no hook yet)     |

> Sessions that are already running start reporting status on their next event
> once the hooks are added.

## Options

Set any of these before the plugin loads (defaults shown):

```tmux
set -g @opencode_launch_key     't'        # prefix key: launch/open for current dir
set -g @opencode_list_key       'T'        # prefix key: open the picker
set -g @opencode_command        'opencode' # command run in new sessions
set -g @opencode_session_prefix 'opencode-' # tmux session name prefix
set -g @opencode_popup_width    '90%'      # popup width
set -g @opencode_popup_height   '85%'      # popup height
```

## How it works

- The **launcher** creates a detached `opencode-<hash-of-dir>` tmux session
  running `opencode --port <port>`, records the window it came from in
  `@opencode_origin`, and attaches to it in a popup.
- The **hooks** set `@opencode_state` / `@opencode_state_at` on each session
  as opencode works.
- The **picker** lists sessions matching the prefix, reads their state and a
  live `capture-pane` preview, and on selection moves your client to the
  session's origin window before resuming it in the popup.
- Pressing `prefix` + `T` **from inside a session popup** detaches that popup
  first (closing it), then reopens the picker full-size on the outer host
  client — so you never end up with a cramped popup-in-popup.

## Acknowledgments

This project is a fork of [tmux-claude-session-manager](https://github.com/craftzdog/tmux-claude-session-manager)
by **[Takuya Matsuyama (craftzdog)](https://github.com/craftzdog)** — the original
idea and implementation for managing Claude Code sessions across projects.

Thank you for the brilliant design and clean code that made this adaptation possible.

## License

[MIT](LICENSE) © Takuya Matsuyama
