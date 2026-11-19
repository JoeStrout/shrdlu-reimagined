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
//
// Standing orders ("Never touch a green object", "Keep all the cubes in the
// box") are kept by the brain, which the planner asks (as `rules`) before
// each step:
//   rules.forbids(goal)               is this goal against an order?  Every
//                                     goal is checked as it's set up.
//   rules.placementProblem(thing, p)  would setting the thing down at this
//                                     placement break an order?
// Each returns null if all is well, or the reply saying which order is in
// the way ("I can't.  You told me not to touch the blue block.").  Finding
// space skips places that would break an order, and getting rid of
// something tries other places than the table, if the table won't do.

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
Goal.verb = null      // for a goal the user asked for, the verb they used ("drop")
Goal.near = null      // for a putOn: where on the target, as {rel, other} ("next to
                      // the blue block") or {at: [x, z]} (back where it was)
Goal.place = null     // for a getRidOf: where it's going (the table, unless an
                      // order rules that out)

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
Planner.rules = null    // what keeps the standing orders (the brain), or null
Planner.vetoed = null   // the last reply from rules about a place, while finding space

Planner.make = function(theWorld)
	p = new Planner
	p.world = theWorld
	return p
end function

Planner.now = function
	return [self.world.turn, self.world.step]
end function

// Work on a goal: record it, run its procedure, and note how it went.
// Returns null on success, or the reason it failed.  `near` is for a putOn
// that says where on the target (see Goal.near).
Planner.achieve = function(kind, args, near=null)
	w = self.world
	g = new Goal
	g.id = "g" + (w.goals.len + 1)
	g.kind = kind
	g.args = args
	g.parent = w.currentGoal
	g.children = []
	g.turn = w.turn
	g.status = "active"
	if kind == "putOn" then g.near = near
	g.start = self.now
	if g.parent then g.parent.children.push g
	w.goals.push g

	w.currentGoal = g
	// Is this against a standing order?  (A getRidOf is checked once we
	// know where it's going.)
	problem = null
	if self.rules and kind != "getRidOf" then problem = self.rules.forbids(g)
	if problem then
		// (Nothing to do.)
	else if kind == "grasp" then
		problem = self.grasp(args[0])
	else if kind == "putOn" then
		problem = self.putOn(args[0], args[1], near)
	else if kind == "clearOff" then
		problem = self.clearOff(args[0])
	else if kind == "getRidOf" then
		problem = self.getRidOf(args[0])
	else if kind == "stack" then
		// (For a stack, `near` says whether to keep the order given; see
		// Brain.build.)
		problem = self.stack(args, near == "ordered")
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

// Put one thing on (or in) another, perhaps at a particular place on it
// (see Goal.near).
Planner.putOn = function(thing, target, near=null)
	if refEquals(thing, target) then return "I can't put something on itself."
	if target.shape == "pyramid" then return "I can't balance anything on a pyramid."
	if not thing.movable then return "I can't move " + self.name(thing) + "."
	if near and near.hasIndex("other") and refEquals(near.other, thing) then return "I can't put something next to itself."
	// Already there?
	if self.restsOnlyOn(thing, target) and (near == null or self.isNear(thing, near)) then return null
	// If we're holding the thing to put it on (or next to), set that down
	// first: "Put Bob under the blue block", with Bob in the hand.
	held = self.world.hand.holding
	if refEquals(held, target) or (near and near.hasIndex("other") and refEquals(held, near.other)) then
		problem = self.achieve("getRidOf", [held])
		if problem then return problem
	end if
	return self.moveOnto(thing, target, near)
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
// If an order rules that out ("Never put a pyramid on the table"), then
// somewhere else: in the box, or on top of some block.  (That's a putOn
// of its own, so "Why did you put the green pyramid in the box?" gets "To
// get rid of it.")
Planner.getRidOf = function(thing)
	w = self.world
	g = w.currentGoal
	g.place = w.table
	if self.restsOnlyOn(thing, w.table) then return null
	if not self.rules then return self.moveOnto(thing, w.table)
	firstProblem = null
	for place in self.placesFor(thing)
		g.place = place
		problem = self.rules.forbids(g)
		if not problem then
			if refEquals(place, w.table) then
				problem = self.moveOnto(thing, place)
			else
				problem = self.achieve("putOn", [thing, place])
			end if
			if not problem then return null
		end if
		if firstProblem == null then firstProblem = problem
		// Try somewhere else only if an order was what got in the way.
		if not self.rules.isOrderProblem(problem) then break
	end for
	g.place = w.table
	return firstProblem
end function

// Where something could go to be out of the way, best first: the table,
// then the box (unless it's in there already), then the tops of the blocks
// that have nothing on them, nearest first.  Not a block the goals above
// this one are about, since those are being worked on.  (But the box will
// do even if something else is going into it, unless we're emptying it.)
Planner.placesFor = function(thing)
	w = self.world
	busy = [thing]
	emptying = false
	g = w.currentGoal
	while g
		busy += g.args
		if g.kind == "clearOff" and g.args[0].shape == "box" then emptying = true
		g = g.parent
	end while
	result = [w.table]
	tops = []
	for t in w.things
		if t.shape == "table" or t.shape == "pyramid" then continue
		if t.shape == "box" then
			if not emptying and not containsRef(thing.supporters, t) then result.push t
			continue
		end if
		if containsRef(busy, t) then continue
		if not w.isClear(t) or refEquals(t, w.hand.holding) then continue
		dx = t.x - thing.x
		dz = t.z - thing.z
		tops.push {"thing": t, "dist": dx*dx + dz*dz}
	end for
	tops.sort "dist"
	for t in tops
		result.push t.thing
	end for
	return result
