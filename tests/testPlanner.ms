// testPlanner.ms
//
// Tests for commands, the planner, and questions about what the robot did
// (why, how, when).  Most of it is a conversation in the style of
// Winograd's dialogue, written in ICL, played against the Winograd scene.
// Run from the repo root:
//
//   MS_IMPORT_PATH=src miniscript tests/testPlanner.ms
//
// For brevity, the ICL here separates lines with "; ".

import "geometry"
import "world"
import "scenes"
import "relations"
import "planner"
import "brain"

failures = 0
checks = 0
check = function(condition, what)
	globals.checks += 1
	if condition then return
	globals.failures += 1
	print "FAILED: " + what
end function
nl = char(10)

expect = function(b, iclText, expected)
	reply = b.respond(iclText.replace("; ", nl))
	check reply == expected, iclText + nl + "    expected: " + expected + nl + "    got:      " + reply
	checkWorld b.world, iclText
end function

// After every move, the world should still make sense: everything not in
// the hand rests exactly where it would land if dropped there now.  (To
// check that, we set aside whatever is above it: stacked on it, or
// overhanging it.)
checkWorld = function(w, when)
	allThings = w.things
	for t in w.movableThings
		if refEquals(t, w.hand.holding) then continue
		w.things = []
		for other in allThings
			if other.y < t.top - geometry.epsilon then w.things.push other
		end for
		p = w.placementFor(t, t.x, t.z)
		w.things = allThings
		ok = p.ok and abs(p.y - t.y) < geometry.epsilon and p.supporters.len == t.supporters.len
		check ok, t.id + " is resting properly after: " + when
	end for
end function

on = function(a, b)
	return relations.binary.on(w, w.thing(a), w.thing(b))
end function

w = world.World.make
w.load scenes.byName.winograd
b = brain.Brain.make(w)

//----------------------------------------------------------------------
// The conversation
//----------------------------------------------------------------------

// "Pick up a big red block."  The green cube is on it, so that has to go.
expect b, "x1 = a block [color red] [size big]; PickUp x1", "OK."
check refEquals(w.hand.holding, w.thing("b3")), "holding the big red block"
check on("b4", "table"), "the green cube was put on the table"

// "Grasp the pyramid."
expect b, "x1 = the pyramid; Grasp x1", "I don't understand which pyramid you mean."

// "Find a block which is taller than the one you are holding and put it
// into the box."
expect b, "x1 = a block [taller x2]; x2 = the one [held]; x3 = the box; Find x1; PutIn x1, x3", "OK."
check on("b5", "box"), "the tall blue block is in the box"
check on("b3", "table"), "the big red block was put down to free the hand"
check w.hand.holding == null, "the hand is empty"

// "What does the box contain?"
expect b, "x1 = which things [in x2]; x2 = the box; Ask which x1", "The blue block and the blue pyramid."

// "How many blocks are not in the box?"
expect b, "x1 = how-many blocks [not [in x2]]; x2 = the box; Ask count x1", "Four of them."

// "Is at least one of them narrower than the one which I told you to pick up?"
expect b, "x1 = at-least-1 of them; x2 = the one [commanded PickUp]; Ask yes-no x1 [narrower x2]",
  "Yes, the red cube, the large green cube and the small green cube."

// "Will you please stack up both of the large red blocks and either a green cube
// or a pyramid?"
expect b, "x1 = 2 blocks [color red]; x2 = a cube [color green]; Stack x1, x2", "OK."
check on("b1", "b3") and on("b4", "b1"), "stacked: the big red block, the red cube, the small green cube"
check on("p1", "table"), "the green pyramid had to come off the red cube"

// "Which cube is sitting on the table?"
expect b, "x1 = which cube [on x2]; x2 = the table; Ask which x1", "The large green cube."

// "Why did you pick up the green pyramid?" and then "Why?" up the chain.
expect b, "x1 = the pyramid [color green]; e1 = event PickUp x1; Ask why e1", "To get rid of it."
expect b, "e1 = event Do; Ask why e1", "To clean off the red cube."
expect b, "e1 = event Do; Ask why e1", "To put it on the large red block."
expect b, "e1 = event Do; Ask why e1", "To stack up the large red block, the red cube and the small green cube."
expect b, "e1 = event Do; Ask why e1", "Because you asked me to."

// "How did you do it?"
expect b, "e1 = event Do; Ask how e1",
  "By putting it on the large red block, then putting the small green cube on the red cube."
// "How did you clear off the red cube?"
expect b, "x1 = the cube [color red]; e1 = event ClearOff x1; Ask how e1", "By getting rid of the green pyramid."
expect b, "x1 = the pyramid [color green]; e1 = event GetRidOf x1; Ask how e1",
  "By picking it up, then setting it down on the table."

