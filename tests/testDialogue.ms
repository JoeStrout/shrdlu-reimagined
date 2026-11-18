// testDialogue.ms
//
// The acceptance test: Winograd's published dialogue, in English, played in
// order from the starting scene.  Each turn gives what the user says and
// what Winograd's robot replied.  A turn passes when our robot says the
// same thing (ignoring capitals and spacing).
//
// Turns we can't do yet are marked as known gaps, with the reason.  The
// list of gaps should shrink until it's empty; if a gap starts passing,
// this test says so, and it should be taken off the list.  A gap that is a
// command which changes the world can give ICL to do instead, so that the
// rest of the dialogue still happens in the right world.
//
// Where our reply rightly differs from Winograd's (say, because our scene
// isn't exactly his, or our robot says a bit more), the turn gives the
// reply we accept instead, and why.
//
// The dialogue is the book version: section 1.3 of "Understanding Natural
// Language" (1972), with SHRDLU's replies converted from capitals.  His
// thesis (MIT AI TR-235, 1971) has nearly the same dialogue, but talks
// about liking rather than owning in turns 13-16, and has two more turns
// after turn 21 ("Does the shortest thing the tallest pyramid's support
// supports support anything green?" "Yes, the green pyramid."  "What color
// is it?" "By "it", I assume you mean the shortest thing the tallest
// pyramid's support supports.  Red.").  See
// references/winograd-scene-and-dialog.md.
//
// Run from the repo root:
//
//   MS_IMPORT_PATH=src miniscript tests/testDialogue.ms
//
// Set verbose (below) to true to see every turn.

import "world"
import "scenes"
import "brain"

w = world.World.make
w.load scenes.byName.winograd
robot = brain.Brain.make(w)

verbose = false    // true: show every turn, not just the failures

passes = 0
gaps = 0
failures = 0
turnNumber = 0

normalize = function(s)
	s = s.lower
	while s.indexOf("  ") != null
		s = s.replace("  ", " ")
	end while
	return s
end function

// One turn of the dialogue.  options may have:
//   ours  the reply we accept instead of Winograd's, and
//   why   the reason it differs
//   gap   a reason we can't do this turn yet
//   icl   for a gap: ICL to carry out instead of the English
turn = function(text, winograd, options=null)
	if options == null then options = {}
	globals.turnNumber += 1
	expected = winograd
	if options.hasIndex("ours") then expected = options.ours
	if options.hasIndex("gap") and options.hasIndex("icl") then
		reply = robot.respond(options.icl.replace("; ", char(10)))
	else
		reply = robot.hear(text)
	end if
	ok = normalize(reply) == normalize(expected)
	label = turnNumber + ". " + text
	if options.hasIndex("gap") then
		globals.gaps += 1
		if ok and not options.hasIndex("icl") then
			print "GAP NOW PASSES (take it off the list): " + label
		else if verbose then
			print "gap   " + label + char(10) + "        Winograd: " + winograd +
			  char(10) + "        ours:     " + reply + char(10) + "        (" + options.gap + ")"
		end if
	else if ok then
		globals.passes += 1
		if verbose then print "ok    " + label + char(10) + "        " + reply
	else
		globals.failures += 1
		print "FAIL  " + label + char(10) + "        expected: " + expected + char(10) + "        got:      " + reply
	end if
end function

//----------------------------------------------------------------------
// The dialogue
//----------------------------------------------------------------------

turn "Pick up a big red block.", "OK."

turn "Grasp the pyramid.", "I don't understand which pyramid you mean."

turn "Find a block which is taller than the one you are holding and put it into the box.",
  "By ""it"", I assume you mean the block which is taller than the one I am holding. OK.",
  {"gap": "announcing what a pronoun was taken to mean"}

turn "What does the box contain?", "The blue pyramid and the blue block.",
  {"ours": "The blue block and the blue pyramid.", "why": "we list things in a different order"}

turn "What is the pyramid supported by?", "The box."

turn "How many blocks are not in the box?", "Four of them."

turn "Is at least one of them narrower than the one which I told you to pick up?", "Yes, the red cube."

turn "Is it supported?", "Yes, by the table."

turn "Can the table pick up blocks?", "No."

turn "Can a pyramid be supported by a block?", "Yes."

// Winograd's robot had no rule for this; ours knows that nothing stays on
// top of a pyramid (the next turn shows it).
turn "Can a pyramid support a pyramid?", "I don't know.",
  {"ours": "No. Nothing will stay on top of a pyramid.", "why": "our robot knows, and says why"}

