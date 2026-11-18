// testBrain.ms
//
// Tests for relations, speech, and the brain's reference resolution and
// question answering, using hand-written ICL against the scenes.
// Run from the repo root:
//
//   MS_IMPORT_PATH=src:tests miniscript tests/testBrain.ms
//
// For brevity, the ICL in these tests separates lines with "; ".

import "world"
import "scenes"
import "fixtures"
import "icl"
import "relations"
import "speech"
import "brain"
import "meaning"

failures = 0
checks = 0
check = function(condition, what)
	globals.checks += 1
	if condition then return
	globals.failures += 1
	print "FAILED: " + what
end function

// A world with the early scene (see fixtures.ms), or one of the real ones.
newWorld = function(sceneName=null)
	w = world.World.make
	if sceneName == null then scene = fixtures.earlyScene else scene = scenes.byName[sceneName]
	problems = w.load(scene)
	if problems then print "Scene problems: " + problems
	return w
end function

// Give the brain some ICL and check its reply.
expect = function(b, iclText, expected)
	reply = b.respond(iclText.replace("; ", char(10)))
	check reply == expected, iclText + nl + "    expected: " + expected + nl + "    got:      " + reply
end function
nl = char(10)

// The Winograd scene (provisional; see scenes.ms):
//   b1 small red cube, with the green pyramid p1 on it
//   b2 large green cube, with the red pyramid p2 on it
//   b3 large red block, with the small green cube b4 on it
//   b5 tall blue block
//   the box, with the blue pyramid p3 in it
w = newWorld
b1 = w.thing("b1"); b2 = w.thing("b2"); b3 = w.thing("b3"); b4 = w.thing("b4"); b5 = w.thing("b5")
p1 = w.thing("p1"); p2 = w.thing("p2"); p3 = w.thing("p3")
box = w.thing("box"); table = w.table

//----------------------------------------------------------------------
// Relations
//----------------------------------------------------------------------

r = relations.binary
check r.on(w, p1, b1) and not r.on(w, p1, table), "p1 is on b1, not directly on the table"
check r.above(w, p1, table) and r.below(w, table, p1), "p1 is above the table"
check r.supports(w, b2, p2), "b2 supports p2"
check r["in"](w, p3, box) and r.contains(w, box, p3) and not r["in"](w, p1, box), "p3 is in the box"
check r.touches(w, p1, b1) and not r.touches(w, p1, b2), "touching by support"
check r.taller(w, b5, b3) and r.shorter(w, b1, b5), "taller and shorter"
check r.wider(w, b3, b2) and r.narrower(w, b4, b2) and not r.narrower(w, b4, b1), "wider and narrower"
check r.bigger(w, b3, b2) and r.smaller(w, b1, b2), "bigger and smaller"
check r.behind(w, b5, b1) and r.inFrontOf(w, b1, b5), "b5 is behind b1"
check r.leftOf(w, b1, b3) and r.rightOf(w, box, b2), "left and right"
check relations.sizeClass(w, b3) == "big" and relations.sizeClass(w, b2) == "big", "big blocks"
check relations.sizeClass(w, b1) == "small" and relations.sizeClass(w, b5) == "small", "small blocks"
check relations.sizeClass(w, box) == null, "only one box, so it's neither big nor small"
check relations.valued.size(w, b3, "large") and relations.valued.size(w, b1, "little"), "size synonyms"
check relations.extreme([b1, b2, b3, b4, b5], "tallest") == [b5], "tallest"
check relations.extreme([b1, b2, b3, b4, b5], "littlest").len == 2, "littlest keeps ties"
check relations.nounFits(b1, "cube") and not relations.nounFits(b3, "cube") and relations.nounFits(b1, "block"), "cubes are blocks"
check relations.nounFits(table, "thing") and not relations.nounFits(table, "object") and relations.nounFits(box, "object"), "the table is a thing, but not an object"
check not relations.binary.leftOf(w, table, box) and not relations.binary.behind(w, b1, table), "the table is in no direction"

// Side by side, in the playground: the green cubes b4 and b5 start half a
// unit apart, so they're next to each other but not touching.
pw = newWorld("playground")
pb4 = pw.thing("b4"); pb5 = pw.thing("b5")
check relations.binary.nextTo(pw, pb4, pb5) and not relations.binary.touches(pw, pb4, pb5), "half a unit apart"
check not relations.binary.nextTo(pw, pb4, pw.thing("b6")), "far apart things aren't next to each other"
pw.pickUp pb5
pw.putAt 0, 2     // now they're side by side, touching
check relations.binary.touches(pw, pb4, pb5) and relations.binary.nextTo(pw, pb4, pb5), "side by side cubes touch"
check not relations.binary.touches(pw, pb4, pw.thing("b3")), "but not the lintel"

