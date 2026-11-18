// console.ms
//
// The console: a panel where you talk to the robot in English, and read its
// replies.  It will grow into the "under the hood" panel that shows how each
// sentence was understood.
//
//   > Pick up a big red block.
//   OK.
//
// A line starting with ":" is ICL (the robot's internal language, see
// icl.ms), which goes straight to the brain.  Since ICL is usually several
// lines, a semicolon stands for a line break:
//
//   > : x1 = a block [color red] [size big]; PickUp x1
//   OK.
//
// Lines starting with "/" are commands to the console itself: /help, /clear,
// /icl (show the ICL for each English sentence), and any that the main
// program adds (such as /scene).
//
// The console waits for the robot: a reply appears when the robot has finished
// acting it out, and anything typed meanwhile waits its turn.
//
// If it has a log (see sessionLog.ms), everything said goes there too, along
// with the ICL for every English sentence.

import "textInput"

rl = raylib

Console = {}
Console.brain = null      // the Brain that ICL goes to
Console.fontSize = 20
Console.lineGap = 4
Console.padding = 10
Console.maxEntries = 500
Console.showIcl = false  // show the ICL for each English sentence?
Console.log = null       // a SessionLog to write the transcript to, or null
Console.style = {
	"panel": "#000000AA", "you": "#9FC9F0", "robot": "#F0F0F0", "note": "#9AA3AD",
	"icl": "#8FB89A"}

Console.make = function
	c = new Console
	c.entries = []          // the transcript: {text, kind}, oldest first
	c.scroll = 0            // rows scrolled back from the newest
	c.queue = []            // lines typed but not yet handled
	c.pendingReply = null   // a reply waiting for the robot to finish moving
	c.rect = null           // where the console was last drawn
	c.input = textInput.TextInput.make("Type here, for example:  Pick up a big red block.   (/help for more)")
	c.input.newlineReplacement = "; "
	// Commands: name -> {"run": function(console, argument), "help": text}
	c.commands = {}
	c.addCommand "help", @helpCommand, "/help: show this help"
	c.addCommand "clear", @clearCommand, "/clear: clear the transcript"
	c.addCommand "icl", @iclCommand, "/icl: show (or stop showing) the ICL for each English sentence"
	return c
end function

Console.addCommand = function(name, f, helpText)
	self.commands[name] = {"run": @f, "help": helpText}
end function

// Add a line (or several, split at line breaks) to the transcript.
// The kind is "you", "robot", "note", or "icl"; it sets the color.
Console.say = function(text, kind="note")
	for line in str(text).split(char(10))
		self.entries.push {"text": line, "kind": kind}
	end for
	if self.log then self.log.add kind, text
	while self.entries.len > self.maxEntries
		self.entries.pull
	end while
	self.scroll = 0
end function

//----------------------------------------------------------------------
// Handling what's typed.
//----------------------------------------------------------------------

// Call once per frame.  busy says whether the robot is still acting out
// earlier work; until it's done, replies and new lines wait.
Console.update = function(busy=false)
	line = self.input.update
	if line != null then self.queue.push line
	if pressed(rl.KEY_PAGE_UP) then self.scrollBy self.visibleRows - 1
	if pressed(rl.KEY_PAGE_DOWN) then self.scrollBy 1 - self.visibleRows
	if busy then return
	if self.pendingReply != null then
		self.say self.pendingReply, "robot"
		self.pendingReply = null
	else if self.queue then
		self.handle self.queue.pull
	end if
end function

pressed = function(key)
	return rl.IsKeyPressed(key) or rl.IsKeyPressedRepeat(key)
end function

// Handle one line: echo it, then run it as a command or give it to the brain
// (as ICL if it starts with ":", otherwise as English).  The brain's reply is
// held until the robot finishes moving.
Console.handle = function(line)
	self.say self.input.prompt + line, "you"
	line = strip(line)
	if line == "" then return
	if line[0] == "/" then
		self.runCommand line[1:]
	else if self.brain == null then
		self.say "(There's no brain to talk to.)"
	else if line[0] == ":" then
		self.pendingReply = self.brain.respond(line[1:].replace(";", char(10)))
	else
		self.pendingReply = self.brain.hear(line)
		if self.showIcl then
			self.sayIcl self.brain.lastUnderstanding
		else if self.log then
			for icl in self.iclLines(self.brain.lastUnderstanding)
				self.log.add "icl", icl
			end for
		end if
	end if
end function

// Show the ICL the brain acted on for an English sentence, one line per
// line of ICL.
Console.sayIcl = function(understanding)
	for line in self.iclLines(understanding)
		self.say line, "icl"
	end for
end function

// The lines that sayIcl shows: the ICL, indented, noting which reading was
// chosen if there were several.  If the sentence didn't parse, the parser's
// complaint.  (Nothing, if a sentence settled an earlier question, like a
// "2" or "The green one.", so that no new understanding came of it.)
Console.iclLines = function(understanding)
	if understanding == null then return []
	if understanding.error then return ["    (no parse: " + understanding.error + ")"]
	if not understanding.programs or not understanding.hasIndex("chosen") then return []
	i = 0
	if understanding.hasIndex("chosen") then i = understanding.chosen
	note = ""
	if understanding.programs.len > 1 then
		note = "  (reading " + (i + 1) + " of " + understanding.programs.len + ")"
	end if
	result = []
	for line in understanding.programs[i].format.split(char(10))
		result.push "    " + line
	end for
	result[-1] += note
	return result
