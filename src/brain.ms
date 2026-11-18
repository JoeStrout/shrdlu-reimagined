// brain.ms
//
// The robot's brain: it takes a sentence's meaning (as ICL), works out what
// the user is talking about, and answers or acts.
//
// It covers:
//
//   - Reference resolution: which actual objects does "the big red block",
//     "it", "them", or "the one you are holding" mean?  (Design note §2.4.)
//   - Questions: is there..., how many..., which..., what color..., and
//     yes/no questions like "is it taller than the blue block?"
//   - Commands: pick up, put on, clear off, stack up...  The planner
//     (planner.ms) does the work and keeps a record of its goals.
//   - Questions about what it did: why, how, and when, answered from that
//     record of goals.
//
// How resolution works.  A description like
//     x1 = a block [color red] [on x2]
// is resolved in two stages:
//   1. candidates: every object that fits the noun and all the constraints.
//      For [on x2], that means being on whatever x2 refers to.
//   2. the determiner then decides what to do with them.  "the" needs exactly
//      one (or complains); "a" is happy with any; "every" wants them all.
// The same two stages work inside constraints: "on a green cube" is true if
// the thing is on *some* green cube, and "on the green cube" first insists
// that there is just one green cube.
//
// When something goes wrong (no such object, or it's ambiguous), the brain
// records a `problem`: a reply saying so, like "I don't understand which
// pyramid you mean."  Everything stops at the first problem.

import "icl"
import "world"
import "relations"
import "speech"
import "planner"
import "meaning"
import "parser"
import "lexicon"

containsRef = @world.containsRef

Brain = {}
Brain.world = null

// What we've been talking about, for "it", "them", "one", and "do that".
Brain.focus = null      // {it: Thing, them: list of Things, noun: string, event: Goal,
                        //  time: the moment we last talked about, for "then",
                        //  itFrom: how "it" came up (see noteFocus)}

// The planner that carries out commands.
Brain.planner = null

// The object the user last clicked on, for "this" and "that".
Brain.selected = null

// What the user has told us they own (see Brain.owns).
Brain.ownership = null

// Words the user has taught us: word -> {prog, var}, the description the
// word means and the program it's in.  (See Brain.define.)
Brain.definitions = null
Brain.expanding = null  // the defined words being worked out right now

// Per-sentence working state.
Brain.prog = null       // the ICL program being handled
Brain.cache = null      // var -> candidates, so each is only worked out once
Brain.chosen = null     // var -> the things picked for "a block" etc. in a command
Brain.busy = null       // vars being resolved right now (to catch loops)
Brain.problem = null    // a reply explaining what went wrong, or null
Brain.used = null       // while filtering: see Brain.filter
Brain.bound = null      // var -> [thing], while testing [did e1] (see didWith)
Brain.missing = false   // set when a test met "the X" with no X (see referInside)
Brain.phrases = null    // var -> the user's words for it, when we heard English
Brain.itMeant = null    // what "it" turned out to mean (see Brain.itNote)
Brain.failed = false    // did the last reply say what went wrong?
Brain.question = null   // a question we asked the user: {understanding, choices}
Brain.moving = []       // in a command, the variables for the things to be moved
Brain.unclear = null    // the variable we just said we didn't understand ("which pyramid?")
Brain.pending = null    // what to finish if the user tells us which: {understanding, index, var}

Brain.make = function(theWorld)
	b = new Brain
	b.world = theWorld
	b.focus = {"it": null, "them": null, "noun": null, "event": null, "time": null, "itFrom": null}
	b.planner = planner.Planner.make(theWorld)
	b.ownership = []
	b.definitions = {}
	b.expanding = {}
	return b
end function

// Note a problem (only the first one counts).  Returns null, so callers can
// write `return self.fail("...")`.
Brain.fail = function(message)
	if not self.problem then self.problem = message
	return null
end function

//----------------------------------------------------------------------
// The main entry point
//----------------------------------------------------------------------

// Respond to one sentence, given as ICL (a Program, or its printed form).
// Returns the reply as a string.
Brain.respond = function(prog)
	if prog isa string then prog = icl.read(prog)
	if prog.errors then return "(I couldn't read that ICL: " + prog.errors[0] + ")"
	self.prog = prog
	self.chosen = {}
	self.world.beginTurn
	self.itMeant = null
	self.failed = false
	self.unclear = null
	replies = []
	for statement in prog.statements
		// (Each statement may change the world, so candidates are worked
		// out afresh for each one.)
		self.cache = {}
		self.busy = {}
		self.problem = null
		reply = self.handle(statement)
		if self.problem then
			replies.push self.problem
			self.failed = true
			break
		end if
		// "Find a block ... and put it in the box" gets just one "OK."
		if not replies or reply != replies[-1] then replies.push reply
	end for
	return replies.join(" ")
end function

// What the robot says to social niceties ("Thank you.", "Hello.", "Help.").
// The lexicon says which reply goes with which words.
chatReplies = {
  "thanks": "You're welcome!",
  "hello": "Hello!  Ask me to move things, or ask me about them.",
  "praise": "Thank you!",
  "sorry": "That's all right.",
  "help": "I can pick things up, put them on or in other things, stack them up, and clear things off.  " +
    "You can ask me where things are, what color or size they are, what's on or in something, " +
    "and why, how or when I did something.  You can also teach me new words.  (Type /help for examples.)",
  "who": "I'm a robot arm.  I live in this little world of blocks, and I'll do what you ask, if I can.",
  "stop": "OK.",
  "bye": "Goodbye!",
  "ok": "OK."}

Brain.handle = function(statement)
	if statement.hasIndex("verb") and statement.verb == "chat" then return chatReplies[statement.args[0]]
	if statement.kind == "ask" then return self.answer(statement)
	if statement.kind == "claim" then return self.checkClaim(statement)
	if statement.kind == "command" then return self.command(statement)
	if statement.kind == "declare" and statement.verb == "name" then return self.giveName(statement)
	if statement.kind == "declare" and statement.verb == "define" then return self.define(statement)
	if statement.kind == "declare" and statement.verb == "own" then return self.learnOwnership(statement, true)
	if statement.kind == "declare" and statement.verb == "dontOwn" then return self.learnOwnership(statement, false)
	return "Sorry, I can't do that yet."
end function

//----------------------------------------------------------------------
// Reference resolution
//----------------------------------------------------------------------

// The description (or event) a variable stands for.
Brain.lookup = function(var)
	item = self.prog.lookup(var)
	if item == null then return self.fail("(" + var + " isn't defined.)")
	return item
end function

// Stage 1: every object that fits a description's noun and constraints,
// ignoring its determiner.
Brain.candidates = function(var)
	if self.bound and self.bound.hasIndex(var) then return self.bound[var]
	if self.cache.hasIndex(var) then return self.cache[var]
	d = self.lookup(var)
	if d == null then return null
	if self.busy.hasIndex(var) then
		return self.fail("(I went in circles: " + var + " is described in terms of itself.)")
	end if
	self.busy[var] = true
	if d.kind == "group" then
		result = self.groupCandidates(d)
	else
		result = self.thingsForHead(d)
		selfRef = null
		if self.mentions(d.props, var) then selfRef = var
		if result != null then result = self.filter(result, d.props, selfRef)
	end if
	self.busy.remove var
	if self.problem then return null
	// What depends on a thing being tested (see filter and didWith) may
	// be different next time, so it isn't kept.
	if not self.dependsOnBound(var) then self.cache[var] = result
	return result
end function

// Does this ICL (constraints, or a line) mention the variable, directly or
// through the descriptions it mentions?  ("Anything which is not as wide as
// the thing that supports it" mentions itself: see Meaning.boundPronoun.)
Brain.mentions = function(item, var, seen=null)
	if seen == null then seen = {}
	for v in icl.varsUsedIn(item)
		if v == var then return true
		if seen.hasIndex(v) then continue
		seen[v] = true
		line = self.prog.lookup(v)
		if line and self.mentions(line, var, seen) then return true
	end for
	return false
end function

// Does this variable's meaning depend on a description that mentions
// itself, so that it means something different for each thing tested?
Brain.variesPerThing = function(var)
	line = self.prog.lookup(var)
	for v in self.prog.vars.indexes
		item = self.prog.lookup(v)
		if item.kind == "description" and self.mentions(item.props, v) and self.mentions(line, v) then return true
	end for
	return false
end function

// Does this variable's meaning depend on a thing being tried out right now?
Brain.dependsOnBound = function(var)
	if not self.bound then return false
	if self.bound.hasIndex(var) then return true
	line = self.prog.lookup(var)
	if line == null then return false
	for b in self.bound.indexes
		if self.mentions(line, b) then return true
	end for
	return false
end function

// Joined noun phrases ("the red cube and a pyramid") could mean anything
// any of their parts could mean.
Brain.groupCandidates = function(g)
	result = []
	for member in g.members
		things = self.candidates(member)
		if things == null then return null
		for t in things
			if not containsRef(result, t) then result.push t
		end for
	end for
	return result
end function

// Is this variable a group (noun phrases joined by "and" or "or")?
Brain.isGroup = function(var)
	item = self.prog.lookup(var)
	return item != null and item.kind == "group"
end function

