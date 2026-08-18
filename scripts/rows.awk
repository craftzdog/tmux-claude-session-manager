# Build the picker rows from four tagged streams on stdin.
#
#   P  <pid> <tty>                       every process, from ps
#   T  <tty> <pane_id> <session> <loc>   every tmux pane
#   M  <sessionId> <mtime> <title>       per-session transcript facts
#   A  <pid> <status> <sessionId> <cwd> <waitingFor>   the agents themselves
#
# Kept in its own file rather than quoted inline in agents.sh so it can be driven
# from fixtures without a live tmux or a running Claude. See test/contract.sh.
#
# Required -v args: now bg_attn bg_active projw prefix
  function dim(s) { return "\033[90m" s "\033[0m" }

  # Sessions stay open for days, so raw minutes overflow the column and stop being
  # readable at a glance ("7342m"). One unit, no decimals — this is a recency cue,
  # not a measurement.
  function fmt_age(mins) {
    if (mins <   60) return mins "m"
    if (mins < 2880) return int(mins / 60) "h"
    return int(mins / 1440) "d"
  }

  # show <icon> <age> <loc> <project> <title>  — the whole visible row, padded here
  # so alignment survives fzf reassembling it.
  function show(icon, age, loc, project, title) {
    return sprintf("%s %5s  %-9s  %s  %s", icon, age, loc,
      dim(sprintf("%-" projw "." projw "s", project)), title)
  }

  $1 == "P" { tty_of[$2] = $3; next }
  $1 == "T" { sub(/^\/dev\//, "", $2); pane[$2] = $3; sess[$2] = $4; loc[$2] = $5; next }
  $1 == "M" { seen_at[$2] = $3; title[$2] = $4; next }
  $1 == "A" {
    tty = tty_of[$2]
    # A Claude outside tmux has no pane to jump to. Counted, not dropped — an
    # overview that quietly omits a running session is the bug this tool exists
    # to fix.
    if (tty == "" || !(tty in pane)) {
      orphans++
      orphan_pids = (orphan_pids == "") ? $2 : orphan_pids "," $2
      next
    }

    if      ($3 == "waiting") { icon = "\033[33m●\033[0m waiting"; rank = 0 }  # yellow - needs input
    else if ($3 == "idle")    { icon = "\033[32m●\033[0m idle   "; rank = 1 }  # green  - done, your turn
    else if ($3 == "busy")    { icon = "\033[31m●\033[0m working"; rank = 3 }  # red    - busy, leave it
    else                      { icon = "\033[90m●\033[0m   ?    "; rank = 2 }  # grey   - unrecognised status

    agemin = (seen_at[$4] != "") ? int((now - seen_at[$4]) / 60) : 0
    age    = (seen_at[$4] != "") ? fmt_age(agemin) : "-"

    # Claude Code puts worktrees at <repo>/.claude/worktrees/<name>, so they fold
    # into their repo group rather than each becoming a project of one, with the
    # worktree name kept visible to tell sibling checkouts apart.
    cwd = $5; wt = ""
    if (match(cwd, /\/\.claude\/worktrees\//)) {
      wt  = substr(cwd, RSTART + RLENGTH)
      cwd = substr(cwd, 1, RSTART - 1)
    }
    proj = cwd; sub(/.*\//, "", proj)
    cell = (wt != "") ? proj "/" wt : proj

    n++
    f_rank[n] = rank; f_agemin[n] = agemin; f_pane[n] = pane[tty]; f_pid[n] = $2
    f_kind[n] = (index(sess[tty], prefix) == 1) ? "dedicated" : "loose"
    f_icon[n] = icon; f_age[n] = age; f_loc[n] = loc[tty]
    # `waitingFor` says what it is blocked on (permission prompt, input needed,
    # sandbox request, ...) — the thing you actually triage on, so it leads.
    f_cell[n] = cell; f_proj[n] = cwd
    f_title[n] = ($3 == "waiting" && $6 != "") ? "\033[33m" $6 "\033[0m — " title[$4] : title[$4]

    if (!(cwd in grp) || rank < grp[cwd]) grp[cwd] = rank
  }

  END {
    for (i = 1; i <= n; i++)
      printf "%d\t%s\t%d\t%d\t%s\t%s\t%s\t%s\n",
        grp[f_proj[i]], f_proj[i], f_rank[i], f_agemin[i],
        f_pane[i], f_pid[i], f_kind[i],
        show(f_icon[i], f_age[i], f_loc[i], f_cell[i], f_title[i])

    # Background agents: pinned above everything when any is blocked, parked at
    # the bottom otherwise, so the row is a signal and not just a door.
    if (bg_attn > 0) {
      bg_icon = "\033[33m●\033[0m blocked"; bg_grp = -1
      bg_text = bg_attn " need you" (bg_active > 0 ? ", " bg_active " running" : "")
    } else {
      bg_icon = "\033[90m●\033[0m agents "; bg_grp = 99
      bg_text = (bg_active > 0 ? bg_active " running" : "none needing you")
    }
    printf "%d\t~background\t0\t0\t-\t-\tbg\t%s\n",
      bg_grp, show(bg_icon, "-", "enter", "background agents", bg_text)

    # The pids ride along in the hidden pid field so the preview can detail them
    # without rebuilding the pid -> tty -> pane join.
    if (orphans > 0)
      printf "100\t~orphans\t0\t0\t-\t%s\tnote\t%s\n",
        orphan_pids,
        show("\033[90m●\033[0m outside", "-", "-", "not in tmux",
             dim(orphans " Claude session" (orphans == 1 ? "" : "s") " running outside tmux — cannot jump"))
  }
