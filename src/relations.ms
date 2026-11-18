// relations.ms
//
// The relations the robot can talk about: "on", "in", "behind", "taller
// than", "big", and so on.  None of these are stored anywhere; each one is
// worked out from the world model whenever it's asked.
//
// Each relation is a small function, collected into tables by kind, so the
// brain can look up an ICL predicate by name:
//
//   unary[pred](world, thing)              [held], [clear], [supported]
//   valued[pred](world, thing, word)       [color red], [size big]
//   binary[pred](world, thing, other)      [on x2], [taller x2]
//   superlatives[pred]                     [biggest], [littlest] (these pick
//                                          the extremes from a whole set)
//
// Stacks are worked out here too (see stacks, below): they aren't things
// in the world, but the brain can talk about them as if they were.
//
// See notes/design-world-and-icl.md §1.7.  The definitions of "behind",
// "left of" and so on are first guesses, to be tuned against the Winograd
// dialogue.

import "geometry"
import "world"

eps = geometry.epsilon
containsRef = @world.containsRef

//----------------------------------------------------------------------
// Helpers
//----------------------------------------------------------------------

// The rectangle a thing covers on the table, as seen from above.
bounds = function(thing)
	return polyBounds(thing.footprint)
end function

// The smallest rectangle around a polygon: {minX, maxX, minZ, maxZ}.
polyBounds = function(poly)
	b = {"minX": poly[0][0], "maxX": poly[0][0], "minZ": poly[0][1], "maxZ": poly[0][1]}
	for p in poly
		if p[0] < b.minX then b.minX = p[0]
		if p[0] > b.maxX then b.maxX = p[0]
		if p[1] < b.minZ then b.minZ = p[1]
		if p[1] > b.maxZ then b.maxZ = p[1]
	end for
	return b
end function

// How far apart two things are, as seen from above: the larger of the gaps
// along x and along z.  Zero (or less) means their footprints touch or overlap.
gapBetween = function(a, b)
	return boundsGap(bounds(a), bounds(b))
end function

// The same, for two rectangles from polyBounds.
boundsGap = function(ba, bb)
	gapX = ba.minX - bb.maxX
	if bb.minX - ba.maxX > gapX then gapX = bb.minX - ba.maxX
	gapZ = ba.minZ - bb.maxZ
	if bb.minZ - ba.maxZ > gapZ then gapZ = bb.minZ - ba.maxZ
	if gapX > gapZ then return gapX
	return gapZ
end function

// Everything under a thing: its supporters, their supporters, and so on
// down to the table.
allBelow = function(thing)
	result = []
	toDo = thing.supporters[:]
	while toDo
		t = toDo.pop
		if containsRef(result, t) then continue
		result.push t
		for s in t.supporters
			toDo.push s
		end for
	end while
	return result
end function

// Is this thing "big", "small", or neither?  Size words are relative: a
// thing is big if its volume is in the upper half of the range for things
// of the same shape.  (If they're all the same size, it's neither.)  We
// judge sizes by ratio, as people do: a cube twice as wide is eight times
// the volume, so the middle of the range is the geometric mean of the
// ends, not the average.  In Winograd's scene that makes both green cubes
// large (volume 8, where the blocks range from 1 to 16).
//
// The same goes for height ("tall", "short") and breadth ("wide",
// "narrow"): pass the measure to use.
sizeClass = function(theWorld, thing, measure=null)
	if @measure == null then measure = @volumeOf
	lo = null
	hi = null
	for t in theWorld.things
		if t.shape != thing.shape then continue
		v = measure(t)
		if lo == null or v < lo then lo = v
		if hi == null or v > hi then hi = v
	end for
	if lo == null or hi - lo < eps then return null
	middle = sqrt(hi * lo)
	if measure(thing) > middle + eps then return "big"
	if measure(thing) < middle - eps then return "small"
	return null
end function

// Words that mean "big" or "small".
sizeWords = {"big": "big", "large": "big", "huge": "big",
  "small": "small", "little": "small", "tiny": "small"}

// Does this thing fit a noun like "block" or "pyramid"?
// "Thing" fits anything (so "What is it on?" can be answered "The table."),
// but "object" fits only what's on the table ("How many objects did you
// touch?").  "Stack" fits only stacks, which aren't in the world's list of
// things; see stacks.
nounFits = function(thing, noun)
	if noun == "cube" then return thing.shape == "block" and thing.isCube
	if noun == "object" then return thing.shape != "table"
	if noun == "thing" then return thing.shape != "stack"
	return thing.shape == noun
end function

// The nouns that nounFits understands.
nouns = ["block", "cube", "pyramid", "cylinder", "box", "table", "thing", "object", "stack"]

//----------------------------------------------------------------------
// Unary relations: true or false of a single thing.
//----------------------------------------------------------------------

unary = {}
unary.held = function(theWorld, a)
	return refEquals(theWorld.hand.holding, a)