// The things a description's head word could mean, before any constraints.
Brain.thingsForHead = function(d)
	head = d.head
	// "this" and "that" mean what the user clicked on, if anything.
	if (head == "this" or head == "that") and self.selected then return [self.selected]
	if head == "it" or head == "that" or head == "this" then
		if self.focus.it == null then return self.fail("I don't know what you mean by """ + head + """.")
		if head == "it" and self.itMeant == null then self.noteIt d
		return [self.focus.it]
	end if
	if head == "them" or head == "they" then
		if not self.focus.them then return self.fail("I don't know what you mean by """ + head + """.")
		return self.focus.them[:]
	end if
	if head == "one" then head = self.antecedentNoun(d)
	if self.definitions.hasIndex(head) then return self.definedThings(head)
	if head == "stack" then return relations.stacks(self.world)
	if relations.nouns.indexOf(head) != null then
		result = []
		for t in self.world.things
			if relations.nounFits(t, head) then result.push t
		end for
		return result
	end if
	// Not a noun we know: maybe it's a name the user gave something.
	t = self.world.thing(head)
	if t then return [t]
	return self.fail("Sorry, I don't know the word """ + head + """.")
end function

// "One" borrows its noun from something said earlier: "a red one" after
// "a block" means a red block.  We look back through this sentence first,
// then at the last sentence, and settle for "thing" if there's nothing.
Brain.antecedentNoun = function(d)
	found = null
	for item in self.prog.lines
		if refEquals(item, d) then break
		if item.kind != "description" then continue
		if self.isNoun(item.head) then found = item.head
	end for
	if found then return found
	if self.focus.noun then return self.focus.noun
	return "thing"
end function

// Keep only the things that meet every constraint.  Superlatives ("the
// biggest") are applied last, since they compare the survivors.
//
// A "the" inside a constraint is settled by the description around it.
// In "the green pyramid on the block", there may be several blocks, but
// only one that the green pyramid is on, and that's the one meant.  So
// such an inner "the" may have several candidates while we test (see
// referInside), and afterward the survivors must all be related to the
// same one of them (or, failing that, to the one we were just talking
// about).
//
// If the description mentions itself (selfRef is its variable), then while
// each thing is tested, that variable means just that thing.
Brain.filter = function(things, props, selfRef=null)
	savedUsed = self.used
	passed = []     // the things that meet every constraint...
	usedBy = []     // ...and for each, inner "the" var -> what it was related to
	if selfRef and self.bound == null then self.bound = {}
	for t in things
		self.used = {}
		if selfRef then self.bound[selfRef] = [t]
		ok = true
		for c in props
			if relations.superlatives.hasIndex(c.pred) then continue
			if not self.test(t, c) then
				ok = false
				break
			end if
		end for
		if selfRef then self.bound.remove selfRef
		if self.problem then return null
		if ok then
			passed.push t
			usedBy.push self.used
		end if
	end for
	self.used = savedUsed
	result = passed
	for c in props
		if not relations.superlatives.hasIndex(c.pred) then continue
		// [tallest], or [tallest 2] for the second tallest
		rank = 1
		if c.args then rank = c.args[0]
		result = relations.extreme(result, c.pred, rank)
	end for
	return self.settleInnerDefinites(passed, usedBy, result)
end function

// After filtering, settle each inner "the": the survivors must all be
// related to just one of its candidates.  If they're related to several,
// the one just talked about (see inFocus) will do, and the survivors that
// aren't related to it drop out.  Returns the survivors, or null (with a
// complaint) if an inner "the" is still ambiguous.
Brain.settleInnerDefinites = function(passed, usedBy, survivors)
	related = {}     // var -> the things the survivors are related to
	for i in passed.indexes
		if not containsRef(survivors, passed[i]) then continue
		for var in usedBy[i].indexes
			if not related.hasIndex(var) then related[var] = []
			for other in usedBy[i][var]
				if not containsRef(related[var], other) then related[var].push other
			end for
		end for
	end for
	for var in related.indexes
		if related[var].len <= 1 then continue
		meant = self.inFocus(related[var])
		if meant.len != 1 then
			d = self.lookup(var)
			self.unclear = var
			return self.fail("I don't understand which " + self.phraseFor(d, false, false) + " you mean.")
		end if
		// Keep only the survivors related to the one meant.
		kept = []
		for i in passed.indexes
			if not containsRef(survivors, passed[i]) then continue
			if usedBy[i].hasIndex(var) and containsRef(usedBy[i][var], meant[0]) then kept.push passed[i]
		end for
		survivors = kept
	end for
	return survivors
end function

// Note that the thing being tested is related to this candidate for an
// inner "the" (see filter).
Brain.noteUsed = function(var, other)
	if self.used == null then return
	if not self.used.hasIndex(var) then self.used[var] = []
	self.used[var].push other
end function

// What a variable inside a constraint refers to.  Like refer, except for a
// singular "the X" that fits more than one thing: then we test against all
// of them, keeping track of which ones matter (see filter).
Brain.referInside = function(var)
	d = self.lookup(var)
	if d == null then return null
	// "The thing that supports it", where "it" is the thing being tested:
	// whatever supports this thing, if anything.  (If nothing does, the
	// relation just doesn't hold.)
	if d.kind == "description" and isDefinite(d) and self.dependsOnBound(var) then
		things = self.candidates(var)
		if things == null then return null
		if not things then
			self.missing = true
			return {"things": [], "quantity": "some", "n": 0}
		end if
		return {"things": things, "quantity": "all", "n": 0}
	end if
	if d.det != "the" or d.plural then return self.refer(var)
	things = self.candidates(var)
	if things == null then return null
	if things.len <= 1 then return self.refer(var)
	return {"things": things, "quantity": "some", "n": 0, "inner": var}
end function

// Does one thing meet one constraint?// Does one thing meet one constraint?
Brain.test = function(thing, c)
	pred = c.pred
	if pred == "not" then
		// "Not as wide as the thing that supports it" is no more true than
		// "as wide as..." when nothing supports it.
		self.missing = false
		result = self.test(thing, c.args[0])
		if self.missing then return false
		return not result
	end if
	if pred == "or" then
		for alternative in c.args
			if self.test(thing, alternative) then return true
		end for
		return false
	end if
	if pred == "and" then
		for part in c.args
			if not self.test(thing, part) then return false
		end for
		return true
	end if
	if pred == "oneOf" then return self.isOneOf(thing, c.args[0])
	if pred == "could" then
		// "Which blocks can you pick up?"  The ones that can be moved.
		e = self.lookup(c.args[0])
		if e.verb == "pickUp" or e.verb == "grasp" then return thing.movable
		return self.fail("I'm not sure what I could " + e.verb + ".")
	end if
	if pred == "commanded" then return self.wasCommanded(thing, c.args)
	if pred == "owned" then return self.owns(thing) == true
	if pred == "did" then return self.didWith(thing, c.args[0])
	if (pred == "before" or pred == "after") and c.args.len == 2 then return self.testThen(thing, c)
	if pred == "then" then
		if self.focus.time == null then return self.fail("I'm not sure when you mean by ""then"".")
		return self.testAt(thing, c.args[0], self.focus.time)
	end if
	if relations.superlatives.hasIndex(pred) then return self.isMost(thing, c)
	if relations.unary.hasIndex(pred) then return relations.unary[pred](self.world, thing)
	if relations.valued.hasIndex(pred) then return relations.valued[pred](self.world, thing, c.args[0])
	if relations.binary.hasIndex(pred) then
		if c.args.len != 1 or not icl.isVar(c.args[0]) then
			return self.fail("([" + pred + "] needs one variable.)")
		end if
		if self.isGroup(c.args[0]) then return self.testGroup(thing, c)
		ref = self.referInside(c.args[0])
		if ref == null then return false
		related = @relations.binary[pred]
		count = 0
		for other in ref.things
			if not refEquals(other, thing) and related(self.world, thing, other) then
				count += 1
				if ref.hasIndex("inner") then self.noteUsed ref.inner, other
			end if
		end for
		return self.quantityOk(ref, count)
	end if
	return self.fail("I don't know what """ + pred + """ means.")
end function

// "Is the blue block the tallest?"  A superlative as a claim: is it the
// tallest of the things its noun fits (here, the tallest block)?
Brain.isMost = function(thing, c)
	rank = 1
	if c.args then rank = c.args[0]
	kind = []
	for t in self.world.things
		if relations.nounFits(t, thing.noun) then kind.push t
	end for
	return containsRef(relations.extreme(kind, c.pred, rank), thing)
end function

// [oneOf x3]: is this thing one of the things x3 means?  ("Which is taller,
// the red cube or the blue block?"  Each of those must mean one thing.)
Brain.isOneOf = function(thing, var)
	if self.isGroup(var) then members = self.lookup(var).members else members = [var]
	for member in members
		ref = self.refer(member)
		if ref == null then return false
		if containsRef(ref.things, thing) then return true
	end for
	return false
end function

// A relation to joined noun phrases: "supports the red cube and a pyramid"
// means it supports the red cube and supports a pyramid; with "or", either
// one will do.
Brain.testGroup = function(thing, c)
	g = self.lookup(c.args[0])
	for member in g.members
		ok = self.test(thing, icl.constraint(c.pred, [member]))
		if self.problem then return false
		if ok and g.join == "or" then return true
		if not ok and g.join == "and" then return false
	end for
	return g.join == "and"
end function

// [did e1]: is this thing one the robot did e1 to?  ("The objects you
// touched": e1 = event Touch x1, and x1 is the description being worked
// out.)  We try the event with just this thing in that place.
Brain.didWith = function(thing, eventVar)
	e = self.lookup(eventVar)
	if e == null then return false
	if e.kind != "event" then return self.fail("([did " + eventVar + "] needs an event.)")
	// The description being worked out right now is the one this is about.
	place = null
	for a in e.args
		if self.busy.hasIndex(a) then place = a
	end for
	if place == null then return self.fail("([did " + eventVar + "] needs an event about what it describes.)")
	if self.bound == null then self.bound = {}
	self.bound[place] = [thing]
	goals = self.matchingGoals(eventVar)
	self.bound.remove place
	return goals != null and goals.len > 0
end function

// [before e1 [on x2]]: was the constraint true just before the robot
// started e1?  ([after e1 ...]: just after it finished.)  We put the world
// back the way it was then, test, and put it back.  Descriptions inside
// the constraint keep their present meaning ("the red cube" is the red
// cube), so they're worked out first.
Brain.testThen = function(thing, c)
	g = self.findGoal(c.args[0])
	if g == null then return false
	inner = c.args[1]
	for a in inner.args
		if icl.isVar(a) and a[0] == "x" then self.candidates a
	end for
	if c.pred == "before" then time = g.start else time = g.finish
	self.focus.time = time      // for "then", later
	return self.testAt(thing, inner, time)
end function

// Was the constraint true at that time?
Brain.testAt = function(thing, c, time)
	w = self.world
	now = w.snapshot
	w.restore w.snapshotAt(time)
	result = self.test(thing, c)
	w.restore now
	return result
end function

// Stage 2: what a description refers to, with its determiner taken into
// account.  Returns {things, quantity, n}, where quantity says how many of
// those things must meet a condition for it to count:
//   "all"      the X, the Xs, it, them, every X, and names
//   "some"     a X, any X, which X
//   "none"     no X
//   "at-least" at least n of them (also "2 blocks")
Brain.refer = function(var)
	d = self.lookup(var)
	if d == null then return null
	if d.kind == "group" then return self.fail("(I can only use """ + d.join + """ in commands and relations so far.)")
	if isDefinite(d) then
		things = self.definite(var)
		if things == null then return null
		return {"things": things, "quantity": "all", "n": 0}
	end if
	things = self.candidates(var)
	if things == null then return null
	quantity = "some"
	if d.det == "every" then quantity = "all"
	if d.det == "no" then quantity = "none"
	if d.det == "number" or d.det == "at-least" then quantity = "at-least"
	return {"things": things, "quantity": quantity, "n": d.n}
end function

// Does this description mean particular things we both know about: "the
// X", "both Xs", "it", a name?
isDefinite = function(d)
	return d.det == null or d.det == "the" or d.det == "both"
end function

// Given a reference and how many of its things met some condition, does
// the condition hold?
Brain.quantityOk = function(ref, count)
	if ref.quantity == "all" then return count == ref.things.len
	if ref.quantity == "some" then return count > 0
	if ref.quantity == "none" then return count == 0
	return count >= ref.n
end function

// The things a definite description ("the X", "it", a name) refers to.  A
// singular one must pick out exactly one thing; a plural one, at least one.
Brain.definite = function(var)
	d = self.lookup(var)
	if d == null then return null
	things = self.candidates(var)
	if things == null then return null
	if things.len == 0 then
		if relations.nouns.indexOf(d.head) == null and d.head != "one" then
			return self.fail("I don't see anything like that.")
		end if
		return self.fail(self.noneSeen(d))
	end if
	// "Both of the red blocks" says there are two.
	if d.det == "both" and things.len != 2 then
		return self.fail("I see " + speech.numberWord(things.len) + " " + self.phraseFor(d, things.len != 1) + ", not two.")
	end if
	if things.len > 1 and not d.plural then
		// "The pyramid", when there are several, can still mean the one
		// that's clicked on, or the one we were just talking about.
		things = self.inFocus(things)
		if things.len != 1 then
			self.unclear = var
			return self.fail("I don't understand which " + self.phraseFor(d, false, false) + " you mean.")
		end if
	end if
	return things
end function

// Of these things, the ones the user is pointing at or we were just
// talking about: first the clicked one, then "it", then "them".  If none
// of those narrows it down, all of them.
Brain.inFocus = function(things)
	if self.selected and containsRef(things, self.selected) then return [self.selected]
	if self.focus.it and containsRef(things, self.focus.it) then return [self.focus.it]
	if self.focus.them then
		recent = []
		for t in things
			if containsRef(self.focus.them, t) then recent.push t
		end for
		if recent then return recent
	end if
	return things
end function

// Remember what we just talked about, for "it", "them", and "one".
Brain.noteFocus = function(var, things)
	d = self.prog.lookup(var)
	if d and d.kind == "description" and self.isNoun(d.head) then self.focus.noun = d.head
	// After "What is in the box?"  "The blue pyramid.", the last noun said
	// was the robot's own "pyramid", so "the green one" is a green pyramid.
	if d and d.kind == "description" and (d.head == "thing" or d.head == "object") and things then
		nouns = []
		for t in things
			if nouns.indexOf(t.noun) == null then nouns.push t.noun
		end for
		if nouns.len == 1 then self.focus.noun = nouns[0]
	end if
	if things.len == 1 then
		self.focus.it = things[0]
		words = null
		if self.phrases and self.phrases.hasIndex(var) then words = self.phrases[var]
		// (Not the words of a question, like "which block": "the which
		// block" isn't a name for anything.)
		if d and d.kind == "description" and (d.det == "which" or d.det == "how-many") then words = null
		self.focus.itFrom = {"thing": things[0], "words": words, "turn": self.world.turn}
	end if
	if things.len > 1 then self.focus.them = things[:]
end function

// We've just taken "it" to mean focus.it.  Note what we'll say if we
// should tell the user so (see itNote), and whether something else in the
// same sentence could have been "it": "Find a block which is taller than
// the one you are holding and put it into the box" might mean putting the
// held one in the box.  We count anything else mentioned earlier in the
// sentence that is one particular thing the robot could move.
Brain.noteIt = function(d)
	it = self.focus.it
	from = self.focus.itFrom
	if from == null or not refEquals(from.thing, it) then from = {"thing": it, "words": null, "turn": 0}
	words = from.words
	if words and icl.pronouns.hasIndex(words) then words = null
	if words then phrase = speech.echoPhrase(words) else phrase = speech.specificNamesFor(self.world, [it])
	self.itMeant = {"phrase": phrase, "thisSentence": from.turn == self.world.turn, "rival": false}
	if not self.itMeant.thisSentence then return
	savedProblem = self.problem
	for item in self.prog.lines
		if refEquals(item, d) then break
		if item.kind != "description" or item.plural or not isDefinite(item) then continue
		if icl.pronouns.hasIndex(item.head) or self.busy.hasIndex(item.var) then continue
		if self.variesPerThing(item.var) then continue
		things = self.candidates(item.var)
		if things and things.len == 1 and things[0].movable and not refEquals(things[0], it) then
			self.itMeant.rival = true
		end if
	end for
	self.problem = savedProblem
end function

// "By "it", I assume you mean the block which is taller than the one I am
// holding."  We say so when "it" could have meant something else in the
// same sentence, or when it came from an earlier sentence and what we
// replied was a complaint, so the user can see whether we misunderstood.
Brain.itNote = function
	m = self.itMeant
	if m == null then return null
	if m.rival or (self.failed and not m.thisSentence) then
		return "By ""it"", I assume you mean " + m.phrase + "."
	end if
	return null
end function

// Words for a description, for complaints: "red pyramids", "blocks in the
// box", "pyramids on the blue block", "blocks taller than the blue block".
// With full false, just the adjectives and the noun: "I don't understand
// which green cube you mean."  ("One" borrows its noun, as always.)
Brain.phraseFor = function(d, plural, full=true)
	words = []
	for c in d.props
		if not relations.superlatives.hasIndex(c.pred) then continue
		if c.args then words.push lexicon.ordinals[c.args[0]]     // "seventh tallest"
		words.push c.pred
	end for
	for c in d.props
		if ["size", "height", "breadth", "color"].indexOf(c.pred) == null or c.args.len != 1 then continue
		if c.args[0] == "big" then words.push "large" else words.push c.args[0]     // as we say it
	end for
	noun = d.head
	if noun == "one" then noun = self.antecedentNoun(d)
	if icl.pronouns.hasIndex(noun) then noun = "thing"
	if plural then noun = icl.pluralize(noun)
	words.push noun
	if full then
		for c in d.props
			tail = self.constraintPhrase(c, plural)
			if tail then words.push tail
		end for
	end if
	return words.join(" ")
end function

// "I don't see any blue pyramids in the box."  ("Anything", not "any
// things".)
Brain.noneSeen = function(d)
	phrase = self.phraseFor(d, true)
	if phrase.indexOf("things") == 0 then return "I don't see anything" + phrase[6:] + "."
	return "I don't see any " + phrase + "."
end function

// How we say a relation after a noun: "on", "to the left of", "taller than".
relationWords = {"on": "on", "in": "in", "above": "above", "below": "below",
  "behind": "behind", "inFrontOf": "in front of", "leftOf": "to the left of",
  "rightOf": "to the right of", "nextTo": "next to",
  "taller": "taller than", "shorter": "shorter than", "wider": "wider than",
  "narrower": "narrower than", "bigger": "bigger than", "smaller": "smaller than",
  "asTall": "as tall as", "asWide": "as wide as", "asBig": "as big as"}
// And relations that are verbs: "which support", "which supports".
relationVerbs = {"supports": "support", "contains": "contain", "touches": "touch"}

// The words for a constraint after a noun ("in the box", "which support
// a pyramid", "not on the table"), or null if we have none.
Brain.constraintPhrase = function(c, plural)
	if c.pred == "not" and c.args and c.args[0] isa map then
		inner = self.constraintPhrase(c.args[0], plural)
		if inner == null then return null
		if inner.indexOf("which ") == 0 then return null
		return "not " + inner
	end if
	if c.pred == "held" then return "which I am holding"
	if c.args.len != 1 or not icl.isVar(c.args[0]) then return null
	other = self.argPhrase(c.args[0])
	if other == null then return null
	if relationWords.hasIndex(c.pred) then return relationWords[c.pred] + " " + other
	if relationVerbs.hasIndex(c.pred) then
		verb = relationVerbs[c.pred]
		if not plural then verb = icl.pluralize(verb)     // "supports"
		return "which " + verb + " " + other
	end if
	return null
end function

// The user's words for what a variable means, including a group: "two
// green cubes and a pyramid".
Brain.wordsFor = function(var)
	item = self.prog.lookup(var)
	if item and item.kind == "group" then
		parts = []
		for m in item.members
			parts.push self.wordsFor(m)
		end for
		return speech.listPhrase(parts, item.join)
	end if
	return self.argPhrase(var)
end function

// The words for what a variable means, as the user said it if we heard
// English ("the blue block"), or else from its description.
Brain.argPhrase = function(var)
	if self.phrases and self.phrases.hasIndex(var) then return speech.swapPersons(self.phrases[var])
	d = self.prog.lookup(var)
	if d == null or d.kind != "description" then return null
	if icl.pronouns.hasIndex(d.head) then return d.head
	phrase = self.phraseFor(d, d.plural, false)
	if d.det == "the" then return "the " + phrase
	if d.det == "a" then return speech.withArticle(phrase)
	if d.det == "any" or d.det == null then return phrase
	return null
end function

//----------------------------------------------------------------------
// Questions
//----------------------------------------------------------------------

Brain.answer = function(q)
	if q.q == "why" or q.q == "how" or q.q == "when" then return self.answerAboutEvent(q)
	if q.q == "what" then return self.answerWhatDone(q.target)
	if q.q == "method" then return self.answerMethod(q.target)
	if q.q == "exists" and icl.isVar(q.target) and q.target[0] == "e" then return self.answerDid(q.target)
	if q.q == "exists" then return self.answerExists(q.target)
	if q.q == "count" then return self.answerCount(q.target)
	if q.q == "which" then return self.answerWhich(q.target)
	if q.q == "identify" then return self.answerIdentify(q.target)
	if q.q == "where" then return self.answerWhere(q.target)
	if q.q == "attribute" then return self.answerAttribute(q.target, q.attr)
	if q.q == "yes-no" then return self.answerYesNo(q.target, q.claim)
	if q.q == "can" then return self.answerCan(q)
	return self.fail("(I don't know that kind of question.)")
end function

// "Is there a big red block?"
Brain.answerExists = function(var)
	things = self.candidates(var)
	if things == null then return null
	self.noteFocus var, things
	// (Even with none, the noun is what we're talking about: "Are there any
	// steeples now?"  "No."  "Build one.")
	if not things then return "No."
	// "Can you see the box?"  There's no need to name what was named.
	if isDefinite(self.lookup(var)) then return "Yes."
	return "Yes, " + self.countedNames(var, things) + "."
end function

// The things found for a question's noun phrase, counted if there's more
// than one: "the red cube", "three of them: a large red one, ...", or, for
// "anything" or "something", "two things: the blue block and the blue
// pyramid".
Brain.countedNames = function(var, things)
	d = self.lookup(var)
	names = speech.namesFor(self.world, things, d.head)
	if things.len == 1 then return names
	// "Yes, two large green cubes." rather than "Yes, two of them: two
	// large green cubes."
	if names.indexOf(speech.numberWord(things.len) + " ") == 0 and names.indexOf(" and ") == null then return names
	if d.head == "thing" then return speech.numberWord(things.len) + " things: " + names
	return speech.numberWord(things.len) + " of them: " + names
end function

// "How many blocks are not in the box?"
//
// "How many blocks can you pick up?" is really asking how many at once.
Brain.answerCount = function(var)
	for c in self.lookup(var).props
		if c.pred != "could" then continue
		e = self.lookup(c.args[0])
		if e.verb == "pickUp" or e.verb == "grasp" then return "I can only hold one thing at a time."
	end for
	things = self.candidates(var)
	if things == null then return null
	if not things then return "None."
	self.noteFocus var, things
	if things.len == 1 then return "Just one."
	return speech.capitalize(speech.numberWord(things.len)) + " of them."
end function

// "Which cube is on the table?"  "What does the box contain?"
// "Which cube" asks us to pick out each one, so we say enough to tell it
// from the other cubes; "what" just asks what's there.
Brain.answerWhich = function(var)
	things = self.candidates(var)
	if things == null then return null
	noun = self.lookup(var).head
	if not things and noun == "thing" then return "Nothing."
	if not things then return "None."
	self.noteFocus var, things
	if noun == "thing" then
		names = speech.namesFor(self.world, things)
	else
		names = speech.specificNamesFor(self.world, things, noun)
	end if
	return speech.capitalize(names) + "."
end function

// "What is it?"  "Which is the tallest block?"  We say what the noun phrase
// means, by name.
Brain.answerIdentify = function(var)
	d = self.lookup(var)
	if d == null then return null
	if isDefinite(d) then things = self.definite(var) else things = self.candidates(var)
	if things == null then return null
	if not things then return "Nothing."
	self.noteFocus var, things
	return speech.capitalize(speech.specificNamesFor(self.world, things)) + "."
end function

// "Where is the red cube?"  "On the table."  For several things, we say
// where each is, with the things in one place together: "The red cube and a
// large green cube are on the table, and a large green cube is on the large
// red block."
Brain.answerWhere = function(var)
	d = self.lookup(var)
	if d == null then return null
	if isDefinite(d) then things = self.definite(var) else things = self.candidates(var)
	if things == null then return null
	if not things then return self.fail(self.noneSeen(d))
	self.noteFocus var, things
	if things.len == 1 then return speech.capitalize(self.placeOf(things[0])) + "."
	places = []     // in the order we come to them
	groups = {}     // place -> the things there
	for t in things
		place = self.placeOf(t)
		if not groups.hasIndex(place) then
			places.push place
			groups[place] = []
		end if
		groups[place].push t
	end for
	clauses = []
	for place in places
		if groups[place].len == 1 then verb = " is " else verb = " are "
		clauses.push speech.namesFor(self.world, groups[place]) + verb + place
	end for
	if clauses.len == 1 then return speech.capitalize(clauses[0]) + "."
	return speech.capitalize(clauses[:-1].join(", ") + ", and " + clauses[-1]) + "."
end function

// Where a thing is, as a phrase: "on the table", "in the box", "in my hand".
Brain.placeOf = function(thing)
	if refEquals(self.world.hand.holding, thing) then return "in my hand"
	if not thing.supporters then return "nowhere"     // (the table)
	return speech.placePhrase(self.world, thing.supporters[0])[1:]
end function

// "What color is it?"
Brain.answerAttribute = function(var, attr)
	// "What color is the pyramid?" needs a pyramid we both know about.
	// "What color is a pyramid?" lets the robot pick any one (the same way
	// it picks one for "pick up a pyramid"), which then becomes "it".
	d = self.lookup(var)
	if d == null then return null
	if ["a", "an", "any"].indexOf(d.det) != null then
		things = self.candidates(var)
		if things == null then return null
		if not things then return self.fail(self.noneSeen(d))
		things = self.choose(var)
	else
		things = self.definite(var)
	end if
	if things == null then return null
	self.noteFocus var, things
	values = []
	for t in things
		v = self.attributeOf(t, attr)
		if v == null then return self.fail("I don't know how to tell its " + attr + ".")
		if values.indexOf(v) == null then values.push v
	end for
	return speech.capitalize(speech.listPhrase(values)) + "."
end function

Brain.attributeOf = function(thing, attr)
	if attr == "color" then return thing.color
	if attr == "shape" then return speech.withArticle(thing.noun)     // "a pyramid"
	if attr == "size" then
		word = speech.sizeWord(self.world, thing)
		if word == null then return "medium-sized"
		return word
	end if
	return null
end function

// "Is at least one of them narrower than the red cube?"
// The target's determiner says how many must meet the claim.
Brain.answerYesNo = function(var, claim)
	ref = self.refer(var)
	if ref == null then return null
	meeting = []
	for t in ref.things
		if self.test(t, claim) then meeting.push t
		if self.problem then return null
	end for
	if not self.quantityOk(ref, meeting.len) then
		// "Do I own the table?"  We weren't told either way.
		if claim.pred == "owned" and ref.things.len == 1 and self.owns(ref.things[0]) == null then
			return "I don't know."
		end if
		return "No."
	end if
	self.noteFocus var, ref.things
	// "Is it supported?"  "Yes, by the table."
	if claim.pred == "supported" and ref.things.len == 1 then
		return "Yes, by " + speech.namesFor(self.world, ref.things[0].supporters) + "."
	end if
	// For "is there one which...", say which ones did.
	if ref.quantity == "some" or ref.quantity == "at-least" then
		self.noteFocus var, meeting
		return "Yes, " + self.countedNames(var, meeting) + "."
	end if
	return "Yes."
end function

// "Can a pyramid be supported by a block?"  Yes, if one is now.  "Can a
// pyramid support a pyramid?"  No, since nothing stays on a pyramid.  "Can
// a block be in the box?"  Yes, if we could put one there (we try it out,
// and put everything back).  Otherwise we don't know.  ("Can the table
// pick up blocks?"  No: only the robot does things.)
Brain.answerCan = function(q)
	if q.target[0] == "e" then
		e = self.lookup(q.target)
		if e == null then return null
		for c in e.props
			if c.pred == "by" then return "No."
		end for
		return self.fail("(I can only answer that about other things, so far.)")
	end if
	if q.claim == null then return self.fail("(Ask can " + q.target + " needs a claim.)")
	things = self.candidates(q.target)
	if things == null then return null
	for t in things
		if self.test(t, q.claim) then return "Yes."
		if self.problem then return null
	end for
	if self.cantBe(q.target, q.claim) then return "No. " + planner.pyramidRule
	if self.couldMake(q.target, q.claim) then return "Yes."
	if self.problem then return null
	return "I don't know."
end function

// Could we make the claim true of one of the things a variable means, by
// putting something somewhere?  For [on x2] or [in x2], we try putting one
// of them on (or in) one of x2's things; for [supports x2], one of x2's
// things on one of them.  (We try a few of each, nearest first.)
Brain.couldMake = function(var, claim)
	if claim.args.len != 1 or not icl.isVar(claim.args[0]) then return false
	if ["on", "in", "supports"].indexOf(claim.pred) == null then return false
	these = self.candidates(var)
	ref = self.refer(claim.args[0])
	if these == null or ref == null then return false
	these = self.leastTrouble(these)[:3]
	those = self.leastTrouble(ref.things)[:3]
	for a in these
		for b in those
			if refEquals(a, b) then continue
			if claim.pred == "supports" then pair = [b, a] else pair = [a, b]
			if not pair[0].movable then continue
			if self.wouldWork("putOn", pair) then return true
		end for
	end for
	return false
end function

// Would the planner manage this goal?  We try it, then put the world back
// just as it was, forgetting what we did.
Brain.wouldWork = function(kind, args)
	w = self.world
	saved = {"snapshot": w.snapshot, "hand": w.hand.pos[:], "goals": w.goals.len,
	  "history": w.history.len, "step": w.step}
	problem = self.planner.achieve(kind, args)
	w.restore saved.snapshot
	w.hand.pos = saved.hand
	w.goals = w.goals[:saved.goals]
	w.history = w.history[:saved.history]
	w.step = saved.step
	return problem == null
end function

// Is this against the way things work?  For now we know one rule: nothing
// stays on top of a pyramid.
Brain.cantBe = function(var, claim)
	if claim.pred == "supports" then
		pyramids = self.candidates(var)
	else if claim.pred == "on" or claim.pred == "above" then
		pyramids = self.candidates(claim.args[0])
	else
		return false
	end if
	if not pyramids then return false
	for t in pyramids
		if t.shape != "pyramid" then return false
	end for
	return true
end function

//----------------------------------------------------------------------
// Claims: things the user says are so
//----------------------------------------------------------------------

// "There were five blocks to the left of the box then."  We check, and say
// so if it's wrong.  A number in a claim means just that many.
Brain.checkClaim = function(c)
	if c.q != "exists" then return self.fail("(I can only check claims that there are things, so far.)")
	things = self.candidates(c.target)
	if things == null then return null
	d = self.lookup(c.target)
	if d.det == "number" then
		right = things.len == d.n
	else if d.det == "at-least" then
		right = things.len >= d.n
	else
		right = things.len > 0
	end if
	if right then
		self.noteFocus c.target, things
		return "That's right."
	end if
	if not things then return "No, none."
	self.noteFocus c.target, things
	prefix = "No, "
	if d.hasIndex("n") and d.n and things.len < d.n then prefix = "No, only "
	return prefix + self.countedNames(c.target, things) + "."
end function

//----------------------------------------------------------------------
// Commands
//----------------------------------------------------------------------

// The commands we understand, and the kind of goal each one sets.
// ("putDown" and "find" are handled here rather than by the planner.)
commandGoals = {
  "pickUp": "grasp", "grasp": "grasp",
  "putOn": "putOn", "putIn": "putOn", "putDown": "putDown", "drop": "putDown",
  "putAt": "putAt",
  "clearOff": "clearOff", "cleanOff": "clearOff",
  "getRidOf": "getRidOf",
  "stack": "stack", "stackUp": "stack",
  "find": "find"}

Brain.command = function(cmd)
	if cmd.verb == "undo" then return self.undo
	if cmd.verb == "putBack" then return self.putBackCommand(cmd)
	// "Move the red pyramid" (with nowhere to move it) makes sense as a
	// question ("Why did you move it?"), but not as a command.
	if cmd.verb == "move" then return self.fail("Where should I move it to?  You can say, for example, ""Move it onto the box.""")
	if cmd.verb == "build" then return self.build(cmd)
	if not commandGoals.hasIndex(cmd.verb) then
		return "Sorry, I don't know how to " + cmd.verb + "."
	end if
	kind = commandGoals[cmd.verb]
	// Work out what each argument means.  The things to be moved are the
	// first argument (or all of them, for a stack).
	if kind == "stack" then self.moving = cmd.args else self.moving = cmd.args[:1]
	if kind == "clearOff" or kind == "find" then self.moving = []
	groups = []
	for var in cmd.args
		if not icl.isVar(var) then continue     // a word, like the nextTo in PutAt
		things = self.choose(var)
		if things == null then return null
		groups.push things
	end for
	self.moving = []

	// Turn the command into a list of goals for the planner.
	table = self.world.table
	goals = []
	if kind == "find" then
		if groups.len != 1 then return self.fail("(Find needs one thing.)")
	else if kind == "grasp" then
		if groups.len != 1 then return self.fail("(" + cmd.verb + " needs one thing.)")
		if groups[0].len > 1 then return self.fail("I can only hold one thing at a time.")
		goals.push ["grasp", groups[0]]
	else if kind == "putDown" then
		if not groups then
			if not self.world.hand.holding then return self.fail("I'm not holding anything.")
			groups.push [self.world.hand.holding]
		end if
		for t in groups[0]
			goals.push ["putOn", [t, table]]
		end for
	else if kind == "putOn" then
		if groups.len != 2 then return self.fail("(" + cmd.verb + " needs two things.)")
		if groups[1].len > 1 then return self.fail("I can only put things in one place at a time.")
		for t in groups[0]
			goals.push ["putOn", [t, groups[1][0]]]
		end for
	else if kind == "putAt" then
		// "Put the red cube next to the blue block": on whatever the blue
		// block stands on, at a spot next to it.  (PutAt x1, nextTo, x2)
		if groups.len != 2 or cmd.args.len != 3 then return self.fail("(" + cmd.verb + " needs two things and a relation.)")
		if groups[1].len > 1 then return self.fail("I can only put things in one place at a time.")
		other = groups[1][0]
		surface = self.world.table
		if other.shape == "table" then
			surface = other
		else if other.supporters then
			surface = other.supporters[0]
		end if
		for t in groups[0]
			goals.push ["putOn", [t, surface], {"rel": cmd.args[1], "other": other}]
		end for
	else if kind == "stack" then
		all = []
		for g in groups
			all += g
		end for
		goals.push ["stack", all]
	else
		// clearOff and getRidOf: one goal for each thing.
		for t in groups[0]
			goals.push [kind, [t]]
		end for
	end if

	// Carry them out.  Each one the user asked for directly is marked with
	// the verb they used (for "the one I told you to pick up").
	for g in goals
		first = self.world.goals.len
		near = null
		if g.len > 2 then near = g[2]
		problem = self.planner.achieve(g[0], g[1], near)
		root = self.world.goals[first]
		root.verb = cmd.verb
		self.focus.event = root
		if problem then return self.fail(problem)
	end for
	if cmd.args then self.noteFocus cmd.args[0], groups[0]
	return "OK."