//----------------------------------------------------------------------
// Speech
//----------------------------------------------------------------------

check speech.nameFor(w, b3) == "the large red block", "the large red block (a cube is a block too)"
check speech.nameFor(w, b1) == "the red cube", "the red cube"
check speech.nameFor(w, b2) == "the large green cube", "the large green cube"
check speech.nameFor(w, b4) == "the small green cube", "the small green cube"
check speech.nameFor(w, box) == "the box", "the box"
check speech.nameFor(w, table) == "the table", "the table"
check speech.listPhrase(["a", "b", "c"]) == "a, b and c", "list phrase"
check speech.numberWord(4) == "four", "number words"
// Two things that differ only in where they are.
tw = world.World.make
tw.load [
  {"id": "b1", "kind": "block", "color": "red", "size": [1,1,1], "at": [-2, 0]},
  {"id": "b2", "kind": "block", "color": "red", "size": [1,1,1], "at": [2, 0]},
  {"id": "b3", "kind": "block", "color": "blue", "size": [1,1,1], "at": [2, 0]}]
check speech.nameFor(tw, tw.thing("b3")) == "the blue cube", "the blue cube"
check speech.nameFor(tw, tw.thing("b2")) == "the red cube which supports the blue cube", "told apart by what it supports"
check speech.nameFor(tw, tw.thing("b1")) == "the red cube which is to the left of the blue cube", "or by where it is"
check speech.nameFor(tw, tw.thing("b2"), false) == "a red cube", "when it doesn't matter which"
check speech.namesFor(tw, [tw.thing("b1"), tw.thing("b2")]) == "two red cubes", "alike things counted together"
check speech.nameFor(w, b3, false) == "the large red block", "the size is added when color isn't enough"
check speech.nameFor(w, b2, false) == "the large green cube", "and that may be enough"

//----------------------------------------------------------------------
// Reference resolution and questions, in Winograd's scene
//----------------------------------------------------------------------

b = brain.Brain.make(w)

// "Grasp the pyramid."  (We can't grasp yet, but we can complain properly.)
expect b, "x1 = the pyramid; Ask color x1", "I don't understand which pyramid you mean."
expect b, "x1 = the pyramid [color purple]; Ask color x1", "I don't see any purple pyramids."
expect b, "x1 = the pyramid [color blue]; Ask size x1", "Large."
expect b, "x1 = the pyramid [littlest]; Ask color x1", "Green."
// "What color is a pyramid?"  Any one will do (whichever is least trouble
// to reach; here, the red one), and it becomes "it".
expect b, "x1 = a pyramid; Ask color x1", "Red."
expect b, "x1 = it; x2 = a cube; Ask yes-no x1 [on x2]", "Yes."
expect b, "x1 = a pyramid; Ask shape x1", "Pyramid."
expect b, "x1 = a pyramid [color purple]; Ask color x1", "I don't see any purple pyramids."

// "Is there a big red block?"
expect b, "x1 = a block [color red] [size big]; Ask exists x1", "Yes, the large red one."
expect b, "x1 = a block [color yellow]; Ask exists x1", "No."
expect b, "x1 = a pyramid [on x2]; x2 = a cube; Ask exists x1",
  "Yes, two of them: the green one and the red one."

// "What does the box contain?"
expect b, "x1 = which thing [in x2]; x2 = the box; Ask which x1", "The blue pyramid."
// "What is the red pyramid supported by?"
expect b, "x1 = which thing [supports x2]; x2 = the pyramid [color red]; Ask which x1",
  "The large green cube."
// "What color is it?"  "It" is now the large green cube.
expect b, "x1 = it; Ask color x1", "Green."
expect b, "x1 = it; Ask shape x1", "Cube."

// "How many blocks are not in the box?"
expect b, "x1 = how-many blocks [not [in x2]]; x2 = the box; Ask count x1", "Five of them."
// "Is at least one of them narrower than the red cube?"  ("Them" is those five.)
expect b, "x1 = at-least-1 of them; x2 = the cube [color red]; Ask yes-no x1 [narrower x2]", "No."
expect b, "x1 = at-least-1 of them; x2 = the cube [color red]; Ask yes-no x1 [wider x2]",
  "Yes, two of them: the large green cube and the large red block."
