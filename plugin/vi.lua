-- vi: vim-style NORMAL and INSERT over programs that only take arrows (a
-- shell's line editor, Claude Code's prompt).
--
-- Needs ranma 0.4.0 or newer.
--
-- In every program but the excepted ones, a pane rests in NORMAL: hjkl are
-- sent as arrows and other keys are swallowed. i or a goes to INSERT, which is
-- plain ranma (keys reach the program). Esc in INSERT goes back to NORMAL, and
-- Esc in NORMAL is sent on, so a program's own Esc (Claude Code's interrupt) is
-- Esc twice from INSERT. Enter in NORMAL is sent too, and goes to INSERT, as
-- zsh's vi mode starts each prompt in insert: a program the line starts gets
-- its keys.
--
-- In the excepted programs (editors, pagers, full-screen tools with keys of
-- their own) nothing changes: Esc is passed on. A program missing from that
-- list is taken over, so add it to `vi.except` when one misbehaves.
--
-- Each pane keeps its own state (in pane.vars), so typing in one leaves the
-- others in NORMAL.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md
-- ("User modes", "Hooks", "Options").

ranma.option("vi.except", {
  type = "string", default = "",
  name = "Also leave alone",
  desc = "Programs to leave alone, separated by spaces, on top of the built-in list "
    .. "(editors, pagers, full-screen tools, REPLs).",
})

-- Programs that handle Esc and hjkl themselves.
local EXCEPT = {
  "nvim", "vim", "vi", "nano", "emacs", "hx", "helix", "kak",
  "less", "more", "man", "most", "bat",
  "htop", "btop", "top", "nvtop", "k9s",
  "lazygit", "lazydocker", "tig", "yazi", "ranger", "lf", "nnn",
  "fzf", "sk", "tmux", "zellij", "ranma", "ssh", "mosh", "mosh-client",
  "python", "python3", "node", "psql", "sqlite3", "lua", "ghci",
}
local builtin = {}
for _, name in ipairs(EXCEPT) do
  builtin[name] = true
end

-- The option is read where it is used: init.lua sets it after this file has
-- loaded, and the settings panel can change it at any time.
local extra_src, extra = nil, {}
local function excepted(program)
  if builtin[program] then
    return true
  end
  local src = ranma.get("vi.except")
  if src ~= extra_src then
    extra_src, extra = src, {}
    for name in src:gmatch("%S+") do
      extra[name] = true
    end
  end
  return extra[program] == true
end

-- The mode ranma is in, as mode_change names it: "vi" while NORMAL is on.
local current = "normal"

local function modal(p)
  return p ~= nil and not excepted(p:program() or "")
end

local function normal(p)
  p.vars.insert = false
  ranma.action("mode vi")
end

local function insert(p)
  if p then
    p.vars.insert = true
  end
  ranma.action("exit_mode")
end

ranma.mode("vi", {
  label = "NORMAL",
  hint = false,
  binds = {
    h = { "send left", desc = "left" },
    j = { "send down", desc = "down" },
    k = { "send up", desc = "up / history" },
    l = { "send right", desc = "right" },
    -- Moving through panes, as the global alt+arrows do (those work here too).
    ["alt+h"] = { "focus left", desc = "pane left" },
    ["alt+j"] = { "focus down", desc = "pane down" },
    ["alt+k"] = { "focus up", desc = "pane up" },
    ["alt+l"] = { "focus right", desc = "pane right" },
    -- Word and line motions as emacs-style line editors (zsh, Claude Code) spell them.
    w = { "send alt+f", desc = "next word" },
    b = { "send alt+b", desc = "word back" },
    ["0"] = { "send home", desc = "line start" },
    ["$"] = { "send end", desc = "line end" },
    x = { "send delete", desc = "delete" },
    i = { function() insert(ranma.pane()) end, desc = "insert" },
    a = { function() insert(ranma.pane()) end, desc = "insert" },
    escape = { "send escape", desc = "esc to program" },
    ["return"] = {
      function()
        local p = ranma.pane()
        if p then
          p:keys("return")
        end
        insert(p)
      end,
      desc = "run, insert",
    },
  },
})

ranma.bind("escape", function()
  local p = ranma.pane()
  if modal(p) then
    normal(p)
  elseif p then
    p:keys("escape")
  end
end, { global = true, desc = "normal mode" })

ranma.on("mode_change", function(e)
  current = e.mode
end)

-- Focus lands in the pane's own state: NORMAL unless it was left in INSERT.
-- Not in the middle of WM mode, which a focus bind may still be in.
ranma.on("focus_change", function(e)
  if current == "wm" then
    return
  end
  local p = e.pane and ranma.pane(e.pane)
  if modal(p) and not p.vars.insert then
    if current ~= "vi" then
      ranma.action("mode vi")
    end
  elseif current == "vi" then
    ranma.action("exit_mode")
  end
end)
