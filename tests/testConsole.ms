// testConsole.ms
//
// Tests for the text-input widget and the ICL console, without a window
// (using the stand-in for raylib).  Run from the repo root:
//
//   MS_IMPORT_PATH=src:tests miniscript tests/testConsole.ms

import "fakeRaylib"
globals.raylib = fakeRaylib.module
rl = raylib

import "world"
import "scenes"
import "brain"
import "textInput"
import "console"

failures = 0
checks = 0
check = function(condition, what)
	globals.checks += 1
	if condition then return
	globals.failures += 1
	print "FAILED: " + what
end function

// One frame of input: type some characters and/or press some keys (holding
// down any modifiers), then let the widget read them.
frame = function(widget, chars="", keys=null, held=null)
	rl.type chars
	if keys then
		for k in keys
			rl.press k
		end for
	end if
	rl.keysDown = []
	if held then
		for k in held
			rl.keysDown.push rl["KEY_" + k]
		end for
	end if
	result = widget.update
	rl.endFrame
	rl.keysDown = []
	return result
end function

//----------------------------------------------------------------------
// The text-input widget
//----------------------------------------------------------------------

f = textInput.TextInput.make
check frame(f, "hello") == null and f.text == "hello" and f.cursor == 5, "typing"
frame f, "", ["LEFT"]
frame f, "", ["LEFT"]
frame f, "XY"
check f.text == "helXYlo" and f.cursor == 5, "insert in the middle"
frame f, "", ["BACKSPACE"]
frame f, "", ["DELETE"]
check f.text == "helXo", "backspace and delete: " + f.text
frame f, "", ["HOME"]
check f.cursor == 0, "home"
frame f, "", ["BACKSPACE"]
check f.text == "helXo", "backspace at the start does nothing"
frame f, "", ["END"]
check f.cursor == 5, "end"

f.setText "pick up the red block"
frame f, "", ["LEFT"], ["LEFT_ALT"]
check f.cursor == 16, "alt-left goes to the start of the word"
frame f, "", ["LEFT"], ["LEFT_ALT"]
check f.cursor == 12, "and again"
frame f, "", ["RIGHT"], ["LEFT_ALT"]
check f.cursor == 15, "alt-right goes to the end of the word"
frame f, "", ["BACKSPACE"], ["LEFT_ALT"]
check f.text == "pick up the  block" and f.cursor == 12, "alt-backspace deletes a word: " + f.text
frame f, "", ["K"], ["LEFT_SUPER"]
check f.text == "pick up the ", "cmd-K deletes to the end"
frame f, "", ["A"], ["LEFT_CONTROL"]
check f.cursor == 0, "ctrl-A goes to the start"
frame f, "q", [], ["LEFT_SUPER"]
check f.text == "pick up the ", "cmd-Q is a command, not a character"
frame f, "", ["ESCAPE"]
check f.text == "", "escape clears"

// Paste: line breaks become whatever the field says.
rl.clipboard = "x1 = it" + char(10) + "PickUp x1"
f.newlineReplacement = "; "
frame f, "", ["V"], ["LEFT_SUPER"]
check f.text == "x1 = it; PickUp x1", "paste: " + f.text

// Submitting, and the history.
check frame(f, "", ["ENTER"]) == "x1 = it; PickUp x1" and f.text == "", "return hands over the line"
frame f, "second"
check frame(f, "", ["KP_ENTER"]) == "second", "so does the keypad's enter"
frame f, "draft"
frame f, "", ["UP"]
check f.text == "second", "up: the last line"
frame f, "", ["UP"]
check f.text == "x1 = it; PickUp x1", "up again: the one before"
frame f, "", ["UP"]
check f.text == "x1 = it; PickUp x1", "no further back than the first"
frame f, "", ["DOWN"]
frame f, "", ["DOWN"]
check f.text == "draft", "down past the newest: back to the draft"
frame f, "", ["ENTER"]
frame f, "", ["ENTER"]
check f.history.len == 3, "an empty line isn't remembered"

