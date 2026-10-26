-- vi: vim-style NORMAL and INSERT over programs that only take arrows (a
-- shell's line editor, Claude Code's prompt).
--
-- Needs ranma 0.4.0 or newer; motions that read the line (w b e W B E ^ $
-- f t, operators, yank and paste, r ~ v) need a ranma with pane:cursor()
-- (ranma.has("pane.cursor")), and fall back or say so on an older one.
--
-- In every program but the excepted ones, a pane rests in NORMAL: keys move
-- and edit the line, other keys are swallowed. i or a goes to INSERT, which
-- is plain ranma (keys reach the program). Esc in INSERT goes back to
-- NORMAL, and Esc in NORMAL is sent on, so a program's own Esc (Claude
-- Code's interrupt) is Esc twice from INSERT. Enter in NORMAL is sent too,
-- and goes to INSERT, as zsh's vi mode starts each prompt in insert: a
-- program the line starts gets its keys.
--
-- NORMAL acts by typing into the program: it reads the line under the cursor
-- (pane:cursor()), works out where a motion lands, and sends that many
-- arrows. Deleting toward the line's end is Delete and toward its start
-- Backspace, which stop by themselves at the edge of what was typed. A shell
-- that marks its prompt (OSC 133 B; powerlevel10k with
-- POWERLEVEL9K_TERM_SHELL_INTEGRATION=true) tells it where the typed text
-- starts and ends, for dd cc yy ^ I; without the mark those use the
-- program's own keys (home, end, ctrl+u, ctrl+k) and yy says it cannot.
--
-- Full-screen programs (editors, pagers, htop, fzf, a ranma) are left alone:
-- told by the alternate screen where the server has it (ranma.has(
-- "pane.alt_screen"), which works over ssh), else by name. REPLs and a few
-- others are excepted by name too; add more to `vi.except`.
--
-- Each pane keeps its own state (in pane.vars), so typing in one leaves the
-- others in NORMAL.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md
-- ("User modes", "Pane handles", "Hooks", "Options").

ranma.option("vi.except", {
  type = "string", default = "",
  name = "Also leave alone",
  desc = "Programs to leave alone, separated by spaces, on top of the built-in list "
    .. "(editors, pagers, full-screen tools, REPLs).",
})
ranma.option("vi.clipboard", {
  type = "bool", default = true,
  name = "Yank to the clipboard",
  desc = "What y, d, c, x and s take also goes to the clipboard (OSC 52, over ssh too). "
    .. "Off, it stays in vi's own register for p and P.",
})
ranma.option("vi.undo", {
  type = "string", default = "ctrl+_",
  name = "Undo key",
  desc = "The key u sends: the line editor's undo (ctrl+_ in zsh, bash and readline).",
})

local function has(name)
  return ranma.has ~= nil and ranma.has(name)
end
local CURSOR = has("pane.cursor")
local ALT = has("pane.alt_screen")

