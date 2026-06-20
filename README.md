# tmux-claude-session-manager

[![screenshot](./docs/screenshot.jpg)](https://youtu.be/NnTV6r4l5D0)

Run many [Claude Code](https://claude.com/claude-code) sessions across your
projects, each in its own tmux session — then **list them, see which are done
vs. still working, and jump to one** from a single popup.

If you launch Claude per-directory (one nested session per project), you quickly
end up with a dozen of them and no way to tell which are finished without opening
each one. This plugin gives you:

- 🔢 **A central picker** (`prefix` + `u`) listing every running Claude session.
- 🟢 **Live status** per session — `working` / `waiting` / `idle` — driven by
  Claude Code hooks, so you instantly see which need you.
- 👁️ **A live preview** of each session's screen right in the picker.
- 🎯 **Smart jump** — selecting a session switches your client to the window it
  was launched from, then resumes it in a popup over it.
- 🚀 **A launcher** (`prefix` + `y`) that opens/attaches a Claude session for the
  current directory.
- ❌ **Quick kill** (`ctrl-x`) of finished sessions from the picker.

Status is optional: without the hooks the picker still lists, previews, jumps,
and kills — sessions just show `?` instead of a color.

## Prerequisites

- **tmux ≥ 3.2** (for `display-popup`)
- **[fzf](https://github.com/junegunn/fzf)** — the picker UI
- **[Claude Code](https://claude.com/claude-code)** CLI (the `claude` command)
- bash; macOS or Linux

## Install (tpm)

Add to `~/.tmux.conf` (or `~/.config/tmux/tmux.conf`):

```tmux
set -g @plugin 'craftzdog/tmux-claude-session-manager'
```

Then hit `prefix` + <kbd>I</kbd> to install.

> **Keybinding note:** by default the plugin binds `prefix` + `y` (launch) and
> `prefix` + `u` (list). If your config binds those elsewhere, either change the
> options below, or make sure the plugin loads **after** your own bindings (put
> `run '~/.tmux/plugins/tpm/tpm'` _after_ them) so the one you want wins.

### Manual install

```sh
git clone https://github.com/craftzdog/tmux-claude-session-manager ~/clone/path
```

Add to `~/.tmux.conf`, then reload (`prefix` + <kbd>r</kbd> or `tmux source ~/.tmux.conf`):

```tmux
run-shell ~/clone/path/claude_session_manager.tmux
```

## Usage

| Key            | Action                                                                                |
| -------------- | ------------------------------------------------------------------------------------- |
| `prefix` + `y` | Launch (or re-attach to) a **Claude** session for the current directory, in a popup   |
| `prefix` + `Y` | Open the **AI provider menu** (Claude / Codex / OpenCode) and launch the chosen one    |
| `prefix` + `u` | Open the session picker (lists sessions across all providers)                          |

Inside the picker:

| Key                       | Action                                                                    |
| ------------------------- | ------------------------------------------------------------------------- |
| `enter`                   | Jump to the session (switches to its origin window, resumes in the popup) |
| `ctrl-x`                  | Kill the highlighted session                                              |
| `↑` / `↓`, type to filter | fzf navigation                                                            |

Sessions needing your attention (`waiting`, `idle`) sort to the top.

## Status setup (optional, recommended)

Status comes from [Claude Code hooks](https://code.claude.com/docs/en/hooks)
that stamp each session's state onto its tmux session. Add the following to your
Claude Code settings (`~/.claude/settings.json`), merging into any existing
`hooks` block. Adjust the path if your plugins live elsewhere (e.g.
`~/.tmux/plugins/...`):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/tmux/plugins/tmux-claude-session-manager/scripts/state.sh working"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/tmux/plugins/tmux-claude-session-manager/scripts/state.sh waiting"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/tmux/plugins/tmux-claude-session-manager/scripts/state.sh waiting"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.config/tmux/plugins/tmux-claude-session-manager/scripts/state.sh idle"
          }
        ]
      }
    ]
  }
}
```

The state machine:

| Event                            | State        | Meaning                   |
| -------------------------------- | ------------ | ------------------------- |
| `UserPromptSubmit`               | 🔴 `working` | Busy — leave it           |
| `Notification` (permission)      | 🟡 `waiting` | Needs permission          |
| `PreToolUse` (`AskUserQuestion`) | 🟡 `waiting` | Asking you a question     |
| `Stop`                           | 🟢 `idle`    | Turn finished — your move |

> Claude Code reloads `hooks` dynamically — no restart needed. Sessions that are
> already running start reporting status on their next event once the hooks are
> added.

## Options

Set any of these before the plugin loads (defaults shown):

```tmux
set -g @ai_launch_key      'y'        # prefix key: launch/open Claude for current dir
set -g @ai_launch_menu_key 'Y'        # prefix key: open the AI provider menu
set -g @ai_list_key        'u'        # prefix key: open the picker
set -g @ai_command         'claude'   # command for the claude provider (override)
set -g @ai_popup_width      '90%'     # popup width
set -g @ai_popup_height     '90%'     # popup height
set -g @ai_picker_opts      ''        # extra fzf flags for the picker (see below)

