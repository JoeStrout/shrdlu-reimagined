// testCoverage.ms
//
// The breadth test.  testDialogue.ms checks that we can do Winograd's
// dialogue; this checks that we can do the many other ways people might
// say things, so that a visitor doesn't have to memorize the robot's
// grammar to talk to it.
//
// The sentences come from three places:
//   - the 2008 project's list of sentences from SHRDLU dialogues
//     (../shrdlutng/notes/sentences.txt), marked "(2008)"
//   - things noticed along the way and noted in notes/progress-log.md,
//     marked "(log)"
//   - new phrasings: other natural ways of saying what the robot can
//     already do (or should), written to avoid repeating the examples
//     above
//
// Each conversation starts afresh from Winograd's scene, so they don't
// depend on each other.  Within one, each line gives what the user says
// and the reply we want.  A line passes when the robot says exactly that
// (ignoring capitals and spacing).  Lines may also be:
//   gap   something we mean to handle but can't yet, with the reason.  The
//         reply given is the one we want.  When a gap starts passing, this
//         test says so, and it should be taken off the list.
//   out   out of scope for now (it needs things the world doesn't have,
//         like faces or rolling).  The reply given is the honest one we
//         give now, so these pass, but they're counted separately.
// A gap that changes the world can give ICL to do instead ("icl"), so
// that the rest of its conversation happens in the right world.
//
// Run from the repo root:
//
//   MS_IMPORT_PATH=src miniscript tests/testCoverage.ms
//
// Add -v to see every line, or -g to see what each gap says now.

import "world"
import "scenes"
import "brain"

verbose = shellArgs.indexOf("-v") != null
showGaps = verbose or shellArgs.indexOf("-g") != null

passes = 0
gaps = 0
outOfScope = 0
failures = 0
lineNumber = 0
title = ""
robot = null

normalize = function(s)
	s = s.lower.replace(char(10), " ")
	while s.indexOf("  ") != null
		s = s.replace("  ", " ")
	end while
	return s
end function

// Start a new conversation, in a fresh world.
conversation = function(name, sceneName="winograd")
	globals.title = name
	w = world.World.make
	w.load scenes.byName[sceneName]
	globals.robot = brain.Brain.make(w)
	if verbose then print char(10) + "== " + name
end function

// One line of a conversation.  options may have "gap" or "out" (the
// reason), and for a gap, "icl" to carry out instead.
say = function(text, want, options=null)
	if options == null then options = {}
	globals.lineNumber += 1
	if options.hasIndex("gap") and options.hasIndex("icl") then
		reply = robot.respond(options.icl.replace("; ", char(10)))
	else
		reply = robot.hear(text)
	end if
	ok = normalize(reply) == normalize(want)
	label = "[" + title + "] " + text
	if options.hasIndex("gap") then
		globals.gaps += 1
		if ok and not options.hasIndex("icl") then
			print "GAP NOW PASSES (take it off the list): " + label
		else if showGaps then
			print "gap   " + label + char(10) + "        want: " + want +
			  char(10) + "        now:  " + reply + char(10) + "        (" + options.gap + ")"
		end if
	else if ok then
		if options.hasIndex("out") then globals.outOfScope += 1 else globals.passes += 1
		if verbose then print "ok    " + label + char(10) + "        " + reply
	else
		globals.failures += 1
		print "FAIL  " + label + char(10) + "        want: " + want + char(10) + "        got:  " + reply
	end if
end function

gap = function(reason, icl=null)
	result = {"gap": reason}
	if icl then result.icl = icl
	return result
end function

out = function(reason)
	return {"out": reason}
end function

// (A line break in a reply, as when the robot asks which sense of "on top
// of" we meant.)
nl = char(10)

//======================================================================
// Looking at the world
//======================================================================

conversation "what's where"
say "What is in the box?", "The blue pyramid."
say "What's in the box?", "The blue pyramid."
say "Is there anything in the box?", "Yes, the blue pyramid."
say "Is the box empty?", "No."
say "What is on the red cube?", "The green pyramid."
say "What's on top of the large green cube?", "The red pyramid."
say "What is the red cube sitting on?", "The table."
say "What is the green pyramid on?", "The red cube."
say "What's the red pyramid on?", "A large green cube."
say "What supports the red pyramid?", "A large green cube."
say "Does anything support the blue pyramid?", "Yes, the box."
say "What is under the green pyramid?", "The table and the red cube."
say "Is anything on the blue block?", "No."
say "Is the blue pyramid in the box?", "Yes."
say "Is the red cube inside the box?", "No."
say "Are there any blocks in the box?", "No."
say "Are any blocks in the box?", "No."
say "Is the green pyramid to the left of the red pyramid?", "Yes."
say "Is the box to the right of the blue block?", "Yes."
say "What is on the table?", "The red cube, a large green cube, the large red block, the blue block and the box."

conversation "where is it"
say "Where is the red cube?", "On the table."
say "Where is the blue pyramid?", "In the box."
say "Where's the green pyramid?", "On the red cube."
say "Where are all the cubes?", "The red cube and a large green cube are on the table, and a large green cube is on the large red block."

conversation "where is the red block"
say "Where is the red block?", "I don't understand which red block you mean."

conversation "counting"
say "How many pyramids are there?", "Three of them."
say "How many blocks are there?", "Five of them."
say "How many blocks are on the table?", "Four of them."
say "How many red things are there?", "Three of them."
say "How many objects are there?", "Nine of them."
say "How many things are in the box?", "Just one."
say "How many cubes are in the box?", "None."
say "Count the blocks.", "Five of them."
say "Are there any green pyramids?", "Yes, the green one."
say "Is there a blue block?", "Yes, the blue one."

conversation "colors, shapes and sizes"
say "What color is the box?", "White."
say "What colour is the pyramid in the box?", "Blue."
say "What color are the cubes?", "Red and green."
say "What shape is the thing in the box?", "A pyramid."
// (The red pyramid is big for a pyramid, so this is fair.)
say "What shape is the big red thing?", "I don't understand which large red thing you mean."
say "How big is the blue block?", "Large."
say "What size is the red cube?", "Small."
say "Is the blue block taller than the red pyramid?", "Yes."
say "Is the blue block bigger than the box?", "No."
say "Which is taller, the red cube or the blue block?", "The blue block."
say "Which is bigger, the box or the blue block?", "The box."
say "Which is taller, the red cube or the green one?", "I don't understand which green cube you mean."

conversation "biggest and smallest"
say "Which block is the biggest?", "The blue one."
say "Which is the tallest block?", "The blue block."
say "What is the tallest thing?", "The blue block."
say "What is the smallest block?", "The red cube."
say "Which pyramid is the tallest?", "The red one."
say "What is the biggest thing on the table?", "The box."
say "Which is the second tallest block?", "The large red block."
say "What is the third tallest block?", "I don't understand which third tallest block you mean."
say "The one on the table.", "The large green cube which supports the red pyramid."
say "Which block is the smallest?", "The red cube."
say "Find the seventh tallest cube.", "I don't see any seventh tallest cubes."

