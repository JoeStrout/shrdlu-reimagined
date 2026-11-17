// testWorld.ms
//
// Tests for the geometry and world-model modules.  These don't need raylib;
// run them from the repo root with plain command-line MiniScript:
//
//   MS_IMPORT_PATH=src miniscript tests/testWorld.ms
//
// Each check prints a line only when it fails, and a summary at the end.

import "geometry"
import "world"
import "scenes"

failures = 0
checks = 0

check = function(condition, what)
	globals.checks += 1
	if condition then return
	globals.failures += 1
	print "FAILED: " + what
end function

near = function(a, b)
	return abs(a - b) < 0.001
end function

// Make a world from a little scene; complain if it didn't load cleanly.
build = function(scene)
	w = world.World.make
	problems = w.load(scene)
	check problems.len == 0, "scene loads cleanly: " + problems
	return w
end function

spec = function(id, kind, size, at)
	return {"id": id, "kind": kind, "color": "red", "size": size, "at": at}
end function

//--------------------------------------------------------------------
// Geometry
//--------------------------------------------------------------------
sq = geometry.rectPoly(0, 0, 2, 2)
check near(geometry.polyArea(sq), 4), "area of a 2x2 square"
check geometry.pointInPoly([0.5, 0.5], sq), "point inside square"
check not geometry.pointInPoly([1.5, 0], sq), "point outside square"
check geometry.pointInPoly([1, 0], sq), "point on edge counts as inside"
overlap = geometry.clipPolygon(sq, geometry.rectPoly(1, 1, 2, 2))
check near(geometry.polyArea(overlap), 1), "overlap of offset squares is 1x1"
check not geometry.polysOverlap(sq, geometry.rectPoly(2, 0, 2, 2)), "squares sharing an edge don't overlap"
check near(geometry.polyArea(geometry.convexHull([[0,0], [2,0], [1,1], [0,2], [2,2]])), 4), "hull ignores interior point"
check geometry.convexHull([[0,0], [1,0], [2,0]]).len == 2, "hull of points in a line is a segment"
check abs(geometry.polyArea(geometry.circlePoly(0, 0, 1, 64)) - pi) < 0.01, "64-gon area close to pi"
check geometry.snap(1.13) == 1.25, "snap to grid"

//--------------------------------------------------------------------
// Stacking and support
//--------------------------------------------------------------------
w = build([spec("a", "block", [1,1,1], [0, 0]), spec("b", "block", [1,1,1], [0, 0])])
a = w.thing("a"); b = w.thing("b")
check near(b.y, 1), "a block dropped on a block rests on top of it"
check world.containsRef(b.supporters, a), "the lower block supports the upper one"
check not w.isClear(a), "the lower block is not clear"
check w.isClear(b), "the upper block is clear"

// Overhang: a block centered over the edge is unbalanced; slightly off is ok.
w = build([spec("a", "block", [1,1,1], [0, 0])])
probe = world.Block.make("p", "blue", [1,1,1])
check w.placementFor(probe, 0.25, 0).ok, "small overhang is fine"
check w.placementFor(probe, 1, 0).ok, "fully beside it rests on the table"
p = w.placementFor(probe, 0.75, 0)
check p.reason == "unbalanced", "big overhang is unbalanced (got " + p.reason + ")"

// Pyramids: one tip or two tips can't support anything; three can.
w = build([spec("p1", "pyramid", [1,1,1], [0, 0])])
plate = world.Block.make("plate", "blue", [3, 0.5, 3])
check w.placementFor(plate, 0, 0).reason == "noArea", "nothing balances on one pyramid tip"
w = build([spec("p1", "pyramid", [1,1,1], [-1, 0]), spec("p2", "pyramid", [1,1,1], [1, 0])])
check w.placementFor(plate, 0, 0).reason == "noArea", "nothing balances on two pyramid tips"
w = build([spec("p1", "pyramid", [1,1,1], [-1, -1]), spec("p2", "pyramid", [1,1,1], [1, -1]),
  spec("p3", "pyramid", [1,1,1], [0, 1])])
p = w.placementFor(plate, 0, 0)
check p.ok, "a plate balances on three pyramid tips (got " + p.reason + ")"
check p.supporters.len == 3, "all three pyramids support the plate"

