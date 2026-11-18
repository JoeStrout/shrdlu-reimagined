// textInput.ms
//
// A text field for one line of input: you type, it shows what you typed
// with a blinking cursor, and pressing Return hands the line over.  A line
// too long for the field wraps onto more rows, and the field grows taller
// (up to maxRows, after which it scrolls).  It knows nothing about what the
// text means, so any console can use it.
//
// Usage, once per frame:
//
//   line = field.update          // read the keyboard; the line, on Return
//   if line != null then ...     // (otherwise null)
//   h = field.heightFor(width)   // how tall it will be, for layout
//   field.draw x, y, width
//
// Keys (on a Mac, Cmd works wherever Ctrl is listed):
//   Left/Right          move the cursor        Alt-Left/Right   a word at a time
//   Home/End            start or end of line   Ctrl-A, Ctrl-E   the same
//   Backspace/Delete    delete a character     Alt-Backspace    delete a word
//   Ctrl-U, Ctrl-K      delete to the start, or to the end, of the line
//   Up/Down             the row above or below; from the top or bottom row,
//                       earlier lines you entered (the history)
//   Ctrl-V              paste                  Escape           clear the line

import "uiText"
import "mathUtil"

rl = raylib

TextInput = {}
TextInput.text = ""
TextInput.cursor = 0           // where the next character goes, 0 to text.len
TextInput.prompt = "> "
TextInput.placeholder = ""     // shown, dimmed, while the field is empty
TextInput.focused = true       // only a focused field reads the keyboard
TextInput.fontSize = 16
TextInput.lineGap = 4          // extra space between rows
TextInput.padding = 6
TextInput.maxRows = 6          // grow to this many rows, then scroll
TextInput.maxHistory = 100
TextInput.newlineReplacement = " "   // what a pasted line break becomes
TextInput.style = {
	"background": "#14171CEE", "border": "#5A6470", "focusedBorder": "#8FA8C0",
	"text": "#E8E8E8", "prompt": "#8FA8C0", "placeholder": "#6A737D", "cursor": "#E8E8E8"}

TextInput.make = function(placeholder="")
	f = new TextInput
	f.placeholder = placeholder
	f.history = []        // lines entered so far, oldest first
	f.historyPos = 0      // which history line is showing; history.len means none
	f.draft = ""          // what was being typed before browsing the history
	f.scrollRow = 0       // the first row shown, when there are more than maxRows
	f.blinkStart = 0      // when the cursor last moved (it stays lit while moving)
	f.layout = null       // how the text was last wrapped (see layoutFor)
	return f
end function

//----------------------------------------------------------------------
// Editing.  These work without a window, so they can be tested directly.
//----------------------------------------------------------------------

TextInput.setText = function(s)
	self.text = s
	self.cursor = s.len
	self.touched
end function

// Note that the user did something (keeps the cursor lit while typing).
TextInput.touched = function
	self.blinkStart = rl.GetTime
end function

TextInput.insert = function(s)
	self.text = self.text[:self.cursor] + s + self.text[self.cursor:]
	self.cursor += s.len
	self.touched
end function

TextInput.moveTo = function(i)
	self.cursor = mathUtil.clamp(i, 0, self.text.len)
	self.touched
end function

// Delete the text between two positions (in either order).
TextInput.deleteRange = function(a, b)
	if a > b then
		t = a; a = b; b = t
	end if
	if a < 0 then a = 0
	if b > self.text.len then b = self.text.len
	self.text = self.text[:a] + self.text[b:]
	self.cursor = a
	self.touched
end function

TextInput.deleteBack = function
	self.deleteRange self.cursor - 1, self.cursor
end function

TextInput.deleteForward = function
	self.deleteRange self.cursor, self.cursor + 1
end function

// Where the previous word starts: skip back over spaces, then over the word.
TextInput.wordStartBefore = function(i)
	while i > 0 and self.text[i-1] == " "
		i -= 1
	end while
	while i > 0 and self.text[i-1] != " "
		i -= 1
	end while
	return i
end function

// Where the next word ends: skip over spaces, then over the word.
TextInput.wordEndAfter = function(i)
	n = self.text.len
	while i < n and self.text[i] == " "
		i += 1
	end while
	while i < n and self.text[i] != " "
		i += 1
	end while
	return i
end function