conversation "the hand"
say "What are you holding?", "Nothing."
say "Are you holding anything?", "No."
say "Is your hand empty?", "Yes."
say "Pick up the red cube.", "OK."
say "What are you holding?", "The red cube."
say "What's in your hand?", "The red cube."
say "Are you holding the red cube?", "Yes."
say "Tell me what you are holding.", "The red cube."
say "What is it?", "The red cube."

conversation "seeing"
say "Do you see a red pyramid?", "Yes, the red one."
say "Can you see the box?", "Yes."
say "Do you see any yellow blocks?", "No."

conversation "joined predicates"
say "Which blocks are red and on the table?", "The red cube and the large red one."
say "Which cubes are green but not on the table?", "The large green one which is on the large red block."
say "What is on the large green cube?", "The red pyramid."
say "What blocks are red and next to the pyramid?", "None."
say "Which blocks are taller than any pyramid?", "The blue one."

conversation "clear"
say "Is the red cube clear?", "No."
say "Is the top of the red cube clear?", "No."
say "Is the blue block clear?", "Yes."

conversation "is that cube red"
say "Find the red cube.", "OK."
say "Is that cube red?", "Yes."
say "What is that block's color?", "Red."
say "Is it on the table?", "Yes."

//======================================================================
// Doing things
//======================================================================

conversation "picking up"
say "Grab the red cube.", "OK."
say "Take the blue pyramid.", "OK."
say "Get the green pyramid.", "OK."
say "Hold the red cube.", "OK."
say "Pick up the green pyramid please.", "OK."
say "Please pick up the red cube.", "OK."
say "Lift the blue block.", "OK."

conversation "putting down"
say "Pick up the green pyramid.", "OK."
say "Set it down.", "OK."
say "Pick it up.", "OK."
say "Let go of it.", "OK."
say "Pick it up again.", "OK."
say "Drop it.", "OK."
say "Put down the red cube.", "OK."

conversation "putting on and in"
say "Put the red cube on top of the blue block.", "OK."
say "Place the green pyramid on the large red block.", "OK."
say "Move the red cube onto the table.", "OK."
say "Move the red cube to the box.", "OK."
say "Stick the green pyramid in the box.", "OK."
say "Stack the red cube on the blue block.", "OK."
say "Put a pyramid on the blue block.", "OK."
say "Put the littlest block on the biggest block.", "OK."

conversation "taking out and off"
say "Take the blue pyramid out of the box.", "OK."
say "Take the green cube off the red block.", "OK."
say "Get the green pyramid off the red cube.", "OK."
say "Remove the red pyramid.", "OK."

conversation "clearing"
say "Clear the large red block.", "OK."
say "Clean off the red cube.", "OK."
say "Empty the box.", "OK."
say "Is the box empty?", "Yes."

conversation "commands in a row"
say "Pick up the red cube and then put it on the blue block.", "OK."
say "Put the green pyramid in the box then pick up the red cube.", "OK."
say "First pick up the blue pyramid, then put it on the table.", "OK."
say "Now put it in the box.", "OK."

conversation "polite and roundabout"
say "Could you please pick something up?", "OK."
say "Could you put the red cube in the box?", "OK."
say "I want you to pick up the blue pyramid.", "OK."
say "I'd like you to put it on the table.", "OK."
say "Go find a block under a pyramid.", "OK."
say "Try to find a red pyramid.", "OK."

conversation "stacking"
say "Stack up the blue block, the red cube and the green pyramid.", "OK."
say "Pile up the red cube and the blue block.", "OK."

conversation "many things"
say "Put the red cube and the green pyramid in the box.", "OK."
say "Take either a red block or a green one and put it on a blue one.", "OK."
say "Drop everything.", "OK."

conversation "everything in the box"
say "Put everything in the box.", "There's no room in the box for the large green cube which is on the large red block."

conversation "find"
say "Find an object on a red cube.", "OK."
say "What is it?", "The green pyramid."
say "Find a block which is taller than the blue block.", "I don't see any blocks taller than the blue block."

conversation "complaints"
say "Put the yellow block in the box.", "I don't see any yellow blocks."
say "Pick up a block which is in the box.", "I don't see any blocks in the box."
say "Pick up the pyramid on the blue block.", "I don't see any pyramids on the blue block."
say "Put the red cube on the block.", "I don't understand which block you mean."

conversation "places on the table"
say "Put the red cube next to the blue block.", "OK."
// (The red cube came from the sentence before, and the reply is a
// complaint, so the robot says what it took "it" to be.)
say "Put it beside the pyramid.", "By ""it"", I assume you mean the red cube. I don't understand which pyramid you mean."
say "Put the red cube to the left of the box.", "OK."
say "Put the red cube under the green pyramid.", "OK."
say "Move the red cube to the front of the table.", "OK."
say "Put it back.", "OK."

//======================================================================
// Answering back: settling what the robot asked
//======================================================================

conversation "which one"
say "Put the blue pyramid on the green cube.", "I don't understand which green cube you mean."
say "The one supporting a pyramid.", "OK."

conversation "which one, then something else"
say "Grasp the pyramid.", "I don't understand which pyramid you mean."
say "What is in the box?", "The blue pyramid."
say "Pick up the green one.", "OK."

conversation "which one, again"
say "Grasp the pyramid.", "I don't understand which pyramid you mean."
say "The green one.", "OK."

conversation "any one"
say "Pick up the cube.", "I don't understand which cube you mean."
say "Any one.", "OK."

conversation "the one you are holding"
say "What color is the block?", "I don't understand which block you mean."
say "The small one.", "Red."
say "What is it on?", "The table."

//======================================================================
// The past
//======================================================================

conversation "what did you do"
say "Put the red cube in the box.", "OK."
say "What did you put in the box?", "The red cube."
say "Which block did you move?", "The red cube."
say "Did you touch the blue block?", "No."
say "Did you put the red cube in the box?", "Yes."
say "Why did you pick up the green pyramid?", "To get rid of it."
say "How did you do that?", "By picking it up, then setting it down on the table."
say "When did you put the red cube in the box?", "When you asked me to."
say "What did you do last?", "I put the red cube in the box."
say "What did you have to move to do that?", "The green pyramid."
say "Did you pick up the green pyramid before you put the red cube in the box?", "Yes."
say "What did the box contain before you put the red cube in it?", "By ""it"", I assume you mean the box. The blue pyramid."
say "Have you ever touched the blue block?", "No."
say "Where did the red cube go?", "In the box."

conversation "it, after a question"
say "Put the red cube in the box.", "OK."
say "Which block did you move?", "The red cube."
say "Put it on the pyramid.", "By ""it"", I assume you mean the red cube. I don't understand which pyramid you mean."

conversation "moved"
say "Pick up a green cube.", "OK."
say "Which green cube did you move?", "The large green one which I am holding."

//======================================================================
// What could be
//======================================================================

conversation "could it be"
say "Can a block be in the box?", "Yes."
say "Can the red cube be on the blue block?", "Yes."
say "Can a table support a pyramid?", "Yes."
say "Can a pyramid be on a pyramid?", "No. Nothing will stay on top of a pyramid."
say "Can you put a block on a pyramid?", "I can't balance anything on a pyramid."
say "How many blocks can you pick up?", "I can only hold one thing at a time."
say "Which things can you pick up?", "The red cube, the green pyramid, two large green cubes, the red pyramid, the large red block, the blue block and the blue pyramid."

