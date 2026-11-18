// world.ms
//
// The world model: every object on the table, what rests on what, the robot's
// hand, and a history of everything that has happened.
//
// This is the single source of truth about the world.  The 3D display only
// shows what's here (with some animation to make it look nice); the robot's
// "brain" asks questions of it and changes it.  Nothing here uses raylib, so
// this module can be tested from the plain command line.
//
// See notes/design-world-and-icl.md (Part 1) for the reasoning behind it.
//
// Coordinates: y is up, and the table top is at y = 0.  x runs left to right
// and z runs back to front, as seen from the front of the table, where the
// user sits.  The robot arm is mounted at the back.

import "geometry"

// Shorthand for checking whether a list contains a particular object (the
// very same one, not just one that looks the same).
containsRef = function(list, item)
	for x in list
		if refEquals(x, item) then return true
	end for
	return false
end function

//======================================================================
// Thing: anything physical in the world.
//
// Each kind of Thing (Block, Pyramid, ...) describes its own shape by
// answering three questions:
//   footprintAt(x, z): what area of the table it covers, centered at (x, z)
//   solidsAt(x, y, z): the space it fills, as a list of upright slabs
//   surfacesAt(x, y, z): the places on top of it where other things can rest
// Everything else (stacking, balancing, finding room) is worked out from those.
//======================================================================

Thing = {}
Thing.id = ""          // short internal name, like "b1"; shown in the under-the-hood view
Thing.shape = "thing"
Thing.color = "gray"
Thing.size = [1, 1, 1] // [width (x), height (y), depth (z)]
Thing.pos = [0, 0, 0]  // center of its bottom face
Thing.supporters = []  // the Things it rests on (each instance gets its own list)
Thing.names = []       // names the user has given it
Thing.owner = null
Thing.movable = true

// Make a new Thing of this kind.  (Call it on a kind: Block.make(...).)
Thing.make = function(id, color, size, pos=null)
	t = new self
	t.id = id
	t.color = color
	t.size = size[:]
	if pos == null then t.pos = [0, 0, 0] else t.pos = pos[:]
	t.supporters = []
	t.names = []
	return t
end function

Thing.width = function; return self.size[0]; end function
Thing.height = function; return self.size[1]; end function
Thing.depth = function; return self.size[2]; end function
Thing.x = function; return self.pos[0]; end function
Thing.y = function; return self.pos[1]; end function
Thing.z = function; return self.pos[2]; end function
Thing.top = function; return self.pos[1] + self.size[1]; end function
Thing.volume = function; return self.size[0] * self.size[1] * self.size[2]; end function

// "Width" in the everyday sense, for words like "narrower": the larger of
// its two horizontal dimensions.
Thing.breadth = function
	if self.size[0] > self.size[2] then return self.size[0]
	return self.size[2]
end function

// The x/z point it balances on.  For all of our shapes this is simply the
// center of the footprint, but the stability code always asks for it by this
// name, so that a lopsided shape could be added later.
Thing.centerOfMassAt = function(x, z)
	return [x, z]
end function

// The footprint, surfaces, and solids where the Thing actually is now.
Thing.footprint = function; return self.footprintAt(self.pos[0], self.pos[2]); end function
Thing.surfaces = function; return self.surfacesAt(self.pos[0], self.pos[1], self.pos[2]); end function
Thing.solids = function; return self.solidsAt(self.pos[0], self.pos[1], self.pos[2]); end function

// Default shape: a rectangular block.  Other kinds override what differs.
Thing.footprintAt = function(x, z)
	return geometry.rectPoly(x, z, self.size[0], self.size[2])
end function

// A "solid" is an upright slab of space: a polygon (seen from above) that
// fills everything from height `bottom` to height `top`.
Thing.solidsAt = function(x, y, z)
	return [{"poly": self.footprintAt(x, z), "bottom": y, "top": y + self.size[1]}]
end function