// "When did you pick it up?"
expect b, "x1 = the pyramid [color green]; e1 = event PickUp x1; Ask when e1",
  "While I was stacking up the large red block, the red cube and the small green cube."
expect b, "x1 = the block [color blue]; e1 = event PutIn x1, x2; x2 = the box; Ask when e1", "When you asked me to."

// Events in time: "Why did you pick up the green pyramid while you were
// stacking up the red cube?"  (It wasn't before or after.)
expect b, "x1 = the pyramid [color green]; e1 = event PickUp x1 [while e2]; e2 = event Stack x2; x2 = the cube [color red]; Ask why e1",
  "To get rid of it."
expect b, "x1 = the pyramid [color green]; e1 = event PickUp x1 [before e2]; e2 = event Stack x2; x2 = the cube [color red]; Ask why e1",
  "I don't remember doing that."
// The red block was picked up (at the start) before the stacking.
expect b, "x1 = the block [color red] [size big]; e1 = event PickUp x1 [before e2]; e2 = event Stack x2; x2 = the cube [color red]; Ask why e1",
  "Because you asked me to."

//----------------------------------------------------------------------
// Things it can't do
//----------------------------------------------------------------------

expect b, "x1 = the cube [color red]; x2 = the pyramid [color red]; PutOn x1, x2", "I can't balance anything on a pyramid."
expect b, "x1 = 2 pyramids; Stack x1", "I can't. Nothing will stay on top of a pyramid."
expect b, "x1 = the box; PickUp x1", "I can't pick up the box."
expect b, "x1 = the cube [color red]; PutOn x1, x1", "I can't put something on itself."
expect b, "PutDown", "I'm not holding anything."
expect b, "x1 = 9 blocks; PickUp x1", "I don't see enough blocks."
expect b, "x1 = it; x2 = the table; e1 = event PutOn x1, x2 [before e2]; e2 = event Juggle x1; Ask why e1",
  "I don't know what it means to juggle."

// Put down what's held; "put it on the table".
expect b, "x1 = the pyramid [color red]; PickUp x1", "OK."
expect b, "PutDown", "OK."
check on("p2", "table"), "put the red pyramid down on the table"

// Putting something where it already is does nothing.
before = w.history.len
expect b, "x1 = the pyramid [color red]; x2 = the table; PutOn x1, x2", "OK."
check w.history.len == before, "nothing to do"

// Clearing off something with a stack on it.
expect b, "x1 = the block [color red] [size big]; ClearOff x1", "OK."
check w.isClear(w.thing("b3")), "the large red block is clear"
expect b, "e1 = event Do; Ask how e1", "By getting rid of the red cube."

//----------------------------------------------------------------------
// Finding space
//----------------------------------------------------------------------

// Several things in the box: there's room for a few cubes beside the
// pyramid and the blue block, and then there isn't.
w2 = world.World.make
w2.load scenes.byName.playground
b2 = brain.Brain.make(w2)
expect b2, "x1 = every cube [color green]; x2 = the box; PutIn x1, x2", "OK."
check relations.binary["in"](w2, w2.thing("b4"), w2.thing("box")) and relations.binary["in"](w2, w2.thing("b5"), w2.thing("box")), "both green cubes in the box"
expect b2, "x1 = the block [color yellow]; x2 = the box; PutIn x1, x2",
  "There's no room for the yellow block in the box."

// Putting something on a thing that's already occupied: the planner clears
// it off first.
expect b2, "x1 = the block [color yellow]; x2 = the cylinder [color yellow]; PutOn x1, x2", "OK."
expect b2, "x1 = the cylinder [color blue]; x2 = the block [color yellow]; PutOn x1, x2", "OK."
expect b2, "x1 = the block [color blue]; x2 = the block [color yellow]; PutOn x1, x2", "OK."
check relations.binary.on(w2, w2.thing("b3"), w2.thing("b6")), "the blue block is on the yellow block"
check relations.binary.on(w2, w2.thing("c2"), w2.thing("b3")) or relations.binary.on(w2, w2.thing("c2"), w2.thing("b6")),
  "there was room for both, so the blue cylinder stayed"
expect b2, "x1 = the cylinder [color yellow]; x2 = the block [color blue]; PutOn x1, x2", "OK."
expect b2, "x1 = the block [color yellow]; e1 = event ClearOff x1; Ask why e1", "To get rid of it."
expect b2, "e1 = event Do; Ask why e1", "To clean off the yellow cylinder."
expect b2, "e1 = event Do; Ask why e1", "To put it on the blue block."
expect b2, "e1 = event Do; Ask why e1", "Because you asked me to."

print checks + " checks, " + failures + " failures."
exit (failures > 0)