// Drawing, including a line much too long for the field.
f.setText "x" * 200
f.draw 0, 0, 400
check f.scrollX > 0, "a long line scrolls to keep the cursor in view"
f.moveTo 0
f.draw 0, 0, 400
check f.scrollX == 0, "and scrolls back"
unfocused = textInput.TextInput.make
unfocused.focused = false
check frame(unfocused, "abc", ["ENTER"]) == null and unfocused.text == "", "an unfocused field ignores the keyboard"

//----------------------------------------------------------------------
// The console
//----------------------------------------------------------------------

w = world.World.make
w.load scenes.byName.winograd
c = console.Console.make
c.brain = brain.Brain.make(w)

lastLines = function(n)
	result = []
	for e in c.entries[-n:]
		result.push e.text
	end for
	return result
end function

// A question: echoed, then answered (on the next frame, since nothing moves).
frame c, "x1 = the pyramid [color blue]; Ask size x1", ["ENTER"]
check lastLines(1) == ["> x1 = the pyramid [color blue]; Ask size x1"], "the line is echoed"
c.update
check lastLines(1) == ["Large."], "and answered: " + lastLines(1)
check c.entries[-1].kind == "robot" and c.entries[-2].kind == "you", "entry kinds"

// A command: the reply waits until the robot has finished moving.
frame c, "x1 = a block [color red] [size big]; PickUp x1", ["ENTER"]
check w.hand.holding != null, "the robot picked it up"
c.update true
c.update true
check c.entries[-1].kind == "you", "no reply while busy"
c.update false
check lastLines(1) == ["OK."], "then the reply"

// Lines typed while busy wait their turn.
rl.type "x1 = it; Ask color x1"
rl.press "ENTER"
c.update true
rl.endFrame
check c.queue.len == 1 and c.entries[-1].text == "OK.", "queued while busy"
c.update
c.update
check lastLines(2) == ["> x1 = it; Ask color x1", "Red."], "then handled: " + lastLines(2)

// Errors and console commands.
frame c, "x1 = a block [on x2", ["ENTER"]
c.update
check lastLines(1)[0].indexOf("couldn't read") != null, "bad ICL"
frame c, "/nonsense", ["ENTER"]
check lastLines(1) == ["There's no command /nonsense.  Try /help."], "unknown command"
frame c, "/help", ["ENTER"]
check c.entries.len > 15, "help"
said = null
c.addCommand "scene", function(con, arg); globals.said = arg; end function, "/scene name"
frame c, "/scene  playground ", ["ENTER"]
check said == "playground", "added commands get their argument, stripped"
frame c, "/clear", ["ENTER"]
check c.entries == [], "clear"

// The examples in /help all work, in order, in a fresh Winograd scene.
hw = world.World.make
hw.load scenes.byName.winograd
hb = brain.Brain.make(hw)
hb.selected = hw.thing("box")
for ex in console.Console.examples
	reply = hb.respond(ex[0].replace(";", char(10)))
	check reply.indexOf("(") != 0 and reply.indexOf("I don't") == null, "help example: " + ex[0] + " -> " + reply
end for

// Long replies wrap; scrolling stays in range.
c.say "word " * 100, "robot"
c.draw 0, 500, 640, 300
check c.entries[0].rows.len > 1, "a long line wraps"
check c.entries[0].rows[1].indexOf("    word") == 0, "continuation rows are indented"
for i in range(1, 50)
	c.say "line " + i
end for
c.scrollBy 1000
c.draw 0, 500, 640, 300
check c.scroll > 0 and c.scroll < 70, "scrolling back is limited to what's there: " + c.scroll
check c.contains({"x": 10, "y": 600}) and not c.contains({"x": 10, "y": 100}), "contains"

print checks + " checks, " + failures + " failures."
exit (failures > 0)