// "Is it taller than..." with "the" and "every".
expect b, "x1 = the cube [color red]; x2 = the block [color blue]; Ask yes-no x1 [shorter x2]", "Yes."
expect b, "x1 = every pyramid; x2 = the box; Ask yes-no x1 [in x2]", "No."
expect b, "x1 = no pyramid; x2 = the table; Ask yes-no x1 [on x2]", "Yes."
// Quantifiers inside constraints: on *a* cube, versus on *the* cube.
expect b, "x1 = how-many pyramids [on x2]; x2 = a cube; Ask count x1", "Two of them."
// "The cube" is ambiguous (both cubes have a pyramid on them)...
expect brain.Brain.make(w), "x1 = how-many pyramids [on x2]; x2 = the cube; Ask count x1", "I don't understand which cube you mean."
// ...unless we were just talking about one of them: "it" is the red cube now.
expect b, "x1 = how-many pyramids [on x2]; x2 = the cube; Ask count x1", "One of them."
expect b, "x1 = how-many things [on x2]; x2 = every block; Ask count x1", "None."
// "Red or green"
expect b, "x1 = how-many pyramids [color red|green]; Ask count x1", "Two of them."

// "Call it superblock."
expect b, "x1 = the block [color red] [size big]; Name x1, superblock", "OK."
expect b, "x1 = superblock; Ask color x1", "Red."
expect b, "x1 = superblock; x2 = it; Ask yes-no x1 [supports x2]", "No."
expect b, "x1 = the cube [on x2]; x2 = superblock; Ask size x1", "Small."

// "One" borrows a noun from earlier in the sentence.
expect b, "x1 = a block [taller x2]; x2 = the one [color red] [size small]; Ask exists x1",
  "Yes, three of them: the large green cube, the one named superblock and the blue one."

// Things we can't do or don't know.
fresh = brain.Brain.make(newWorld)
expect fresh, "x1 = it; Ask color x1", "I don't know what you mean by ""it""."
expect fresh, "x1 = them; Ask count x1", "I don't know what you mean by ""them""."
expect fresh, "x1 = a block [sparkly]; Ask exists x1", "I don't know what ""sparkly"" means."
expect fresh, "x1 = a widget; Ask exists x1", "Sorry, I don't know the word ""widget""."
expect fresh, "x1 = a block [on x2]; x2 = a pyramid [under x1]; Ask exists x1", "I don't know what ""under"" means."
expect fresh, "x1 = it; e1 = event PickUp x1; Ask why e1", "I don't know what you mean by ""it""."
// A description may mention itself: "a block on a block that supports it".
// While each block is tested, x1 means that block.
expect fresh, "x1 = a block [on x2]; x2 = a block [supports x1]; Ask exists x1", "Yes, the small green cube."
expect fresh, "x1 = a block [on x1]; Ask exists x1", "No."
// Everything narrower than what it's on.  Not the green pyramid (as wide
// as the red cube), and not the table, which nothing supports.
expect fresh, "x1 = a thing [not [asWide x2]]; x2 = the thing [supports x1]; Ask which x1",
  "The red cube, the large green cube, the red pyramid, the large red block, the small green cube, the blue block, the box and the blue pyramid."
expect fresh, "x1 = a block; Juggle x1", "Sorry, I don't know how to juggle."
expect fresh, "x1 = a block [on x2", "(I couldn't read that ICL: line 1: missing ])"

// Holding something: "the one you are holding".  With no noun anywhere in
// the sentence or before it, "one" means "thing".
hw = newWorld
hb = brain.Brain.make(hw)
hw.pickUp hw.thing("b4")
expect hb, "x1 = the one [held]; Ask color x1", "Green."
expect hb, "x1 = a block [taller x2]; x2 = the one [held]; Ask exists x1",
  "Yes, three of them: the large green cube, the large red one and the blue one."
check speech.nameFor(hw, hw.thing("b4")) == "the small green cube", "held things keep their names"

// Clicking on something: "this" and "that".
hb.selected = hw.thing("p2")
expect hb, "x1 = this; Ask color x1", "Red."

//----------------------------------------------------------------------
// Inner "the": settled by the description around it
//----------------------------------------------------------------------