//======================================================================
// "On top of", asked about (log)
//======================================================================

conversation "on top of, asked"
say "Put the red cube on the blue block.", "OK."
say "Put the green pyramid on the red cube.", "OK."
say "Is the green pyramid on top of the blue block?",
  "I'm not sure what you mean by ""on top of"" in the phrase ""on top of the blue block"".  Do you mean:" + nl +
  "1 - directly on the surface" + nl + "2 - anywhere on top of?"
say "2", "Yes."

//======================================================================
// Names and new words
//======================================================================

conversation "names"
say "Call it Bert.", "I don't know what you mean by ""it""."
say "Call the blue block Bert.", "OK."
say "Where is Bert?", "On the table."

conversation "steeples"
say "A ""steeple"" is a stack which contains two green cubes and a pyramid.", "I understand."
say "Make me a steeple.", "OK."
say "How do you build a steeple?", "By stacking up two green cubes and a pyramid."

//======================================================================
// More ways of saying things (a second batch of new phrasings)
//======================================================================

conversation "more about what's where"
say "What is sitting on the red cube?", "The green pyramid."
say "What's resting on the large green cube?", "The red pyramid."
say "Is there anything on top of the blue block?", "No."
say "Does the red cube have anything on it?", "Yes."
say "Does the box have anything in it?", "Yes."
say "What is the blue pyramid in?", "The box."
say "What's inside the box?", "The blue pyramid."
say "Which things are in the box?", "The blue pyramid."
say "Are there any pyramids on the table?", "No."
say "Is there a green block?", "Yes, two large green cubes."
say "What is next to the large red block?", "Nothing."
say "What's behind the red cube?", "The large red block, a large green cube, the blue block, the box and the blue pyramid."
say "Is the blue block behind the large green cube?", "Yes."
say "Where are the pyramids?", "The green pyramid is on the red cube, the red pyramid is on a large green cube, and the blue pyramid is in the box."
say "Where's the box?", "On the table."

conversation "more counting and comparing"
say "How many cubes are there?", "Three of them."
say "How many green things are there?", "Three of them."
say "How many things are on the large red block?", "Just one."
say "How many pyramids are not in the box?", "Two of them."
say "Which block is red?", "The red cube and the large red one."
say "What color is the pyramid on the red cube?", "Green."
say "What color is the thing on top of the green cube?", "Red."
say "What color are the pyramids?", "Green, red and blue."
say "Is the green pyramid small?", "Yes."
say "Is the box big?", "No."
say "Is the blue block the tallest?", "Yes."
say "Is the red cube the tallest block?", "No."
say "Is the red cube smaller than the green pyramid?", "No."
say "Which is the biggest pyramid?", "The blue pyramid."
say "Are both green cubes on the table?", "No."
say "Is every pyramid on a block?", "No."
say "What's the color of the tall block?", "I don't understand which tall block you mean."
say "Which blocks are tall?", "The large red one and the blue one."
say "Is the blue block narrow?", "No."

conversation "more about the hand"
say "What are you holding right now?", "Nothing."
say "Are you holding something?", "No."
say "Do you have anything in your hand?", "No."
say "Pick up the small red cube.", "OK."
say "Is the red cube in your hand?", "Yes."
say "Do you have the red cube?", "Yes."
say "Is your hand empty?", "No."
say "Is your hand full?", "Yes, the red cube."

conversation "more picking up and putting"
say "Pick the red cube up.", "OK."
say "Place it on the table.", "OK."
say "Pick up a pyramid that is on a cube.", "OK."
say "Lift up the blue pyramid.", "OK."
say "Please put the green pyramid in the box.", "OK."
say "Drop the blue pyramid in the box.", "OK."
say "Put the red cube onto the large red block.", "OK."

conversation "more putting"
say "Set the red cube on top of the large green cube.", "I don't understand which large green cube you mean."
say "Stack the green pyramid on top of the red cube.", "OK."
say "Put a block in the box.", "OK."
say "Put two pyramids on the table.", "OK."
say "Put the blue pyramid on the red block.", "I don't understand which red block you mean."

conversation "moving off and out"
say "Move the green pyramid off the red cube.", "OK."
say "Move the blue pyramid out of the box.", "OK."
say "Take the red pyramid down.", "OK."
say "Where is it?", "On the table."
say "Put the red pyramid down on the table.", "OK."
say "Take the blue pyramid out of the box.", "I don't see any blue pyramids in the box."

conversation "more clearing"
say "Clear off the top of the large green cube.", "I don't understand which large green cube you mean."
say "Clean up the box.", "OK."
say "Stack up two blocks.", "OK."
say "Stack the blue pyramid on the green pyramid.", "I can't balance anything on a pyramid."

conversation "more finding"
say "Pick up the thing in the box.", "OK."
say "Find a red block and pick it up.", "OK."
say "Find the biggest block.", "OK."
say "Pick up the biggest pyramid.", "OK."
say "Pick up the one on the red cube.", "OK."
say "Pick up something green.", "OK."
say "Pick up anything red.", "OK."
say "Pick up the thing in the box.", "I don't see anything in the box."
say "Is the red cube a block?", "Yes."
say "Is the box a pyramid?", "No."

conversation "more about the past"
say "Put the red cube in the box.", "OK."
say "What did you just do?", "I put the red cube in the box."
say "Why did you put the green pyramid on the table?", "To clean off the red cube."
say "When did you pick up the green pyramid?", "While I was putting the red cube in the box."
say "How did you put the red cube in the box?", "By cleaning it off, then picking it up, then setting it down in the box."
say "Did you move the blue block?", "No."
say "Have you moved the red cube?", "Yes."
say "How many things have you moved?", "Two of them."
say "What have you picked up?", "The red cube and the green pyramid."
say "Which things did you pick up?", "The red cube and the green pyramid."
say "What did you move to do that?", "The green pyramid."

conversation "chat"
say "Hello.", "Hello!  Ask me to move things, or ask me about them."
say "Hi there.", "Hello!  Ask me to move things, or ask me about them."
say "Who are you?", "I'm Robot, a robot arm.  I live in this little world of blocks, and I'll do what you ask, if I can."
say "What can you do?", "I can pick things up, put them on or in other things, stack them up, and clear things off.  You can ask me where things are, what color or size they are, what's on or in something, and why, how or when I did something.  You can also teach me new words.  (Type /help for examples.)"
say "Pick up the red cube.", "OK."
say "Good job.", "Thank you!"
say "Thanks a lot.", "You're welcome!"
say "Sorry.", "That's all right."
say "Stop.", "OK."
say "Goodbye.", "Goodbye!"

conversation "show me, and undo"
say "Show me the red cube.", "On the table."
say "Put the red cube in the box.", "OK."
say "Undo that.", "OK."
say "Where is the red cube?", "On the table."

//======================================================================
// Small talk: names, and questions about the robot
//======================================================================

// The robot's name is Robot until the user gives it another.  The user's
// name is unknown until they say it.  People test chatbots by asking
// "What's my name?" right away, or after telling it, so both are here.

