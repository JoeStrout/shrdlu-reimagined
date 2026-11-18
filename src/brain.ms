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

containsRef = @world.containsRef

Brain = {}
Brain.world = null

// What we've been talking about, for "it", "them", "one", and "do that".
Brain.focus = null      // {it: Thing, them: list of Things, noun: string, event: Goal}

// The planner that carries out commands.
Brain.planner = null

// The object the user last clicked on, for "this" and "that".
Brain.selected = null

// What the user has told us they own (see Brain.owns).
Brain.ownership = null

// Per-sentence working state.
Brain.prog = null       // the ICL program being handled
Brain.cache = null      // var -> candidates, so each is only worked out once
Brain.chosen = null     // var -> the things picked for "a block" etc. in a command
Brain.busy = null       // vars being resolved right now (to catch loops)
Brain.problem = null    // a reply explaining what went wrong, or null
Brain.used = null       // while filtering: see Brain.filter

Brain.make = function(theWorld)
	b = new Brain
	b.world = theWorld
	b.focus = {"it": null, "them": null, "noun": null, "event": null}
	b.planner = planner.Planner.make(theWorld)
	b.ownership = []
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
			break
		end if
		// "Find a block ... and put it in the box" gets just one "OK."
		if not replies or reply != replies[-1] then replies.push reply
	end for
	return replies.join(" ")
end function

Brain.handle = function(statement)
	if statement.hasIndex("verb") and statement.verb == "thank" then return "You're welcome!"
	if statement.kind == "ask" then return self.answer(statement)
	if statement.kind == "command" then return self.command(statement)
	if statement.kind == "declare" and statement.verb == "name" then return self.giveName(statement)
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
	if self.cache.hasIndex(var) then return self.cache[var]
	d = self.lookup(var)
	if d == null then return null
	if self.busy.hasIndex(var) then
		return self.fail("(I went in circles: " + var + " is described in terms of itself.)")
	end if
	self.busy[var] = true
	result = self.thingsForHead(d)
	if result != null then result = self.filter(result, d.props)
	self.busy.remove var
	if self.problem then return null
	self.cache[var] = result
	return result
end function

