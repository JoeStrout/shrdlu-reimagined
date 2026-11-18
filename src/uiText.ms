// uiText.ms
//
// Text for the user interface: which font to use, and how to measure, draw,
// and wrap text in it.  Everything that draws words on the screen (the
// console, its input field, the labels over the 3D view) goes through here,
// so the whole program uses one font.
//
// Until load is called (for example in the tests, which have no window),
// raylib's small built-in font is used.
//
// Note: each module that imports this one gets its own fresh copy of it, so
// the loaded font can't simply be kept in a variable here; the console's
// copy would never see the font that main.ms loaded into its copy.  So the
// font is kept in the one place they all share: globals.uiFont.

rl = raylib

spacing = 0         // extra space between characters, in pixels

// The loaded Font, or null for raylib's default font.
font = function
	if globals.hasIndex("uiFont") then return globals.uiFont
	return null
end function

// Load the UI font from a TrueType file.  On a high-resolution (Retina)
// screen each point is several pixels, so we render the glyphs at a larger
// size than we'll draw them, and let the GPU smooth them down; otherwise
// text looks blurry.
load = function(path="assets/DejaVuSans.ttf", baseSize=48)
	// Plain ASCII, the Latin-1 letters (é, ü, ...), and a few typographic
	// marks that turn up in pasted text: dashes, curly quotes, ellipsis.
	codepoints = range(32, 126) + range(160, 255) + [8211, 8212, 8216, 8217, 8220, 8221, 8230]
	f = rl.LoadFontEx(path, baseSize, codepoints)
	if f == null then
		print "Couldn't load the font " + path + "; using the default font."
		return
	end if
	rl.SetTextureFilter f.texture, rl.TEXTURE_FILTER_BILINEAR
	globals.uiFont = f
end function

// How wide the text would be, in screen points.
measure = function(text, size)
	f = font
	if f == null then return rl.MeasureText(text, size)
	return rl.MeasureTextEx(f, text, size, spacing).x
end function

// Draw text with its top-left corner at x, y.
draw = function(text, x, y, size, color)
	f = font
	if f == null then
		rl.DrawText text, x, y, size, color
	else
		rl.DrawTextEx f, text, [x, y], size, spacing, color
	end if
end function

// Break text into rows no wider than the given width.  Returns a list of
// [start, stop] index pairs into the text, which together cover all of it,
// in order (so a position in the text can be found on screen, which the
// input field needs for its cursor).  Rows break after a space where
// possible; a word too long for a row is broken wherever it must be.
// The spaces at a break stay at the end of the row before, where they
// take no visible room.
wrapRanges = function(text, width, size)
	n = text.len
	if n == 0 then return [[0, 0]]
	rows = []
	start = 0
	while start < n
		// Grow the row a character at a time until it no longer fits
		// (ignoring trailing spaces, which can hang past the edge).
		stop = start + 1
		lastBreak = -1     // just after the last space seen in this row
		while stop <= n
			if text[stop-1] == " " then
				lastBreak = stop
			else if measure(text[start:stop], size) > width then
				break
			end if
			stop += 1
		end while
		if stop > n then
			rows.push [start, n]
			break
		end if
		// stop-1 is the first character that didn't fit.
		if lastBreak > start then
			stop = lastBreak
		else
			stop -= 1
			if stop <= start then stop = start + 1   // always take at least one
		end if
		rows.push [start, stop]
		start = stop
	end while
	return rows
end function