// A "surface" is a flat place that can hold things up: a polygon at height y.
// (A pyramid's surface is a single point instead, its apex.)
Thing.surfacesAt = function(x, y, z)
	return [{"poly": self.footprintAt(x, z), "y": y + self.size[1]}]
end function

// A plain description, like "red cube" or "green pyramid".  (Size words such
// as "big" and "little" depend on what else is around, so they're left to
// the brain.)
Thing.noun = function; return self.shape; end function
Thing.description = function
	return self.color + " " + self.noun
end function

//----------------------------------------------------------------------
// Block: a rectangular box shape.  A block whose sides are all the same
// is also a cube.
//----------------------------------------------------------------------
Block = new Thing
Block.shape = "block"
Block.isCube = function
	return self.size[0] == self.size[1] and self.size[1] == self.size[2]
end function
Block.noun = function
	if self.isCube then return "cube"
	return "block"
end function

//----------------------------------------------------------------------
// Pyramid: square or rectangular base, rising to a single point.
// Its top "surface" is just that point.  Something can rest on a pyramid's
// apex only if other supporters, at the same height, make up a support
// polygon with some area (see World.placementFor).
//----------------------------------------------------------------------
Pyramid = new Thing
Pyramid.shape = "pyramid"
Pyramid.surfacesAt = function(x, y, z)
	return [{"point": [x, z], "y": y + self.size[1]}]
end function
// For checking what's in the way, we treat the pyramid as if it filled its
// whole box.  That's a little cautious, and it's also what stops anything
// from being set down on a pyramid's sloping side.

//----------------------------------------------------------------------
// Cylinder: always standing on one flat end.  size[0] and size[2] are both
// its diameter.
//----------------------------------------------------------------------
Cylinder = new Thing
Cylinder.shape = "cylinder"
Cylinder.footprintAt = function(x, z)
	return geometry.circlePoly(x, z, self.size[0] / 2)
end function

//----------------------------------------------------------------------
// Box: an open-topped container.  Things inside rest on its floor; its four
// walls are in the way of anything that would overlap them.
//----------------------------------------------------------------------
Box = new Thing
Box.shape = "box"
Box.movable = false
Box.wallThickness = 0.15
Box.floorThickness = 0.1

// The open space inside the walls, as seen from above.
Box.interiorAt = function(x, z)
	t = self.wallThickness
	return geometry.rectPoly(x, z, self.size[0] - 2*t, self.size[2] - 2*t)
end function

Box.solidsAt = function(x, y, z)
	w = self.size[0]; h = self.size[1]; d = self.size[2]; t = self.wallThickness
	floorTop = y + self.floorThickness
	return [
		{"poly": geometry.rectPoly(x, z, w, d), "bottom": y, "top": floorTop},              // floor
		{"poly": geometry.rectPoly(x, z - d/2 + t/2, w, t), "bottom": y, "top": y + h},     // back wall
		{"poly": geometry.rectPoly(x, z + d/2 - t/2, w, t), "bottom": y, "top": y + h},     // front wall
		{"poly": geometry.rectPoly(x - w/2 + t/2, z, t, d), "bottom": y, "top": y + h},     // left wall
		{"poly": geometry.rectPoly(x + w/2 - t/2, z, t, d), "bottom": y, "top": y + h}]     // right wall
end function

// Only the floor inside the walls can hold things up.  (We don't let things
// balance on the thin tops of the walls.)
Box.surfacesAt = function(x, y, z)
	return [{"poly": self.interiorAt(x, z), "y": y + self.floorThickness}]
end function

//----------------------------------------------------------------------
// Table: the ground everything stands on.  Its top is at y = 0, so its
// "pos" is the center of that top.  It fills no space above y = 0.
//----------------------------------------------------------------------
Table = new Thing
Table.shape = "table"
Table.movable = false
Table.solidsAt = function(x, y, z); return []; end function
Table.surfacesAt = function(x, y, z)
	return [{"poly": self.footprintAt(x, z), "y": 0}]
end function
Table.top = function; return 0; end function

//======================================================================
// World: the whole scene, plus the hand and the history.
//======================================================================