w = newWorld
b = brain.Brain.make(w)
// There are several blocks, but only one that the green pyramid is on.
expect b, "x1 = the pyramid [color green] [on x2]; x2 = the block; Ask size x1", "Small."
expect b, "x1 = which thing [on x2]; x2 = the block [supports x3]; x3 = the pyramid [color green]; Ask which x1", "The green pyramid."
// But both cubes have a pyramid on them, so this is still ambiguous.
expect b, "x1 = the pyramid [on x2]; x2 = the cube; Ask color x1", "I don't understand which cube you mean."

//----------------------------------------------------------------------
// English, and choosing among readings
//----------------------------------------------------------------------

hear = function(b, text, expected)
	reply = b.hear(text)
	check reply == expected, text + nl + "    expected: " + expected + nl + "    got:      " + reply
end function

// "Put the green pyramid on the block in the box" can mean putting it on
// a block that's in the box, or putting the pyramid that's on a block into
// the box.  At first there's no block in the box, so only the second makes
// sense, and the robot just does it.
w = newWorld
b = brain.Brain.make(w)
hear b, "Put the green pyramid on the block in the box.", "OK."
check refEquals(w.thing("p1").supporters[0], w.thing("box")), "the green pyramid went into the box"

// With the blue block in the box, both make sense.  The robot takes the
// first (the nearest noun gets "in the box"), and says so.
w = newWorld
b = brain.Brain.make(w)
hear b, "Put the blue block in the box.", "OK."
hear b, "Put the green pyramid on the block in the box.",
  "By ""the block in the box"", I assume you mean the blue block. OK."
check refEquals(w.thing("p1").supporters[0], w.thing("b5")), "the green pyramid went onto the blue block"

// Checking a reading changes nothing: not the world, and not "it".
w = newWorld
b = brain.Brain.make(w)
hear b, "Pick up the red pyramid.", "OK."
r = meaning.understand("Put the green pyramid on the block in the box.")
for prog in r.programs
	b.check prog
end for
check refEquals(w.hand.holding, w.thing("p2")), "still holding the red pyramid"
check refEquals(b.focus.it, w.thing("p2")), "it is still the red pyramid"

// Words it doesn't know, and sentences it can't parse.
hear b, "Pick up the frobnicator.", "Sorry, I don't know the word ""frobnicator""."
hear b, "Pick up the block the box.", "I didn't understand the part starting with ""the""."

// Names the user has taught are names in English too.
hear b, "Put it down.", "OK."
b.respond "x1 = the block [color red] [size big]" + nl + "Name x1, superblock"
hear b, "What color is superblock?", "Red."

// "Move" with nowhere to move it is for questions, not commands.  A thing
// that was moved was put somewhere, or got rid of, or at least picked up.
w = newWorld
b = brain.Brain.make(w)
hear b, "Move the red pyramid.", "Where should I move it to?  You can say, for example, ""Move it onto the box."""
hear b, "Why did you move the red pyramid?", "I can't explain a nonexistent event."
hear b, "Pick up the large red block.", "OK."
hear b, "Why did you move the small green cube?", "To clean off the large red block."
hear b, "Why did you move the large red block?", "Because you asked me to."
hear b, "Put the red pyramid on the table.", "OK."
hear b, "Why did you move the red pyramid?", "Because you asked me to."

// Did the robot do something?  Touching something means picking it up.  An
// indefinite thing ("any pyramid") gets named, and "it" and the event
// we're talking about become the ones found.
w = newWorld
b = brain.Brain.make(w)
hear b, "Did you pick up the red cube?", "No."
hear b, "Pick up the large red block.", "OK."
hear b, "Did you touch any block?", "Yes, two of them: the small green cube and the large red one."
hear b, "Did you touch a cube?", "Yes, the small green one."
hear b, "Put the large red block on the small green cube.", "OK."
hear b, "Did you touch any cube after you picked up the large red block?", "Yes, the small green one."
hear b, "Did you touch any pyramid before you picked up the large red block?", "No."
// The event just found is the one meant, even if there's a later one: the
// small green cube was moved again just now, but this asks about the first time.
hear b, "Had you touched any cube before you put the large red block on the small green cube?", "Yes, the small green one."
hear b, "Why did you pick it up?", "To get rid of it."

