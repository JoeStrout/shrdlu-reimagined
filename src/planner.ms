// planner.ms
//
// The planner: how the robot gets things done.
//
// The world only knows three primitive actions: move the hand, grasp, and
// let go.  Everything else is a *goal procedure* here, which works by setting
// itself smaller goals.  To put the red cube on the green one, say, the robot
// may first have to clear off the green one, which means getting rid of the
// pyramid on top of it, which means picking up the pyramid, and so on.
//
// Every goal is recorded, with a link to the goal it was serving (its
// parent).  That record is the robot's memory of *why* it did things:
//
//   stack up the red cube, the red block and the green cube   (you asked)
//     put the green cube on the red block
//       clear off the red block
//         get rid of the green pyramid
//           pick up the green pyramid
//     ...
//
// "Why did you pick up the green pyramid?"  Look at its parent: "To get rid
// of it."  "Why did you do that?"  Up one more: "To clean off the red
// block."  At the top: "Because you asked me to."  And "How did you do it?"
// reads the children instead.  (See notes/design-world-and-icl.md §1.6.)
//
// A goal procedure returns null when it succeeds, or a reply explaining why
// it couldn't.

import "geometry"
import "world"
import "relations"
import "speech"

containsRef = @world.containsRef

//----------------------------------------------------------------------
// Goal: one thing the robot set out to do.
//----------------------------------------------------------------------

Goal = {}
Goal.id = ""          // "g1", "g2", ...
Goal.kind = ""        // grasp, putOn, clearOff, getRidOf, stack
Goal.args = null      // the Things it's about
Goal.parent = null    // the goal this one serves, or null if the user asked for it
Goal.children = null  // the goals set up to achieve this one, in order
Goal.turn = 0         // which of the user's sentences started it all
Goal.status = ""      // "active", "done", or "failed"
Goal.start = null     // [turn, step] when work on it began
Goal.finish = null    // [turn, step] when it finished

// The goal at the top of this one's chain: the thing the user asked for.
Goal.root = function
	g = self
	while g.parent
		g = g.parent
	end while
	return g
end function

//----------------------------------------------------------------------
// Planner
//----------------------------------------------------------------------

Planner = {}
Planner.world = null

Planner.make = function(theWorld)
	p = new Planner
	p.world = theWorld
	return p
end function

Planner.now = function
	return [self.world.turn, self.world.step]
end function

// Work on a goal: record it, run its procedure, and note how it went.
// Returns null on success, or the reason it failed.
Planner.achieve = function(kind, args)
	w = self.world
	g = new Goal
	g.id = "g" + (w.goals.len + 1)
	g.kind = kind
	g.args = args
	g.parent = w.currentGoal
	g.children = []
	g.turn = w.turn
	g.status = "active"
	g.start = self.now
	if g.parent then g.parent.children.push g
	w.goals.push g

	w.currentGoal = g
	if kind == "grasp" then
		problem = self.grasp(args[0])
	else if kind == "putOn" then
		problem = self.putOn(args[0], args[1])
	else if kind == "clearOff" then
		problem = self.clearOff(args[0])
	else if kind == "getRidOf" then
		problem = self.getRidOf(args[0])
	else if kind == "stack" then
		problem = self.stack(args)
	else
		problem = "I don't know how to " + kind + "."
	end if
	w.currentGoal = g.parent

	g.finish = self.now
	if problem then g.status = "failed" else g.status = "done"
	return problem
end function

// Is this thing resting on that one, and nothing else?
Planner.restsOnlyOn = function(thing, target)
	return thing.supporters.len == 1 and refEquals(thing.supporters[0], target)
end function

// Shorthand for naming things in replies.
Planner.name = function(thing)
	return speech.nameFor(self.world, thing)
end function

//----------------------------------------------------------------------
// The goal procedures
//----------------------------------------------------------------------

// Pick something up.  First empty the hand, and clear off the thing.
Planner.grasp = function(thing)
	w = self.world
	if refEquals(w.hand.holding, thing) then return null
	if not thing.movable then return "I can't pick up " + self.name(thing) + "."
	if w.hand.holding then
		problem = self.achieve("getRidOf", [w.hand.holding])
		if problem then return problem
	end if
	if not w.isClear(thing) then
		problem = self.achieve("clearOff", [thing])
		if problem then return problem
	end if
	w.moveTo thing.x, thing.z
	return w.grasp(thing)
end function

// Put one thing on (or in) another.
Planner.putOn = function(thing, target)
	if refEquals(thing, target) then return "I can't put something on itself."
	if target.shape == "pyramid" then return "I can't balance anything on a pyramid."
	if not thing.movable then return "I can't move " + self.name(thing) + "."
	if self.restsOnlyOn(thing, target) then return null   // already there
	return self.moveOnto(thing, target)
end function