end function

//----------------------------------------------------------------------
// Putting things back, and undoing
//----------------------------------------------------------------------

// "Put it back": back where it was before we last moved it.
Brain.putBackCommand = function(cmd)
	if cmd.args.len != 1 then return self.fail("(PutBack needs one thing.)")
	self.moving = cmd.args
	things = self.choose(cmd.args[0])
	self.moving = []
	if things == null then return null
	for t in things
		g = self.lastMoveOf(t)
		if g == null then return self.fail("I haven't moved " + speech.nameFor(self.world, t) + ".")
		if not self.putBack(t, g.root.start, cmd.verb) then return null
	end for
	self.noteFocus cmd.args[0], things
	return "OK."
end function

// The last goal that moved this thing, or null.
Brain.lastMoveOf = function(thing)
	for i in range(self.world.goals.len - 1, 0, -1)
		g = self.world.goals[i]
		if g.status == "done" and (g.kind == "putOn" or g.kind == "getRidOf") and refEquals(g.args[0], thing) then return g
	end for
	return null
end function

// Put a thing back where it was at an earlier time: on the same thing, at
// the same spot if we can, or else anywhere on it.  Returns true if it
// worked (or else notes the problem and returns false).
Brain.putBack = function(thing, time, verb)
	w = self.world
	was = w.snapshotAt(time)[thing.id]
	if not was.supporters then return true     // it was in the hand; leave it be
	target = w.thing(was.supporters[0])
	first = w.goals.len
	problem = self.planner.achieve("putOn", [thing, target], {"at": [was.pos[0], was.pos[2]]})
	if problem then
		w.goals[first].status = "failed"
		first = w.goals.len
		problem = self.planner.achieve("putOn", [thing, target])
	end if
	w.goals[first].verb = verb
	self.focus.event = w.goals[first]
	if problem then
		self.fail problem
		return false
	end if
	return true
