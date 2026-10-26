# AGENTS.md

vi.ranma is a ranma plugin in Lua: `plugin/vi.lua` is all of it, and its
header comment is the reference that `README.md` repeats. ranma's API is
https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md (`ranma --dump-types` prints it as LuaLS annotations).

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit; a key goes in the README's key table, an option in its options
  table.
- Use only what the latest ranma release has: CI loads the plugin into it.
  Something newer is used only behind a check that the server has it
  (`if p.cursor then`), with the old behaviour kept as the fallback, and the
  README's "How it works" section says which release brings what.
- Options are read where they are used (`ranma.get`), never cached at load:
  plugins load before `init.lua` sets them, and the settings panel changes
  them at any time.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server.
  CI (`.github/workflows/ci.yml`) loads it into the latest ranma release on
  every push and pull request and fails if it does not.
- Test behaviour on a private server, never the one your terminal runs in:
  unset `RANMA_SOCKET RANMA RANMA_PANE TMUX`, point `RANMA_CONFIG_DIR` and
  the `XDG_*` directories at a temp dir, and drive ranma in a private tmux
  (`tmux -L <name>`), as ranma's `scripts/smoke.sh` does. **Stop the server
  when done**: killing the tmux only detaches it, and a ranma server outlives
  its terminal. Kill the `ranma` whose `XDG_RUNTIME_DIR` is your temp dir
  (`/proc/<pid>/environ`), never by name. Read the line with `ranma lua
  'return ranma.pane():cursor()'`, with `RANMA_SOCKET` taken from the test
  shell's environment, and wait for the first prompt before typing.
- Test against a zsh with `bindkey -e`, a right prompt, and OSC 133 marks,
  once with `B` and once without (the two paths: arrows and Backspace, or
  the program's Delete, Home and End). Cases worth repeating: each motion
  with and without a count; `dw` and `cw` mid-line and on the last word;
  `D` `dd` `S` `x` `r` `~` `p`; `f F ; ,` with no match; Enter runs and
  leaves INSERT; Esc in `less` reaches it and leaves no NORMAL; two panes
  keep their own state across focus changes; a program named in `vi.except`
  is left alone; an older ranma (0.4.0) loads it and keeps the old keys.
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.