World = {}

// How high the hand travels between actions.  It must be high enough to
// carry anything over the tallest stack.  (A fixed height is fine for now;
// later the hand could rise only as high as each move needs.)
World.cruiseHeight = 7

World.make = function(tableWidth=12, tableDepth=8)
	w = new World
	w.things = []
	w.table = Table.make("table", "wood", [tableWidth, 0, tableDepth])
	w.things.push w.table
	w.hand = {"holding": null, "pos": [0, World.cruiseHeight, -tableDepth/2]}
	w.history = []   // list of events, oldest first
	w.goals = []     // every goal the planner has worked on, oldest first
	w.currentGoal = null   // the goal being worked on now (set by the planner)
	w.turn = 0       // increases with each sentence from the user
	w.step = 0       // increases with each event within a turn
	return w
end function

// Look up a Thing by its id (or one of the names the user gave it).
World.thing = function(idOrName)
	for t in self.things
		if t.id == idOrName or hasName(t, idOrName) then return t
	end for
	return null
end function

// Does the thing have this name?  (In any case: "Bob" and "bob" are one
// name.)
hasName = function(thing, name)
	for n in thing.names
		if n.lower == name.lower then return true
	end for
	return false
end function

// The things that can be moved around (everything but the table and box).
World.movableThings = function
	result = []
	for t in self.things
		if t.movable then result.push t
	end for
	return result
end function

// What's resting directly on `thing`.
World.thingsOn = function(thing)
	result = []
	for t in self.things
		if containsRef(t.supporters, thing) then result.push t
	end for
	return result
end function

// Is nothing resting on `thing`?
World.isClear = function(thing)
	return self.thingsOn(thing).len == 0
end function

//----------------------------------------------------------------------
// Placement: where would a thing come to rest, and would it stay there?
//
// Imagine holding `thing` above the table, centered over (x, z), and letting
// it down slowly and straight down.  It stops at the first thing it touches,
// and whatever it touches holds it up.  Then we check:
//   1. Is it over the table at all?
//   2. Is the space it would fill actually free?
//   3. Do its supporters give it a "support polygon" with some area?
//      (A single pyramid tip is a point, and two tips make only a line:
//      nothing can balance on those.)
//   4. Is its center of mass over that support polygon?
//
// The result is a map:
//   ok           true if it would stay put
//   reason       if not: "offTable", "blocked", "noArea", or "unbalanced"
//   x, y, z      where it would rest (y is the height of its bottom)
//   supporters   the things it would rest on
//   supportPoly  the support polygon (useful for showing what happened)
//   blocker      for "blocked": the thing that's in the way
//----------------------------------------------------------------------
World.placementFor = function(thing, x, z)
	result = {"ok": false, "reason": "", "x": x, "y": 0, "z": z,
	  "supporters": [], "supportPoly": [], "blocker": null}
	footprint = thing.footprintAt(x, z)

	// 1. It has to be over the table.
	if not geometry.polyInside(footprint, self.table.footprint) then
		result.reason = "offTable"
		return result
	end if

	// Everything else in the world, except whatever is in the hand.
	others = []
	for t in self.things
		if refEquals(t, thing) or refEquals(t, self.hand.holding) then continue
		others.push t
	end for

	// Find every surface under the footprint, and the highest one.
	under = []      // list of [thing, surface]
	restY = 0
	for t in others
		for s in t.surfaces
			if s.hasIndex("point") then
				touching = geometry.pointInPoly(s.point, footprint)
			else
				touching = geometry.polysOverlap(s.poly, footprint)
			end if
			if not touching then continue
			under.push [t, s]
			if s.y > restY then restY = s.y
		end for
	end for
	result.y = restY

	// The supporters are everything whose surface is at exactly that height.
	contactPoints = []
	for pair in under
		t = pair[0]; s = pair[1]
		if abs(s.y - restY) > geometry.epsilon then continue
		if not containsRef(result.supporters, t) then result.supporters.push t
		// The contact region is where that surface meets our footprint.
		if s.hasIndex("point") then
			contactPoints.push s.point
		else
			contactPoints += geometry.clipPolygon(s.poly, footprint)
		end if
	end for

	// 2. The space it would fill must be free.
	top = restY + thing.height
	for t in others
		for solid in t.solids
			// Does this solid overlap our slab of space vertically...
			if solid.top <= restY + geometry.epsilon then continue
			if solid.bottom >= top - geometry.epsilon then continue
			// ...and horizontally?
			if geometry.polysOverlap(solid.poly, footprint) then
				result.reason = "blocked"
				result.blocker = t
				return result
			end if
		end for
	end for

	// 3. The support polygon must have some area.
	result.supportPoly = geometry.convexHull(contactPoints)
	if geometry.polyArea(result.supportPoly) < geometry.epsilon then
		result.reason = "noArea"
		return result
	end if

	// 4. The center of mass must be over the support polygon.
	if not geometry.pointInPoly(thing.centerOfMassAt(x, z), result.supportPoly) then
		result.reason = "unbalanced"
		return result
	end if

	result.ok = true
	return result