end function

// "Undo that": put back everything we moved for the last thing we were
// asked to do, the last one moved first.  (So after "Put the red cube in
// the box", which meant moving the green pyramid off it first, the red cube
// goes back where it was, and then the green pyramid goes back on it.)
Brain.undo = function
	g = self.lastAsked
	if g == null then return null
	w = self.world
	before = w.snapshotAt(g.start)
	// What moved, in the order each was last set down.
	moved = []
	for e in w.history
		if e.action != "ungrasp" or timeValue(e.time) < timeValue(g.start) then continue
		if containsRef(moved, e.thing) then moved.remove moved.indexOf(e.thing)
		moved.push e.thing
	end for
	if not moved then return "There's nothing to undo."
	for i in range(moved.len - 1, 0, -1)
		if not self.putBack(moved[i], g.start, "undo") then return null
	end for
	return "OK."
end function

// The things a command's argument means.  "The" and "every" mean what they
// always do; for "a block" or "two blocks", we pick the ones that are least
// trouble: the one in the hand, then ones with nothing on top, then the
// nearest.  The choice is remembered for the rest of the sentence, so that
// "find a block ... and put it in the box" means the same block both times.
Brain.choose = function(var)
	if self.chosen.hasIndex(var) then return self.chosen[var]
	d = self.lookup(var)
	if d == null then return null
	if d.kind == "group" then
		things = self.chooseFromGroup(d)
	else if isDefinite(d) then
		things = self.definite(var)
	else
		things = self.candidates(var)
		if things == null then return null
		// "A block" in a command means one we haven't already picked for
		// something else in this sentence ("stack up the red cube and a
		// block" won't pick the red cube again).
		// "Everything", as something to move, means the things that can be
		// moved: not the box or the table.
		if self.moving.indexOf(var) != null then things = movableOnes(things)
		fitting = things
		things = self.notChosenYet(fitting)
		want = things.len
		if d.det == "a" or d.det == "any" or d.det == "which" then want = 1
		if d.det == "number" or d.det == "at-least" then want = d.n
		if things.len == 0 or things.len < want then
			if fitting.len > things.len and want == 1 then
				return self.fail("I don't see another " + self.phraseFor(d, false) + ".")
			end if
			if not fitting then return self.fail(self.noneSeen(d))
			return self.fail("I don't see enough " + self.phraseFor(d, true) + ".")
		end if
		things = self.leastTrouble(things)[:want]
	end if
	if things == null then return null
	self.chosen[var] = things
	return things