conversation "the user's name"
say "What is my name?", "I don't know.  You haven't told me.  What is it?"
say "Joe.", "Nice to meet you, Joe."
say "What's my name?", "Your name is Joe."
say "Who am I?", "Your name is Joe."
say "Do you know my name?", "Your name is Joe."
say "Do you remember my name?", "Your name is Joe."
say "What do you call me?", "Your name is Joe."
say "What's my name again?", "Your name is Joe."
say "Is my name Joe?", "Yes."
say "Is my name Fred?", "No, it's Joe."
say "Am I Joe?", "Yes."
say "My name is Joe.", "I know, Joe."
say "Hello.", "Hello, Joe!  Ask me to move things, or ask me about them."
say "Goodbye.", "Goodbye, Joe!"

conversation "telling the robot my name"
say "My name is Joe.", "Nice to meet you, Joe."
say "What is my name?", "Your name is Joe."
say "Actually, call me Joseph.", "OK, I'll call you Joseph now."
say "What is my name?", "Your name is Joseph."
say "Is my name Joe?", "No, it's Joseph."

conversation "other ways of saying my name"
say "I'm Joe.", "Nice to meet you, Joe."
say "Call me Jo.", "OK, I'll call you Jo now."
say "You can call me Joey.", "OK, I'll call you Joey now."
say "Please call me Joe.", "OK, I'll call you Joe now."
say "My name's Joseph.", "OK, I'll call you Joseph now."
say "I am called Joe.", "OK, I'll call you Joe now."
say "People call me Jojo.", "OK, I'll call you Jojo now."
say "Everyone calls me Joe.", "OK, I'll call you Joe now."
say "I go by Joe.", "I know, Joe."
say "My name is now Bert.", "OK, I'll call you Bert now."

conversation "hello, I'm Joe"
say "Hi, I'm Joe.", "Nice to meet you, Joe."
say "Nice to meet you.", "Nice to meet you too, Joe."

conversation "hello, my name is"
say "Hello, my name is Joe Strout.", "Nice to meet you, Joe Strout."
say "What's my name?", "Your name is Joe Strout."

conversation "a name typed in lower case"
say "my name is joe", "Nice to meet you, Joe."
say "what is my name", "Your name is Joe."

conversation "the user's name, asked first"
say "Is my name Joe?", "I don't know.  You haven't told me.  What is it?"
say "It's Joe.", "Nice to meet you, Joe."
say "Who am I?", "Your name is Joe."

conversation "the user's name, asked and not answered"
say "Who am I?", "I don't know.  You haven't told me.  What is it?"
say "What is in the box?", "The blue pyramid."
say "What is my name?", "I don't know.  You haven't told me.  What is it?"
say "My name is Joe.", "Nice to meet you, Joe."

// "I am" or "I'm" with a word that isn't a name: names are capitalized.
conversation "I'm not a name"
say "I'm tired.", "Sorry, I don't know the word ""tired""."
say "What is my name?", "I don't know.  You haven't told me.  What is it?"

conversation "the robot's name"
say "What is your name?", "My name is Robot."
say "What's your name?", "My name is Robot."
say "Do you have a name?", "My name is Robot."
say "What should I call you?", "My name is Robot."
say "What do I call you?", "My name is Robot."
say "What are you called?", "My name is Robot."
say "Is your name Robot?", "Yes."
say "Is your name Bob?", "No, it's Robot."
say "Are you Bob?", "No, it's Robot."
say "Who are you?", "I'm Robot, a robot arm.  I live in this little world of blocks, and I'll do what you ask, if I can."

conversation "renaming the robot"
say "Your name is now Bob.", "OK, my name is Bob now."
say "What is your name?", "My name is Bob."
say "Is your name Bob?", "Yes."
say "Is your name Robot?", "No, it's Bob."
say "Who are you?", "I'm Bob, a robot arm.  I live in this little world of blocks, and I'll do what you ask, if I can."
say "Your name is Bob.", "Yes, that's my name."
say "I'm going to call you Shrdlu.", "OK, my name is Shrdlu now."
say "What's your name?", "My name is Shrdlu."

conversation "other ways of renaming the robot"
say "Your name is Bob.", "OK, my name is Bob now."
say "I'll call you Robbie.", "OK, my name is Robbie now."
say "I will call you Bob.", "OK, my name is Bob now."
say "Let's call you Robbie.", "OK, my name is Robbie now."
say "Can I call you Bob?", "OK, my name is Bob now."
say "May I call you Robbie?", "OK, my name is Robbie now."
say "Call yourself Bob.", "OK, my name is Bob now."
say "Your new name is Robbie.", "OK, my name is Robbie now."
say "From now on, your name is Bob.", "OK, my name is Bob now."
say "You are Robbie.", "OK, my name is Robbie now."
say "You're now Bob.", "OK, my name is Bob now."
say "I want to call you Robbie.", "OK, my name is Robbie now."
say "I'd like to call you Bob.", "OK, my name is Bob now."
say "I name you Robbie.", "OK, my name is Robbie now."
say "Your name is bob now.", "OK, my name is Bob now."

conversation "the robot's name, and things' names"
say "Call the big red block Bob.", "OK."
say "Your name is Bob.", "Sorry, something else is called Bob already."
say "What is your name?", "My name is Robot."

// Both names at once, kept apart.
conversation "two names"
say "My name is Joe.", "Nice to meet you, Joe."
say "Your name is Bob.", "OK, my name is Bob now."
say "What is my name?", "Your name is Joe."
say "What is your name?", "My name is Bob."

// Speaking to the robot by name, at the start or the end.
conversation "calling the robot by name"
say "Robot, what is in the box?", "The blue pyramid."
say "Hi, Robot.", "Hello!  Ask me to move things, or ask me about them."
say "Your name is Bob.", "OK, my name is Bob now."
say "Bob, pick up the red cube.", "OK."
say "Put it in the box, Bob.", "OK."
say "Thanks, Bob.", "You're welcome!"
say "What is your name, Bob?", "My name is Bob."
say "Bob?", "Yes, I'm here."
say "Hi Bob, my name is Al.", "Nice to meet you, Al."
say "Robot, put the red cube on the table.", "My name is Bob, not Robot.  OK."
say "Fred, what is in the box?", "My name is Bob, not Fred.  The blue pyramid."
say "Thanks, Fred.", "My name is Bob, not Fred.  You're welcome!"
say "Hi Fred.", "My name is Bob, not Fred.  Hello, Al!  Ask me to move things, or ask me about them."
say "What is your name, Fred?", "My name is Bob, not Fred."
// (Only a capitalized word, first or last, is taken for a name.)
say "fred, what is in the box?", "Sorry, I don't know the word ""fred""."
say "Robbie, how are you?", "My name is Bob, not Robbie.  I'm fine, thank you.  Ready to move some blocks!"

