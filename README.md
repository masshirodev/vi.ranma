# vi.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: vim-style NORMAL and INSERT over programs that only take arrows, such as a shell's line editor or Claude Code's prompt. Motions, counts, operators, finds, yank and paste, worked out from the line on screen and typed into the program.

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/specs/vi.lua`:

```lua
return { "masshirodev/vi.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/vi.ranma ~/.config/ranma/pack/plugins/start/vi.ranma
```

Needs ranma 0.4.0 or newer. Most of it needs a ranma with `pane:cursor()` (`ranma.has("pane.cursor")`, after 0.4.0): on an older one NORMAL is what it always was (`h j k l w b 0 $ x i a`, as arrows and emacs keys) and the other keys say they need a newer ranma. A ranma with `pane:alt_screen()` also tells full-screen programs apart over ssh, and one with a mode's `cursor` draws NORMAL's cursor as a block.

## What it does

```text
In every program but the excepted ones, a pane rests in NORMAL: keys move
and edit the line, other keys are swallowed. i or a goes to INSERT, which
is plain ranma (keys reach the program). Esc in INSERT goes back to
NORMAL, and Esc in NORMAL is sent on, so a program's own Esc (Claude
Code's interrupt) is Esc twice from INSERT. Enter in NORMAL is sent too,
and goes to INSERT, as zsh's vi mode starts each prompt in insert: a
program the line starts gets its keys.

NORMAL acts by typing into the program: it reads the line under the cursor
(pane:cursor()), works out where a motion lands, and sends that many
arrows.

Full-screen programs (editors, pagers, htop, fzf, a ranma) are left alone:
told by the alternate screen where the server has it, which works over
ssh, else by name. REPLs and a few others are excepted by name too.

Each pane keeps its own state, so typing in one leaves the others in NORMAL.
```

The bar's `mode` module says `NORMAL`, and `DELETE`, `CHANGE`, `YANK` or `CHAR` while an operator or a find waits for its next key; the cursor is a block in NORMAL and underlined while it waits.

### The prompt's edges

Where the shell marks its prompt (OSC 133 `B`), vi knows exactly where the typed text starts and ends, and everything is arrows and Backspace, which every line editor has. powerlevel10k sends the mark with `typeset -g POWERLEVEL9K_TERM_SHELL_INTEGRATION=true` in `~/.p10k.zsh`; other shells' integrations (kitty's, wezterm's, iTerm2's) send it too.

Without it (Claude Code, a shell with no integration), vi still knows the line and the cursor, and:

- deleting toward the end is the program's Delete, and toward the start Backspace: both stop by themselves at the edge of the input, so `dw` on the last word never reaches past it;
- `0`, `^`, `I` are Home, `$`, `A` End, `D` and `C` are `ctrl+k`, `dd`, `cc` and `S` are `End` then `ctrl+u`;
- `yy` and `Y` say they need the mark.

These need the program to bind Delete, Home and End, which Claude Code, readline and a configured zsh do.

## Keys

In NORMAL. A count before a motion or an operator repeats it (`3w`, `d2w`, `2dfx`).

| Key | |
| --- | --- |
| `h` `l` | Left, right. |
| `j` `k` | Down, up (history in a shell). |
| `w` `b` `e` | Next word, word back, word end (letters, digits and `_` make a word; punctuation is a word of its own). |
| `W` `B` `E` | The same over WORDs: anything not blank. |
| `0` `^` `$` | Line start, first non-blank, line end. |
| `f` `F` `t` `T` + char | Find the character forward or back, or stop just before it. `;` repeats, `,` repeats the other way. |
| `i` `a` `I` `A` | INSERT here, after the cursor, at the start, at the end. |
| `d` `c` `y` + motion | Delete, change (then INSERT), yank. `dd` `cc` `yy` take the whole line; `cw` changes to the word's end, as in vim. |
| `D` `C` `Y` | Delete or change to the end, yank the line. |
| `x` `X` | Delete the character under the cursor, or before it. |
| `s` `S` | Change the character, or the line. |
| `r` + char | Replace the character under the cursor. |
| `~` | Toggle the case of the character and move on. |
| `p` `P` | Paste what was yanked (or deleted) after or at the cursor. |
| `u` | The line editor's undo (`vi.undo`). A deletion vi made of several keys may take several `u` in zsh, which undoes key by key. |
| `v` | Copy mode at the cursor, to select with vi keys; its yank fills `p` too. |
| `/` | Search the history (`ctrl+r`) in INSERT. |
| `⏎` | Run the line and go to INSERT. |
| `esc` | Send Esc to the program. |
| `alt+h/j/k/l` | Move the focus between panes. |

Everywhere else: `esc` goes to NORMAL in a pane that is not left alone, and is sent on in one that is. `ranma.unbind("escape")` in `init.lua` takes that over again.

## Options

In ranma's settings panel under `vi`, or with hako's `opts` (`{ "masshirodev/vi.ranma", opts = { ... } }`), or `ranma.set { vi = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `vi.except` | `""` | Programs to leave alone, separated by spaces, on top of the built-in list. |
| `vi.clipboard` | `true` | What `y`, `d`, `c`, `x` and `s` take also goes to the clipboard (OSC 52, over ssh too). Off, it stays in vi's own register for `p` and `P`. |
| `vi.undo` | `"ctrl+_"` | The key `u` sends. |

The built-in list: `nvim vim vi nano emacs hx helix kak less more man most bat htop btop top nvtop k9s lazygit lazydocker tig yazi ranger lf nnn fzf sk tmux zellij ranma python python3 node psql sqlite3 lua ghci`, and `ssh mosh mosh-client` on a ranma without `pane:alt_screen()`, where what runs past ssh cannot be told.

## How it works

`pane:cursor()` gives the line under the cursor (its soft-wrapped rows joined), the cursor's offset in characters, and, at a marked prompt, what was typed. vi computes the motion on those characters and sends arrows; an operator becomes arrows plus Backspace or Delete. `p` uses bracketed paste. Nothing is read from the program but the screen, so it works the same over ssh.

What it cannot do: undo a vi command as one step (the editor sees keys), registers other than the one, `.` repeat, visual mode in place (`v` is ranma's copy mode, which selects and copies but does not edit), and text objects (`diw`, `ci"`).

## License

MIT or Apache-2.0, at your option.