// Questions about what the robot did things to, and about the past.  A
// failed attempt isn't something it did.  ("Thing" includes the table, so
// "What is it on?" can say so.)
w = newWorld
b = brain.Brain.make(w)
hear b, "Which green cube did you move?", "None."
hear b, "Pick up the large red block.", "OK."
hear b, "Which green cube did you move?", "The small green one."
hear b, "Put the large red block in the box.", "There's no room for the large red block in the box."
hear b, "What did you put in the box?", "Nothing."
hear b, "What did the large red block support before you picked it up?", "The small green cube."
hear b, "What did the large red block support after you picked it up?", "Nothing."
hear b, "What is the small green cube on?", "The table."
hear b, "What was the small green cube on before you picked up the large red block?", "The large red block."
hear b, "How many objects did you touch while you were picking up the large red block?", "Two of them."

// Emptying the box.  Each thing taken out was put on the table, by way of
// getting rid of it, and a question about putting it there finds that.
w = newWorld
b = brain.Brain.make(w)
hear b, "Put the blue block in the box.", "OK."
hear b, "Empty the box.", "OK."
hear b, "What does the box contain?", "Nothing."
hear b, "Why did you put the blue block on the table?", "To empty the box."
hear b, "Why did you put down the blue pyramid?", "To empty the box."
hear b, "How did you empty the box?", "By getting rid of the blue block, then getting rid of the blue pyramid."

// Ownership: particular things, or kinds of thing.  A kind is checked when
// it matters, so it covers things that come to fit it later, and what was
// said last counts most.
w = newWorld
b = brain.Brain.make(w)
hear b, "Do I own the box?", "I don't know."
hear b, "The blue pyramid is mine.", "I understand."
hear b, "Is the blue pyramid mine?", "Yes."
hear b, "I own blocks which are not red, but I don't own anything which supports a pyramid.", "I understand."
hear b, "Do I own the box?", "No."
hear b, "Which blocks do I own?", "The small green cube and the blue one."
hear b, "Put the red pyramid on the table.", "OK."
hear b, "Do I own the large green cube?", "Yes."
hear b, "I don't own the blue block.", "I understand."
hear b, "Do I own anything which is not in the box?", "Yes, two things: the large green cube and the small green cube."

// Joined noun phrases.  "Or" takes the first that can be found; "a" won't
// pick something already picked in the same sentence; "both" insists on two.
w = newWorld
b = brain.Brain.make(w)
hear b, "Is there a block which supports a pyramid and a block?", "No."
expect b, "x1 = a block [supports x4]; x2 = a block; x3 = a pyramid; x4 = x2 or x3; Ask exists x1",
  "Yes, three of them: the red cube, the large green cube and the large red one."
hear b, "Pick up the blue cube or the red pyramid.", "OK."
check refEquals(w.hand.holding, w.thing("p2")), "picked up the red pyramid"
hear b, "Pick up the blue cube or the green cube in the box.", "I don't see any blue cubes."
hear b, "Pick up both of the pyramids.", "I see three pyramids, not two."
hear b, "Stack up both of the red blocks and either a green cube or a pyramid.", "OK."
// (It picks the small green cube, which was on the red block already.)
above = @relations.binary.above
check above(w, w.thing("b1"), w.thing("b3")), "the red cube is on the large red block"
check above(w, w.thing("b4"), w.thing("b1")), "the small green cube is on top"
hear b, "Stack up the red cube and a red block.", "OK."
hear b, "Stack up the red cube and a red cube.", "I don't see another red cube."

// Ability: yes if it's so now, no if it's against the rules, and otherwise
// we don't know.  Only the robot does things.
w = newWorld
b = brain.Brain.make(w)
hear b, "Can a pyramid be supported by a block?", "Yes."
hear b, "Can a block be on a pyramid?", "No. Nothing will stay on top of a pyramid."
hear b, "Can a pyramid support a block?", "No. Nothing will stay on top of a pyramid."
hear b, "Can a block be in the box?", "I don't know."
hear b, "Can the box pick up a pyramid?", "No."

// Claims.  A number means just that many.  "Then" is the time we last
// talked about.
w = newWorld
b = brain.Brain.make(w)
hear b, "There are two red blocks.", "That's right."
hear b, "There are three green blocks.", "No, only two of them: the large green cube and the small green cube."
hear b, "There is a block in the box.", "No, none."
hear b, "There was a pyramid on the box then.", "I'm not sure when you mean by ""then""."
hear b, "Put the small green cube in the box.", "OK."
hear b, "What did the large red block support before you put the small green cube in the box?", "The small green cube."
hear b, "There was a block on the large red block then.", "That's right."
hear b, "There is a block on the large red block.", "No, none."