conversation "about the robot"
say "Tell me about yourself.", "I'm Robot, a robot arm in a little world of blocks.  I can move things, answer questions about them, learn new words, and tell you why I did what I did.  Everything I say comes from hand-written rules, with no machine learning."
say "Tell me about you.", "I'm Robot, a robot arm in a little world of blocks.  I can move things, answer questions about them, learn new words, and tell you why I did what I did.  Everything I say comes from hand-written rules, with no machine learning."
say "Describe yourself.", "I'm Robot, a robot arm in a little world of blocks.  I can move things, answer questions about them, learn new words, and tell you why I did what I did.  Everything I say comes from hand-written rules, with no machine learning."
say "What are you?", "I'm Robot, a robot arm in a little world of blocks.  I can move things, answer questions about them, learn new words, and tell you why I did what I did.  Everything I say comes from hand-written rules, with no machine learning."
say "What are you holding?", "Nothing."
say "How do you work?", "I read your sentence with a grammar of English, and turn it into a little language of my own, called ICL (type /icl to see it).  Then I work out which things you mean, and answer, or plan the moves that do what you asked.  I remember my goals, so I can tell you why I did things."
say "How does this work?", "I read your sentence with a grammar of English, and turn it into a little language of my own, called ICL (type /icl to see it).  Then I work out which things you mean, and answer, or plan the moves that do what you asked.  I remember my goals, so I can tell you why I did things."
say "How do you understand me?", "I read your sentence with a grammar of English, and turn it into a little language of my own, called ICL (type /icl to see it).  Then I work out which things you mean, and answer, or plan the moves that do what you asked.  I remember my goals, so I can tell you why I did things."
say "What can you do?", "I can pick things up, put them on or in other things, stack them up, and clear things off.  You can ask me where things are, what color or size they are, what's on or in something, and why, how or when I did something.  You can also teach me new words.  (Type /help for examples.)"
say "What are you able to do?", "I can pick things up, put them on or in other things, stack them up, and clear things off.  You can ask me where things are, what color or size they are, what's on or in something, and why, how or when I did something.  You can also teach me new words.  (Type /help for examples.)"
say "What can I ask you?", "I can pick things up, put them on or in other things, stack them up, and clear things off.  You can ask me where things are, what color or size they are, what's on or in something, and why, how or when I did something.  You can also teach me new words.  (Type /help for examples.)"
say "Who made you?", "I was written by Joe Strout, with help from Claude."
say "Who created you?", "I was written by Joe Strout, with help from Claude."
say "Who wrote you?", "I was written by Joe Strout, with help from Claude."
say "How old are you?", "I started up when this conversation began."

conversation "how are you"
say "How are you?", "I'm fine, thank you.  Ready to move some blocks!"
say "How are you doing?", "I'm fine, thank you.  Ready to move some blocks!"
say "How's it going?", "I'm fine, thank you.  Ready to move some blocks!"
say "Nice to meet you.", "Nice to meet you too."
say "Pleased to meet you.", "Nice to meet you too."

// The sanity checks people try on chatbots.
conversation "are you a robot"
say "Are you a robot?", "Yes, a robot arm."
say "Are you human?", "No, I'm a robot arm."
say "Are you a person?", "No, I'm a robot arm."
say "Are you alive?", "No, I'm a robot arm."
say "Are you intelligent?", "I know a lot about blocks, and not much else."
say "Are you smart?", "I know a lot about blocks, and not much else."
say "Are you there?", "Yes, I'm here."
say "Can you hear me?", "Yes, I'm here."
say "Do you understand me?", "Mostly.  When I don't, I'll say which part I didn't understand."

conversation "what did I say"
say "What did I just say?", "You haven't said anything yet."
say "What is in the box?", "The blue pyramid."
say "What did I just say?", "You said, ""What is in the box?"""
say "What did I say?", "You said, ""What did I just say?"""

//======================================================================
// From the user's sessions (logs/session-NNN.txt)
//======================================================================

conversation "session 1"
say "How many green blocks are there?", "Two of them."
say "Are any of them on top of a red block?", "Yes, a large green cube."
say "Is any green block on top of a red block?", "Yes, a large green cube."
say "Pick it up.", "OK."
say "Place it on the table, and put the blue block on top.", "OK."
say "How many red objects are there?", "Three of them."
// ("One" is a red object here, not just an object.)
say "Is there one on top of a green block?", "Yes, the red pyramid."
// (Now that the robot says just the red pyramid, "the blue one" could be
// the blue block or the blue pyramid, so it asks, and the user says.)
say "Grab the blue one.", "I don't understand which blue object you mean."
say "The one on the green cube.", "OK."
say "Put it in the box.", "OK."
say "Clear off the small red cube.", "OK."
say "Stack up the three red objects.", "OK."
say "Call that a steeple.", "I understand."
say "Pick up one of the green cubes.", "OK."
say "That cube's name is Bob.", "OK."
say "Name that cube ""Bob"".", "OK."
say "Put Bob on top of the blue block.", "OK."
say "Where is Bob?", "On the blue block."
say "What is supporting Bob?", "The blue block."

conversation "session 2"
// (In the session, "this" was the red pyramid, clicked on.)
say "What is the red pyramid?", "The red pyramid."
say "Put it on the table.", "OK."
say "Pick up a green cube.", "OK."
say "Call that Bob.", "OK."
say "Put Bob under the blue box.", "I don't see any blue boxes."
// Bob is in the hand, so first it's set down.
say "Put Bob under the blue block.", "OK."
say "What is the blue block on?", "The cube named Bob."
say "Why did you put Bob on the table?", "To put the blue block on it."

conversation "session 2, varied"
say "Pick up the red cube.", "OK."
say "Put the green pyramid on it.", "OK."
say "Where is the red cube?", "On the table."
say "Pick up the red cube.", "OK."
say "Put the blue pyramid next to it.", "OK."
say "Is the blue pyramid next to the red cube?", "Yes."

// From session 3: "other", "add", and a definition that's an arrangement.
conversation "the other one"
say "Put the red pyramid next to the green cube on the table.", "OK."
say "Pick up the other green cube.", "OK."
say "Is it on the table?", "No."
say "Stack it on top of the other green cube.", "OK."
say "What is on the large red block?", "Nothing."
say "Pick up the red cube.", "OK."
say "Put another block on it.", "OK."
// (The nearest block that's free; it balances, centered on the cube.)
say "What is on the red cube?", "The large red block."

conversation "add"
say "What's in the box?", "The blue pyramid."
say "Add the red pyramid.", "OK."
say "What's in the box?", "The red pyramid and the blue pyramid."
say "What is on the red cube?", "The green pyramid."
say "Add the small green cube.", "I don't see any small green cubes."
say "Add the blue block to the box.", "There's no room in the box for the blue block."

conversation "an arrangement, defined"
say "A ""steeple"" is a pyramid on top of a cube.", "I understand."
say "Are there any steeples?", "Yes, two of them: the stack of the red cube and the green pyramid and the stack of a large green cube and the red pyramid."
say "Make one.", "OK."
say "How many steeples are there now?", "Three of them."
say "How do you build a steeple?", "By putting a pyramid on a cube."
say "Make another one.", "I can't build another steeple without taking one apart."
say "A ""tower"" is a block on a block on a block.", "I understand."
say "How do you build a tower?", "By putting a block on a block, then a block on that."