end function
unary.clear = function(theWorld, a)
	return theWorld.isClear(a)
end function
// "Is the box empty?"  Nothing in it, or on it.
unary.empty = function(theWorld, a)
	return theWorld.thingsOn(a).len == 0
end function
// "Is it supported?"  Resting on something (not held, and not the table).
unary.supported = function(theWorld, a)
	return a.supporters.len > 0
end function

//----------------------------------------------------------------------
// Valued relations: a thing and a word.
//----------------------------------------------------------------------

valued = {}
valued.color = function(theWorld, a, value)
	return a.color == value
end function
valued.size = function(theWorld, a, value)
	if not sizeWords.hasIndex(value) then return false
	return sizeClass(theWorld, a) == sizeWords[value]
end function
// [height tall], [height short]
valued.height = function(theWorld, a, value)
	if value == "tall" then want = "big" else want = "small"
	return sizeClass(theWorld, a, @heightOf) == want
end function
// [breadth wide], [breadth narrow]
valued.breadth = function(theWorld, a, value)
	if value == "wide" then want = "big" else want = "small"
	return sizeClass(theWorld, a, @breadthOf) == want
end function

//----------------------------------------------------------------------
// Binary relations: is `a` related this way to `b`?
//----------------------------------------------------------------------

binary = {}

// Support: "on" means directly on.
binary.on = function(theWorld, a, b)
	return containsRef(a.supporters, b)
end function
binary.supports = function(theWorld, a, b)
	return containsRef(b.supporters, a)
end function

// "Above" and "below" follow the support chain any distance.
binary.above = function(theWorld, a, b)
	return containsRef(allBelow(a), b)
end function
binary.below = function(theWorld, a, b)
	return containsRef(allBelow(b), a)
end function

// "In the box" counts anything whose support chain reaches the box, so a
// block stacked on a block in the box is in the box too.
// A stack contains its parts.
binary["in"] = function(theWorld, a, b)
	if b.shape == "stack" then return containsRef(b.parts, a)
	return b.shape == "box" and containsRef(allBelow(a), b)
end function
binary.contains = function(theWorld, a, b)
	if a.shape == "stack" then return containsRef(a.parts, b)
	return a.shape == "box" and containsRef(allBelow(b), a)
end function

// Touching: one rests on the other, or they stand side by side with no gap
// and some overlap in height.
binary.touches = function(theWorld, a, b)
	if containsRef(a.supporters, b) or containsRef(b.supporters, a) then return true
	if gapBetween(a, b) > eps then return false
	return a.y < b.top - eps and b.y < a.top - eps
end function

// Next to: standing at the same level, no more than half a unit apart.
// (Not the table, which everything on it stands in.)
binary.nextTo = function(theWorld, a, b)
	if a.shape == "table" or b.shape == "table" then return false
	if abs(a.y - b.y) > eps then return false
	return gapBetween(a, b) <= 0.5 + eps
end function

// Directions, as seen by the user at the front of the table.  `a` is behind
// `b` if a's center is at or beyond b's back edge (and so on for the others).
// The table is under everything, so it's in no direction from anything.
// But something can be at the back of the table, or on its left: then
// it's in the back third, or the left third (see tableSide).
binary.behind = function(theWorld, a, b)
	if a.shape == "table" then return false
	if b.shape == "table" then return tableSide(a, b, "back")
	return a.z <= bounds(b).minZ + eps
end function
binary.inFrontOf = function(theWorld, a, b)
	if a.shape == "table" then return false
	if b.shape == "table" then return tableSide(a, b, "front")
	return a.z >= bounds(b).maxZ - eps
end function
binary.leftOf = function(theWorld, a, b)
	if a.shape == "table" then return false
	if b.shape == "table" then return tableSide(a, b, "left")
	return a.x <= bounds(b).minX + eps
end function
binary.rightOf = function(theWorld, a, b)
	if a.shape == "table" then return false
	if b.shape == "table" then return tableSide(a, b, "right")
	return a.x >= bounds(b).maxX - eps
end function

// Is the thing's center in that third of the table: "left", "right",
// "back" or "front"?
tableSide = function(thing, table, side)
	tb = bounds(table)
	width = tb.maxX - tb.minX
	depth = tb.maxZ - tb.minZ
	if side == "left" then return thing.x < tb.minX + width/3
	if side == "right" then return thing.x > tb.maxX - width/3
	if side == "back" then return thing.z < tb.minZ + depth/3
	return thing.z > tb.maxZ - depth/3
end function

// Comparisons.  "Wide" uses breadth (the larger horizontal side), and "big"
// uses volume.
binary.taller = function(theWorld, a, b)
	return a.height > b.height + eps
end function
binary.shorter = function(theWorld, a, b)
	return a.height < b.height - eps
end function
binary.wider = function(theWorld, a, b)
	return a.breadth > b.breadth + eps