// Get everything off the top of something.
Planner.clearOff = function(thing)
	w = self.world
	if thing.shape == "table" then return "I can't clear off the whole table."
	for attempt in range(1, 20)
		onTop = w.thingsOn(thing)
		if not onTop then return null
		problem = self.achieve("getRidOf", [onTop[0]])
		if problem then return problem
	end for
	return "I couldn't get everything off " + self.name(thing) + "."
end function

// Put something out of the way: somewhere on the table near where it is.
Planner.getRidOf = function(thing)
	if self.restsOnlyOn(thing, self.world.table) then return null
	return self.moveOnto(thing, self.world.table)
end function

// Why a pyramid can't be under anything.  (The brain says it too, when
// asked "Can a pyramid support a pyramid?")
pyramidRule = "Nothing will stay on top of a pyramid."

// Stack things up, one on another.  The biggest goes at the bottom, and a
// pyramid (only one!) can only go on top.  Of two the same size, one
// standing on the table goes below, so the stack stands on the table.
Planner.stack = function(things)
	if things.len < 2 then return "I need at least two things to make a stack."
	blocks = []
	pyramids = []
	for t in things
		size = t.volume
		if self.restsOnlyOn(t, self.world.table) then size += 0.001   // (just a tie-breaker)
		if t.shape == "pyramid" then pyramids.push t else blocks.push {"thing": t, "size": size}
	end for
	if pyramids.len > 1 then return "I can't. " + pyramidRule
	blocks.sort "size", false
	order = []
	for b in blocks
		order.push b.thing
	end for
	order += pyramids
	for i in range(1, order.len - 1)
		problem = self.achieve("putOn", [order[i], order[i-1]])
		if problem then return problem
	end for
	return null
end function

//----------------------------------------------------------------------
// The work shared by putOn and getRidOf: grasp the thing, carry it over to
// a free spot on the target, and let go.  (Not a goal of its own; it's how
// those two goals are carried out.)
//----------------------------------------------------------------------
Planner.moveOnto = function(thing, target)
	w = self.world
	spot = self.findSpace(thing, target)
	// No room on top of something?  Clear it off.  (But not the table, and
	// not the box: emptying the box to put something into it would be silly.)
	if spot == null and target.shape != "table" and target.shape != "box" and not w.isClear(target) then
		problem = self.achieve("clearOff", [target])
		if problem then return problem
		spot = self.findSpace(thing, target)
	end if
	if spot == null then return self.noRoom(thing, target)
	// Clear the thing off here, rather than leaving it to grasp, so that the
	// record says we cleared it off in order to move it.
	if not w.isClear(thing) then
		problem = self.achieve("clearOff", [thing])
		if problem then return problem
	end if
	if not refEquals(w.hand.holding, thing) then
		problem = self.achieve("grasp", [thing])
		if problem then return problem
	end if
	// Clearing things off may have changed what's free, so look again.
	spot = self.findSpace(thing, target)
	if spot == null then return self.noRoom(thing, target)
	w.moveTo spot[0], spot[1]
	return w.ungrasp
end function

Planner.noRoom = function(thing, target)
	return "There's no room for " + self.name(thing) + speech.placePhrase(self.world, target) + "."
end function

//----------------------------------------------------------------------
// Finding space
//
// Try every grid point on the target's top, nearest first, and take the
// first one where the thing would rest on the target (and only the target)
// and stay put.  Spots with some elbow room are preferred, so that things
// don't end up crammed against each other.
//----------------------------------------------------------------------

Planner.findSpace = function(thing, target)
	w = self.world
	b = relations.bounds(target)
	if target.shape == "table" then
		// Somewhere near where the thing is now, in steps of half a unit.
		near = [thing.x, thing.z]
		step = 0.5
	else if target.shape == "box" then
		// Into the box from the side nearest the thing, which packs things
		// toward the walls and leaves room for more.
		near = [thing.x, thing.z]
		step = geometry.gridSize
	else
		near = [target.x, target.z]
		step = geometry.gridSize
	end if
	spots = []
	for x in range(b.minX, b.maxX, step)
		for z in range(b.minZ, b.maxZ, step)
			dx = x - near[0]
			dz = z - near[1]
			spots.push {"x": x, "z": z, "dist": dx*dx + dz*dz}
		end for
	end for
	spots.sort "dist"
	fallback = null
	for s in spots
		p = w.placementFor(thing, s.x, s.z)
		if not p.ok or p.supporters.len != 1 or not refEquals(p.supporters[0], target) then continue
		if self.elbowRoom(thing, s.x, s.z, target) >= 0.5 then return [s.x, s.z]
		if fallback == null then fallback = [s.x, s.z]
	end for
	return fallback
end function

// How far a thing at (x, z) would be from its nearest neighbor on the same
// surface.
Planner.elbowRoom = function(thing, x, z, target)
	mine = relations.polyBounds(thing.footprintAt(x, z))
	room = 999
	for other in self.world.thingsOn(target)
		if refEquals(other, thing) then continue
		gap = relations.boundsGap(mine, relations.bounds(other))
		if gap < room then room = gap
	end for
	return room
end function
