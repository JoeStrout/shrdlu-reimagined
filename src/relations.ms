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
// of the same shape.  (If they're all the same size, it's neither.)
sizeClass = function(theWorld, thing)
	lo = null
	hi = null
	for t in theWorld.things
		if t.shape != thing.shape then continue
		v = t.volume
		if lo == null or v < lo then lo = v
		if hi == null or v > hi then hi = v
	end for
	if hi - lo < eps then return null
	middle = (hi + lo) / 2
	if thing.volume > middle + eps then return "big"
	if thing.volume < middle - eps then return "small"
	return null
end function

// Words that mean "big" or "small".
sizeWords = {"big": "big", "large": "big", "huge": "big",
  "small": "small", "little": "small", "tiny": "small"}

// Does this thing fit a noun like "block" or "pyramid"?
// "Thing" and "object" fit anything but the table.
nounFits = function(thing, noun)
	if noun == "cube" then return thing.shape == "block" and thing.isCube
	if noun == "thing" or noun == "object" then return thing.shape != "table"
	return thing.shape == noun
end function

// The nouns that nounFits understands.
nouns = ["block", "cube", "pyramid", "cylinder", "box", "table", "thing", "object"]

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
binary["in"] = function(theWorld, a, b)
	return b.shape == "box" and containsRef(allBelow(a), b)
end function
binary.contains = function(theWorld, a, b)
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
binary.nextTo = function(theWorld, a, b)
	if abs(a.y - b.y) > eps then return false
	return gapBetween(a, b) <= 0.5 + eps
end function

// Directions, as seen by the user at the front of the table.  `a` is behind
// `b` if a's center is at or beyond b's back edge (and so on for the others).
binary.behind = function(theWorld, a, b)
	return a.z <= bounds(b).minZ + eps
end function
binary.inFrontOf = function(theWorld, a, b)
	return a.z >= bounds(b).maxZ - eps
end function
binary.leftOf = function(theWorld, a, b)
	return a.x <= bounds(b).minX + eps
end function
binary.rightOf = function(theWorld, a, b)
	return a.x >= bounds(b).maxX - eps
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
// Ties are all kept.
extreme = function(things, pred)
	measure = @superlatives[pred][0]
	direction = superlatives[pred][1]
	best = null
	for t in things
		v = measure(t) * direction
		if best == null or v > best then best = v
	end for
	result = []
	for t in things
		if measure(t) * direction >= best - eps then result.push t
	end for
	return result
end function