end function
binary.narrower = function(theWorld, a, b)
	return a.breadth < b.breadth - eps
end function
// "As tall as" means at least as tall: the same height or taller.
binary.asTall = function(theWorld, a, b)
	return a.height >= b.height - eps
end function
binary.asWide = function(theWorld, a, b)
	return a.breadth >= b.breadth - eps
end function
binary.asBig = function(theWorld, a, b)
	return a.volume >= b.volume - eps
end function
binary.bigger = function(theWorld, a, b)
	return a.volume > b.volume + eps
end function
binary.smaller = function(theWorld, a, b)
	return a.volume < b.volume - eps
end function

//----------------------------------------------------------------------
// Superlatives: from a set of things, keep the one(s) at an extreme.
// Each entry is [measure, direction], where direction 1 means "most".
//----------------------------------------------------------------------

volumeOf = function(t); return t.volume; end function
heightOf = function(t); return t.height; end function
breadthOf = function(t); return t.breadth; end function

superlatives = {
  "biggest": [@volumeOf, 1], "largest": [@volumeOf, 1],
  "smallest": [@volumeOf, -1], "littlest": [@volumeOf, -1],
  "tallest": [@heightOf, 1], "shortest": [@heightOf, -1],
  "widest": [@breadthOf, 1], "narrowest": [@breadthOf, -1]}

// The things in the list that are the most (or least) of something.
// Ties are all kept.  With a rank, the things in that place: rank 2 of
// "tallest" means the second tallest.  Things the same height share a
// place, so with blocks 4, 3, 2, 2 and 1 tall, the third tallest are the
// two that are 2 tall.
extreme = function(things, pred, rank=1)
	measure = @superlatives[pred][0]
	direction = superlatives[pred][1]
	// The different values, worst first (so the best is last).
	values = []
	for t in things
		v = measure(t) * direction
		found = false
		for u in values
			if abs(u - v) < eps then found = true
		end for
		if not found then values.push v
	end for
	values.sort
	if rank > values.len then return []
	wanted = values[values.len - rank]
	result = []
	for t in things
		if abs(measure(t) * direction - wanted) < eps then result.push t
	end for
	return result
end function

//----------------------------------------------------------------------
// Stacks.  A stack isn't a thing in the world: it's worked out from what
// rests on what.  It is two or more things, each resting on the one below
// (and only on it), from one standing on the table or in the box, up to
// one with nothing more on it.  So after Winograd's turn 17 there is one
// stack: the red block, the green cube, and the red cube on top.  Where
// two things rest side by side on one block, there are two stacks, which
// share what's below.
//
// A Stack is a Thing, so that relations like "to the left of" work on it:
// it stands where its bottom part stands, and is as tall as all its parts
// together.
//----------------------------------------------------------------------

Stack = new world.Thing
Stack.shape = "stack"
Stack.color = null
Stack.movable = false
Stack.parts = null      // the things in it, bottom first

Stack.volume = function
	total = 0
	for p in self.parts
		total += p.volume
	end for
	return total
end function

Stack.breadth = function
	widest = 0
	for p in self.parts
		if p.breadth > widest then widest = p.breadth
	end for
	return widest
end function

Stack.footprintAt = function(x, z)
	return self.parts[0].footprintAt(x, z)
end function

// Every stack in the world right now.  The same parts always give the same
// Stack object, so that a stack found twice is recognized as one.
stacks = function(theWorld)
	result = []
	for t in theWorld.things
		if t.supporters.len != 1 or not t.movable then continue
		base = t.supporters[0].shape
		if base == "table" or base == "box" then addStacksFrom theWorld, [t], result
	end for
	return result
end function

// Follow things up from the top of a partial stack, adding each finished
// stack to the result.
addStacksFrom = function(theWorld, parts, result)
	above = []
	for t in theWorld.thingsOn(parts[-1])
		if t.supporters.len == 1 then above.push t
	end for
	if not above then
		if parts.len > 1 then result.push stackOf(theWorld, parts)
		return
	end if
	for t in above
		addStacksFrom theWorld, parts + [t], result
	end for
end function

// The Stack made of these parts (bottom first), set to where they are now.
stackOf = function(theWorld, parts)
	ids = []
	for p in parts
		ids.push p.id
	end for
	key = ids.join(",")
	if not theWorld.hasIndex("stackMemo") then theWorld.stackMemo = {}
	if not theWorld.stackMemo.hasIndex(key) then
		s = new Stack
		s.id = "stack:" + key
		s.parts = parts
		s.names = []
		theWorld.stackMemo[key] = s
	end if
	s = theWorld.stackMemo[key]
	s.pos = parts[0].pos[:]
	s.size = [parts[0].size[0], parts[-1].top - parts[0].y, parts[0].size[2]]
	s.supporters = parts[0].supporters[:]
	return s
end function