// From session 10: "X on top of Y is called a Z" could name just X (the
// pyramid that's on a cube) or the whole arrangement (the stack).  The
// user meant the stack, but we took it as just the pyramid (DefineLike, as
// for "call the box a crate"), so "make another one" couldn't build one.
// Ask instead.  (Answer 1 would be DefineLike, as now.)
conversation "an arrangement, called"
say "A pyramid on top of a cube is called a ""steeple"".",
  "By ""steeple"", do you mean:" + nl + "1 - just the pyramid" + nl + "2 - the whole stack?",
  gap("naming a thing vs. an arrangement: ask which")
say "2", "I understand.", gap("naming a thing vs. an arrangement: ask which",
  "x1 = a pyramid [on x2]; x2 = a cube; Define steeple, x1")
say "How do you build a steeple?", "By putting a pyramid on a cube."
say "Make a steeple.", "OK."

// From session 4: names, "also", and a clause about the question word.
conversation "asking a name"
say "What is the red cube called?", "It doesn't have a name."
say "Call the red cube ""Rex"".", "OK."
say "What is the red cube called?", "Rex."
say "What is it named?", "Rex."
say "What is its name?", "Rex."
say "What is the name of the box?", "It doesn't have a name."
say "What's the blue block's name?", "It doesn't have a name."

conversation "owning, more"
say "I own the red cube.", "I understand."
say "I also own the blue block.", "I understand."
say "I own the box too.", "I understand."
say "How many objects do I own?", "Three of them."
say "Put the red cube and the blue pyramid in the box.", "OK."
say "What is in the box that I don't own?", "The blue pyramid."
say "Which things in the box do I own?", "The red cube."
say "Put the green pyramid in the box.", "OK."
say "Remove anything I don't own from the box.", "OK."
say "What is in the box?", "The red cube."

// Owning, liking and so on are false of everything until the user says
// otherwise.
conversation "attitudes"
say "Do I own the box?", "No."
say "I own the red cube.", "I understand."
say "What do I own?", "The red cube."
say "Do I own the blue block?", "No."
say "I like tall blocks.", "I understand."
say "Which blocks do I like?", "The large red one and the blue one."
say "I also like the red cube.", "I understand."
say "I don't like the blue block.", "I understand."
say "What do I like?", "The red cube and the large red block."
say "I hate pyramids.", "I understand."
say "Do I hate the green pyramid?", "Yes."
say "Do I like anything which I hate?", "No."
say "Do I love the box?", "No."
say "I dislike the box.", "I understand."
say "How many things that I like are on the table?", "Two of them."

// Feelings are one scale, from hate (-2) through neutral (0) to love (2),
// so they can't contradict each other.
conversation "feelings"
say "I love the red cube.", "I understand."
say "I hate the red cube.", "I understand."
say "Do I love the red cube?", "No."
say "Do I like the red cube?", "No."
say "Do I dislike the red cube?", "Yes."
say "I don't hate the red cube.", "I understand."
say "Do I dislike the red cube?", "Yes."
say "Do I hate the red cube?", "No."
say "I don't dislike it.", "I understand."
say "Do I like it?", "No."
say "Do I dislike it?", "No."
say "I like blocks.", "I understand."
say "I love the blue block.", "I understand."
say "Do I like the blue block?", "Yes."
say "I don't love the blue block.", "I understand."
say "Do I like the blue block?", "Yes."
say "Do I love the blue block?", "No."
say "I don't like green blocks.", "I understand."
say "Which blocks do I like?", "The red cube, the large red one and the blue one."
say "I own the red cube.", "I understand."
say "I hate it.", "I understand."
say "Do I own it?", "Yes."

// The robot can own things too ("you own..."), and "my" and "your" are
// what each of us owns.
conversation "yours and mine"
say "Put my blocks in the box.", "I don't see any blocks which you own."
say "You own the blue block.", "I understand."
say "Do you own the blue block?", "Yes."
say "Do I own the blue block?", "No."
say "You also own all the pyramids.", "I understand."
say "How many things do you own?", "Four of them."
say "The box is yours.", "I understand."
say "Is the box yours?", "Yes."
say "I own the red cube.", "I understand."
say "Is the red cube mine?", "Yes."
say "Put my cube in your box.", "OK."
say "Where is my cube?", "In the box."
say "Pick up your blue block.", "OK."
say "Put your pyramids on the table.", "OK."
say "Do I own any of your pyramids?", "No."
say "You like the box.", "I understand."
say "Do you like the box?", "Yes."
say "Do I like the box?", "No."

// From session 7: negative questions about owning, and "What about...?"
conversation "what don't I own"
say "I own the red cube.", "I understand."
say "Put the red cube and the blue pyramid in the box.", "OK."
say "What don't I own?", "The table, the green pyramid, two large green cubes, the red pyramid, the large red block, the blue block, the box and the blue pyramid."
say "What objects in the box do I not own?", "The blue pyramid."
say "Which things in the box don't I own?", "The blue pyramid."

// "What about X?": X takes the place of part of what was said last.
conversation "what about"
say "What about the box?", "What about it?  I'm not sure what you're asking."
say "I love tall blocks.", "I understand."
say "Is there anything in the box that I love?", "No."
say "What about on the table?", "Yes, two things: the large red block and the blue block."
say "How many red blocks are there?", "Two of them."
say "What about green ones?", "Two of them."
say "And blue ones?", "Just one."
say "Is the red cube on the table?", "Yes."
say "What about the blue pyramid?", "No."
say "How about the box?", "Yes."
say "Put the green pyramid in the box.", "OK."
say "What about the red cube?", "OK."
say "What is in the box?", "The red cube, the green pyramid and the blue pyramid."
say "What about on the large red block?", "A large green cube."

// The robot likes everything (as Winograd's did), until told otherwise.
conversation "the robot's feelings"
say "Do you like the box?", "Yes, I like everything."
say "Do you love the box?", "No."
say "You hate the box.", "I understand."
say "Do you like the box?", "No."
say "Do you dislike the box?", "Yes."
say "How many things do you like?", "Nine of them."

// "Mine" and "yours" as noun phrases: "my ones", borrowing the noun.
conversation "mine and yours"
say "I own the red cube and the green pyramid.", "I understand."
say "Put mine in the box.", "OK."
say "What is in the box?", "The red cube, the green pyramid and the blue pyramid."
say "You own the blue block and the large red block.", "I understand."
say "Which blocks are tall?", "The large red one and the blue one."
say "Put yours on the table.", "OK."
say "I own the large green cubes.", "I understand."
say "Pick up mine.", "I can only hold one thing at a time."
say "Which cubes are mine?", "The red one, the large green one which supports the red pyramid and the large green one which is on the large red block."

// "No" in a statement: "I own no red blocks" is "I don't own any".
conversation "no red blocks"
say "I own blocks.", "I understand."
say "I own no red blocks.", "I understand."
say "Do I own the red cube?", "No."
say "Which blocks do I own?", "The large green cube which supports the red pyramid, the large green cube which is on the large red block and the blue one."
say "I like no pyramids.", "I understand."
say "I love the green pyramid.", "I understand."
say "Which pyramids do I like?", "The green one."

conversation "one, in a complaint"
say "How many green cubes are there?", "Two of them."
// (There's a pyramid on the red cube, not a green cube.)
say "I own the one on top of the red cube.", "I don't see any green cubes on the red cube."