// A pyramid and a block of the same height can share a load.
w = build([spec("p1", "pyramid", [1,1,1], [-1, 0]), spec("a", "block", [1,1,1], [1, 0])])
check w.placementFor(plate, 0, 0).ok, "a pyramid and a block together can support a plate"

// Landing on a pyramid's slope is refused.
w = build([spec("p1", "pyramid", [1,2,1], [0, 0])])
small = world.Block.make("s", "blue", [1, 1, 1])
check w.placementFor(small, 0.75, 0).reason == "blocked", "can't rest on a pyramid's sloping side"

// An arch: two posts and a lintel.
w = build([spec("left", "block", [1,2,1], [-1, 0]), spec("right", "block", [1,2,1], [1, 0]),
  spec("lintel", "block", [3, 0.5, 1], [0, 0])])
lintel = w.thing("lintel")
check near(lintel.y, 2), "the lintel rests on top of the posts"
check lintel.supporters.len == 2, "the lintel has two supporters"

// Posts of different heights can't share the lintel; it rests on the taller one.
w = build([spec("left", "block", [1,2,1], [-1, 0]), spec("right", "block", [1,1,1], [1, 0])])
p = w.placementFor(world.Block.make("l", "blue", [3, 0.5, 1]), 0, 0)
check p.reason == "unbalanced", "a lintel on posts of unequal height tips (got " + p.reason + ")"

// Cylinders stack like blocks.
w = build([spec("c1", "cylinder", [1,1,1], [0, 0]), spec("c2", "cylinder", [1,1,1], [0, 0])])
check near(w.thing("c2").y, 1), "a cylinder stacks on a cylinder"

// The box: things inside rest on its floor; its walls are in the way.
w = build([spec("box", "box", [3, 1.5, 3], [0, 0]), spec("a", "block", [1,1,1], [0, 0])])
check world.containsRef(w.thing("a").supporters, w.thing("box")), "a block dropped into the box rests on the box"
check w.placementFor(probe, 1.5, 0).reason == "blocked", "the box wall is in the way"

// Off the edge of the table.
w = build([])
check w.placementFor(probe, 5.75, 0).reason == "offTable", "can't place off the table"

//--------------------------------------------------------------------
// Primitive actions and history
//--------------------------------------------------------------------
w = build([spec("a", "block", [1,1,1], [0, 0]), spec("b", "block", [1,1,1], [0, 0])])
a = w.thing("a"); b = w.thing("b")
w.beginTurn
check w.pickUp(a) != null, "can't pick up a block with something on it"
check w.pickUp(b) == null, "can pick up the top block"
check refEquals(w.hand.holding, b), "the hand holds what it picked up"
check w.isClear(a), "the lower block is clear once the top one is lifted"
check w.putAt(3, 0) == null, "can put it down on the table"
check near(b.y, 0) and near(b.x, 3), "it's where we put it"
check w.hand.holding == null, "the hand is empty again"
// (The failed pickUp of a still moved the hand, so that's an event too.)
check w.history.len == 5, "five events recorded (got " + w.history.len + ")"
check w.history[2].action == "grasp", "third event is the grasp"
check w.history[2].before.b.supporters == ["a"], "the snapshot remembers b was on a"

// A forced, unstable placement falls off and leaves the world unchanged.
w.pickUp b
result = w.putAt(0.75, 0, true)
check result == "It fell off.", "an unbalanced forced placement falls (got " + result + ")"
check refEquals(w.hand.holding, b), "after falling, it's back in the hand"
check w.history[-1].action == "failedPlace", "the failed attempt is recorded"
check w.putAt(0.75, 0) != null, "without force, an unbalanced placement is refused"

//--------------------------------------------------------------------
// The scenes load cleanly
//--------------------------------------------------------------------
for name in scenes.names
	w = world.World.make
	problems = w.load(scenes.byName[name])
	check problems.len == 0, "scene '" + name + "' loads: " + problems
end for

print checks + " checks, " + failures + " failures."
// Exit with a nonzero code if anything failed, so scripts can tell.
exit (failures > 0)
