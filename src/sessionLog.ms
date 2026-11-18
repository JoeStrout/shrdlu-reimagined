// sessionLog.ms
//
// On the desktop, the app writes each session's conversation to a file in
// logs/ (one file per session, numbered: session-001.txt, session-002.txt,
// and so on), so that after
// trying things out we can look back at what worked and what didn't.  On
// the web there's nowhere to write, so there's no log.
//
// Each line of the transcript is written with its kind in front:
//
//   you:    > Pick up a big red block.
//   icl:        x1 = a block [color red] [size big]
//   icl:        PickUp x1
//   robot:  OK.
//
// The ICL for every English sentence is logged, even when the console isn't
// showing it, since that's usually what we need to see when a sentence goes
// wrong.  (When a sentence doesn't parse, the "icl:" line says why.)
//
// Writing to a file only saves it when the file is closed, so rather than
// keep it open, we rewrite the whole file after each line.  Sessions are
// short, and this way the log is complete even if the app is stopped
// suddenly.

SessionLog = {}
SessionLog.path = null    // the file we're writing
SessionLog.lines = null   // everything logged so far

// Start a new log, or return null if we can't (as on the web).
SessionLog.make = function(folder="logs")
	if version.hasIndex("platform") and version.platform == "Web" then return null
	if not file.exists(folder) then
		if file.makedir(folder) != null then return null
	end if
	log = new SessionLog
	log.path = file.child(folder, "session-" + nextNumber(folder) + ".txt")
	log.lines = []
	platform = ""
	if version.hasIndex("platform") then platform = ", on " + version.platform
	log.add "note", "SHRDLU Reimagined session" + platform
	// (Not every build can tell the date, but the file it just wrote knows.)
	info = file.info(log.path)
	if info and info.hasIndex("date") then log.add "note", "Started " + info.date
	return log
end function

// The number for the next session's log: one more than the highest so far,
// as three digits ("007"), so the files sort in order.
nextNumber = function(folder)
	highest = 0
	names = file.children(folder)
	if names isa list then
		for name in names
			if name.len < 12 or name[:8] != "session-" or name[-4:] != ".txt" then continue
			n = name[8:-4].val
			if n > highest then highest = n
		end for
	end if
	return ("000" + (highest + 1))[-3:]
end function

// Log one line of the given kind ("you", "robot", "note", or "icl").
SessionLog.add = function(kind, text)
	label = (kind + ":        ")[:8]
	for line in str(text).split(char(10))
		self.lines.push label + line
	end for
	file.writeLines self.path, self.lines
end function