end function

// Just the things that can be moved.
movableOnes = function(things)
	result = []
	for t in things
		if t.movable then result.push t
	end for
	return result
end function

// For "X and Y", what each part means; for "X or Y", the first one we can
// find.
Brain.chooseFromGroup = function(g)
	if g.join == "and" then
		result = []
		for member in g.members
			things = self.choose(member)
			if things == null then return null
			for t in things
				if not containsRef(result, t) then result.push t
			end for
		end for
		return result
	end if
	// "Either a green cube or a pyramid": try each in turn, and if none
	// works, give the complaint about the first.
	firstProblem = null
	for member in g.members
		things = self.choose(member)
		if things != null then
			self.problem = null
			return things
		end if
		if firstProblem == null then firstProblem = self.problem
		self.problem = null
	end for
	return self.fail(firstProblem)
end function

// Of these things, the ones not yet picked for any other part of this
// sentence.
Brain.notChosenYet = function(things)
	result = []
	for t in things
		taken = false
		for picked in self.chosen.values
			if containsRef(picked, t) then taken = true
		end for
		if not taken then result.push t
	end for
	return result
end function

// Sort things by how much trouble they'd be to pick up.  Something
// sitting on a thing already picked for this sentence costs nothing extra,
// since it will have to be moved anyway.  (So to build a steeple from a
// green cube with the red pyramid on it, we use that pyramid, rather than
// fetching one from the box.)
Brain.leastTrouble = function(things)
	hand = self.world.hand
	scored = []
	for t in things
		cost = 0
		if not refEquals(t, hand.holding) and not self.onChosen(t) then
			cost = 100
			for other in self.world.things
				if relations.binary.above(self.world, other, t) then cost += 100
			end for
			dx = t.x - hand.pos[0]
			dz = t.z - hand.pos[2]
			cost += sqrt(dx*dx + dz*dz)
		end if
		scored.push {"thing": t, "cost": cost}
	end for
	scored.sort "cost"
	result = []
	for s in scored
		result.push s.thing
	end for
	return result