conversation "session 1, varied"
say "Which of the blocks are red?", "The red cube and the large red one."
say "Is any of the cubes red?", "Yes, the red one."
say "How many of them are on the table?", "Two of them."
say "Pick up two of the blocks on the table.", "I can only hold one thing at a time."
say "What is the large red block supporting?", "A large green cube."
say "Is the box containing anything?", "Yes."
say "The red cube is named Rex.", "OK."
say "What is Rex's color?", "Red."
say "Its name is Max.", "OK."
say "Where is Max?", "On the table."
say "Stack up the two red cubes.", "I see one red cube, not two."

conversation "teaching by example"
// Only the shapes and their order are kept: a block, a block, and a
// pyramid on top.  Not the colors or sizes.
say "Stack up the large red block, the small red cube, and the red pyramid.", "OK."
say "Call that a steeple.", "I understand."
say "Are there any steeples?", "Yes, the stack of the large red block, the red cube and the red pyramid."
say "How do you build a steeple?", "By putting a block on a block, then a pyramid on that."
say "Build another one.", "OK."
say "How many steeples are there?", "Two of them."
say "Is the box a crate?", "Sorry, I don't know the word ""crate""."
say "Call the box a crate.", "I understand."
say "Is the box a crate?", "Yes."
say "Call any cube a die.", "I understand."
say "Which blocks are dice?", "The red cube, the large green cube which is on the table and the large green cube which supports the green pyramid."
say "How many dice are on the table?", "Just one."
say "Is the red cube a die?", "Yes."
say "Call all pyramids leaves.", "I understand."
say "How many leaves are there?", "Three of them."
say "Is the green pyramid a leaf?", "Yes."
say "Call all pyramids wedges.", "I understand."
say "How many wedges are there?", "Three of them."

// Naming something just after making a stack names the whole stack.
conversation "naming a stack"
say "Put the red cube on the blue block.", "OK."
say "That is a ""tower"".", "I understand."
say "How many towers are there?", "Two of them."
say "Put the green pyramid on the red cube.", "OK."
say "Call it Spire.", "OK."
say "What is Spire?", "The stack named Spire."
say "Where is Spire?", "On the table."
say "Is the blue block in Spire?", "Yes."
say "Pick up the red cube.", "OK."
say "Where is Spire?", "Spire isn't a stack any more."

// Naming one thing names just that thing, even with "a".
conversation "naming one thing"
say "Call the box a crate.", "I understand."
say "How many crates are there?", "Just one."
say "Pick up the red cube.", "OK."
say "Call it Rex.", "OK."
say "Where is Rex?", "In my hand."
say "What is Rex?", "The cube named Rex."

conversation "one, borrowing"
say "How many big blocks are there?", "Four of them."
say "Is there one in the box?", "No."
say "Is there a small one?", "Yes, the red cube."
say "How many green pyramids are there?", "Just one."
say "Where is it?", "On the red cube."
say "Is there a red one?", "Yes, the red pyramid."

//======================================================================
// The rest of the 2008 list
//======================================================================

