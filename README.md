# rex-resurrect

Tracks which coding agent (Claude Code, Codex, Copilot CLI) runs in which Rex
pane and which agent session it has open. After the Rex server restarts, it
resumes each agent, in its own pane, on the session it had.

Rex restores sessions, tabs and panes with the same IDs on restart, but each
pane comes back as a plain shell. rex-resurrect keeps a map of
`block ID -> agent, agent session ID, cwd` and types the resume command into
those shells.

## Install

Requires Rex on macOS or Linux, on the machine that runs the Rex server.

```sh
curl -fsSL https://raw.githubusercontent.com/ekristen/rex-resurrect/main/install.sh | sh
```

The script downloads `resurrect.lua` into `~/.config/rex`, adds one line to
`init.lua`, and reloads the configuration. It finds `rex` when it is not on
your PATH. Run the same command again to update.

### By hand

rex-resurrect is one file. From a checkout, copy it next to your `init.lua`
and load it:

```sh
mkdir -p ~/.config/rex
cp resurrect.lua ~/.config/rex/
echo 'require("resurrect").setup{}' >> ~/.config/rex/init.lua
rex config reload
```

`./install.sh` in a checkout does the same with the local file. To update by
hand, copy the new `resurrect.lua` over the old one, then:

```sh
rex config reload
rex do resurrect_restart
```

Loading the configuration starts a background tracker (`rex do resurrect.lua
--all`). The server starts it again each time it starts, and only one runs at
a time.

Check that it is running:

```sh
rex do resurrect_status
```

`tracker_pid` is set when the tracker is up, and `agents` lists what it has
found.

### If `rex` is not on your PATH

Rex adds `rex` to the PATH of panes it creates, but not of panes it restores
after a restart. The plugin and `install.sh` find the binary on their own. For
your own use, link it somewhere on your PATH:

```sh
ln -s "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex" ~/.local/bin/rex
```

### Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/ekristen/rex-resurrect/main/install.sh | sh -s -- --uninstall
```

or `./install.sh --uninstall` from a checkout.

This stops the tracker, removes the copy and the line in `init.lua`, and
leaves the state directory (`~/.local/state/rex-resurrect`) in place.

## How it works

- **Tracking.** The tracker scans every terminal when a foreground process
  changes, and every 10 seconds. A pane whose foreground process is `claude`,
  `codex` or `copilot` gets an entry in
  `~/.local/state/rex-resurrect/state.json`.
- **Session IDs.** They are read from what each agent already writes:

  | Agent | Source |
  | --- | --- |
  | Claude Code | `~/.claude/sessions/PID.json` (follows `/clear` and `/resume`) |
  | Codex | the open `rollout-…-UUID.jsonl` file of the process |
  | Copilot CLI | `~/.copilot/session-state/UUID/inuse.PID.hold` |

  A session ID given on the command line (`claude --resume ID`) is the fallback.
- **Profiles.** An agent may run with its own configuration directory,
  chosen by `CLAUDE_CONFIG_DIR`, `CODEX_HOME` or `COPILOT_HOME`, whether direnv
  sets it per project or you set it for one command. The tracker reads that
  variable from the running agent, looks for the session there, and records
  the value. On restore it is set again in front of the command:
  `CLAUDE_CONFIG_DIR='/Users/you/.claude-work' claude --resume ID`. The `env`
  list of each agent names the variables treated this way.
- **Forgetting.** An agent that leaves its pane is forgotten after 90 seconds
  (`grace`). The delay is what lets entries survive a shutdown, where the
  agents exit a moment before the tracker does.
- **Restoring.** The state file records the server's instance ID. A tracker
  that starts under a different instance resumes every entry: it types
  `cd CWD && claude --resume ID` into the pane, provided the pane is at a shell
  prompt. Panes that already run an agent, are busy, or no longer exist are
  skipped. The outcome is written to `last-restore.json` and `daemon.log`.

## Commands

From the command palette or `rex do`:

| Action | Does |
| --- | --- |
| `resurrect_status` | List tracked agents and the command that would resume each. |
| `resurrect_restore` | Resume tracked agents now. `dry=true` only reports. `all=true` includes agents that had exited. |
| `resurrect_restart` | Restart the tracker, for example after changing options. |

Without the configuration file, run the script directly:

```sh
rex do resurrect.lua                    # status
rex do resurrect.lua cmd=scan           # look now, write nothing
rex do resurrect.lua cmd=restore dry=true
rex do resurrect.lua cmd=stop
```

## Options

```lua
require("resurrect").setup{
  scan_interval  = 10,     -- seconds between full scans
  grace          = 90,     -- seconds before a departed agent is forgotten
  auto_restore   = true,   -- resume on restart without being asked
  restore_delay  = 3,      -- seconds to wait before typing into panes
  reopen_missing = false,  -- open a new tab when the pane is gone
  agents = {
    -- {id} is the agent's session ID. Add the flags you always use.
    claude  = { resume = "claude --resume {id}" },
    codex   = { resume = "codex resume {id}" },
    copilot = { resume = "copilot --resume={id}" },
  },
}
```

Add another agent with `names` (the program names to look for) and `resume`.
It is tracked by any session ID on its command line.

## What gets typed into a pane

The plugin types into your shells, so what it types is kept narrow.

The state file holds data, never commands. The resume command comes from the
`agents` option in `init.lua`, and three kinds of value are filled in:

- **The session ID.** It must be a UUID. Anything else is skipped.
- **Profile directories.** Only the variables named in an agent's `env`
  list are set. Each value is held to the rules for the directory below, and
  the directory must be owned by you, because an agent runs the hooks and
  settings it finds there.
- **The directory.** Rex restores a pane in the directory it was in, so no
  `cd` is typed when the pane is already there. Otherwise the recorded
  directory must be an absolute path that exists.

A directory or profile path is never typed if it has a control character,
quote, backslash or exclamation mark in it. Directory names come from
wherever the agent ran, a cloned repository included, and shells disagree
about those characters inside quotes. That agent is skipped and the reason
is logged.

Before typing, the plugin checks that the pane is at a shell prompt, that the
shell runs as you rather than root, and it clears anything already typed on
the line.

The tracker's options are passed through a file in the state directory, not
on its command line, so they don't show in `ps`.

The state directory is created with mode `700`, and a state file or
directory owned by someone else is ignored. Whoever can write the state file
can choose a profile directory for an agent, which amounts to running code as
you, so keep `state_dir` somewhere only you can write.

## Limits

- An agent is resumed with the command in `agents`, not with the flags it was
  first started with. A profile chosen by a flag (`codex --profile work`)
  rather than a variable is not carried over.
- A profile directory with a space in its path is not read correctly on
  macOS, and that agent is skipped at restore.
- An agent started as the pane's own command (`rex run -- claude`) rather than
  from a shell is restarted by Rex itself, without its session.
- Local server only. The tracker reads agent files and processes on the
  machine it runs on.