end function

// A short English explanation of why a placement failed (for debugging, and
// until the brain learns to say these things more gracefully).
World.explainPlacement = function(placement)
	r = placement.reason
	if r == "" then return "It fits."
	if r == "offTable" then return "That isn't on the table."
	if r == "blocked" then return "The " + placement.blocker.description + " is in the way."
	if r == "noArea" then return "It would have nothing to balance on but a point or an edge."
	if r == "unbalanced" then return "It would tip over."
	return "I can't put it there (" + r + ")."
end function

//----------------------------------------------------------------------
// History.
//
// Every change to the world is recorded as an event.  Each event remembers
// the time, what was done, and a snapshot of where everything was *just
// before*, so the brain can later answer questions about the past.
//----------------------------------------------------------------------

// Start a new turn of conversation.
World.beginTurn = function
	self.turn += 1
	self.step = 0
end function

// A compact record of where everything is and what holds it up.
World.snapshot = function
	snap = {}
	for t in self.things
		ids = []
		for s in t.supporters
			ids.push s.id
		end for
		snap[t.id] = {"pos": t.pos[:], "supporters": ids}
	end for
	if self.hand.holding then snap["(hand)"] = self.hand.holding.id
	return snap
end function

// Where everything was at a time ([turn, step], as goals record them):
// the snapshot taken just before the first event after that time, or now,
// if nothing has happened since.
World.snapshotAt = function(time)
	for e in self.history
		if e.time[0] > time[0] or (e.time[0] == time[0] and e.time[1] > time[1]) then return e.before
	end for
	return self.snapshot
end function

// Put everything where a snapshot says it was.  This is for looking at
// the past: take a snapshot of the present first, and restore that after.
World.restore = function(snap)
	for t in self.things
		if not snap.hasIndex(t.id) then continue
		t.pos = snap[t.id].pos[:]
		t.supporters = []
		for id in snap[t.id].supporters
			t.supporters.push self.thing(id)
		end for
	end for
	self.hand.holding = null
	if snap.hasIndex("(hand)") then self.hand.holding = self.thing(snap["(hand)"])
end function

World.record = function(action, info)
	self.step += 1
	event = {"time": [self.turn, self.step], "action": action,
	  "before": self.snapshot, "goal": self.currentGoal}
	for kv in info
		event[kv.key] = kv.value
	end for
	self.history.push event
	return event
end function

//----------------------------------------------------------------------
// The three primitive actions.  Everything the robot does is built from
// these.  Each returns null on success, or a string saying why it couldn't.
//----------------------------------------------------------------------

// Move the hand (and whatever it holds) to above the point (x, z).
World.moveTo = function(x, z)
	from = self.hand.pos[:]
	to = [x, World.cruiseHeight, z]
	self.record "moveTo", {"from": from, "to": to}
	self.hand.pos = to
	if self.hand.holding then
		held = self.hand.holding
		held.pos = [x, World.cruiseHeight - held.height, z]
	end if
	return null