-- Programs that handle Esc and hjkl themselves. Where the alternate screen
-- is known the full-screen ones would be found anyway; the rest (REPLs,
-- `man` before its pager starts) are line editors vi should not drive.
local EXCEPT = {
  "nvim", "vim", "vi", "nano", "emacs", "hx", "helix", "kak",
  "less", "more", "man", "most", "bat",
  "htop", "btop", "top", "nvtop", "k9s",
  "lazygit", "lazydocker", "tig", "yazi", "ranger", "lf", "nnn",
  "fzf", "sk", "tmux", "zellij", "ranma",
  "python", "python3", "node", "psql", "sqlite3", "lua", "ghci",
}
-- Without the alternate screen nothing says what runs past ssh: a remote
-- shell goes without NORMAL rather than a remote editor getting a broken one.
if not ALT then
  for _, name in ipairs({ "ssh", "mosh", "mosh-client" }) do
    EXCEPT[#EXCEPT + 1] = name
  end
end
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

local function modal(p)
  if p == nil or excepted(p:program() or "") then
    return false
  end
  return not (ALT and p:alt_screen())
end

-- The mode ranma is in, as mode_change names it: "vi" in NORMAL, "vi_*" in
-- the modes NORMAL passes through (an operator waiting, a character to read).
local current = "normal"
local function in_vi(mode)
  return mode == "vi" or mode:sub(1, 3) == "vi_"
end

-- What NORMAL is in the middle of: a count being typed, and an operator
-- waiting for its motion. Both go when a command runs or the focus moves.
local count = ""
local operator = nil
local function reset()
  count, operator = "", nil
end
local function take_count()
  local n = tonumber(count) or 1
  count = ""
  return math.min(n, 999)
end

local function normal(p)
  reset()
  if p then
    p.vars.insert = false
  end
  -- Entering it again would be a mode_change for every motion.
  if current ~= "vi" then
    ranma.action("mode vi")
  end
end

local function insert(p)
  reset()
  if p then
    p.vars.insert = true
  end
  ranma.action("exit_mode")
end

-- Press a key n times (n may be 0).
local function press(p, key, n)
  if n <= 0 then
    return
  end
  local keys = {}
  for i = 1, n do
    keys[i] = key
  end
  p:keys(table.unpack(keys))
end

local function move(p, from, to)
  if to > from then
    press(p, "right", to - from)
  elseif to < from then
    press(p, "left", from - to)
  end
end

-- The register p and P paste; yanks fill it.
local register = ""
local function yank(text)
  if text == "" then
    return
  end
  register = text
  if ranma.get("vi.clipboard") then
    ranma.copy(text)
  end
end
-- A copy made in copy mode (v) is a yank too.
ranma.on("copy", function(e)
  if e.source == "copy_mode" and e.text and e.text ~= "" then
    register = e.text
  end
end)

local warned = false
local function needs_cursor()
  if not warned then
    warned = true
    ranma.notify("vi: this key needs a newer ranma (pane:cursor)")
  end
end

-- The line under the cursor, as characters: positions are 0-based, `pos` the
-- cursor's, `lo`..`hi` what may be edited (the typed text when the shell
-- marks its prompt, else the whole line), `known` whether it was marked.
local function line(p)
  local c = p:cursor()
  local chars = {}
  for _, code in utf8.codes(c.text) do
    chars[#chars + 1] = utf8.char(code)
  end
  local l = { chars = chars, pos = c.offset, lo = 0, hi = #chars, known = false, cursor = c }
  if c.input then
    l.lo, l.hi, l.known = c.input.from, c.input.to, true
  end
  return l
end

local function at(l, i)
  return l.chars[i + 1]
end

local function slice(l, a, b)
  return table.concat(l.chars, "", a + 1, b)
end

-- 0 blank, 1 word (letters, digits, _, anything not ASCII), 2 punctuation;
-- a WORD (W B E) is anything not blank.
local function class(ch, big)
  if ch == nil or ch:match("^%s$") then
    return 0
  elseif big or #ch > 1 or ch:match("^[%w_]$") then
    return 1
  end
  return 2
end

local function word_forward(l, i, big)
  local c = class(at(l, i), big)
  if c ~= 0 then
    while i < l.hi and class(at(l, i), big) == c do
      i = i + 1
    end
  end
  while i < l.hi and class(at(l, i), big) == 0 do
    i = i + 1
  end
  return i
end

local function word_back(l, i, big)
  if i > l.lo then
    i = i - 1
  end
  while i > l.lo and class(at(l, i), big) == 0 do
    i = i - 1
  end
  local c = class(at(l, i), big)
  while i > l.lo and class(at(l, i - 1), big) == c do
    i = i - 1
  end
  return i
end

local function word_end(l, i, big)
  local last = math.max(l.lo, l.hi - 1)
  if i < last then
    i = i + 1
  end
  while i < last and class(at(l, i), big) == 0 do
    i = i + 1
  end
  local c = class(at(l, i), big)
  while i < last and class(at(l, i + 1), big) == c do
    i = i + 1
  end
  return i
end

-- The nth `ch` after (or before) the cursor, or nil.
local function find(l, ch, n, back)
  local i = l.pos
  while n > 0 do
    i = back and i - 1 or i + 1
    if i < l.lo or i >= l.hi then
      return nil
    end
    if at(l, i) == ch then
      n = n - 1
    end
  end
  return i
end

-- The last f F t T, for ; and ,.
local last_find = nil

-- Motions: given the line and a count, where the cursor lands and whether an
-- operator takes the character there too (vim's inclusive motions). nil:
-- nowhere to go, nothing happens.
local function repeat_word(f, big)
  return function(l, n)
    local i = l.pos
    for _ = 1, n do
      i = f(l, i, big)
    end
    return i
  end
end
local MOTIONS = {
  h = function(l, n) return math.max(l.lo, l.pos - n), false end,
  l = function(l, n) return math.min(l.hi, l.pos + n), false end,
  w = function(l, n) return repeat_word(word_forward, false)(l, n), false end,
  ["shift+w"] = function(l, n) return repeat_word(word_forward, true)(l, n), false end,
  b = function(l, n) return repeat_word(word_back, false)(l, n), false end,
  ["shift+b"] = function(l, n) return repeat_word(word_back, true)(l, n), false end,
  e = function(l, n) return repeat_word(word_end, false)(l, n), true end,
  ["shift+e"] = function(l, n) return repeat_word(word_end, true)(l, n), true end,
  ["0"] = function(l) return l.lo, false end,
  ["^"] = function(l)
    local i = l.lo
    while i < l.hi and class(at(l, i)) == 0 do
      i = i + 1
    end
    return i, false
  end,
  ["$"] = function(l) return math.max(l.lo, l.hi - 1), true end,
}
local function find_motion(kind, ch)
  return function(l, n)
    local back = kind == "F" or kind == "T"
    local i = find(l, ch, n, back)
    if i == nil then
      return nil
    end
    if kind == "t" then
      i = i - 1
    elseif kind == "T" then
      i = i + 1
    end
    return i, not back
  end
end
local REVERSE = { f = "F", F = "f", t = "T", T = "t" }

-- Keys a motion that cannot read the line sends instead, on an older ranma
-- or where it needs the prompt's bounds and the shell did not mark them.
local FALLBACK = {
  w = "alt+f", b = "alt+b", e = "alt+f",
  ["shift+w"] = "alt+f", ["shift+b"] = "alt+b", ["shift+e"] = "alt+f",
  ["0"] = "home", ["^"] = "home", ["$"] = "end",
}
local NEEDS_BOUNDS = { ["0"] = true, ["^"] = true, ["$"] = true }

-- Delete [a, b) of the line. Unmarked, toward the end it is Delete from a and
-- toward the start Backspace from b: both stop at the edge of what can be
-- edited, so a range that runs past it deletes no more than is there.
local function delete(p, l, a, b)
  if b <= a then
    return
  end
  yank(slice(l, a, b))
  -- Where the prompt marked the typed text the range is exact, and Backspace
  -- is the one deleting key every line editor has (a bare zsh leaves Delete
  -- unbound and types its escape sequence).
  if l.known then
    move(p, l.pos, b)
    press(p, "backspace", b - a)
  elseif a >= l.pos then
    move(p, l.pos, a)
    press(p, "delete", b - a)
  else
    move(p, l.pos, b)
    press(p, "backspace", b - a)
  end
end

-- The character under the cursor, for r and ~ (the caller checks there is one).
local function delete_under(p, l)
  if l.known then
    p:keys("right", "backspace")
  else
    p:keys("delete")
  end
end

-- Run the waiting operator (or a plain move) over a motion.
local function apply(p, op, motion, n)
  if not CURSOR then
    local key = FALLBACK[motion.key]
    if op == nil and key then
      press(p, key, NEEDS_BOUNDS[motion.key] and 1 or n)
    elseif op == nil and (motion.key == "h" or motion.key == "l") then
      press(p, motion.key == "h" and "left" or "right", n)
    elseif op ~= "y" and (motion.key == "h" or motion.key == "l") then
      -- x X s: a character either side needs no reading of the line.
      press(p, motion.key == "h" and "backspace" or "delete", n)
    else
      needs_cursor()
    end
    return
  end
  local l = line(p)
  if NEEDS_BOUNDS[motion.key] and not l.known then
    -- The line's start and end are the program's to say.
    if op == nil then
      p:keys(FALLBACK[motion.key])
    elseif motion.key == "$" then
      yank(slice(l, l.pos, l.hi))
      p:keys("ctrl+k")
    else
      -- Not ctrl+u, which is the whole line in zsh: Backspace stops at the
      -- prompt by itself. Not yanked either, since the prompt is in `text`.
      press(p, "backspace", l.pos)
    end
    return
  end
  local to, inclusive = motion.fn(l, n)
  if to == nil then
    return
  end
  to = math.max(l.lo, math.min(l.hi, to))
  if op == nil then
    move(p, l.pos, to)
    return
  end
  -- cw on a word changes to its end, as vim does (it is ce, not dw).
  if op == "c" and (motion.key == "w" or motion.key == "shift+w") and class(at(l, l.pos)) ~= 0 then
    to, inclusive = repeat_word(word_end, motion.key == "shift+w")(l, n), true
  end
  local a, b = math.min(l.pos, to), math.max(l.pos, to)
  if inclusive then
    b = math.min(l.hi, b + 1)
  end
  if op == "y" then
    yank(slice(l, a, b))
  else
    delete(p, l, a, b)
  end
end

-- The whole typed line: dd cc yy S.
local function whole_line(p, op)
  if not CURSOR then
    needs_cursor()
    return
  end
  local l = line(p)
  if not l.known then
    if op == "y" then
      ranma.notify("vi: yy needs a shell that marks its prompt (OSC 133 B)")
    else
      p:keys("end", "ctrl+u")
    end
    return
  end
  if op == "y" then
    yank(slice(l, l.lo, l.hi))
    return
  end
  yank(slice(l, l.lo, l.hi))
  move(p, l.pos, l.hi)
  press(p, "backspace", l.hi - l.lo)
end

-- After an operator: c leaves in INSERT, the others back in NORMAL.
local function finish(p, op)
  if op == "c" then
    insert(p)
  else
    normal(p)
  end
end

local function motion_key(key)
  return function()
    local p = ranma.pane()
    if not p then
      return
    end
    local op, n = operator, take_count()
    apply(p, op, { key = key, fn = MOTIONS[key] }, n)
    finish(p, op)
  end
end

-- f F t T: the next key is the character to find.
local reading = nil
local function read_char(then_do)
  reading = then_do
  ranma.action("mode vi_char")
end

local function find_key(kind)
  return function()
    local p = ranma.pane()
    if not p then
      return
    end
    local op, n = operator, take_count()
    read_char(function(ch)
      last_find = { kind = kind, ch = ch }
      apply(p, op, { key = kind, fn = find_motion(kind, ch) }, n)
      finish(p, op)
    end)
  end
end

local function repeat_find(reverse)
  return function()
    local p = ranma.pane()
    local op, n = operator, take_count()
    if p and last_find then
      local kind = reverse and REVERSE[last_find.kind] or last_find.kind
      apply(p, op, { key = kind, fn = find_motion(kind, last_find.ch) }, n)
    end
    finish(p, op)
  end
end

local function digit(d)
  return function()
    count = count .. d
  end
end

local function with_pane(f)
  return function()
    local p = ranma.pane()
    if p then
      f(p)
    end
  end
end

local function enter_operator(op)
  return function()
    operator = op
    ranma.action("mode vi_" .. op)
  end
end

-- The keys every NORMAL-like mode shares: counts, motions, finds.
local function motion_binds(binds)
  for d = 1, 9 do
    binds[tostring(d)] = { digit(tostring(d)), desc = "count" }
  end
  -- 0 is a digit once a count has begun, else the line's start.
  binds["0"] = {
    function()
      if count ~= "" then
        count = count .. "0"
      else
        motion_key("0")()
      end
    end,
    desc = "line start",
  }
  local names = {
    h = "left", l = "right", w = "next word", b = "word back", e = "word end",
    ["shift+w"] = "next WORD", ["shift+b"] = "WORD back", ["shift+e"] = "WORD end",
    ["^"] = "first non-blank", ["$"] = "line end",
  }
  for key, desc in pairs(names) do
    binds[key] = { motion_key(key), desc = desc }
  end
  for _, kind in ipairs({ "f", "t" }) do
    binds[kind] = { find_key(kind), desc = kind == "f" and "find" or "till" }
    binds["shift+" .. kind] = { find_key(kind:upper()), desc = kind == "f" and "find back" or "till back" }
  end
  binds[";"] = { repeat_find(false), desc = "repeat find" }
  binds[","] = { repeat_find(true), desc = "repeat find back" }
  return binds
end

local CURSOR_SHAPE = has("mode.cursor")
local function mode(name, label, cursor, binds)
  local def = { label = label, hint = false, binds = binds }
  if CURSOR_SHAPE then
    def.cursor = cursor
  end
  ranma.mode(name, def)
end

-- NORMAL.
local normal_binds = motion_binds({
  j = { function() local p = ranma.pane() if p then press(p, "down", take_count()) end end, desc = "down / history" },
  k = { function() local p = ranma.pane() if p then press(p, "up", take_count()) end end, desc = "up / history" },
  -- Moving through panes, as the global alt+arrows do (those work here too).
  ["alt+h"] = { "focus left", desc = "pane left" },
  ["alt+j"] = { "focus down", desc = "pane down" },
  ["alt+k"] = { "focus up", desc = "pane up" },
  ["alt+l"] = { "focus right", desc = "pane right" },

  i = { function() insert(ranma.pane()) end, desc = "insert" },
  a = {
    with_pane(function(p)
      if CURSOR then
        local l = line(p)
        if l.pos < l.hi then
          p:keys("right")
        end
      end
      insert(p)
    end),
    desc = "append",
  },
  ["shift+i"] = {
    with_pane(function(p)
      take_count()
      apply(p, nil, { key = "^", fn = MOTIONS["^"] }, 1)
      insert(p)
    end),
    desc = "insert at start",
  },
  ["shift+a"] = {
    with_pane(function(p)
      local l = CURSOR and line(p)
      if l and l.known then
        move(p, l.pos, l.hi)
      else
        p:keys("end")
      end
      insert(p)
    end),
    desc = "append at end",
  },

  d = { enter_operator("d"), desc = "delete…" },
  c = { enter_operator("c"), desc = "change…" },
  y = { enter_operator("y"), desc = "yank…" },
  ["shift+d"] = { function() operator = "d" motion_key("$")() end, desc = "delete to end" },
  ["shift+c"] = { function() operator = "c" motion_key("$")() end, desc = "change to end" },
  ["shift+y"] = { with_pane(function(p) take_count() whole_line(p, "y") normal(p) end), desc = "yank line" },
  x = { function() operator = "d" motion_key("l")() end, desc = "delete" },
  ["shift+x"] = { function() operator = "d" motion_key("h")() end, desc = "delete back" },
  s = { function() operator = "c" motion_key("l")() end, desc = "substitute" },
  ["shift+s"] = { with_pane(function(p) take_count() whole_line(p, "c") insert(p) end), desc = "substitute line" },
  r = {
    with_pane(function(p)
      take_count()
      if not CURSOR then
        needs_cursor()
        return
      end
      read_char(function(ch)
        local l = line(p)
        if l.pos < l.hi then
          delete_under(p, l)
          p:send(ch)
          p:keys("left")
        end
        normal(p)
      end)
    end),
    desc = "replace",
  },
  ["~"] = {
    with_pane(function(p)
      local n = take_count()
      if not CURSOR then
        needs_cursor()
        return
      end
      local l = line(p)
      for i = l.pos, math.min(l.hi, l.pos + n) - 1 do
        local ch = at(l, i)
        local swapped = ch:lower() ~= ch and ch:lower() or ch:upper()
        if swapped ~= ch then
          delete_under(p, l)
          p:send(swapped)
        else
          p:keys("right")
        end
      end
    end),
    desc = "toggle case",
  },
  p = {
    with_pane(function(p)
      local n = take_count()
      if CURSOR then
        local l = line(p)
        if l.pos < l.hi then
          p:keys("right")
        end
      end
      p:paste(register:rep(n))
    end),
    desc = "paste after",
  },
  ["shift+p"] = { with_pane(function(p) p:paste(register:rep(take_count())) end), desc = "paste before" },
  u = {
    with_pane(function(p)
      local ok, err = pcall(press, p, ranma.get("vi.undo"), take_count())
      if not ok then
        ranma.notify("vi.undo: " .. tostring(err))
      end
    end),
    desc = "undo",
  },
  v = {
    with_pane(function(p)
      reset()
      if not CURSOR then
        needs_cursor()
        return
      end
      local c = p:cursor()
      p:copy_mode(c.line, c.col)
    end),
    desc = "select (copy mode)",
  },
  ["/"] = { with_pane(function(p) p:keys("ctrl+r") insert(p) end), desc = "search history" },
  escape = { function() reset() local p = ranma.pane() if p then p:keys("escape") end end, desc = "esc to program" },
  ["return"] = {
    with_pane(function(p)
      p:keys("return")
      insert(p)
    end),
    desc = "run, insert",
  },
})
mode("vi", "NORMAL", "block", normal_binds)

-- An operator waiting for its motion: d c y, then the same key again for the
-- whole line (dd cc yy). Esc gives up.
for op, label in pairs({ d = "DELETE", c = "CHANGE", y = "YANK" }) do
  local binds = motion_binds({})
  binds[op] = {
    with_pane(function(p)
      take_count()
      whole_line(p, op)
      finish(p, op)
    end),
    desc = "whole line",
  }
  binds.escape = { with_pane(normal), desc = "cancel" }
  binds["return"] = { with_pane(normal), desc = "cancel" }
  mode("vi_" .. op, label, "underline", binds)
end

-- One character, for f F t T r: any key that types one.
local function cancel_read()
  reading = nil
  normal(ranma.pane())
end
local char_binds = {
  escape = { cancel_read, desc = "cancel" },
  ["return"] = { cancel_read, desc = "cancel" },
  space = function()
    local f = reading
    reading = nil
    if f then f(" ") end
  end,
}
local function reads(ch, key)
  char_binds[key or ch] = function()
    local f = reading
    reading = nil
    if f then
      f(ch)
    else
      normal(ranma.pane())
    end
  end
end
for b = string.byte("a"), string.byte("z") do
  local ch = string.char(b)
  reads(ch)
  reads(ch:upper(), "shift+" .. ch)
end
for ch in ("0123456789`~!@#$%^&*()-_=+[]{}\\|;:'\",.<>/?"):gmatch(".") do
  reads(ch)
end
mode("vi_char", "CHAR", "underline", char_binds)

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
  if not in_vi(current) then
    reset()
    reading = nil
  end
end)

-- Focus lands in the pane's own state: NORMAL unless it was left in INSERT.
-- Not in the middle of WM mode, which a focus bind may still be in.
local function settle(p)
  if current == "wm" then
    return
  end
  if modal(p) and not p.vars.insert then
    if current ~= "vi" then
      normal(p)
    end
  elseif in_vi(current) then
    reset()
    ranma.action("exit_mode")
  end
end

ranma.on("focus_change", function(e)
  settle(e.pane and ranma.pane(e.pane))
end)

-- A full-screen program taking the focused pane (or leaving it) changes
-- whether NORMAL belongs there, with no key pressed.
if has("hook.screen_change") then
  ranma.on("screen_change", function(e)
    local p = ranma.pane()
    if p and p.id == e.pane then
      settle(p)
    end
  end)
end