# Providers shown in the `prefix` + `Y` menu and listed by the picker.
# Space-separated  key:command:Label  entries (command/Label optional).
set -g @ai_providers 'claude:claude:Claude codex:codex:Codex opencode:opencode:OpenCode'
```

> **Back-compat:** every user-facing option also accepts its legacy `@claude_*`
> spelling (e.g. `@claude_providers`), so existing configs keep working. The
> `@ai_*` namespace is canonical and takes precedence when both are set.

Each provider gets its own session prefix derived from its key (`claude-`,
`codex-`, `opencode-`), so the same directory can hold one session per provider
without collisions. Add or remove providers by overriding `@ai_providers` —
e.g. drop OpenCode, or add `gemini:gemini:Gemini`.

Because `@ai_providers` is space-delimited, the `command` field there cannot
contain arguments. To launch a provider with flags, use the per-provider option
`@ai_cmd_<key>`, which may contain spaces:

```tmux
set -g @ai_cmd_codex 'codex --model o1'
set -g @ai_cmd_claude 'claude --resume'
```

### Customizing the picker

The picker inherits your global `FZF_DEFAULT_OPTS` (theme, keybindings) and pins
only the flags it needs for its layout — a 3/7 list/preview split and full popup
height (`--height=100%`, which overrides a `--height` you may have set in
`FZF_DEFAULT_OPTS`). To tweak the picker without editing the script, append flags
via `@ai_picker_opts`; they are applied last and win over everything else:

```tmux
set -g @ai_picker_opts '--color=preview-border:6,list-border:8 --preview-window=right,60%'
```

Tokens are space-split, so use it for a list of simple flags; flag values that
contain spaces are not supported through this option.

## How it works

- The **launcher** creates a detached `<provider>-<hash-of-dir>` tmux session
  running that provider's command (e.g. `claude-<hash>` running `claude`), records
  the window it came from in `@ai_origin`, and attaches to it in a popup.
- The **provider menu** (`prefix` + `Y`) is built from `@ai_providers`; each
  entry launches via the same launcher with its own command and session prefix.
- The **hooks** set `@ai_state` / `@ai_state_at` on each session as Claude
  works.
- The **picker** lists sessions matching any provider prefix, reads their state and a live
  `capture-pane` preview, and on selection moves your client to the session's
  origin window before resuming it in the popup.
- Pressing `prefix` + `u` **from inside a session popup** detaches that popup
  first (closing it), then reopens the picker full-size on the outer host client —
  so you never end up with a cramped popup-in-popup.

## Development

Unit tests for the pure helpers (no tmux required — it is stubbed):

```bash
./tests/run.sh
```

## License

[MIT](LICENSE) © Takuya Matsuyama