end function

// Pick up `thing`.  The hand must be empty and directly above it, and
// nothing may be resting on it.
World.grasp = function(thing)
	if self.hand.holding then return "My hand is already full."
	if not thing.movable then return "I can't pick up the " + thing.shape + "."
	if not self.isClear(thing) then return "Something is on top of it."
	if abs(self.hand.pos[0] - thing.x) > geometry.epsilon or abs(self.hand.pos[2] - thing.z) > geometry.epsilon then
		return "My hand isn't above it."
	end if
	self.record "grasp", {"thing": thing, "from": thing.pos[:]}
	self.hand.holding = thing
	thing.supporters = []
	thing.pos = [thing.x, World.cruiseHeight - thing.height, thing.z]
	return null
end function

// Let go of whatever is in the hand, setting it down straight below.
// If it wouldn't stay put there, then normally we refuse; but with
// force = true we try anyway, and it falls off.  (The display shows it
// toppling; then it's back in the hand, and the world is unchanged.)
World.ungrasp = function(force=false)
	held = self.hand.holding
	if held == null then return "I'm not holding anything."
	x = self.hand.pos[0]; z = self.hand.pos[2]
	placement = self.placementFor(held, x, z)
	if not placement.ok then
		canTry = placement.reason == "noArea" or placement.reason == "unbalanced"
		if not force or not canTry then return self.explainPlacement(placement)
		self.record "failedPlace", {"thing": held, "placement": placement}
		return "It fell off."
	end if
	self.record "ungrasp", {"thing": held, "to": [x, placement.y, z],
	  "supporters": placement.supporters[:]}
	held.pos = [x, placement.y, z]
	held.supporters = placement.supporters
	self.hand.holding = null
	return null
end function

// Conveniences built from the primitives (handy for testing, and for the
// hard-coded demos until the planner exists).
World.pickUp = function(thing)
	self.moveTo thing.x, thing.z
	return self.grasp(thing)
end function

World.putAt = function(x, z, force=false)
	self.moveTo x, z
	return self.ungrasp(force)
end function

//----------------------------------------------------------------------
// Setting up a scene.
//
// A scene is a list of object specs, each a map like
//   {"id": "b1", "kind": "block", "color": "red", "size": [1,1,1], "at": [-4, 1.5]}
// "at" gives only x and z.  Each object is dropped into place in order, so
// list stacks from the bottom up, and the world works out the heights and
// supporters itself.  That way a scene can't describe an impossible
// arrangement: if something wouldn't fit or wouldn't balance, we say so.
//----------------------------------------------------------------------

World.kinds = {"block": Block, "pyramid": Pyramid, "cylinder": Cylinder, "box": Box}

// Add one object, dropping it into place.  Returns null, or a string
// explaining why it couldn't be placed.
World.addThing = function(spec)
	kind = World.kinds[spec.kind]
	x = geometry.snap(spec.at[0])
	z = geometry.snap(spec.at[1])
	thing = kind.make(spec.id, spec.color, spec.size)
	placement = self.placementFor(thing, x, z)
	if not placement.ok then
		return spec.id + ": " + self.explainPlacement(placement)
	end if
	thing.pos = [x, placement.y, z]
	thing.supporters = placement.supporters
	self.things.push thing
	return null
end function

// Build a whole scene.  Returns a list of problems (empty if all went well).
World.load = function(scene)
	problems = []
	for spec in scene
		problem = self.addThing(spec)
		if problem then problems.push problem
	end for
	return problems
end function

// A text summary of the world, for debugging: each thing and what it's on.
World.dump = function
	for t in self.things
		if t.shape == "table" then continue
		on = []
		for s in t.supporters
			on.push s.id
		end for
		where = "on " + on.join(", ")
		if refEquals(t, self.hand.holding) then where = "in the hand"
		print t.id + " (" + t.description + ") at " + t.pos + ", " + where
	end for
end function