TextInput.deleteWordBack = function
	self.deleteRange self.wordStartBefore(self.cursor), self.cursor
end function

TextInput.paste = function(s)
	if s == null then return
	s = s.replace(char(13) + char(10), char(10)).replace(char(13), char(10))
	s = s.replace(char(10), self.newlineReplacement).replace(char(9), " ")
	self.insert s
end function

// Step back (-1) or forward (+1) through the lines entered earlier.
TextInput.browseHistory = function(direction)
	if not self.history then return
	if self.historyPos == self.history.len then self.draft = self.text
	pos = self.historyPos + direction
	if pos < 0 or pos > self.history.len then return
	self.historyPos = pos
	if pos == self.history.len then self.setText self.draft else self.setText self.history[pos]
end function

// Hand over the line: remember it, clear the field, and return it.
TextInput.submit = function
	line = self.text
	if line != "" and (not self.history or self.history[-1] != line) then
		self.history.push line
		if self.history.len > self.maxHistory then self.history.pull
	end if
	self.historyPos = self.history.len
	self.draft = ""
	self.setText ""
	self.scrollRow = 0
	return line
end function

//----------------------------------------------------------------------
// Reading the keyboard.
//----------------------------------------------------------------------

// Was this key just pressed, or is it auto-repeating?
pressed = function(key)
	return rl.IsKeyPressed(key) or rl.IsKeyPressedRepeat(key)
end function

// Read this frame's keys.  Returns the line when Return is pressed;
// otherwise null.
TextInput.update = function
	if not self.focused then return null
	alt = rl.IsKeyDown(rl.KEY_LEFT_ALT) or rl.IsKeyDown(rl.KEY_RIGHT_ALT)
	ctrl = rl.IsKeyDown(rl.KEY_LEFT_CONTROL) or rl.IsKeyDown(rl.KEY_RIGHT_CONTROL) or
	  rl.IsKeyDown(rl.KEY_LEFT_SUPER) or rl.IsKeyDown(rl.KEY_RIGHT_SUPER)

	// Ordinary typing.  (Ctrl-something is a command, not a character; but
	// Ctrl-Alt is how some keyboards type certain characters, so allow that.)
	c = rl.GetCharPressed
	while c
		if not ctrl or alt then self.insert char(c)
		c = rl.GetCharPressed
	end while

	if ctrl and not alt then
		if pressed(rl.KEY_A) then self.moveTo 0
		if pressed(rl.KEY_E) then self.moveTo self.text.len
		if pressed(rl.KEY_U) then self.deleteRange 0, self.cursor
		if pressed(rl.KEY_K) then self.deleteRange self.cursor, self.text.len
		if pressed(rl.KEY_V) then self.paste rl.GetClipboardText
	end if

	if pressed(rl.KEY_LEFT) then
		if alt then
			self.moveTo self.wordStartBefore(self.cursor)
		else if ctrl then
			self.moveTo 0
		else
			self.moveTo self.cursor - 1
		end if
	end if
	if pressed(rl.KEY_RIGHT) then
		if alt then
			self.moveTo self.wordEndAfter(self.cursor)
		else if ctrl then
			self.moveTo self.text.len
		else
			self.moveTo self.cursor + 1
		end if
	end if
	if pressed(rl.KEY_HOME) then self.moveTo 0
	if pressed(rl.KEY_END) then self.moveTo self.text.len
	if pressed(rl.KEY_BACKSPACE) then
		if alt then self.deleteWordBack else self.deleteBack
	end if
	if pressed(rl.KEY_DELETE) then self.deleteForward
	if pressed(rl.KEY_UP) then self.upOrDown -1
	if pressed(rl.KEY_DOWN) then self.upOrDown 1
	if rl.IsKeyPressed(rl.KEY_ESCAPE) then self.setText ""

	if rl.IsKeyPressed(rl.KEY_ENTER) or rl.IsKeyPressed(rl.KEY_KP_ENTER) then return self.submit
	return null
end function