end function

Console.runCommand = function(text)
	words = text.split(" ")
	name = words[0]
	argument = strip(words[1:].join(" "))
	if not self.commands.hasIndex(name) then
		self.say "There's no command /" + name + ".  Try /help."
		return
	end if
	run = @self.commands[name].run
	run self, argument
end function

// Examples for /help, which work in order in the Winograd scene (see
// tests/testConsole.ms, which checks that they do).  Each is a sentence,
// and a hint to go with it (or "").
Console.examples = [
  ["Pick up a big red block.", ""],
  ["Find a block which is taller than the one you are holding and put it into the box.", ""],
  ["What does the box contain?", ""],
  ["Why did you pick up the blue block?", ""],
  ["Why?", ""],
  ["How many blocks are not in the box?", ""],
  ["Is there a large block behind a pyramid?", ""],
  ["What color is this?", "click on something first"]]

// An example of typing ICL directly.
Console.iclExample = ": x1 = a pyramid; Ask color x1"

helpCommand = function(console, argument)
	console.say "Talk to the robot in English.  For example (try them in order):"
	for ex in console.examples
		if ex[1] then console.say "  " + ex[0] + "   (" + ex[1] + ")" else console.say "  " + ex[0]
	end for
	console.say "Start a line with "":"" to type ICL, using "";"" between lines:  " + console.iclExample
	console.say "Up/Down: earlier lines   Page Up/Down or wheel: scroll   Esc: clear line"
	names = console.commands.indexes
	names.sort
	for name in names
		console.say console.commands[name].help
	end for
end function

iclCommand = function(console, argument)
	console.showIcl = not console.showIcl
	if console.showIcl then
		console.say "Showing the ICL for each sentence."
	else
		console.say "Not showing the ICL."
	end if
end function

clearCommand = function(console, argument)
	console.entries = []
	console.scroll = 0
end function

// The string without spaces at either end.
strip = function(s)
	i = 0
	while i < s.len and s[i] == " "
		i += 1
	end while
	j = s.len
	while j > i and s[j-1] == " "
		j -= 1
	end while
	return s[i:j]
end function

//----------------------------------------------------------------------
// Drawing.
//----------------------------------------------------------------------

Console.rowHeight = function
	return self.fontSize + self.lineGap
end function

// How many transcript rows fit in the panel (as last drawn).
Console.visibleRows = function
	if self.rect == null then return 1
	room = self.rect.h - self.input.height - 3 * self.padding
	rows = floor(room / self.rowHeight)
	if rows < 1 then rows = 1
	return rows
end function

Console.scrollBy = function(rows)
	self.scroll += rows
	if self.scroll < 0 then self.scroll = 0
end function

// Is a screen point over the console?  (Then clicks and the mouse wheel are
// the console's, not the 3D view's.)
Console.contains = function(point)
	r = self.rect
	if r == null then return false
	return point.x >= r.x and point.x < r.x + r.w and point.y >= r.y and point.y < r.y + r.h
end function

// Break a line of text into rows no wider than the given width, at spaces.
// Continuation rows are indented a little.
wrap = function(text, width, fontSize)
	rows = []
	row = ""
	for word in text.split(" ")
		if row == "" then
			candidate = word
		else
			candidate = row + " " + word
		end if
		if row != "" and rl.MeasureText(candidate, fontSize) > width then
			rows.push row
			row = "    " + word
		else
			row = candidate
		end if
	end for
	rows.push row
	return rows
end function

// All transcript rows, wrapped to the width: a list of [text, kind].
// (Each entry remembers its wrapping, so this is cheap from frame to frame.)
Console.rows = function(width)
	result = []
	for e in self.entries
		if not e.hasIndex("width") or e.width != width then
			e.rows = wrap(e.text, width, self.fontSize)
			e.width = width
		end if
		for r in e.rows
			result.push [r, e.kind]
		end for
	end for
	return result
end function

Console.draw = function(x, y, w, h)
	self.rect = {"x": x, "y": y, "w": w, "h": h}
	pad = self.padding
	rl.DrawRectangle x, y, w, h, self.style.panel
	self.input.draw x + pad, y + h - pad - self.input.height, w - 2 * pad

	// The transcript, newest at the bottom, scrolled back by self.scroll rows.
	rows = self.rows(w - 2 * pad)
	visible = self.visibleRows
	maxScroll = rows.len - visible
	if maxScroll < 0 then maxScroll = 0
	if self.scroll > maxScroll then self.scroll = maxScroll
	last = rows.len - 1 - self.scroll
	first = last - visible + 1
	if first < 0 then first = 0
	rowY = y + h - 2 * pad - self.input.height - (last - first + 1) * self.rowHeight
	for i in range(first, last, 1)
		row = rows[i]
		rl.DrawText row[0], x + pad, rowY, self.fontSize, self.style[row[1]]
		rowY += self.rowHeight
	end for
	if self.scroll > 0 then
		note = "(scrolled back; Page Down for more)"
		rl.DrawText note, x + w - pad - rl.MeasureText(note, 16), y + pad, 16, self.style.note
	end if
end function
