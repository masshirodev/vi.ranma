# vi.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: vim-style NORMAL and INSERT over programs that only take arrows, such as a shell's line editor or Claude Code's prompt.

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/specs/vi.lua`:

```lua
return { "masshirodev/vi.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/vi.ranma ~/.config/ranma/pack/plugins/start/vi.ranma
```

Needs: ranma 0.4.0 or newer (user modes with their own label and hint, the mouse of plain mode, and the pane's cursor shown in them).

## What it does

```text
In every program but the excepted ones, a pane rests in NORMAL: hjkl are
sent as arrows and other keys are swallowed. i or a goes to INSERT, which is
plain ranma (keys reach the program). Esc in INSERT goes back to NORMAL, and
Esc in NORMAL is sent on, so a program's own Esc (Claude Code's interrupt) is
Esc twice from INSERT. Enter in NORMAL is sent too, and goes to INSERT, as
zsh's vi mode starts each prompt in insert: a program the line starts gets
its keys.

In the excepted programs (editors, pagers, full-screen tools with keys of
their own) nothing changes: Esc is passed on. A program missing from that
list is taken over, so add it to `vi.except` when one misbehaves.

Each pane keeps its own state, so typing in one leaves the others in NORMAL.
```

The bar's `mode` module says `NORMAL` while it is on.

## Keys

In NORMAL:

| Key | |
| --- | --- |
| `h` `j` `k` `l` | Arrows: left, down, up (history), right. |
| `w` / `b` | Next word / word back (`alt+f` / `alt+b`, as emacs-style line editors spell them). |
| `0` / `$` | Line start / end (`home` / `end`). |
| `x` | Delete the character under the cursor. |
| `i`, `a` | INSERT. |
| `⏎` | Send it (run the line) and go to INSERT. |
| `esc` | Send Esc to the program. |
| `alt+h/j/k/l` | Move the focus between panes. |

Everywhere else: `esc` goes to NORMAL in a pane that is not excepted, and is sent on in one that is. `ranma.unbind("escape")` in `init.lua` takes that over again.

## Options

In ranma's settings panel under `vi`, or with hako's `opts` (`{ "masshirodev/vi.ranma", opts = { ... } }`), or `ranma.set { vi = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `vi.except` | `""` | Programs to leave alone, separated by spaces, on top of the built-in list. |

The built-in list: `nvim vim vi nano emacs hx helix kak less more man most bat htop btop top nvtop k9s lazygit lazydocker tig yazi ranger lf nnn fzf sk tmux zellij ranma ssh mosh mosh-client python python3 node psql sqlite3 lua ghci`.

## How it works, and what is missing

The program is told apart by `pane:program()`, the name of the process in front. That is why `ssh` is excepted whole: past it, the program on the far side is unknown, so a remote shell gets no NORMAL rather than a remote editor getting a broken one.

NORMAL sends keys and cannot see the line: ranma 0.4.0 gives Lua the pane's text but not its cursor, so motions that need to know where the cursor stands (`f`, `t`, `e`, yank and paste, visual) are not here yet. They are planned on the core's side as `pane:cursor()`, `pane:alt_screen()` with an event when it changes, and a cursor shape per mode.

## License

MIT or Apache-2.0, at your option.
