// testBrain.ms
//
// Tests for relations, speech, and the brain's reference resolution and
// question answering, using hand-written ICL against the scenes.
// Run from the repo root:
//
//   MS_IMPORT_PATH=src miniscript tests/testBrain.ms
//
// For brevity, the ICL in these tests separates lines with "; ".

import "world"
import "scenes"
import "icl"
import "relations"
import "speech"
import "brain"

failures = 0
checks = 0
check = function(condition, what)
	globals.checks += 1
	if condition then return
	globals.failures += 1
	print "FAILED: " + what
end function

newWorld = function(sceneName="winograd")
	w = world.World.make
	problems = w.load(scenes.byName[sceneName])
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
check not relations.nounFits(table, "thing") and relations.nounFits(box, "thing"), "the table isn't a thing"

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
check speech.nameFor(tw, tw.thing("b2")) == "the red cube which is on the table", "located by its supporter"

//----------------------------------------------------------------------
// Reference resolution and questions, in Winograd's scene
//----------------------------------------------------------------------

b = brain.Brain.make(w)

// "Grasp the pyramid."  (We can't grasp yet, but we can complain properly.)
expect b, "x1 = the pyramid; Ask color x1", "I don't understand which pyramid you mean."
expect b, "x1 = the pyramid [color purple]; Ask color x1", "I don't see any purple pyramids."
expect b, "x1 = the pyramid [color blue]; Ask size x1", "Large."
expect b, "x1 = the pyramid [littlest]; Ask color x1", "Green."

// "Is there a big red block?"
expect b, "x1 = a block [color red] [size big]; Ask exists x1", "Yes, the large red block."
expect b, "x1 = a block [color yellow]; Ask exists x1", "No."
expect b, "x1 = a pyramid [on x2]; x2 = a cube; Ask exists x1",
  "Yes, two of them: the green pyramid and the red pyramid."

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
  "Yes, the large green cube and the large red block."
// "Is it taller than..." with "the" and "every".
expect b, "x1 = the cube [color red]; x2 = the block [color blue]; Ask yes-no x1 [shorter x2]", "Yes."
expect b, "x1 = every pyramid; x2 = the box; Ask yes-no x1 [in x2]", "No."
expect b, "x1 = no pyramid; x2 = the table; Ask yes-no x1 [on x2]", "Yes."
// Quantifiers inside constraints: on *a* cube, versus on *the* cube.
expect b, "x1 = how-many pyramids [on x2]; x2 = a cube; Ask count x1", "Two of them."
expect b, "x1 = how-many pyramids [on x2]; x2 = the cube; Ask count x1", "I don't understand which cube you mean."
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
  "Yes, three of them: the large green cube, the large red block and the blue block."

// Things we can't do or don't know.
fresh = brain.Brain.make(newWorld)
expect fresh, "x1 = it; Ask color x1", "I don't know what you mean by ""it""."
expect fresh, "x1 = them; Ask count x1", "I don't know what you mean by ""them""."
expect fresh, "x1 = a block [sparkly]; Ask exists x1", "I don't know what ""sparkly"" means."
expect fresh, "x1 = a widget; Ask exists x1", "I don't know the word ""widget""."
expect fresh, "x1 = a block [on x2]; x2 = a pyramid [under x1]; Ask exists x1", "I don't know what ""under"" means."
expect fresh, "x1 = a block [on x2]; x2 = a block [supports x1]; Ask exists x1",
  "(I went in circles: x1 is described in terms of itself.)"
expect fresh, "x1 = it; e1 = event PickUp x1; Ask why e1", "I don't know what you mean by ""it""."
expect fresh, "x1 = a block; Juggle x1", "Sorry, I don't know how to juggle."
expect fresh, "x1 = a block [on x2", "(I couldn't read that ICL: line 1: missing ])"

// Holding something: "the one you are holding".  With no noun anywhere in
// the sentence or before it, "one" means "thing".
hw = newWorld
hb = brain.Brain.make(hw)
hw.pickUp hw.thing("b4")
expect hb, "x1 = the one [held]; Ask color x1", "Green."
expect hb, "x1 = a block [taller x2]; x2 = the one [held]; Ask exists x1",
  "Yes, three of them: the large green cube, the large red block and the blue block."
check speech.nameFor(hw, hw.thing("b4")) == "the small green cube", "held things keep their names"

// Clicking on something: "this" and "that".
hb.selected = hw.thing("p2")
expect hb, "x1 = this; Ask color x1", "Red."

print checks + " checks, " + failures + " failures."
exit (failures > 0)
