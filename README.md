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

| Key            | Action                                                                          |
| -------------- | ------------------------------------------------------------------------------- |
| `prefix` + `y` | Launch (or re-attach to) a Claude session for the current directory, in a popup |
| `prefix` + `Y` | Open the **AI provider menu** and launch the chosen provider for the directory  |
| `prefix` + `u` | Open the session picker                                                          |

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
set -g @claude_launch_key      'y'        # prefix key: launch/open Claude for current dir
set -g @claude_launch_menu_key 'Y'        # prefix key: open the AI provider menu
set -g @claude_list_key        'u'        # prefix key: open the picker
set -g @claude_command         'claude'   # command for the claude provider (override)
set -g @claude_popup_width      '90%'     # popup width
set -g @claude_popup_height     '90%'     # popup height
```

### Multiple AI providers (optional)

`prefix` + `Y` opens a menu to launch Claude, [Codex](https://github.com/openai/codex),
[OpenCode](https://github.com/sst/opencode), or anything else you configure.
Providers are listed in `@claude_providers` as space-separated `key:command:Label`
entries — the default is just Claude, so nothing changes until you opt in:

```tmux
set -g @claude_providers 'claude:claude:Claude codex:codex:Codex opencode:opencode:OpenCode'
```

Each provider gets its own session prefix from its key (`claude-`, `codex-`,
`opencode-`), so the same directory can hold one session per provider without
collisions, and the picker lists them all with a provider column. To launch a
provider with arguments (the list is space-delimited, so its command field can't
hold them), use the per-provider `@claude_cmd_<key>` option:

```tmux
set -g @claude_cmd_codex 'codex --model o1'
```

## How it works

- The **launcher** creates a detached `<provider>-<hash-of-dir>` tmux session
  running that provider's command (e.g. `claude-<hash>` running `claude`), records
  the window it came from in `@claude_origin`, and attaches to it in a popup.
- The **provider menu** (`prefix` + `Y`) is built from `@claude_providers`; each
  entry launches via the same launcher with its own command and session prefix.
- The **hooks** set `@claude_state` / `@claude_state_at` on each session as Claude
  works.
- The **picker** lists sessions matching any provider prefix, reads their state and a live
  `capture-pane` preview, and on selection moves your client to the session's
  origin window before resuming it in the popup.
- Pressing `prefix` + `u` **from inside a session popup** detaches that popup
  first (closing it), then reopens the picker full-size on the outer host client —
  so you never end up with a cramped popup-in-popup.

## License

[MIT](LICENSE) © Takuya Matsuyama