// Up (-1) or Down (+1): within a wrapped line, move to the row above or
// below, keeping about the same horizontal position.  From the top row
// (going up) or the bottom row (going down), step through the history
// instead, as in a terminal.
TextInput.upOrDown = function(direction)
	lay = self.layout
	if lay == null or lay.text != self.text or self.text == "" then
		self.browseHistory direction
		return
	end if
	row = self.rowOf(self.cursor)
	target = row + direction
	if target < 0 or target >= lay.rows.len then
		self.browseHistory direction
		return
	end if
	// Find the spot in the target row nearest the cursor's x position.
	x = self.xInRow(row, self.cursor)
	r = lay.rows[target]
	best = r[0]
	for i in range(r[0], r[1])
		if i == r[1] and target < lay.rows.len - 1 then break   // that's the next row's start
		if abs(self.xInRow(target, i) - x) < abs(self.xInRow(target, best) - x) then best = i
	end for
	self.moveTo best
end function

//----------------------------------------------------------------------
// Layout: wrapping the text into rows.  The prompt sits at the start of the
// first row, and later rows line up under the text, not under the prompt.
//----------------------------------------------------------------------

// What's shown: the text, or the placeholder while there's none.
TextInput.shownText = function
	if self.text == "" then return self.placeholder
	return self.text
end function

// Wrap the text for a field of the given width; remembered, so that this is
// cheap from frame to frame.  Returns {text, width, rows}, where rows is a
// list of [start, stop] positions in the text (see uiText.wrapRanges).
TextInput.layoutFor = function(width)
	lay = self.layout
	shown = self.shownText
	if lay and lay.width == width and lay.text == self.text and lay.shown == shown then return lay
	room = width - 2 * self.padding - uiText.measure(self.prompt, self.fontSize)
	self.layout = {"text": self.text, "shown": shown, "width": width,
	  "rows": uiText.wrapRanges(shown, room - 4, self.fontSize)}
	return self.layout
end function

// Which row the given text position is in.  A position right at a break
// belongs to the row it starts (except at the very end of the text).
TextInput.rowOf = function(pos)
	rows = self.layout.rows
	for i in rows.indexes
		if pos < rows[i][1] or i == rows.len - 1 then return i
	end for
end function

// How far across its row the given position is, in screen points.
TextInput.xInRow = function(row, pos)
	start = self.layout.rows[row][0]
	return uiText.measure(self.text[start:pos], self.fontSize)
end function

TextInput.rowHeight = function
	return self.fontSize + self.lineGap
end function

// How tall the field will be at the given width (it grows with the text).
TextInput.heightFor = function(width)
	n = self.layoutFor(width).rows.len
	if n > self.maxRows then n = self.maxRows
	return n * self.rowHeight - self.lineGap + 2 * self.padding
end function

//----------------------------------------------------------------------
// Drawing.
//----------------------------------------------------------------------

TextInput.draw = function(x, y, width)
	fs = self.fontSize
	pad = self.padding
	h = self.heightFor(width)
	lay = self.layout
	st = self.style
	rl.DrawRectangle x, y, width, h, st.background
	if self.focused then border = st.focusedBorder else border = st.border
	rl.DrawRectangleLines x, y, width, h, border

	promptWidth = uiText.measure(self.prompt, fs)
	uiText.draw self.prompt, x + pad, y + pad, fs, st.prompt
	textX = x + pad + promptWidth

	// If there are more rows than fit, scroll to keep the cursor's row in view.
	cursorRow = self.rowOf(self.cursor)
	if self.text == "" then cursorRow = 0
	if cursorRow < self.scrollRow then self.scrollRow = cursorRow
	if cursorRow >= self.scrollRow + self.maxRows then self.scrollRow = cursorRow - self.maxRows + 1
	if self.scrollRow > lay.rows.len - self.maxRows then self.scrollRow = lay.rows.len - self.maxRows
	if self.scrollRow < 0 then self.scrollRow = 0

	if self.text == "" then color = st.placeholder else color = st.text
	shown = self.shownText
	rowY = y + pad
	lastRow = self.scrollRow + self.maxRows - 1
	if lastRow >= lay.rows.len then lastRow = lay.rows.len - 1
	for i in range(self.scrollRow, lastRow)
		r = lay.rows[i]
		uiText.draw shown[r[0]:r[1]], textX, rowY, fs, color
		// The cursor blinks, but stays lit while you're typing.
		if i == cursorRow and self.focused and (rl.GetTime - self.blinkStart) % 1 < 0.6 then
			cx = 0
			if self.text != "" then cx = self.xInRow(i, self.cursor)
			rl.DrawRectangle textX + cx, rowY - 1, 2, fs + 2, st.cursor
		end if
		rowY += self.rowHeight
	end for
end function
