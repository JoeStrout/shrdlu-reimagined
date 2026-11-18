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

containsRef = @world.containsRef

Brain = {}
Brain.world = null

// What we've been talking about, for "it", "them", "one", and "do that".
Brain.focus = null      // {it: Thing, them: list of Things, noun: string, event: Goal}

// The planner that carries out commands.
Brain.planner = null

// The object the user last clicked on, for "this" and "that".
Brain.selected = null

// Per-sentence working state.
Brain.prog = null       // the ICL program being handled
Brain.cache = null      // var -> candidates, so each is only worked out once
Brain.chosen = null     // var -> the things picked for "a block" etc. in a command
Brain.busy = null       // vars being resolved right now (to catch loops)
Brain.problem = null    // a reply explaining what went wrong, or null

Brain.make = function(theWorld)
	b = new Brain
	b.world = theWorld
	b.focus = {"it": null, "them": null, "noun": null, "event": null}
	b.planner = planner.Planner.make(theWorld)
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
	if statement.kind == "ask" then return self.answer(statement)
	if statement.kind == "command" then return self.command(statement)
	if statement.kind == "declare" and statement.verb == "name" then return self.giveName(statement)
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
	return self.fail("I don't know the word """ + head + """.")
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
Brain.filter = function(things, props)
	result = []
	for t in things
		ok = true
		for c in props
			if relations.superlatives.hasIndex(c.pred) then continue
			if not self.test(t, c) then
				ok = false
				break
			end if
		end for
		if self.problem then return null
		if ok then result.push t
	end for
	for c in props
		if relations.superlatives.hasIndex(c.pred) then result = relations.extreme(result, c.pred)
	end for
	return result
end function

// Does one thing meet one constraint?
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
	if relations.unary.hasIndex(pred) then return relations.unary[pred](self.world, thing)
	if relations.valued.hasIndex(pred) then return relations.valued[pred](self.world, thing, c.args[0])
	if relations.binary.hasIndex(pred) then
		if c.args.len != 1 or not icl.isVar(c.args[0]) then
			return self.fail("([" + pred + "] needs one variable.)")
		end if
		ref = self.refer(c.args[0])
		if ref == null then return false
		related = @relations.binary[pred]
		count = 0
		for other in ref.things
			if not refEquals(other, thing) and related(self.world, thing, other) then count += 1
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
		return self.fail("I don't understand which " + speech.descriptionPhrase(d, false) + " you mean.")
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
	if things.len == 1 then return "Yes, " + speech.nameFor(self.world, things[0]) + "."
	return "Yes, " + speech.numberWord(things.len) + " of them: " + speech.namesFor(self.world, things) + "."
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
Brain.answerWhich = function(var)
	things = self.candidates(var)
	if things == null then return null
	if not things then return "None."
	self.noteFocus var, things
	return speech.capitalize(speech.namesFor(self.world, things)) + "."
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
	if not self.quantityOk(ref, meeting.len) then return "No."
	self.noteFocus var, ref.things
	// For "is there one which...", say which ones did.
	if ref.quantity == "some" or ref.quantity == "at-least" then
		self.noteFocus var, meeting
		return "Yes, " + speech.namesFor(self.world, meeting) + "."
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
		// When: during whatever the user had asked for.
		root = g.root
		if refEquals(root, g) then return "When you asked me to."
		return "While I was " + speech.goalPhrase(w, root, "ing", it) + "."
	end if
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
