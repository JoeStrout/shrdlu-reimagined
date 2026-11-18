// textInput.ms
//
// A one-line text field: you type, it shows what you typed with a blinking
// cursor, and pressing Return hands the line over.  It knows nothing about
// what the text means, so any console can use it.
//
// Usage, once per frame:
//
//   line = field.update          // read the keyboard; the line, on Return
//   if line != null then ...     // (otherwise null)
//   field.draw x, y, width
//
// Keys (on a Mac, Cmd works wherever Ctrl is listed):
//   Left/Right          move the cursor        Alt-Left/Right   a word at a time
//   Home/End            start or end of line   Ctrl-A, Ctrl-E   the same
//   Backspace/Delete    delete a character     Alt-Backspace    delete a word
//   Ctrl-U, Ctrl-K      delete to the start, or to the end, of the line
//   Up/Down             earlier lines you entered (the history)
//   Ctrl-V              paste                  Escape           clear the line

rl = raylib

TextInput = {}
TextInput.text = ""
TextInput.cursor = 0           // where the next character goes, 0 to text.len
TextInput.prompt = "> "
TextInput.placeholder = ""     // shown, dimmed, while the field is empty
TextInput.focused = true       // only a focused field reads the keyboard
TextInput.fontSize = 20
TextInput.padding = 6
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
	f.scrollX = 0         // how far the text is scrolled left, in pixels
	f.blinkStart = 0      // when the cursor last moved (it stays lit while moving)
	return f
end function

TextInput.height = function
	return self.fontSize + 2 * self.padding
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
	if i < 0 then i = 0
	if i > self.text.len then i = self.text.len
	self.cursor = i
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
	self.scrollX = 0
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
	if pressed(rl.KEY_UP) then self.browseHistory -1
	if pressed(rl.KEY_DOWN) then self.browseHistory 1
	if rl.IsKeyPressed(rl.KEY_ESCAPE) then self.setText ""

	if rl.IsKeyPressed(rl.KEY_ENTER) or rl.IsKeyPressed(rl.KEY_KP_ENTER) then return self.submit
	return null
end function

//----------------------------------------------------------------------
// Drawing.
//----------------------------------------------------------------------

TextInput.draw = function(x, y, width)
	fs = self.fontSize
	pad = self.padding
	h = self.height
	st = self.style
	rl.DrawRectangle x, y, width, h, st.background
	if self.focused then border = st.focusedBorder else border = st.border
	rl.DrawRectangleLines x, y, width, h, border

	promptWidth = rl.MeasureText(self.prompt, fs)
	rl.DrawText self.prompt, x + pad, y + pad, fs, st.prompt
	textX = x + pad + promptWidth
	room = width - 2 * pad - promptWidth

	// Scroll sideways as needed to keep the cursor in view.
	cursorX = rl.MeasureText(self.text[:self.cursor], fs)
	if cursorX - self.scrollX > room - 4 then self.scrollX = cursorX - room + 4
	if cursorX < self.scrollX then self.scrollX = cursorX
	if self.scrollX < 0 then self.scrollX = 0

	rl.BeginScissorMode textX, y, room, h
	if self.text == "" then
		rl.DrawText self.placeholder, textX, y + pad, fs, st.placeholder
	else
		rl.DrawText self.text, textX - self.scrollX, y + pad, fs, st.text
	end if
	// The cursor blinks, but stays lit while you're typing.
	if self.focused and (rl.GetTime - self.blinkStart) % 1 < 0.6 then
		rl.DrawRectangle textX + cursorX - self.scrollX, y + pad - 1, 2, fs + 2, st.cursor
	end if
	rl.EndScissorMode
end function