// The things a description's head word could mean, before any constraints.
Brain.thingsForHead = function(d)
	head = d.head
	// "this" and "that" mean what the user clicked on, if anything.
	if (head == "this" or head == "that") and self.selected then return [self.selected]
	if head == "it" or head == "that" or head == "this" then
		if self.focus.it == null then return self.fail("I don't know what you mean by """ + head + """.")
		return [self.focus.it]
	end if
	if head == "them" or head == "they" then
		if not self.focus.them then return self.fail("I don't know what you mean by """ + head + """.")
		return self.focus.them[:]
	end if
	if head == "one" then head = self.antecedentNoun(d)
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
		if relations.nouns.indexOf(item.head) != null then found = item.head
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
Brain.filter = function(things, props)
	savedUsed = self.used
	passed = []     // the things that meet every constraint...
	usedBy = []     // ...and for each, inner "the" var -> what it was related to
	for t in things
		self.used = {}
		ok = true
		for c in props
			if relations.superlatives.hasIndex(c.pred) then continue
			if not self.test(t, c) then
				ok = false
				break
			end if
		end for
		if self.problem then return null
		if ok then
			passed.push t
			usedBy.push self.used
		end if
	end for
	self.used = savedUsed
	result = passed
	for c in props
		if relations.superlatives.hasIndex(c.pred) then result = relations.extreme(result, c.pred)
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
			return self.fail("I don't understand which " + speech.descriptionPhrase(d, false) + " you mean.")
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
	if d.det != "the" or d.plural then return self.refer(var)
	things = self.candidates(var)
	if things == null then return null
	if things.len <= 1 then return self.refer(var)
	return {"things": things, "quantity": "some", "n": 0, "inner": var}
end function

// Does one thing meet one constraint?// Does one thing meet one constraint?
Brain.test = function(thing, c)
	pred = c.pred
	if pred == "not" then return not self.test(thing, c.args[0])
	if pred == "or" then
		for alternative in c.args
			if self.test(thing, alternative) then return true
		end for
		return false
	end if
	if pred == "commanded" then return self.wasCommanded(thing, c.args)
	if pred == "owned" then return self.owns(thing) == true
	if relations.unary.hasIndex(pred) then return relations.unary[pred](self.world, thing)
	if relations.valued.hasIndex(pred) then return relations.valued[pred](self.world, thing, c.args[0])
	if relations.binary.hasIndex(pred) then
		if c.args.len != 1 or not icl.isVar(c.args[0]) then
			return self.fail("([" + pred + "] needs one variable.)")
		end if
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
	if d.det == null or d.det == "the" then
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
		return self.fail("I don't see any " + speech.descriptionPhrase(d, true) + ".")
	end if
	if things.len > 1 and not d.plural then
		// "The pyramid", when there are several, can still mean the one
		// that's clicked on, or the one we were just talking about.
		things = self.inFocus(things)
		if things.len != 1 then
			return self.fail("I don't understand which " + speech.descriptionPhrase(d, false) + " you mean.")
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
	if d and relations.nouns.indexOf(d.head) != null then self.focus.noun = d.head
	if things.len == 1 then self.focus.it = things[0]
	if things.len > 1 then self.focus.them = things[:]
end function

//----------------------------------------------------------------------
// Questions
//----------------------------------------------------------------------

Brain.answer = function(q)
	if q.q == "why" or q.q == "how" or q.q == "when" then return self.answerAboutEvent(q)
	if q.q == "exists" then return self.answerExists(q.target)
	if q.q == "count" then return self.answerCount(q.target)
	if q.q == "which" then return self.answerWhich(q.target)
	if q.q == "attribute" then return self.answerAttribute(q.target, q.attr)
	if q.q == "yes-no" then return self.answerYesNo(q.target, q.claim)
	return self.fail("(I don't know that kind of question.)")
end function

// "Is there a big red block?"
Brain.answerExists = function(var)
	things = self.candidates(var)
	if things == null then return null
	if not things then return "No."
	self.noteFocus var, things
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
	if d.head == "thing" then return speech.numberWord(things.len) + " things: " + names
	return speech.numberWord(things.len) + " of them: " + names
end function

// "How many blocks are not in the box?"
Brain.answerCount = function(var)
	things = self.candidates(var)
	if things == null then return null
	if not things then return "None."
	self.noteFocus var, things
	return speech.capitalize(speech.numberWord(things.len)) + " of them."
end function

// "Which cube is on the table?"  "What does the box contain?"
// "Which cube" asks us to pick out each one, so we say enough to tell it
// from the other cubes; "what" just asks what's there.
Brain.answerWhich = function(var)
	things = self.candidates(var)
	if things == null then return null
	if not things then return "None."
	self.noteFocus var, things
	noun = self.lookup(var).head
	if noun == "thing" then
		names = speech.namesFor(self.world, things)
	else
		names = speech.specificNamesFor(self.world, things, noun)
	end if
	return speech.capitalize(names) + "."
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
		if not things then return self.fail("I don't see any " + speech.descriptionPhrase(d, true) + ".")
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
	if attr == "shape" then return thing.noun
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

//----------------------------------------------------------------------
// Commands
//----------------------------------------------------------------------

// The commands we understand, and the kind of goal each one sets.
// ("putDown" and "find" are handled here rather than by the planner.)
commandGoals = {
  "pickUp": "grasp", "grasp": "grasp",
  "putOn": "putOn", "putIn": "putOn", "putDown": "putDown", "drop": "putDown",
  "clearOff": "clearOff", "cleanOff": "clearOff",
  "getRidOf": "getRidOf",
  "stack": "stack", "stackUp": "stack",
  "find": "find"}

Brain.command = function(cmd)
	if not commandGoals.hasIndex(cmd.verb) then
		return "Sorry, I don't know how to " + cmd.verb + "."
	end if
	kind = commandGoals[cmd.verb]
	// Work out what each argument means.
	groups = []
	for var in cmd.args
		things = self.choose(var)
		if things == null then return null
		groups.push things
	end for

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
		problem = self.planner.achieve(g[0], g[1])
		root = self.world.goals[first]
		root.verb = cmd.verb
		self.focus.event = root
		if problem then return self.fail(problem)
	end for
	if cmd.args then self.noteFocus cmd.args[0], groups[0]
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
	if d.det == null or d.det == "the" then
		things = self.definite(var)
	else
		things = self.candidates(var)
		if things == null then return null
		want = things.len
		if d.det == "a" or d.det == "any" or d.det == "which" then want = 1
		if d.det == "number" or d.det == "at-least" then want = d.n
		if things.len == 0 or things.len < want then
			return self.fail("I don't see enough " + speech.descriptionPhrase(d, true) + ".")
		end if
		things = self.leastTrouble(things)[:want]
	end if
	if things == null then return null
	self.chosen[var] = things
	return things
end function

// Sort things by how much trouble they'd be to pick up.
Brain.leastTrouble = function(things)
	hand = self.world.hand
	scored = []
	for t in things
		cost = 0
		if not refEquals(t, hand.holding) then
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

// The kinds of goal each event verb can mean.
eventGoals = {
  "pickUp": "grasp", "grasp": "grasp",
  "putOn": "putOn", "putIn": "putOn", "putDown": "putOn",
  "clearOff": "clearOff", "cleanOff": "clearOff",
  "getRidOf": "getRidOf",
  "stack": "stack", "stackUp": "stack"}

// Times are [turn, step]; this makes them easy to compare.
timeValue = function(t)
	return t[0] * 100000 + t[1]
end function

// Which goal an event description means: the most recent one that fits.
// "Do" with no arguments ("why did you do that?") means the goal we were
// just talking about.
Brain.findGoal = function(var)
	e = self.lookup(var)
	if e == null then return null
	if e.kind != "event" then return self.fail("(" + var + " isn't an event.)")
	if e.verb == "do" and not e.args then
		if self.focus.event == null then return self.fail("I don't know what you mean.")
		return self.focus.event
	end if
	if not eventGoals.hasIndex(e.verb) then return self.fail("I don't know what it means to " + e.verb + ".")
	kind = eventGoals[e.verb]
	// What each argument refers to.
	refs = []
	for a in e.args
		ref = self.refer(a)
		if ref == null then return null
		refs.push ref.things
	end for
	// The other events its time constraints refer to.
	others = []
	for c in e.props
		other = self.findGoal(c.args[0])
		if other == null then return null
		others.push other
	end for
	for i in range(self.world.goals.len - 1, 0, -1)
		g = self.world.goals[i]
		if g.kind != kind then continue
		if not self.goalArgsFit(g, refs) then continue
		if not self.goalTimesFit(g, e.props, others) then continue
		return g
	end for
	if self.problem then return null
	return self.fail("I don't remember doing that.")
end function

// Does each argument of the event match the goal?  (For a stack, which has
// any number of things, each argument just has to be one of them.)
Brain.goalArgsFit = function(g, refs)
	for i in refs.indexes
		if g.kind == "stack" then
			candidates = g.args
		else if i < g.args.len then
			candidates = [g.args[i]]
		else
			return false
		end if
		found = false
		for t in refs[i]
			if containsRef(candidates, t) then found = true
		end for
		if not found then return false
	end for
	return true
end function

// Check an event's time constraints: [before e2], [after e2], [while e2].
Brain.goalTimesFit = function(g, props, others)
	for i in props.indexes
		c = props[i]
		other = others[i]
		if c.pred == "before" then
			ok = timeValue(g.finish) <= timeValue(other.start)
		else if c.pred == "after" then
			ok = timeValue(g.start) >= timeValue(other.finish)
		else if c.pred == "while" then
			ok = not refEquals(g, other) and timeValue(g.start) >= timeValue(other.start) and
			  timeValue(g.finish) <= timeValue(other.finish)
		else
			self.fail "I don't know what """ + c.pred + """ means for an event."
			return false
		end if
		if not ok then return false
	end for
	return true
end function

Brain.answerAboutEvent = function(q)
	g = self.findGoal(q.target)
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
		for child in g.children
			steps.push speech.goalPhrase(w, child, "ing", it)
		end for
		// The final move isn't a goal of its own, but it's worth mentioning.
		if g.kind == "putOn" then steps.push speech.settingDownPhrase(w, g.args[1])
		if g.kind == "getRidOf" then steps.push speech.settingDownPhrase(w, w.table)
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
	r = meaning.understand(text, self.knownNames)
	self.lastUnderstanding = r      // for showing what happened under the hood
	if r.error then return r.error
	pick = self.pickReading(r)
	r.chosen = pick.index
	reply = self.respond(r.programs[pick.index])
	if pick.note then reply = pick.note + " " + reply
	return reply
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

// Which reading to act on: {index, note}, where note (if any) says which
// reading we assumed.
Brain.pickReading = function(r)
	if r.programs.len == 1 then return {"index": 0, "note": null}
	checks = []
	sensible = []
	for i in r.programs.indexes
		checks.push self.check(r.programs[i])
		if checks[i].problem == null then sensible.push i
	end for
	// If none make sense, go with the most likely one, so the user hears
	// what's wrong with it.
	if not sensible then return {"index": 0, "note": null}
	best = sensible[0]
	for i in sensible[1:]
		if checks[i].summary != checks[best].summary then
			return {"index": best, "note": self.assumption(r, best, i)}
		end if
	end for
	return {"index": best, "note": null}
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
		item = self.lookup(var)
		if item == null then break
		if item.kind == "event" then
			g = self.findGoal(var)
			if g == null then break
			words.push g.kind + "@" + timeValue(g.start)
			continue
		end if
		if statement.kind == "command" then
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
	if d.det == null or d.det == "the" then
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