end function

// Is this thing resting on something already picked for this sentence?
Brain.onChosen = function(thing)
	for picked in self.chosen.values
		for s in thing.supporters
			if containsRef(picked, s) then return true
		end for
	end for
	return false
end function

// [commanded PickUp]: did the user tell us to do that to this thing?
Brain.wasCommanded = function(thing, args)
	for g in self.world.goals
		if g.parent or not g.hasIndex("verb") then continue
		if args and g.verb != icl.uncapitalize(args[0]) then continue
		if containsRef(g.args, thing) then return true
	end for
	return false
end function

//----------------------------------------------------------------------
// Questions about the past: why, how, and when
//----------------------------------------------------------------------

// The kinds of goal each event verb can mean, in order of preference.
// To touch something, the robot picks it up or puts something on it.
// Getting rid of something is putting it on the table (see goalArgsFit).
// "Move" is any goal that carried a thing somewhere: putting it on
// something, or getting rid of it, or, failing those, picking it up.
// The robot never drops anything (it sets things down carefully), unless
// the user told it to drop something (see matchingGoals).
eventGoals = {
  "pickUp": ["grasp"], "grasp": ["grasp"],
  "putOn": ["putOn", "getRidOf"], "putIn": ["putOn"], "putDown": ["putOn", "getRidOf"],
  "putAt": ["putOn"],
  "move": ["putOn", "getRidOf", "grasp"],
  "drop": ["putOn"],
  "touch": ["grasp", "putOn"],
  "clearOff": ["clearOff"], "cleanOff": ["clearOff"],
  "getRidOf": ["getRidOf"],
  "stack": ["stack"], "stackUp": ["stack"]}

// Times are [turn, step]; this makes them easy to compare.
timeValue = function(t)
	return t[0] * 100000 + t[1]
end function

// Which goal an event description means: the most recent one that fits,
// unless the one we were just talking about fits.  (After "Had you
// touched any pyramid before ...?"  "Yes, the green one.", "When did you
// pick it up?" means that time, not some later one.)  "Do" with no
// arguments ("why did you do that?") means the goal we were just talking
// about.
Brain.findGoal = function(var, noneMessage="I don't remember doing that.")
	e = self.lookup(var)
	if e == null then return null
	if e.kind != "event" then return self.fail("(" + var + " isn't an event.)")
	if e.verb == "do" and not e.args then
		// "What did you do last?": the last thing the user asked for.
		for c in e.props
			if c.pred == "last" then return self.lastAsked
		end for
		if self.focus.event == null then return self.fail("I don't know what you mean.")
		return self.focus.event
	end if
	goals = self.matchingGoals(var)
	if goals == null then return null
	if not goals then return self.fail(noneMessage)
	if self.focus.event and containsRef(goals, self.focus.event) then return self.focus.event
	return goals[0]
end function

// The last thing the user asked us to do (that we did).
Brain.lastAsked = function
	for i in range(self.world.goals.len - 1, 0, -1)
		g = self.world.goals[i]
		if g.parent == null and g.status == "done" then return g
	end for
	return self.fail("I haven't done anything yet.")
end function

// Every goal an event description fits: the preferred kinds first (see
// eventGoals), and the most recent first within each kind.  (Not goals
// that failed: the robot tried those, but didn't do them.)  Returns null
// if there's a problem.
Brain.matchingGoals = function(var)
	e = self.lookup(var)
	if not eventGoals.hasIndex(e.verb) then return self.fail("I don't know what it means to " + e.verb + ".")
	// What each argument refers to.
	refs = []
	for a in e.args
		if not icl.isVar(a) then continue     // (the nextTo in "event PutAt x1, nextTo, x2")
		ref = self.refer(a)
		if ref == null then return null
		refs.push ref.things
	end for
	// The other events its time constraints refer to.
	others = []
	for c in e.props
		if c.pred == "by" then return []     // only the robot does things
		other = self.findGoal(c.args[0])
		if other == null then return null
		others.push other
	end for
	result = []
	for kind in eventGoals[e.verb]
		for i in range(self.world.goals.len - 1, 0, -1)
			g = self.world.goals[i]
			if g.kind != kind or g.status == "failed" then continue
			if e.verb == "drop" and g.verb != "drop" then continue
			if not self.goalArgsFit(g, e.verb, refs) then continue
			if not self.goalTimesFit(g, e.props, others) then continue
			result.push g
		end for
	end for
	if self.problem then return null
	return result
end function

// "Did you pick up the red cube?"  "Had you touched any pyramid before you
// put the green one on the little cube?"  If the event has an indefinite
// argument ("any pyramid"), we say which things it turned out to be: "Yes,
// the green one."
Brain.answerDid = function(var)
	goals = self.matchingGoals(var)
	if goals == null then return null
	if not goals then return "No."
	self.focus.event = goals[0]
	e = self.lookup(var)
	for i in e.args.indexes
		ref = self.refer(e.args[i])
		if ref.quantity != "some" then
			// "Have you picked superblock up?"  Then superblock is "it".
			if i == 0 then self.noteFocus e.args[i], ref.things
			continue
		end if
		things = []
		for g in goals
			for t in self.goalArg(g, e.verb, i)
				if containsRef(ref.things, t) and not containsRef(things, t) then things.push t
			end for
		end for
		self.noteFocus e.args[i], things
		return "Yes, " + self.countedNames(e.args[i], things) + "."
	end for
	return "Yes."
end function

// Does each argument of the event match the goal?
Brain.goalArgsFit = function(g, verb, refs)
	for i in refs.indexes
		found = false
		for t in refs[i]
			if containsRef(self.goalArg(g, verb, i), t) then found = true
		end for
		if not found then return false
	end for
	return true
end function

// What fills the i'th place of an event verb ("touch", "putOn"...) in a
// goal, as a list:
//   - for a stack, any of the things stacked
//   - for getting rid of something, the place is the table
//   - things are touched by picking them up, or by putting something on
//     them, so the thing touched in a putOn is the one it was put on
// and otherwise, the goal's i'th argument.
Brain.goalArg = function(g, verb, i)
	if g.kind == "stack" then return g.args
	// "Why did you put the red cube next to the blue block?"
	if verb == "putAt" and i == 1 then
		if g.near and g.near.hasIndex("other") then return [g.near.other]
		return []
	end if
	if g.kind == "getRidOf" and i == 1 then return [self.world.table]
	if verb == "touch" and g.kind == "putOn" then i += 1
	return g.args[i:i+1]
end function