conversation "the rest of the 2008 list, in its order"
// (One conversation, as in the dialogues these came from, so what was
// said before matters.  Some come from dialogues with other scenes:
// there, "the green cube" may be ambiguous here.)
say "Pick up a block.", "OK."
say "Is the big pyramid green?", "I don't understand which large pyramid you mean."
say "What is on the green cube?", "The red pyramid."
say "Are there any more?", "No.", gap("""any more"": others like the ones just mentioned")
say "Would a cube roll off the top of a pyramid?", "Sorry, I don't know the word ""roll"".", out("rolling")
say "Can you put a pyramid on the side of a cube?", "Sorry, I don't know the word ""side"".", out("things never change orientation")
say "How big is it?", "Large."
say "Now put it on the table.", "OK."
say "Clear an area on the left of the table.", "Sorry, I don't know the word ""area"".", out("free areas")
say "Can you find room on the left of the table for two blocks and a pyramid?", "Sorry, I don't know the word ""room"".", out("free areas")
say "Can pyramids roll?", "Sorry, I don't know the word ""roll"".", out("rolling")
say "Why not?", "I didn't understand the part starting with ""not"".", out("""why not"" after a refusal")
say "What about the former?", "Sorry, I don't know the word ""former"".", out("""the former"" and ""the latter""")
say "Now drop a cube on it.", "By ""it"", I assume you mean the red pyramid. I can't balance anything on a pyramid."
say "Where did the cube go?", "I don't understand which cube you mean."
say "Have you ever seen a blue pyramid?", "Yes, the blue one."
say "Don't ever touch the green cube.", "I don't understand which green cube you mean.", gap("standing orders (and our scene has two green cubes)")
say "Where would you put the red block if you had to move the green one?", "Sorry, I don't know the word ""if"".", out("hypotheticals")
say "Move the green block.", "Where should I move it to?  You can say, for example, ""Move it onto the box."""
say "Did you put the red block where you said you would?", "Sorry, I don't know the word ""said"".", out("what the robot said it would do")
say "Where did I tell you to move the green block?", "I didn't understand the part starting with ""i"".", out("what the user said, as such")
say "Try to find all blocks colored red or blue.", "OK."
say "Move them to the front of the table.", "OK."
say "Move the rest to the back.", "OK.", gap("""the rest"": the others of the kind just talked about")
say "If you build a steeple, where do you start?", "Sorry, I don't know the word ""if"".", out("hypotheticals")
say "Why?", "Because you asked me to."
say "Can a steeple have four blocks?", "Sorry, I don't know the word ""steeple"".", out("""steeple"" hasn't been taught here")
say "How can you tell?", "I didn't understand the part starting with ""tell"".", out("the robot's knowledge")
say "Who said it was red?", "Sorry, I don't know the word ""said"".", out("who said what")
say "I want you to bring me a cube.", "OK."
say "Find the second last block I asked you to move and pick it up.", "I didn't understand the part starting with ""last"".", out("""second last"" and the user's earlier commands")
say "The one you are holding.", "That seems to stop in the middle.", out("a noun phrase with no question to answer")
say "Is the taller green cube taller than the tallest pyramid?", "I didn't understand the part starting with ""taller"".", out("a comparative as an adjective (""the taller green cube"")")
say "Turn the pyramid round so I can see its back.", "Sorry, I don't know the word ""turn"".", out("things never change orientation")
say "Is there a cube not all of whose faces are the same?", "Sorry, I don't know the word ""whose"".", out("faces")
say "Can you find a cube with one face taller than the others?", "Sorry, I don't know the word ""with"".", out("faces")
say "I have just put a cube on the table.", "I didn't understand the part starting with ""have"".", out("the user changing the world")
say "How many colors does that cube have?", "Sorry, I don't know the word ""colors"".", out("faces")
say "How many pairs of opposite faces have the same color?", "Sorry, I don't know the word ""pairs"".", out("faces")
say "Are you sure?", "Sorry, I don't know the word ""sure"".", out("the robot's knowledge")
say "Does Bert have any neighbors?", "Sorry, I don't know the word ""bert"".", out("Bert, from another dialogue")
say "Does Bert like any of his neighbors?", "Sorry, I don't know the word ""bert"".", out("liking")
say "Bert likes only yellow cubes, or cubes with some yellow in them.", "Sorry, I don't know the word ""bert"".", out("liking")
say "Move most cubes to the back, leaving just one or two little cubes at the front.", "Sorry, I don't know the word ""most"".", out("""most"" and ""leaving""")
say "How many did you leave?", "Sorry, I don't know the word ""leave"".", out("""leaving""")
say "How would you begin to dismantle a steeple?", "Sorry, I don't know the word ""dismantle"".", out("dismantling")
say "How did you work that out?", "Sorry, I don't know the word ""work"".", out("the robot's reasoning")
say "When dismantling a steeple, when would you move the bottom block?", "Sorry, I don't know the word ""dismantling"".", out("dismantling")
say "Is there always room to put down a block you are holding?", "Sorry, I don't know the word ""always"".", out("""always""")
say "What is the blue pyramid supported by?", "The box."
say "Are any red blocks resting on the table?", "Yes, two of them: the red cube and the large red one."
say "If there is too much on that block to move it, clear it off.", "Sorry, I don't know the word ""if"".", out("conditional commands")
say "Thank you.", "You're welcome!"

conversation "standing orders"
say "Don't ever touch the blue block.", "OK.", gap("standing orders")
say "Put the red cube on the blue block.", "I can't.  You told me not to touch the blue block.", gap("standing orders")

conversation "colored"
say "Which blocks are colored green?", "The large green cube which supports the red pyramid and the large green cube which is on the large red block."
say "Find all blocks colored red or blue.", "OK."

// "On the left", with no "of": in "the red block on the left" it picks
// one of the red blocks by contrast (the leftmost); elsewhere it means the
// left side of the table.  (From a session log, 2026-11-18, where "left"
// and "right" were unknown words on their own.)
conversation "on the left", "playground"
say "Pick up the red block.", "I don't understand which red block you mean."
say "I mean the one on the left.", "OK."
say "Is the red block you are holding the leftmost block?", "Yes."

conversation "on the right", "playground"
say "Grasp the red block.", "I don't understand which red block you mean."
say "The one on the right.", "OK."
say "Is the block you are holding to the right of the other red block?", "Yes."

conversation "which one is on the left", "playground"
say "Which red block is on the right?", "The red one which is to the right of the blue cylinder."
say "Which red block is the leftmost?", "The red one which is to the left of the blue pyramid."
say "Pick up the red block on the left.", "OK."
say "Is it to the left of the other red block?", "Yes."
say "Which block is furthest to the left?", "The red one which is to the left of the blue pyramid.", gap("""furthest to the left""")

conversation "sides of the table", "playground"
say "What is on the left?", "Two red blocks, the blue block, the blue cylinder and the blue pyramid."
say "Is the box on the left?", "No."
say "Which blocks are on the right?", "The yellow one."
say "Is there a pyramid in front?", "Yes, the blue one."
say "What is at the back?", "Two red blocks, the yellow cylinder, the green pyramid, the red pyramid and the box."
say "What is the frontmost pyramid?", "The blue pyramid."
say "Pick up the rightmost block.", "OK."

conversation "sides in Winograd's scene"
say "Which pyramid is on the left?", "The green one."
say "Is the box at the back?", "Yes."
say "What is the backmost block?", "The blue block."
say "Is the blue pyramid on the right side?", "No."
say "Pick up the pyramid on the right.", "OK."

// From session 12: a side as an adjective, to say which one.
conversation "the left one"
say "Put the green cube into the box.", "I don't understand which green cube you mean."
say "The left one.", "OK."
say "Is the large red block supporting anything?", "No."
conversation "left, right, front and back before a noun"
say "Which is the left green cube?", "The large green cube which is on the large red block."
say "Pick up the right green cube.", "OK."
say "Put it on the left red block.", "OK."
say "What is the back block?", "The blue block."
say "Is the back pyramid blue?", "Yes."
say "Put the blue block on the right side of the table.", "OK."
say "Where is the rear pyramid?", "In the box."
say "Pick up the left-hand pyramid.", "OK."

// From session 13: other ways to define a word, "let's", "how many" with
// no noun, and "now" before a question.
conversation "define a word as"
say "Let's define a ""steeple"" as a pyramid on top of a block.", "I understand."
say "How many steeples are there?", "Two of them."
say "Can you make one?", "OK."
say "Now how many are there?", "Three of them."
conversation "other ways to define a word as"
say "Define a ""steeple"" as a pyramid on top of a block.", "I understand."
say "Please define ""tower"" as a block on top of a block.", "I understand."
say "How many towers are there?", "Just one."
conversation "let's"
say "Let's pick up the red cube.", "OK."
say "Let's put it in the box.", "OK."
say "Let us pick up the blue block.", "OK."
conversation "how many, with no noun"
say "How many blocks are there?", "Five of them."
say "How many are on the table?", "Four of them."
say "How many are there?", "Five of them."
say "How many red blocks are there?", "Two of them."
say "And how many are in the box?", "None."
conversation "a lead word before a question"
say "Now what is in the box?", "The blue pyramid."
say "So how many blocks are there?", "Five of them."
say "OK, where is the red cube?", "On the table."
say "Pick up the red cube.", "OK."
say "And now, what are you holding?", "The red cube."
say "Actually, is the box empty?", "No."

//======================================================================
// Out of scope for now
//======================================================================

conversation "out of scope"
say "Can a cube roll off the table?", "Sorry, I don't know the word ""roll"".", out("(2008) rolling")
say "Roll the pyramid to the left.", "Sorry, I don't know the word ""roll"".", out("(2008) rolling")
say "Will you put the pyramid on its side?", "Sorry, I don't know the word ""side"".", out("(2008) things never change orientation")
say "Turn over a red cube.", "Sorry, I don't know the word ""turn"".", out("(2008) things never change orientation")
say "Does every cube have every face the same?", "Sorry, I don't know the word ""face"".", out("(2008) faces")
say "Does Bert like himself?", "Sorry, I don't know the word ""bert"".", out("(2008) liking")
say "Put a small cube and a pyramid on the large red cube and the large green cube respectively.", "Sorry, I don't know the word ""respectively"".", out("(2008) ""respectively""")
say "In order to build an arch, you need a bar.", "Sorry, I don't know the word ""order"".", out("(2008) arches and bars")
say "If you put one block on another, can you then pick up the latter?", "Sorry, I don't know the word ""if"".", out("(2008) hypotheticals")
say "Assume that there is another block on the table.", "Sorry, I don't know the word ""assume"".", out("(2008) hypotheticals")
say "Is there any space left anywhere?", "Sorry, I don't know the word ""space"".", out("(2008) free space")
say "Were you aware that the green block is in the box?", "Sorry, I don't know the word ""aware"".", out("(2008) the robot's knowledge")
say "How do you know?", "Sorry, I don't know the word ""know"".", out("(2008) the robot's knowledge")

print ""
print passes + " pass, " + gaps + " gaps, " + outOfScope + " out of scope, " + failures + " failures (of " + lineNumber + " lines)."
exit (failures > 0)