end function

// Why a pyramid can't be under anything.  (The brain says it too, when
// asked "Can a pyramid support a pyramid?")
pyramidRule = "Nothing will stay on top of a pyramid."

// Stack things up, one on another.  The biggest goes at the bottom, and a
// pyramid (only one!) can only go on top.  Of two the same size, one
// standing on the table goes below, so the stack stands on the table.
//
// With ordered, the things go up in the order given instead, bottom first:
// that's how to build something taught by example, like a steeple.
Planner.stack = function(things, ordered=false)
	if things.len < 2 then return "I need at least two things to make a stack."
	if ordered then
		// The bottom one stands on the table (or in the box), so that the
		// stack is just these things.
		base = things[0]
		if base.supporters.len != 1 or (base.supporters[0].shape != "table" and base.supporters[0].shape != "box") then
			problem = self.achieve("getRidOf", [base])
			if problem then return problem
		end if
		for i in range(1, things.len - 1)
			if things[i-1].shape == "pyramid" then return "I can't. " + pyramidRule
			problem = self.achieve("putOn", [things[i], things[i-1]])
			if problem then return problem
		end for
		return null
	end if
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
Planner.moveOnto = function(thing, target, near=null)
	w = self.world
	spot = self.findSpace(thing, target, near)
	// No room on top of something?  Clear it off.  (But not the table, and
	// not the box: emptying the box to put something into it would be silly.)
	if spot == null and target.shape != "table" and target.shape != "box" and not w.isClear(target) then
		problem = self.achieve("clearOff", [target])
		if problem then return problem
		spot = self.findSpace(thing, target, near)
	end if
	if spot == null then return self.noRoom(thing, target, near)
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
	spot = self.findSpace(thing, target, near)
	if spot == null then return self.noRoom(thing, target, near)
	w.moveTo spot[0], spot[1]
	return w.ungrasp
end function

Planner.noRoom = function(thing, target, near=null)
	// If there was room, but an order ruled it out, say so.
	if self.vetoed then return self.vetoed
	// (The place comes first: "There's no room for the green cube which is
	// on the red block in the box" would be hard to follow.)
	place = speech.placePhrase(self.world, target)
	if near and near.hasIndex("rel") then place = " " + speech.relationPhrase(self.world, near.rel, near.other)
	return "There's no room" + place + " for " + self.name(thing) + "."
end function

// Is the thing where `near` says (see Goal.near)?
Planner.isNear = function(thing, near)
	if near.hasIndex("at") then
		return abs(thing.x - near.at[0]) < geometry.epsilon and abs(thing.z - near.at[1]) < geometry.epsilon
	end if
	return relations.binary[near.rel](self.world, thing, near.other)
end function

// Would the thing be where `near` says, if it rested at this placement?
// (We move it there for a moment to see, and then put it back.)
Planner.wouldBeNear = function(thing, placement, near)
	saved = thing.pos
	thing.pos = [placement.x, placement.y, placement.z]
	result = self.isNear(thing, near)
	thing.pos = saved
	return result
end function

//----------------------------------------------------------------------
// Finding space
//
// Try every grid point on the target's top, nearest first, and take the
// first one where the thing would rest on the target (and only the target)
// and stay put.  Spots with some elbow room are preferred, so that things
// don't end up crammed against each other.
//----------------------------------------------------------------------

//
// With `near` (see Goal.near), only spots that put the thing there will do,
// and we look near the other thing first.
Planner.findSpace = function(thing, target, near=null)
	w = self.world
	b = relations.bounds(target)
	// Back to just where it was?
	if near and near.hasIndex("at") then
		p = w.placementFor(thing, near.at[0], near.at[1])
		self.vetoed = null
		if not p.ok or p.supporters.len != 1 or not refEquals(p.supporters[0], target) then return null
		if self.rules then self.vetoed = self.rules.placementProblem(thing, p)
		if self.vetoed then return null
		return near.at
	end if
	if target.shape == "table" then
		// Somewhere near where the thing is now, in steps of half a unit.
		center = [thing.x, thing.z]
		step = 0.5
	else if target.shape == "box" then
		// Into the box from the side nearest the thing, which packs things
		// toward the walls and leaves room for more.
		center = [thing.x, thing.z]
		step = geometry.gridSize
	else
		center = [target.x, target.z]
		step = geometry.gridSize
	end if
	// Next to something (or to its left...): look near it first.
	if near and near.other.shape != "table" then
		center = [near.other.x, near.other.z]
		step = 0.5
	end if
	spots = []
	for x in range(b.minX, b.maxX, step)
		for z in range(b.minZ, b.maxZ, step)
			dx = x - center[0]
			dz = z - center[1]
			spots.push {"x": x, "z": z, "dist": dx*dx + dz*dz}
		end for
	end for
	spots.sort "dist"
	fallback = null
	self.vetoed = null
	for s in spots
		p = w.placementFor(thing, s.x, s.z)
		if not p.ok or p.supporters.len != 1 or not refEquals(p.supporters[0], target) then continue
		if near and not self.wouldBeNear(thing, p, near) then continue
		if self.rules then
			problem = self.rules.placementProblem(thing, p)
			if problem then
				self.vetoed = problem
				continue
			end if
		end if
		self.vetoed = null
		if self.elbowRoom(thing, s.x, s.z, target) >= 0.5 then return [s.x, s.z]
		if fallback == null then fallback = [s.x, s.z]
	end for
	if fallback then self.vetoed = null
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