// Check an event's time constraints: [before e2], [after e2], [while e2],
// [for e2].
Brain.goalTimesFit = function(g, props, others)
	for i in props.indexes
		c = props[i]
		other = others[i]
		if c.pred == "before" then
			// Before, or while getting ready for it: picking up the green
			// pyramid to clear off the red cube came before putting the red
			// cube in the box, though it was part of doing that.  (But
			// picking up the red cube itself was part of putting it in the
			// box, not before.)
			ok = timeValue(g.finish) <= timeValue(other.start) or
			  (self.isPartOf(g, other) and not self.sharesThings(g, other))
		else if c.pred == "after" then
			ok = timeValue(g.start) >= timeValue(other.finish)
		else if c.pred == "for" then
			// "What did you have to move to do that?"  Something done as part
			// of it, to other things than what it was about.
			ok = self.isPartOf(g, other) and not self.sharesThings(g, other)
		else if c.pred == "while" then
			// (Inclusive: picking up a block is touching it while you pick it up.)
			ok = timeValue(g.start) >= timeValue(other.start) and
			  timeValue(g.finish) <= timeValue(other.finish)
		else
			self.fail "I don't know what """ + c.pred + """ means for an event."
			return false
		end if
		if not ok then return false
	end for
	return true
end function

// Was goal g done as part of goal other (as a step, or a step of a step...)?
Brain.isPartOf = function(g, other)
	p = g.parent
	while p
		if refEquals(p, other) then return true
		p = p.parent
	end while
	return false
end function

// Is any of goal g's things also one of other's?
Brain.sharesThings = function(g, other)
	for t in g.args
		if containsRef(other.args, t) then return true
	end for
	return false
end function

// "How do you build a steeple?"  "By stacking up two green cubes and a
// pyramid."  We can say how to build something we were taught, from the
// words the user taught it with.
Brain.answerMethod = function(var)
	e = self.lookup(var)
	if e == null then return null
	if e.verb == "build" and e.args then
		d = self.lookup(e.args[0])
		word = d.head
		if word == "one" then word = self.antecedentNoun(d)
		if self.definitions.hasIndex(word) and self.definitions[word].hasIndex("parts") then
			return "By stacking up " + self.definitions[word].parts + "."
		end if
		return "Sorry, I don't know how to build " + speech.withArticle(word) + "."
	end if
	return "I can only explain how to build things you've taught me about."
end function

// "What did you do last?"  "I put the red cube in the box."
Brain.answerWhatDone = function(var)
	g = self.findGoal(var)
	if g == null then return null
	self.focus.event = g
	if g.kind != "stack" then self.focus.it = g.args[0]
	return "I " + speech.goalPhrase(self.world, g, "ed") + "."
end function

Brain.answerAboutEvent = function(q)
	if q.q == "when" then
		g = self.findGoal(q.target)
	else
		g = self.findGoal(q.target, "I can't explain a nonexistent event.")
	end if
	if g == null then return null
	if g.kind != "stack" then self.focus.it = g.args[0]
	it = self.focus.it
	w = self.world
	if q.q == "why" then
		// The reason for a goal is the goal it was serving.
		if g.parent == null then
			self.focus.event = g
			return "Because you asked me to."
		end if
		self.focus.event = g.parent
		return "To " + speech.goalPhrase(w, g.parent, "to", it) + "."
	else if q.q == "how" then
		// How it was done: the steps it took.
		self.focus.event = g
		steps = []
		teller = speech.Teller.make(w, it)
		for child in g.children
			steps.push teller.step(child)
		end for
		// The final move isn't a goal of its own, but it's worth mentioning.
		teller.it = it
		if g.kind == "putOn" then steps.push speech.settingDownPhrase(w, g.args[1], teller)
		if g.kind == "getRidOf" then steps.push speech.settingDownPhrase(w, w.table, teller)
		if not steps then return "I just did it."
		return "By " + steps.join(", then ") + "."
	else
		// When: during whatever the user had asked for.  (A "Why?" after
		// this asks about the same event.)
		self.focus.event = g
		root = g.root
		if refEquals(root, g) then return "When you asked me to."
		return "While I was " + speech.goalPhrase(w, root, "ing", it) + "."
	end if
end function

//----------------------------------------------------------------------
// Understanding English: choosing among readings
//----------------------------------------------------------------------

// Respond to a sentence in English.  The parser may find more than one
// reading; we take the first that makes sense in the world as it is now,
// and if another sensible reading would mean something different, we say
// which we assumed, as Winograd's robot did.
Brain.hear = function(text)
	// The answer to a question we just asked?
	if self.question then
		q = self.question
		self.question = null
		n = choiceNumber(text)
		if n and n <= q.choices.len then return self.actOn(q.understanding, q.choices[n-1])
	end if
	// Telling us which one, after "I don't understand which pyramid you mean"?
	if self.pending then
		p = self.pending
		self.pending = null
		reply = self.settle(p, text)
		if reply then return reply
	end if
	r = meaning.understand(text, self.knownNames, self.definitions.indexes)
	self.lastUnderstanding = r      // for showing what happened under the hood
	if r.error then return r.error
	pick = self.pickReading(r)
	if pick.question then
		self.question = pick.question
		return pick.question.text
	end if
	if pick.sensible != true then
		// Maybe nothing makes sense, because "it" meant something said
		// earlier in this sentence?
		reply = self.tryItReadings(r, pick)
		if reply then return reply
	end if
	reply = self.actOn(r, pick.index)
	if pick.note then reply = pick.note + " " + reply
	return reply
end function

// "What did the box contain before you put the red cube in it?"  "It" is
// usually what we were just talking about, but when that makes no sense,
// it may be something earlier in the same sentence (here, the box).  If one
// of those readings makes sense, we act on it, and say what we took "it" to
// mean.  Returns the reply, or null if none makes sense (or if the reading
// we picked made sense after all).
Brain.tryItReadings = function(r, pick)
	alt = meaning.itReadings(r)
	if not alt.programs then return null
	if pick.sensible == null and not self.check(r.programs[pick.index]).problem then return null
	for i in alt.programs.indexes
		if self.check(alt.programs[i]).problem then continue
		reply = self.actOn(alt, i)
		return "By ""it"", I assume you mean " + speech.echoPhrase(alt.itMeans[i]) + ". " + reply
	end for
	return null
end function

// After "I don't understand which green cube you mean.", the user may just
// say which: "The one supporting a pyramid."  "The small one."  "Any one."
// That's a noun phrase on its own, and it finishes what they asked before:
//   Put the blue pyramid on the green cube.
//   x2 = the cube [color green]
// becomes
//   x2 = the cube [color green] [supports x3]
//   x3 = a pyramid
// and we try again.  "Any one" (or "a green one") lets us choose.  Returns
// the reply, or null if the text isn't a noun phrase (so it's something
// new).
Brain.settle = function(p, text)
	r = parser.parseNounPhrase(text, self.knownNames, self.definitions.indexes)
	if r.error then return null
	prog = p.understanding.programs[p.index]
	d = prog.lookup(p.var)
	m = meaning.Meaning.make
	m.prog = prog
	newVar = m.describe(r.trees[0])
	answer = prog.lookup(newVar)
	if answer.kind != "description" then return null
	// The answer adds to the description, rather than standing apart from
	// it.  (What it mentions, like "a pyramid", stays in the program.)
	prog.lines.remove prog.lines.indexOf(answer)
	prog.vars.remove newVar
	d.props += answer.props
	if ["one", "thing"].indexOf(answer.head) == null and not icl.pronouns.hasIndex(answer.head) then
		d.head = answer.head
	end if
	if answer.det == "a" or answer.det == "any" then d.det = "a"
	return self.actOn(p.understanding, p.index)
end function

// Carry out one reading of what the user said, and reply.
Brain.actOn = function(r, index)
	r.chosen = index
	self.phrases = {}
	for p in r.phrases[index]
		self.phrases[p.var] = p.words
	end for
	reply = self.respond(r.programs[index])
	self.phrases = null
	// If we couldn't tell which thing was meant, the user may tell us.
	if self.failed and self.unclear then
		self.pending = {"understanding": r, "index": index, "var": self.unclear}
	end if
	note = self.itNote
	if note then reply = note + " " + reply
	return reply
end function

// "2" (or "2." or " 2 ") as an answer to "Do you mean: 1 - ... 2 - ...?",
// or null if it isn't a number like that.
choiceNumber = function(text)
	digits = ""
	for c in text
		if c == " " or c == "." then continue
		if "0123456789".indexOf(c) == null then return null
		digits += c
	end for
	if not digits then return null
	return digits.val
end function

// The names the user has given things, which the parser should treat as
// names ("superblock").
Brain.knownNames = function
	result = []
	for t in self.world.things
		result += t.names
	end for
	return result
end function

// Which reading to act on: {index, note, question}, where note (if any)
// says which reading we assumed, and question (if any) is a question to
// ask the user instead (see senseQuestion).
//
// `sensible` says whether the reading picked makes sense: true, false, or
// null if there was only one reading, so we didn't check.
Brain.pickReading = function(r)
	if r.programs.len == 1 then return {"index": 0, "note": null, "question": null, "sensible": null}
	checks = []
	sensible = []
	for i in r.programs.indexes
		checks.push self.check(r.programs[i])
		if checks[i].problem == null then sensible.push i
	end for
	// If none make sense, go with the most likely one, so the user hears
	// what's wrong with it.
	if not sensible then return {"index": 0, "note": null, "question": null, "sensible": false}
	best = sensible[0]
	for i in sensible[1:]
		if checks[i].summary != checks[best].summary then
			q = self.senseQuestion(r, sensible, checks)
			if q then return {"index": null, "note": null, "question": q, "sensible": true}
			return {"index": best, "note": self.assumption(r, best, i), "question": null, "sensible": true}
		end if
	end for
	return {"index": best, "note": null, "question": null, "sensible": true}
end function

// Some words have senses the robot shouldn't guess between ("on top of":
// directly on, or anywhere above; see the lexicon).  When readings that
// use different senses of such a word would mean different things, we
// ask which the user meant, as Winograd's robot did:
//   I'm not sure what you mean by "on top of" in the phrase "on top of
//   green cubes".  Do you mean:
//   1 - directly on the surface
//   2 - anywhere on top of?
// Returns {text, understanding, choices}, where choices are the readings
// to act on for each answer; or null if there's nothing to ask.
Brain.senseQuestion = function(r, sensible, checks)
	choices = []
	senses = []
	summaries = []
	word = null
	phrase = null
	for i in sensible
		pp = sensePhrase(r.trees[i])
		if pp == null then continue
		sense = pp.parts[0].entry.sense
		if senses.indexOf(sense) != null then continue
		choices.push i
		senses.push sense
		if summaries.indexOf(checks[i].summary) == null then summaries.push checks[i].summary
		word = pp.parts[0].word
		phrase = parser.wordsOf(pp)
	end for
	if summaries.len < 2 then return null
	lines = ["I'm not sure what you mean by """ + word + """ in the phrase """ + phrase + """.  Do you mean:"]
	for i in senses.indexes
		lines.push (i+1) + " - " + senses[i]
	end for
	return {"text": lines.join(char(10)) + "?", "understanding": r, "choices": choices}
end function

// The first phrase in a parse tree whose preposition has a sense to ask
// about ("on top of green cubes"), or null.
sensePhrase = function(tree)
	if parser.isLeaf(tree) then return null
	if tree.cat == "PP" and tree.parts[0].hasIndex("entry") and tree.parts[0].entry.hasIndex("sense") then
		return tree
	end if
	for p in tree.parts
		found = sensePhrase(p)
		if found then return found
	end for
	return null
end function

// "By 'the block in the box', I assume you mean the blue block."  The
// phrase we name is the longest one that the chosen reading has and the
// other one doesn't: that's where the two readings part ways.
Brain.assumption = function(r, chosen, other)
	otherWords = []
	for p in r.phrases[other]
		otherWords.push p.words
	end for
	phrase = null
	for p in r.phrases[chosen]
		if otherWords.indexOf(p.words) != null then continue
		if phrase == null or p.words.len > phrase.words.len then phrase = p
	end for
	if phrase == null then return null
	// "The thing that supports it", where "it" is whatever is being
	// tested, isn't one thing we could name.
	savedProg = self.prog
	self.prog = r.programs[chosen]
	varies = self.variesPerThing(phrase.var)
	self.prog = savedProg
	if varies then return null
	things = self.check(r.programs[chosen], phrase.var).referents[phrase.var]
	if not things then return null
	return "By """ + phrase.words + """, I assume you mean " + speech.specificNamesFor(self.world, things) + "."
end function

// Would this program make sense right now?  Works out what each statement
// refers to, without doing anything, and leaves the brain as it was.
// Returns {problem, summary, referents}:
//   problem    the complaint it would make, or null if none
//   summary    what it means, as text: each statement and the ids of the
//              things it's about (two readings with the same summary mean
//              the same thing)
//   referents  var -> the things each statement's arguments refer to (plus
//              alsoVar, if given)
// (Commands are not carried out, so a later statement in the same sentence
// is checked against the world as it is now.)
Brain.check = function(prog, alsoVar=null)
	saved = {"focus": self.focus + {}, "prog": self.prog, "chosen": self.chosen}
	self.prog = prog
	self.chosen = {}
	self.problem = null
	summary = []
	referents = {}
	for statement in prog.statements
		self.cache = {}
		self.busy = {}
		summary.push self.checkStatement(statement, referents)
		if self.problem then break
	end for
	problem = self.problem
	if alsoVar and not referents.hasIndex(alsoVar) and not problem then
		referents[alsoVar] = self.choose(alsoVar)
	end if
	self.focus = saved.focus
	self.prog = saved.prog
	self.chosen = saved.chosen
	self.problem = null
	return {"problem": problem, "summary": summary.join("; "), "referents": referents}
end function

// Check one statement (see check).  Returns its summary.
Brain.checkStatement = function(statement, referents)
	if statement.kind == "ask" then
		words = ["ask", statement.q, statement.attr]
		vars = [statement.target]
		if statement.claim then vars += icl.varsUsedIn(statement.claim)
	else
		words = [statement.kind, statement.verb]
		vars = statement.args
	end if
	for i in vars.indexes
		var = vars[i]
		if not icl.isVar(var) then
			words.push var      // a word, like the name in "Name x1, superblock"
			continue
		end if
		if statement.kind == "declare" and statement.verb == "define" then
			// A definition isn't about anything in the world.
			words.push var
			continue
		end if
		item = self.lookup(var)
		if item == null then break
		if item.kind == "event" then
			g = self.findGoal(var)
			if g == null then break
			words.push g.kind + "@" + timeValue(g.start)
			continue
		end if
		if statement.kind == "command" and (statement.verb == "stack" or statement.verb == "stackUp") and
		  vars.len == 1 then
			// "Stack the green pyramid on top of the red cube" doesn't mean
			// a stack of one thing.
			things = self.choose(var)
			if things != null and things.len < 2 then self.fail "I need at least two things to make a stack."
		else if statement.kind == "command" and statement.verb == "build" then
			things = self.buildParts(var)
		else if statement.kind == "command" then
			things = self.choose(var)
		else
			things = self.refer(var)
			if things != null then things = things.things
		end if
		if things == null then break
		referents[var] = things
		words.push idsOf(things)
		// As in carrying it out: the first argument becomes "it", for the
		// rest of the sentence.
		if i == 0 then self.noteFocus var, things
	end for
	// Two readings of a yes/no question may be about the same things and
	// still mean different things: "Is the green pyramid on top of the blue
	// block?" (directly on it, or anywhere above it).  So the answer is part
	// of what it means.
	if statement.kind == "ask" and statement.q == "yes-no" and not self.problem then
		words.push "answer: " + self.answerYesNo(statement.target, statement.claim)
	end if
	return words.join(" ")
end function

// The ids of some things, like "b1,p2".
idsOf = function(things)
	ids = []
	for t in things
		ids.push t.id
	end for
	return ids.join(",")
end function

//----------------------------------------------------------------------
// Declarations
//----------------------------------------------------------------------

// "Call it superblock."
Brain.giveName = function(statement)
	if statement.args.len != 2 then return self.fail("(Name needs a thing and a name.)")
	things = self.definite(statement.args[0])
	if things == null then return null
	if things.len != 1 then return self.fail("I can only give a name to one thing at a time.")
	things[0].names.push statement.args[1]
	self.noteFocus statement.args[0], things
	return "OK."
end function

//----------------------------------------------------------------------
// Ownership
//
// The user can tell us what they own, either particular things ("The
// blue pyramid is mine") or kinds of thing ("I own blocks which are not
// red").  A kind is kept as its description, and checked whenever it
// matters, so it covers things that come to fit it later.  What we were
// told last counts most, so in "I own blocks which are not red, but I
// don't own anything which supports a pyramid", a blue block that
// supports a pyramid isn't owned.
//----------------------------------------------------------------------

// "Own x1" or "DontOwn x1".  Each thing we're told about, or kind of thing,
// goes in self.ownership as {things, owned} or {prog, var, owned}.
Brain.learnOwnership = function(statement, owned)
	var = statement.args[0]
	d = self.lookup(var)
	if d == null then return null
	if isDefinite(d) then
		things = self.definite(var)
		if things == null then return null
		self.noteFocus var, things
		self.ownership.push {"things": things, "owned": owned}
	else
		self.ownership.push {"prog": self.prog, "var": var, "owned": owned}
	end if
	return "I understand."
end function

// Does the user own this thing?  true, false, or null if we haven't been
// told either way.
Brain.owns = function(thing)
	for i in range(self.ownership.len - 1, 0, -1)
		entry = self.ownership[i]
		if entry.hasIndex("things") then
			if containsRef(entry.things, thing) then return entry.owned
		else if self.fitsDescription(thing, entry) then
			return entry.owned
		end if
	end for
	return null
end function

// Does a thing fit a description the user gave in an earlier sentence?
// `entry` has the program and variable.  The description is checked
// against the world as it is now, and anything that goes wrong (say, "the
// pyramid" in it no longer makes sense) just means it doesn't fit.
Brain.fitsDescription = function(thing, entry)
	if entry.hasIndex("checking") then return false     // a description that mentions itself
	entry.checking = true
	saved = {"prog": self.prog, "cache": self.cache, "busy": self.busy,
	  "problem": self.problem, "used": self.used}
	self.prog = entry.prog
	self.cache = {}
	self.busy = {}
	self.problem = null
	fits = false
	d = self.lookup(entry.var)
	things = self.thingsForHead(d)
	if things and containsRef(things, thing) then
		passed = self.filter([thing], d.props)
		fits = passed != null and passed.len == 1
	end if
	for key in saved.indexes
		self[key] = saved[key]
	end for
	entry.remove "checking"
	return fits
end function

//----------------------------------------------------------------------
// Definitions: words the user teaches us
//----------------------------------------------------------------------

// Is this a noun we know, either built in or taught?
Brain.isNoun = function(word)
	return relations.nouns.indexOf(word) != null or self.definitions.hasIndex(word)
end function

// "A 'steeple' is a stack which contains two green cubes and a pyramid."
//   x1 = a stack [contains x4]  ...  Define steeple, x1
// We keep the program the description is in, and from then on "steeple"
// means anything that fits x1 (see definedThings).
Brain.define = function(statement)
	if statement.args.len != 2 or icl.isVar(statement.args[0]) or not icl.isVar(statement.args[1]) then
		return self.fail("(Define needs a word and a description.)")
	end if
	word = statement.args[0]
	d = self.lookup(statement.args[1])
	if d == null then return null
	if d.kind != "description" then return self.fail("I can only define a word as one kind of thing.")
	if isDefinite(d) then
		return self.fail("That sounds like one particular thing.  To give it a name, say ""Call it " + word + """.")
	end if
	if relations.nouns.indexOf(word) != null then return self.fail("I already know the word """ + word + """.")
	self.definitions[word] = {"prog": self.prog, "var": statement.args[1]}
	// Remember what it's made of, in the user's words, for "How do you
	// build a steeple?"
	for c in d.props
		if c.pred == "contains" and c.args.len == 1 then
			self.definitions[word].parts = self.wordsFor(c.args[0])
		end if
	end for
	return "I understand."
end function

// The things a taught word fits: whatever fits its description, worked out
// in the program that defined it.
Brain.definedThings = function(word)
	if self.expanding.hasIndex(word) then
		return self.fail("(I went in circles: """ + word + """ is defined in terms of itself.)")
	end if
	def = self.definitions[word]
	self.expanding[word] = true
	saved = self.enter(def.prog)
	result = self.candidates(def.var)
	self.leave saved
	self.expanding.remove word
	return result
end function

// Work in another program (a definition's) for a while.  Returns what to
// pass to leave, to get back.
Brain.enter = function(prog)
	saved = {"prog": self.prog, "cache": self.cache, "busy": self.busy,
	  "bound": self.bound, "chosen": self.chosen, "used": self.used}
	self.prog = prog
	self.cache = {}
	self.busy = {}
	self.bound = null
	self.chosen = {}
	self.used = null
	return saved
end function

Brain.leave = function(saved)
	for kv in saved
		self[kv.key] = kv.value
	end for
end function

// "Build one" (meaning a steeple): stack up the things its definition says
// a steeple contains.
Brain.build = function(cmd)
	if cmd.args.len != 1 then return self.fail("(Build needs one thing.)")
	parts = self.buildParts(cmd.args[0])
	if parts == null then return null
	first = self.world.goals.len
	problem = self.planner.achieve("stack", parts)
	root = self.world.goals[first]
	root.verb = cmd.verb
	self.focus.event = root
	if problem then return self.fail(problem)
	// What we built is "it" now.
	for s in relations.stacks(self.world)
		if self.allIn(parts, s.parts) then self.focus.it = s
	end for
	self.focus.them = null
	return "OK."
end function

// Are all of these things in that list?
Brain.allIn = function(things, list)
	for t in things
		if not containsRef(list, t) then return false
	end for
	return true
end function

// What to stack up to build what a description describes.  We can build
// stacks of given things, so the description must be a word we were
// taught, meaning a stack that contains certain things.  We choose them as
// we would for a command ("a pyramid" is one that's little trouble to get).
Brain.buildParts = function(var)
	d = self.lookup(var)
	if d == null then return null
	if d.kind != "description" or d.plural then return self.fail("I can only build one thing at a time.")
	word = d.head
	if word == "one" then word = self.antecedentNoun(d)
	if word == "stack" then return self.fail("What should I stack up?")
	if not self.definitions.hasIndex(word) then
		return self.fail("Sorry, I don't know how to build " + speech.withArticle(word) + ".")
	end if
	def = self.definitions[word]
	saved = self.enter(def.prog)
	parts = self.stackParts(def.var, word)
	self.leave saved
	return parts
end function

// The things a stack description says it contains, chosen.
Brain.stackParts = function(var, word)
	d = self.lookup(var)
	cantBuild = "Sorry, I don't know how to build " + speech.withArticle(word) + "."
	if d.head != "stack" then return self.fail(cantBuild)
	parts = []
	for c in d.props
		if c.pred != "contains" or c.args.len != 1 or not icl.isVar(c.args[0]) then return self.fail(cantBuild)
		things = self.choose(c.args[0])
		if things == null then return null
		for t in things
			if not containsRef(parts, t) then parts.push t
		end for
	end for
	if parts.len < 2 then return self.fail(cantBuild)
	return parts
end function