turn "Stack up two pyramids.", "I can't.",
  {"ours": "I can't. Nothing will stay on top of a pyramid.", "why": "our robot says why"}

turn "The blue pyramid is mine.", "I understand."

turn "I own blocks which are not red, but I don't own anything which supports a pyramid.", "I understand."

turn "Do I own the box?", "No."

turn "Do I own anything in the box?", "Yes, two things: the blue block and the blue pyramid."

turn "Will you please stack up both of the red blocks and either a green cube or a pyramid?", "OK."

turn "Which cube is sitting on the table?", "The large green one which supports the red pyramid."

turn "Is there a large block behind a pyramid?", "Yes, three of them: a large red one, a large green cube and the blue one.",
  {"ours": "Yes, three of them: the large red one, a large green cube and the blue one.",
   "why": "there's only one large red block, so we say ""the"""}

turn "Put a small one onto the green cube which supports a pyramid.", "OK."

turn "Put the littlest pyramid on top of it.", "OK."

turn "How many things are on top of green cubes?",
  "I'm not sure what you mean by ""on top of"" in the phrase ""on top of green cubes"". Do you mean: 1 - directly on the surface 2 - anywhere on top of?",
  {"gap": "asking which meaning of ""on top of"" is meant"}

turn "2", "Three of them.",
  {"gap": "answering the robot's question"}

turn "Had you touched any pyramid before you put the green one on the little cube?", "Yes, the green one."

// The next three turns are about the time the robot picked up the green
// pyramid during turn 17, not the later time in turn 21: the time turn 24
// just found.
turn "When did you pick it up?", "While I was stacking up the red cube, a large red block and a large green cube.",
  {"ours": "While I was stacking up the red cube, the large red block and a large green cube.",
   "why": "there's only one large red block, so we say ""the"""}

turn "Why?", "To get rid of it."

turn "Why did you do that?", "To clean off the red cube."

turn "Why did you clear off that cube?", "To put it on a large green cube."

turn "Why did you do that?", "To stack up the red cube, a large red block and a large green cube.",
  {"ours": "To stack up the red cube, the large red block and a large green cube.",
   "why": "there's only one large red block, so we say ""the"""}

turn "Why did you do that?", "Because you asked me to."

turn "How did you do it?",
  "By putting a large red block on the table; then letting go of it; then putting a large green cube on it; then letting go of that cube; then putting the red cube on that cube; then letting go of that cube.",
  {"gap": "our ""how"" answers are shorter"}

turn "How many objects did you touch while you were doing it?", "Four of them."

turn "What did the red cube support before you started to clean it off?", "The green pyramid."

turn "There were five blocks to the left of the box then.", "No, only four of them: the red cube, two large green cubes and a large red block.",
  {"ours": "No, only four of them: the red cube, two large green cubes and the large red one.",
   "why": "there's only one large red block, so we say ""the"""}

turn "Put the blue pyramid on the block in the box.", "OK."

// Winograd's table had no size, so nothing on it counted as "not as wide
// as" it.  Ours does have a size, and the large red block, the box, and
// (with our inferred sizes) the green cube on the table count too.
turn "Is there anything which is bigger than every pyramid but is not as wide as the thing that supports it?", "Yes, the blue block.",
  {"ours": "Yes, four things: a large green cube, the large red block, the blue block and the box.",
   "why": "things on the table count, since the table has a size"}

turn "Does a steeple", "Sorry, I don't know the word ""steeple""."

turn "A ""steeple"" is a stack which contains two green cubes and a pyramid.", "I understand.",
  {"gap": "definitions"}

turn "Are there any steeples now?", "No.",
  {"gap": "definitions"}

turn "Build one.", "OK.",
  {"gap": "building what was defined"}

turn "Call the biggest block ""superblock"".", "OK."

turn "Have you picked superblock up since we began?", "Yes."

turn "Why did you drop it?", "By ""it"", I assume you mean the superblock. I can't explain a nonexistent event.",
  {"gap": "announcing what a pronoun was taken to mean, and events that didn't happen"}

turn "Is there anything to the right of the red pyramid?", "Yes, four things: the box, the red cube, the blue pyramid and the block named superblock.",
  {"gap": "depends on where ""Build one."" leaves things"}

turn "Thank you.", "You're welcome!"

print passes + " turns as Winograd's, " + gaps + " known gaps, " + failures + " failures (of " + turnNumber + " turns)."
exit (failures > 0)