// Stacks, and words the user teaches.  A stack is worked out from what
// rests on what; the box isn't part of one.
w = newWorld
b = brain.Brain.make(w)
stacks = relations.stacks(w)
check stacks.len == 3, "three stacks to start with: " + stacks.len
check refEquals(relations.stacks(w)[2], stacks[2]), "the same parts make the same stack"
check relations.binary.contains(w, stacks[0], w.thing("p1")), "a stack contains its parts"
hear b, "How many stacks are there?", "Three of them."
hear b, "Is there a stack which contains a pyramid and a red block?", "Yes, the stack of the red cube and the green pyramid."
hear b, "Are there any steeples?", "Sorry, I don't know the word ""steeples""."
hear b, "A ""steeple"" is a stack which contains two green cubes and a pyramid.", "I understand."
hear b, "Are there any steeples?", "No."
hear b, "Build one.", "OK."
hear b, "Is there a steeple?", "Yes, the stack of the large green cube, the small green cube and the red pyramid."
hear b, "Is the blue block in a steeple?", "No."
hear b, "Build a pyramid.", "Sorry, I don't know how to build a pyramid."
hear b, "Build a stack.", "What should I stack up?"
hear b, "Build two steeples.", "I can only build one thing at a time."
hear b, "A ""tower"" is the red block.", "That sounds like one particular thing.  To give it a name, say ""Call it tower""."
hear b, "A ""block"" is a stack which contains a pyramid.", "I already know the word ""block""."

// Saying what "it" was taken to mean: when something else in the sentence
// could have been "it", or when "it" came from an earlier sentence and the
// reply is a complaint.  Otherwise "it" goes without saying.
w = newWorld
b = brain.Brain.make(w)
hear b, "Pick up the small green cube.", "OK."
hear b, "Find a block which is wider than the one you are holding and put it on the table.",
  "By ""it"", I assume you mean the block which is wider than the one I am holding. OK."
hear b, "Pick up the red cube and put it in the box.", "OK."
hear b, "Put it on the blue pyramid.", "By ""it"", I assume you mean the red cube. I can't balance anything on a pyramid."
hear b, "Put the blue block on it.", "OK."

// The robot never drops anything, unless it's told to.
w = newWorld
b = brain.Brain.make(w)
hear b, "Put the red pyramid on the table.", "OK."
hear b, "Why did you drop it?", "By ""it"", I assume you mean the red pyramid. I can't explain a nonexistent event."
hear b, "Drop the small green cube.", "OK."
hear b, "Why did you drop it?", "Because you asked me to."

// "On top of" can mean directly on, or anywhere above.  When it matters,
// the robot asks which, and a number answers it.  Saying something else
// instead drops the question.
w = newWorld
b = brain.Brain.make(w)
question = "I'm not sure what you mean by ""on top of"" in the phrase ""on top of the large red block"".  Do you mean:" +
  nl + "1 - directly on the surface" + nl + "2 - anywhere on top of?"
hear b, "How many things are on top of the large red block?", "One of them."
hear b, "Put the green pyramid on the small green cube.", "OK."
hear b, "How many things are on top of the large red block?", question
hear b, "1", "One of them."
hear b, "How many things are on top of the large red block?", question
hear b, "2.", "Two of them."
hear b, "How many things are on top of the large red block?", question
hear b, "What is the small green cube on top of?", "The large red block."
hear b, "2", "Sorry, I don't know the word ""2""."

// Telling how something was done: "it" is the thing each step was about,
// and something already mentioned isn't named as if it were another one.
w = newWorld
b = brain.Brain.make(w)
hear b, "Stack up the blue block and the red cube.", "OK."
hear b, "How did you do it?", "By putting the red cube on the blue block."
w = newWorld("winograd")
teller = speech.Teller.make(w)
said = [teller.name(w.thing("b3")), teller.name(w.thing("b1")), teller.name(w.thing("b3")), teller.name(w.thing("b1"))]
check said.join("; ") == "a large green cube; the red cube; that cube; the red cube", "teller: " + said.join("; ")
teller.it = w.thing("b1")
check teller.name(w.thing("b1")) == "it", "teller: it"

print checks + " checks, " + failures + " failures."
exit (failures > 0)
