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
import "listUtil"
import "stringUtil"

containsRef = @world.containsRef

Brain = {}
Brain.world = null

// What we've been talking about, for "it", "them", "one", and "do that".
Brain.focus = null      // {it: Thing, them: list of Things, noun: string, event: Goal,
                        //  built: the stack we just made, and when (see thingToName),
                        //  time: the moment we last talked about, for "then",
                        //  itFrom: how "it" came up (see noteFocus)}

// The planner that carries out commands.
Brain.planner = null

// The object the user last clicked on, for "this" and "that".
Brain.selected = null

// What the user has told us they own, like, and so on (see Brain.feels).
Brain.attitudes = null   // verb -> what the user told us (see learnAttitude)
// The other way around: constraint -> verb ("owned" -> "own").
Brain.attitudeFor = {}
for kv in icl.attitudes
	Brain.attitudeFor[kv.value] = kv.key
end for

// Standing orders: what we must never do, or must keep so (see learnOrder).
Brain.orders = null     // oldest first
Brain.ordersBefore = null  // during a command: Keep order -> what already wasn't so
Brain.vetoes = null     // during a command: the replies orders gave -> {goal, thing}
Brain.excluded = null   // during a command: things not to pick for "a block" (see command)

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
Brain.lastUnderstanding = null  // the understanding we last acted on (see hear)
Brain.lastActed = null  // ...and which reading: {understanding, index}, for "What about...?"
Brain.moving = []       // in a command, the variables for the things to be moved
Brain.commandKind = null  // in a command, the kind of goal it sets
Brain.mentioned = []    // the things this sentence has referred to so far (for "other")
Brain.lastMentioned = []  // ...and the last sentence
Brain.unclear = null    // the variable we just said we didn't understand ("which pyramid?")
Brain.pending = null    // what to finish if the user tells us which: {understanding, index, var}

// The two people in the conversation (see Brain.namePerson).
Brain.robotName = "Robot"   // what the robot is called; the user may change it
Brain.userName = null       // the user's name, once they tell us
Brain.askedName = false     // did we just ask the user's name?
Brain.saidLast = null       // the user's last sentence before this one, for "What did I say?"
Brain.saying = null         // ...and this one

Brain.make = function(theWorld)
	b = new Brain
	b.world = theWorld
	b.focus = {"it": null, "them": null, "noun": null, "nounAdjectives": [], "event": null, "time": null,
	  "itFrom": null, "built": null}
	b.planner = planner.Planner.make(theWorld)
	b.attitudes = {}
	b.orders = []
	b.vetoes = {}
	b.excluded = []
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
	if self.mentioned then self.lastMentioned = self.mentioned
	self.mentioned = []
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

// What the robot says to social niceties ("Thank you.", "Hello.", "Help.")
// and small talk ("How are you?").  The lexicon says which reply goes with
// which words.  In a reply, <robot> is the robot's name, and <, user> is a
// comma and the user's name, if we know it ("Hello, Joe!"), or nothing.
chatReplies = {
  "thanks": "You're welcome!",
  "hello": "Hello<, user>!  Ask me to move things, or ask me about them.",
  "praise": "Thank you!",
  "sorry": "That's all right.",
  "help": "I can pick things up, put them on or in other things, stack them up, and clear things off.  " +
    "You can ask me where things are, what color or size they are, what's on or in something, " +
    "and why, how or when I did something.  You can also teach me new words.  (Type /help for examples.)",
  "who": "I'm <robot>, a robot arm.  I live in this little world of blocks, and I'll do what you ask, if I can.",
  "stop": "OK.",
  "bye": "Goodbye<, user>!",
  "ok": "OK.",
  "about": "I'm <robot>, a robot arm in a little world of blocks.  I can move things, answer questions " +
    "about them, learn new words, and tell you why I did what I did.  Everything I say comes from " +
    "hand-written rules, with no machine learning.",
  "work": "I read your sentence with a grammar of English, and turn it into a little language of my " +
    "own, called ICL (type /icl to see it).  Then I work out which things you mean, and answer, or plan " +
    "the moves that do what you asked.  I remember my goals, so I can tell you why I did things.",
  "maker": "I was written by Joe Strout, with help from Claude.",
  "age": "I started up when this conversation began.",
  "howAreYou": "I'm fine, thank you.  Ready to move some blocks!",
  "meet": "Nice to meet you too<, user>.",
  "robot": "Yes, a robot arm.",
  "human": "No, I'm a robot arm.",
  "smart": "I know a lot about blocks, and not much else.",
  "here": "Yes, I'm here.",
  "understand": "Mostly.  When I don't, I'll say which part I didn't understand."}

// The reply to Chat (see chatReplies).
Brain.chat = function(kind)
	if kind == "said" then
		if self.saidLast == null then return "You haven't said anything yet."
		return "You said, """ + self.saidLast.trim + """"
	end if
	reply = chatReplies[kind].replace("<robot>", self.robotName)
	if self.userName then
		return reply.replace("<, user>", ", " + self.userName)
	end if
	return reply.replace("<, user>", "")
end function

Brain.handle = function(statement)
	if statement.hasIndex("verb") and statement.verb == "chat" then return self.chat(statement.args[0])
	if statement.kind == "declare" and statement.verb == "name" and isPerson(statement.args[0]) then
		return self.namePerson(statement.args[0], statement.args[1])
	end if
	if (statement.kind == "ask" or statement.kind == "claim") and isPerson(statement.target) then
		return self.answerAboutPerson(statement)
	end if
	if statement.kind == "ask" then return self.answer(statement)
	if statement.kind == "claim" then return self.checkClaim(statement)
	if statement.kind == "command" then return self.command(statement)
	if statement.kind == "declare" and statement.verb == "name" then return self.giveName(statement)
	if statement.kind == "declare" and statement.verb == "define" then return self.define(statement)
	if statement.kind == "declare" and statement.verb == "defineLike" then return self.defineLike(statement)
	if statement.kind == "declare" and attitudeOf(statement.verb) then return self.learnAttitude(statement)
	if statement.kind == "declare" and icl.orderVerbs.indexOf(statement.verb) != null then return self.learnOrder(statement)
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
		if result != null then result = self.filter(result, d.props + self.borrowedAdjectives(d), selfRef)
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
	// Not a noun we know: maybe it's a name the user gave something, or
	// some stack.
	t = self.world.thing(head)
	if t then return [t]
	for s in relations.stacks(self.world)
		if world.hasName(s, head) then return [s]
	end for
	// A stack that was named, but has since been taken apart.
	for s in self.namedStacks
		if world.hasName(s, head) then return self.fail(s.names[0] + " isn't a stack any more.")
	end for
	return self.fail("Sorry, I don't know the word """ + head + """.")
end function

// "One" borrows its noun from something said earlier: "a red one" after
// "a block" means a red block.  We look back through this sentence first,
// then at the last sentence, and settle for "thing" if there's nothing.
Brain.antecedentNoun = function(d)
	return self.antecedent(d).noun
end function

// What "one" stands for: {noun, adjectives}, from the last description in
// this sentence with a noun, or else from the last sentence.  The
// adjectives are its color and size words, as constraints.
Brain.antecedent = function(d)
	found = null
	for item in self.prog.lines
		if refEquals(item, d) then break
		if item.kind != "description" then continue
		if self.isNoun(item.head) then found = item
	end for
	if found then return {"noun": found.head, "adjectives": adjectivesOf(found)}
	if self.focus.noun then return {"noun": self.focus.noun, "adjectives": self.focus.nounAdjectives}
	return {"noun": "thing", "adjectives": []}
end function

// The color and size constraints of a description ("red", "large", "tall").
adjectivesOf = function(d)
	result = []
	for c in d.props
		if ["color", "size", "height", "breadth"].indexOf(c.pred) != null then result.push c
	end for
	return result
end function

// "One" with no adjectives of its own borrows the antecedent's too: after
// "How many red objects are there?", "Is there one on a green block?"
// means a red one.  But "a small one" (after "a big red block") is just
// small: it says what it is, so it borrows only the noun.  (Winograd's
// "Put a small one onto the green cube" is like that.)
Brain.borrowedAdjectives = function(d)
	if d.head != "one" or adjectivesOf(d) then return []
	return self.antecedent(d).adjectives
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
	// "The other green cube": not one we've just been talking about, in
	// this sentence or the last.
	if pred == "other" then return not containsRef(self.mentioned, thing) and not containsRef(self.lastMentioned, thing)
	if pred == "could" then
		// "Which blocks can you pick up?"  The ones that can be moved.
		e = self.lookup(c.args[0])
		if e.verb == "pickUp" or e.verb == "grasp" then return thing.movable
		return self.fail("I'm not sure what I could " + e.verb + ".")
	end if
	if pred == "commanded" then return self.wasCommanded(thing, c.args)
	if self.attitudeFor.hasIndex(pred) then
		// [owned] is the user's; [owned you] is the robot's
		person = "i"
		if c.args then person = c.args[0]
		return self.feels(self.attitudeFor[pred], thing, person)
	end if
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
	// "Both of the red blocks" says there are two, and "the three red
	// objects" says there are three.
	if d.det == "the" and d.n and things.len != d.n then
		return self.fail("I see " + speech.numberWord(things.len) + " " + self.phraseFor(d, things.len != 1) + ", not " + speech.numberWord(d.n) + ".")
	end if
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
	self.noteMentioned things
	return things
end function

// Note that this sentence referred to these things (see Brain.mentioned).
Brain.noteMentioned = function(things)
	for t in things
		if not containsRef(self.mentioned, t) then self.mentioned.push t
	end for
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
	self.noteMentioned things
	d = self.prog.lookup(var)
	if d and d.kind == "description" and self.isNoun(d.head) then
		self.focus.noun = d.head
		self.focus.nounAdjectives = adjectivesOf(d)
	end if
	// "One" passes on what it borrowed: after "Is there one on a green
	// block?" (a red object), "the blue one" is still an object, and a
	// later bare "one" is still a red object.
	if d and d.kind == "description" and d.head == "one" then
		a = self.antecedent(d)
		self.focus.noun = a.noun
		self.focus.nounAdjectives = adjectivesOf(d)
		if not self.focus.nounAdjectives then self.focus.nounAdjectives = a.adjectives
	end if
	// After "What is in the box?"  "The blue pyramid.", the last noun said
	// was the robot's own "pyramid", so "the green one" is a green pyramid.
	if d and d.kind == "description" and (d.head == "thing" or d.head == "object") and things then
		nouns = []
		for t in things
			if nouns.indexOf(t.noun) == null then nouns.push t.noun
		end for
		if nouns.len == 1 then
			self.focus.noun = nouns[0]
			self.focus.nounAdjectives = []
		end if
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
	// (With what "one" borrowed: "green cubes", for "the one" after "How
	// many green cubes are there?")
	for c in d.props + self.borrowedAdjectives(d)
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
	// "blocks which you own", "pyramids which I like"
	if self.attitudeFor.hasIndex(c.pred) then
		if c.args and c.args[0] == "you" then return "which I " + self.attitudeFor[c.pred]
		return "which you " + self.attitudeFor[c.pred]
	end if
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
	return speech.numberWord(things.len).capitalized + " of them."
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
	return names.capitalized + "."
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
	return speech.specificNamesFor(self.world, things).capitalized + "."
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
	if things.len == 1 then return self.placeOf(things[0]).capitalized + "."
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
	if clauses.len == 1 then return clauses[0].capitalized + "."
	return (clauses[:-1].join(", ") + ", and " + clauses[-1]).capitalized + "."
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
	// "What is that cube called?"
	if attr == "name" and things.len == 1 and not things[0].names then return "It doesn't have a name."
	values = []
	for t in things
		v = self.attributeOf(t, attr)
		if v == null then return self.fail("I don't know how to tell its " + attr + ".")
		if values.indexOf(v) == null then values.push v
	end for
	return speech.listPhrase(values).capitalized + "."
end function

Brain.attributeOf = function(thing, attr)
	if attr == "color" then return thing.color
	if attr == "shape" then return speech.withArticle(thing.noun)     // "a pyramid"
	if attr == "name" then
		if thing.names then return thing.names[0]
		return "one without a name"
	end if
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
	// "Do you like the box?"  If nobody said otherwise: "Yes, I like
	// everything."
	if claim.pred == "liked" and claim.args == ["you"] and ref.things.len == 1 and
	  not self.wasTold(ref.things[0], "you feeling") then return "Yes, I like everything."
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
	saved = self.saveWorld
	if self.orders then self.startOrders
	problem = self.planner.achieve(kind, args)
	self.restoreWorld saved
	return problem == null
end function

// Note how the world is, so that we can put it back just so, forgetting
// whatever we did in between (see restoreWorld).
Brain.saveWorld = function
	w = self.world
	return {"snapshot": w.snapshot, "hand": w.hand.pos[:], "goals": w.goals.len,
	  "history": w.history.len, "step": w.step, "event": self.focus.event}
end function

Brain.restoreWorld = function(saved)
	w = self.world
	w.restore saved.snapshot
	w.hand.pos = saved.hand
	w.goals = w.goals[:saved.goals]
	w.history = w.history[:saved.history]
	w.step = saved.step
	w.currentGoal = null
	self.focus.event = saved.event
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
  "putAt": "putAt", "addTo": "addTo",
  "clearOff": "clearOff", "cleanOff": "clearOff",
  "getRidOf": "getRidOf",
  "stack": "stack", "stackUp": "stack",
  "find": "find"}

// Carry out a command.  Standing orders (see learnOrder) are kept as we
// go: the planner asks before each step.  If an order gets in the way, we
// put the world back as it was, as if we'd only thought it through, and
// either try again or say which order it was.
//
// Trying again is for a choice we made: after "Never touch a green
// object", "Pick up a block" shouldn't stop at a green one, or at one with
// a green one on it.  So whatever "a block" chose that was part of the
// trouble is left out, and we choose again.
Brain.command = function(cmd)
	if not self.orders then return self.carryOut(cmd)
	self.startOrders
	saved = self.saveWorld
	chosen = self.chosen + {}
	self.excluded = []
	firstProblem = null
	for attempt in range(1, 10)
		self.vetoes = {}
		reply = self.carryOut(cmd)
		vetoed = self.problem and self.vetoes.hasIndex(self.problem)
		if not vetoed then
			if self.problem == null or firstProblem == null then
				self.excluded = []
				return reply
			end if
			// Choosing again went wrong some other way ("I don't see another
			// green block"): the order is still the reason.
			break
		end if
		if firstProblem == null then firstProblem = self.problem
		self.restoreWorld saved
		drop = self.choicesToDrop(self.vetoes[self.problem])
		if not drop then break
		self.excluded += drop
		self.chosen = chosen + {}
		self.problem = null
	end for
	self.restoreWorld saved
	self.excluded = []
	self.problem = null
	return self.fail(firstProblem)
end function

// After an order got in the way (`why` is {goal, thing}: what we were
// doing, and what broke a Keep order), the things this command chose for
// "a block" and the like that had to do with it: the ones that goal or
// the goals above it were about.
Brain.choicesToDrop = function(why)
	involved = []
	if why.thing then involved.push why.thing
	g = why.goal
	while g
		involved += g.args
		if g.near and g.near.hasIndex("other") then involved.push g.near.other
		g = g.parent
	end while
	result = []
	for var in self.chosen.indexes
		d = self.lookup(var)
		if d == null or d.kind != "description" or isDefinite(d) then continue
		for t in self.chosen[var]
			if containsRef(involved, t) and not containsRef(self.excluded, t) and not containsRef(result, t) then
				result.push t
			end if
		end for
	end for
	return result
end function

Brain.carryOut = function(cmd)
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
	self.commandKind = kind
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
	else if kind == "addTo" then
		// "Add the red pyramid": put it with the things we were just
		// talking about ("What's in the box?"  "The green pyramid and the
		// blue pyramid."), so where they all are.
		place = self.commonPlace
		if place == null then return self.fail("Add it to what?")
		for t in groups[0]
			goals.push ["putOn", [t, place]]
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
	// Picking something up may have broken a standing order: "Pick up the
	// red cube", when it's to be kept in the box.
	if self.orders then
		problem = self.keepProblem(true)
		if problem then return self.fail(problem)
	end if
	if cmd.args then self.noteFocus cmd.args[0], groups[0]
	// A stack we made is "it" (and "that") now: "Call that a steeple."
	if kind == "stack" then self.noteStack groups[0]
	if kind == "putOn" and groups[1][0].shape != "table" and groups[1][0].shape != "box" then
		self.noteBuilt groups[0][-1]
	end if
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
	for g in self.world.goals.reversed
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
	for thing in moved.reversed
		if not self.putBack(thing, g.start, "undo") then return null
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
		// (Not something that broke a standing order last time we tried:
		// see command.)
		if self.excluded then things = notIn(things, self.excluded)
		want = things.len
		if d.det == "a" or d.det == "any" or d.det == "which" then want = 1
		// "Remove anything I don't own from the box": getting rid of
		// "anything" means all of it.  ("Pick up anything red" means just
		// one, since you can only pick up one.)
		if d.det == "any" and self.commandKind == "getRidOf" then want = things.len
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
	self.noteMentioned things
	return things
end function

// Where the things we were just talking about all are (what they all rest
// on), or null if they're not all in one place.
Brain.commonPlace = function
	things = self.focus.them
	if not things and self.focus.it then things = [self.focus.it]
	if not things then return null
	place = null
	for t in things
		if t.supporters.len != 1 then return null
		if place == null then place = t.supporters[0]
		if not refEquals(place, t.supporters[0]) then return null
	end for
	return place
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
	for g in self.world.goals.reversed
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
		for g in self.world.goals.reversed
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
	if g.kind == "getRidOf" and i == 1 then
		if g.place then return [g.place]
		return [self.world.table]
	end if
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
		if self.definitions.hasIndex(word) and self.definitions[word].hasIndex("layerNames") then
			// "By putting a block on a block, then a pyramid on that."
			names = self.definitions[word].layerNames
			if names.len == 1 then return "I just find " + names[0] + "."
			steps = ["putting " + names[1] + " on " + names[0]]
			for n in names[2:]
				steps.push n + " on that"
			end for
			return "By " + steps.join(", then ") + "."
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
	// (lastUnderstanding is what we acted on, for showing what happened
	// under the hood; actOn sets it.)
	self.lastUnderstanding = null
	self.saidLast = self.saying
	self.saying = text
	// Did we just ask the user's name?  (Only this sentence can answer.)
	expectingName = self.askedName
	self.askedName = false
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
	context = {"robotName": self.robotName, "expectingName": expectingName}
	r = meaning.understand(text, self.knownNames, self.definitions.indexes, context)
	self.lastUnderstanding = r
	if r.error then return r.error
	reply = self.respondToUnderstanding(r)
	// "Fred, what's in the box?"  Put them right, then answer anyway.
	if r.wrongName then
		correction = "My name is " + self.robotName + ", not " + r.wrongName + "."
		// ("What's your name, Fred?" needs only the correction.)
		if reply.indexOf("My name is ") == 0 then reply = correction else reply = correction + "  " + reply
	end if
	return reply
end function

// Respond to a sentence we've parsed (see hear): pick a reading and act on it.
Brain.respondToUnderstanding = function(r)
	if r.trees[0].kind == "whatAbout" then return self.whatAbout(r.trees[0])
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

//----------------------------------------------------------------------
// "What about...?"
//
// "Is there anything in the box that I love?"  "No."  "What about on the
// table?"  The new phrase takes the place of part of what was said last,
// and we answer (or do) that.  Which part:
//   - A place ("on the table") replaces a place: one with the same
//     preposition if there is one ("in the box" here), or else the first.
//   - A noun phrase replaces a noun phrase: first one with the same noun
//     ("Is the red block tall?  What about the green block?"); then one
//     that's the same sort, definite or not ("Do you like the green cube?
//     What about the box?", or "How many red blocks are there?  What about
//     green ones?"); and failing those, what the sentence was about.
// The old question's own determiner stays, so "green ones" in place of
// "how-many blocks [color red]" is "how-many blocks [color green]".
//----------------------------------------------------------------------

Brain.whatAbout = function(tree)
	if self.lastActed == null then return "What about it?  I'm not sure what you're asking."
	before = self.lastActed.understanding
	old = before.programs[self.lastActed.index]
	prog = icl.read(old.format)     // a fresh copy, to change
	m = meaning.Meaning.make
	m.prog = prog
	oldVars = prog.vars.indexes
	phrase = tree.parts[1]
	if phrase.cat == "PP" then
		ok = replaceRelation(prog, m.constraintFor(phrase))
	else
		ok = self.replaceDescription(prog, m.describe(phrase), oldVars)
	end if
	if not ok then return "I'm not sure what you mean."
	r = {"programs": [prog], "trees": [tree], "phrases": [before.phrases[self.lastActed.index] + m.phrases], "error": null}
	return self.actOn(r, 0)
end function

// Put a new place in for an old one (see whatAbout).  Returns whether it
// found one to replace.
replaceRelation = function(prog, c)
	found = null
	for item in prog.lines
		if item.kind != "description" then continue
		for i in item.props.indexes
			p = item.props[i]
			if not relationWords.hasIndex(p.pred) or p.args.len != 1 or not icl.isVar(p.args[0]) then continue
			if found == null or (p.pred == c.pred and found[0].props[found[1]].pred != c.pred) then found = [item, i]
		end for
	end for
	if found == null then return false
	found[0].props[found[1]] = c
	return true
end function

// Put a new noun phrase (newVar) in for an old one (see whatAbout).  Returns
// whether it found one to replace.
Brain.replaceDescription = function(prog, newVar, oldVars)
	d = prog.lookup(newVar)
	if d.kind != "description" then return false
	olds = []
	for v in oldVars
		item = prog.lookup(v)
		if item.kind == "description" then olds.push item
	end for
	target = null
	// The same noun, the latest one.
	for o in olds
		if o.head == d.head and d.head != "one" then target = o
	end for
	// The same sort, definite or not.  (A question's "which" or "how many"
	// counts as not definite.)
	if target == null then
		for o in olds
			if isDefinite(o) == isDefinite(d) and target == null then target = o
		end for
	end if
	// What the sentence was about.
	if target == null then
		for s in prog.statements
			if s.hasIndex("target") and icl.isVar(s.target) then target = prog.lookup(s.target)
			if s.hasIndex("args") and s.args and icl.isVar(s.args[0]) then target = prog.lookup(s.args[0])
		end for
	end if
	if target == null or target.kind != "description" then return false
	// Keep the question's own determiner, and "one" borrows the old noun.
	if target.det == "which" or target.det == "how-many" then
		d.det = target.det
		d.n = target.n
	end if
	if d.head == "one" then d.head = target.head
	// Everything that meant the old one means the new one now.
	for item in prog.lines
		replaceVar item, target.var, newVar
	end for
	prog.lines.remove prog.lines.indexOf(target)
	prog.vars.remove target.var
	return true
end function

// Replace one variable with another, everywhere in a line of ICL
// (constraints, arguments, groups...).
replaceVar = function(item, oldVar, newVar)
	for key in ["args", "members", "props"]
		if not item.hasIndex(key) or not (item[key] isa list) then continue
		list = item[key]
		for i in list.indexes
			if list[i] isa map then
				replaceVar list[i], oldVar, newVar
			else if list[i] == oldVar then
				list[i] = newVar
			end if
		end for
	end for
	if item.hasIndex("target") and item.target == oldVar then item.target = newVar
	if item.hasIndex("claim") and item.claim isa map then replaceVar item.claim, oldVar, newVar
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

// "I mean the one on the left" says no more than "the one on the left", in
// answer to "I don't understand which red block you mean."  So we drop the
// "I mean" (or "No, I meant", and so on) before reading the noun phrase.
iMeanOpenings = ["no i mean ", "no i meant ", "i mean ", "i meant ", "i'm talking about ",
  "i was talking about ", "i am talking about "]
withoutIMean = function(text)
	words = []
	for w in parser.splitWords(text)
		words.push w[0]
	end for
	plain = words.join(" ") + " "
	for opening in iMeanOpenings
		if plain.startsWith(opening) then return words[opening.split(" ").len - 1:].join(" ")
	end for
	return text
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
	text = withoutIMean(text)
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
	self.lastUnderstanding = r
	self.lastActed = {"understanding": r, "index": index}
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
	for s in self.namedStacks
		result += s.names
	end for
	return result
end function

// Every stack the user has named, whether or not it's still stacked.
Brain.namedStacks = function
	result = []
	if not self.world.hasIndex("stackMemo") then return result
	for s in self.world.stackMemo.values
		if s.names then result.push s
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
	// If the other reading means the same things by some phrase of its own
	// ("the box", and "the box that I don't own"), then the readings differ
	// in what's said about them, not in what they mean, and there's no
	// assumption to tell the user about.
	for p in r.phrases[other]
		theirs = self.check(r.programs[other], p.var).referents[p.var]
		if theirs and sameThings(theirs, things) then return null
	end for
	return "By """ + phrase.words + """, I assume you mean " + speech.specificNamesFor(self.world, things) + "."
end function

// Are these the same things (in any order)?
sameThings = function(a, b)
	if a.len != b.len then return false
	for t in a
		if not containsRef(b, t) then return false
	end for
	return true
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
	saved = {"focus": self.focus + {}, "prog": self.prog, "chosen": self.chosen, "mentioned": self.mentioned}
	self.mentioned = self.mentioned[:]
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
	self.mentioned = saved.mentioned
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
	isOrder = statement.kind == "declare" and icl.orderVerbs.indexOf(statement.verb) != null
	// A standing order is about the things its noun phrases mean.
	if isOrder then vars = self.orderArgs(statement)
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
		else if isOrder and item.kind == "group" then
			things = self.candidates(var)
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
	if statement.kind == "ask" and statement.q == "yes-no" and icl.isVar(statement.target) and not self.problem then
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
	things = self.thingToName(statement.args[0])
	if things == null then return null
	if things.len != 1 then return self.fail("I can only give a name to one thing at a time.")
	things[0].names.push statement.args[1]
	self.noteFocus statement.args[0], things
	return "OK."
end function

//----------------------------------------------------------------------
// The two people: names and questions about them
//
// Besides the things on the table, the conversation has two people in
// it: the user, whom the user calls "me" (and the ICL does too), and the
// robot, "you".  Each may have a name.  The robot's is "Robot" until the
// user gives it another; the user's is unknown until they tell us.
//   My name is Joe.          Name me, Joe
//   Your name is Bob.        Name you, Bob
//   What's my name?          Ask name me
//   Is your name Bob?        Ask yes-no you [named Bob]
// People like to test a robot by asking their name before they've said
// it, so it says it doesn't know, and asks.  The next sentence may then be
// just the name ("Joe."; see Parser.smallTalk).
//----------------------------------------------------------------------

isPerson = function(arg)
	return arg == "me" or arg == "you"
end function

// "My name is Joe."  "Your name is now Bob."
Brain.namePerson = function(who, name)
	if who == "me" then
		if self.userName == null then
			self.userName = name
			return "Nice to meet you, " + name + "."
		end if
		if self.userName.lower == name.lower then return "I know, " + self.userName + "."
		self.userName = name
		return "OK, I'll call you " + name + " now."
	end if
	if self.robotName.lower == name.lower then return "Yes, that's my name."
	// The robot's name has to be its own: "Bob, pick it up" would be
	// confusing if a block were called Bob too.
	for n in self.knownNames
		if n.lower == name.lower then return "Sorry, something else is called " + name + " already."
	end for
	self.robotName = name
	return "OK, my name is " + name + " now."
end function

// "What is my name?"  "Is your name Bob?"
Brain.answerAboutPerson = function(q)
	if q.target == "you" then
		name = self.robotName
	else if self.userName then
		name = self.userName
	else
		self.askedName = true
		return "I don't know.  You haven't told me.  What is it?"
	end if
	if q.q == "attribute" and q.attr == "name" then
		if q.target == "you" then return "My name is " + name + "."
		return "Your name is " + name + "."
	end if
	if q.q == "yes-no" and q.claim and q.claim.pred == "named" then
		if q.claim.args[0].lower == name.lower then return "Yes."
		return "No, it's " + name + "."
	end if
	return "I don't know."
end function

//----------------------------------------------------------------------
// Attitudes: owning, liking, and so on
//
// The user can tell us what they own, like, love, hate or dislike (see
// icl.attitudes), either particular things ("The blue pyramid is mine")
// or kinds of thing ("I own blocks which are not red").  A kind is kept as
// its description, and checked whenever it matters, so it covers things
// that come to fit it later.  What we were told last counts most, so in "I
// own blocks which are not red, but I don't own anything which supports a
// pyramid", a blue block that supports a pyramid isn't owned.
//
// Owning is true or false, and false until we're told otherwise.  So "Do I
// own the box?" is "No." if we were never told; that agrees with "How many
// things do I own?", which counts only what we were told.
//
// Feelings are one scale instead (icl.feelingLevels): hate -2, dislike -1,
// neutral 0, like 1, love 2.  Everything starts neutral.
//   - "I like it" sets it to like (1), and so on.
//   - "I don't like it" moves it to the nearest level that isn't liking:
//     from like or love to neutral.  "I don't love it" takes love down to
//     like; "I don't hate it" takes hate up to dislike; "I don't dislike
//     it" takes dislike or hate up to neutral.  A feeling that's already
//     not that is left alone.
//   - "Do I like it?" means like or love; "Do I dislike it?" means dislike
//     or hate; love and hate are the ends.
// Owning and feelings are separate: hating something doesn't stop you
// owning it.
//----------------------------------------------------------------------

// The attitude a statement's verb is about ("dontLike" -> "like"), or null
// if it isn't one.
attitudeOf = function(verb)
	if verb.len > 4 and verb[:4] == "dont" then verb = icl.uncapitalize(verb[4:])
	if icl.attitudes.hasIndex(verb) then return verb
	return null
end function

// "Own x1", "DontLike x1", "Own x1, you"...  Each thing we're told about,
// or kind of thing, goes in a list as {things, verb, holds} or {prog, var,
// verb, holds}: self.attitudes["i own"] for what the user owns,
// self.attitudes["you feeling"] for all the robot's feelings together, and
// so on, in the order we were told.
//
// "I own no red blocks" says the same as "I don't own any red blocks".
// (Winograd's robot did the same.)
Brain.learnAttitude = function(statement)
	verb = attitudeOf(statement.verb)
	holds = statement.verb == verb     // (not "dont...")
	var = statement.args[0]
	person = "i"
	if statement.args.len > 1 then person = statement.args[1]
	d = self.lookup(var)
	if d == null then return null
	// "I own the red cube and the box": each of them.
	if d.kind == "group" then
		nouns = []
		for m in d.members
			reply = self.learnAttitude(statement + {"args": [m] + statement.args[1:]})
			if reply == null then return null
			head = self.lookup(m).head
			if nouns.indexOf(head) == null then nouns.push head
		end for
		// What "one" (or "mine") borrows now: their noun if they share one,
		// or else just "thing".  ("I own the red cube and the green pyramid.
		// Put mine in the box.")
		if nouns.len == 1 and self.isNoun(nouns[0]) then self.focus.noun = nouns[0] else self.focus.noun = "thing"
		self.focus.nounAdjectives = []
		return "I understand."
	end if
	if d.kind == "description" and d.det == "no" then holds = not holds
	key = person + " " + verb
	if icl.feelingLevels.hasIndex(verb) then key = person + " feeling"
	if not self.attitudes.hasIndex(key) then self.attitudes[key] = []
	entry = {"verb": verb, "holds": holds}
	if isDefinite(d) then
		things = self.definite(var)
		if things == null then return null
		self.noteFocus var, things
		entry.things = things
	else
		entry.prog = self.prog
		entry.var = var
	end if
	self.attitudes[key].push entry
	return "I understand."
end function

// Were we told anything about this thing, in this list of attitudes
// ("you feeling", "i own"...)?
Brain.wasTold = function(thing, key)
	if not self.attitudes.hasIndex(key) then return false
	for entry in self.attitudes[key]
		if self.entryFits(entry, thing) then return true
	end for
	return false
end function

// Is this entry (from learnAttitude) about this thing?
Brain.entryFits = function(entry, thing)
	if entry.hasIndex("things") then return containsRef(entry.things, thing)
	return self.fitsDescription(thing, entry)
end function

// Does the user (or, with person "you", the robot) have this attitude to
// this thing ("own", "like"...)?
Brain.feels = function(verb, thing, person="i")
	if icl.feelingLevels.hasIndex(verb) then
		level = icl.feelingLevels[verb]
		feeling = self.feelingFor(thing, person)
		if level > 0 then return feeling >= level     // loving is liking too
		return feeling <= level                       // hating is disliking too
	end if
	// Owning: the newest thing we were told about it decides; if nothing
	// was, no.
	key = person + " " + verb
	if not self.attitudes.hasIndex(key) then return false
	told = self.attitudes[key]
	for entry in told.reversed
		if self.entryFits(entry, thing) then return entry.holds
	end for
	return false
end function

// How everyone feels about things before we're told otherwise: the user is
// neutral (0), and the robot likes everything (1), as Winograd's robot did
// ("There is a theorem which shows that the robot likes everything").
startingFeeling = {"i": 0, "you": 1}

// How the user (or the robot) feels about a thing, from -2 (hate) to 2
// (love): what we were told, oldest first, from where they started.
Brain.feelingFor = function(thing, person="i")
	feeling = startingFeeling[person]
	key = person + " feeling"
	if not self.attitudes.hasIndex(key) then return feeling
	for entry in self.attitudes[key]
		if not self.entryFits(entry, thing) then continue
		level = icl.feelingLevels[entry.verb]
		if entry.holds then
			feeling = level
		else if level > 0 and feeling >= level then
			feeling = level - 1     // "I don't love it": like it, at most
		else if level < 0 and feeling <= level then
			feeling = level + 1     // "I don't hate it": dislike it, at least
		end if
	end for
	return feeling
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
// Standing orders: what we must never do, or must keep so
//
// "Never touch a green object" forbids an event: e1 = event Touch x1,
// Forbid e1.  Every goal the planner sets up is checked against it, the
// same way "Did you touch a green object?" checks the goals we've done
// (see eventGoals and goalArgsFit): picking up a green thing, or putting
// something on one, would be touching it.
//
// "Keep all the cubes in the box" describes something that must stay so:
// Keep x1 [in x2].  Whatever x1 means must go on meeting the claim.  This
// is checked whenever something is about to be set down (the planner asks
// placementProblem about each spot it considers), and at the end of each
// command, for what's left in the hand.  Something that wasn't so already
// when the command began (a cube that's on the table) doesn't count: the
// order is about not *making* it untrue.  (Things in the hand along the
// way don't count either, until the end: moving a cube from one side of
// the box to the other is fine.)
//
// Allow e1 and DontKeep x1 [claim] lift an order.  As with what the user
// owns, the newest order that fits decides, so "Never touch a block", then
// "You may touch the red cube", lets us touch the red cube but no other
// block; and "Don't touch the red cube" after that forbids it again.
//
// Each order is kept as {verb, prog, var, claim, pinned, said}: its
// statement's verb, the program and variable that describe it, the claim
// (for Keep and DontKeep), what each definite noun phrase in it ("the blue
// block", "it") meant when the order was given, and what we'll say if it
// gets in the way: "I can't.  You told me " + said + ".".
//----------------------------------------------------------------------

// "Don't ever touch the blue block" (Forbid e1), and so on.
Brain.learnOrder = function(statement)
	var = statement.args[0]
	if self.lookup(var) == null then return null
	if (statement.verb == "keep" or statement.verb == "dontKeep") and not statement.claim then
		return self.fail("(" + statement.verb.capitalized + " needs a claim.)")
	end if
	order = {"verb": statement.verb, "prog": self.prog, "var": var, "claim": statement.claim, "pinned": {}}
	// "The blue block" means the same thing from now on, and so does "it".
	args = self.orderArgs(statement)
	for v in self.varsWithin(args)
		d = self.lookup(v)
		if d.kind != "description" or not isDefinite(d) or self.variesPerThing(v) then continue
		things = self.definite(v)
		if things == null then return null
		order.pinned[v] = things
	end for
	// What the order is about is "it" now: "Don't touch the box.  Why not?"
	if args and order.pinned.hasIndex(args[0]) then self.noteFocus args[0], order.pinned[args[0]]
	order.said = self.orderPhrase(statement, order)
	self.orders.push order
	self.planner.rules = self
	return "OK."
end function

// The noun phrases an order is about: an event's arguments ("touch x1"), or
// the description and whatever its claim mentions ("Keep x1 [in x2]").
Brain.orderArgs = function(statement)
	item = self.lookup(statement.args[0])
	if item and item.kind == "event" then
		result = []
		for a in item.args
			if icl.isVar(a) then result.push a
		end for
		return result
	end if
	result = statement.args[:1]
	if statement.claim then result += icl.varsUsedIn(statement.claim)
	return result
end function

// These variables, and every variable they mention, and so on.
Brain.varsWithin = function(vars)
	result = []
	todo = vars[:]
	while todo
		v = todo.pop
		if result.indexOf(v) != null then continue
		result.push v
		item = self.lookup(v)
		if item then todo += icl.varsUsedIn(item)
	end while
	return result
end function

// What we'll say back, after "You told me": the user's words, with "you"
// and "I" swapped, and "it" (or "that"...) replaced by what it meant: "not
// to touch the blue block", "never to touch a green object", "to keep all
// the cubes in the box".  (If we were given ICL, not English, we put it
// together from the ICL.)
Brain.orderPhrase = function(statement, order)
	if statement.hasIndex("said") and statement.said then
		words = statement.said.split(" ")
		for kv in order.pinned
			d = self.lookup(kv.key)
			if not icl.pronouns.hasIndex(d.head) then continue
			i = words.indexOf(d.head)
			if i != null then words[i] = speech.specificNamesFor(self.world, kv.value)
		end for
		return speech.swapPersons(words.join(" "))
	end if
	item = self.lookup(statement.args[0])
	if item.kind == "event" then
		args = []
		for a in item.args
			if icl.isVar(a) then args.push self.orderArgPhrase(a, order)
		end for
		verb = item.verb
		if orderVerbWords.hasIndex(verb) then verb = orderVerbWords[verb]
		if (item.verb == "putOn" or item.verb == "putIn") and args.len == 2 then
			return "not to put " + args[0] + " " + item.verb[3:].lower + " " + args[1]
		end if
		return "not to " + verb + " " + args.join(" ")
	end if
	tail = self.constraintPhrase(statement.claim, item.plural)
	if tail == null and statement.claim.args.len == 0 then tail = statement.claim.pred     // [clear]
	return "to keep " + self.orderArgPhrase(statement.args[0], order) + " " + tail
end function

// The words for one of an order's noun phrases (see orderPhrase).
Brain.orderArgPhrase = function(var, order)
	if order.pinned.hasIndex(var) then return speech.specificNamesFor(self.world, order.pinned[var])
	phrase = self.argPhrase(var)
	if phrase == null then phrase = "that"
	return phrase
end function

// The words for an event's verb, when we have to put an order together.
orderVerbWords = {"pickUp": "pick up", "grasp": "pick up", "putDown": "put down",
  "getRidOf": "get rid of", "clearOff": "clear off", "cleanOff": "clear off",
  "stack": "stack up", "stackUp": "stack up"}

// Work inside an order's program, with its definite noun phrases meaning
// what they meant when it was given.  Returns what to pass to leaveOrder.
Brain.enterOrder = function(order)
	saved = self.enter(order.prog)
	saved.problem = self.problem
	saved.mentioned = self.mentioned
	saved.missing = self.missing
	self.bound = order.pinned + {}
	self.problem = null
	self.mentioned = []
	return saved
end function

Brain.leaveOrder = function(saved)
	self.leave saved
end function

// Is this goal against a standing order?  (The planner asks; see
// planner.ms.)  Returns null if not, or our reply if so.  The newest
// Forbid or Allow that fits the goal decides.
Brain.forbids = function(g)
	for order in self.orders.reversed
		if order.verb != "forbid" and order.verb != "allow" then continue
		if not self.orderFits(order, g) then continue
		if order.verb == "allow" then return null
		return self.veto(order, g)
	end for
	return null
end function

// Does a Forbid or Allow order's event fit this goal?
Brain.orderFits = function(order, g)
	saved = self.enterOrder(order)
	e = self.lookup(order.var)
	fits = e != null and eventGoals.hasIndex(e.verb) and eventGoals[e.verb].indexOf(g.kind) != null
	if fits then
		refs = []
		for a in e.args
			if not icl.isVar(a) then continue
			things = self.candidates(a)
			if things == null then
				fits = false
				break
			end if
			refs.push things
		end for
		if fits then fits = self.goalArgsFit(g, e.verb, refs)
	end if
	self.leaveOrder saved
	return fits
end function

// Would this thing break a Keep order, as things are now?  It does if it
// fits the order's description, and the claim isn't so.  (For a DontKeep
// order, the same test says whether the order lets it off.)
Brain.breaksKeep = function(order, thing)
	saved = self.enterOrder(order)
	things = self.candidates(order.var)
	broken = things != null and containsRef(things, thing)
	if broken then broken = not self.test(thing, order.claim)
	if self.problem then broken = false
	self.leaveOrder saved
	return broken
end function

// At the start of a command: for each Keep order, the things that already
// break it.  Those don't count against us (see keepProblem).
Brain.startOrders = function
	self.vetoes = {}
	self.ordersBefore = {}
	for i in self.orders.indexes
		if self.orders[i].verb != "keep" then continue
		already = []
		for t in self.world.things
			if self.breaksKeep(self.orders[i], t) then already.push t
		end for
		self.ordersBefore[i] = already
	end for
end function

// Is a Keep order broken now, by something that didn't break it when the
// command began?  Returns our reply if so, or null.  Something in the hand
// is still on its way somewhere, unless includeHeld is true (at the end of
// a command).
Brain.keepProblem = function(includeHeld=false)
	if self.ordersBefore == null then self.startOrders
	held = self.world.hand.holding
	for i in self.orders.indexes
		order = self.orders[i]
		if order.verb != "keep" then continue
		for t in self.world.things
			if not includeHeld and refEquals(t, held) then continue
			if self.ordersBefore.hasIndex(i) and containsRef(self.ordersBefore[i], t) then continue
			if not self.breaksKeep(order, t) then continue
			if self.letOff(i, t) then continue
			return self.veto(order, null, t)
		end for
	end for
	return null
end function

// Does a DontKeep order newer than order i let this thing off?
Brain.letOff = function(i, thing)
	for later in self.orders[i+1:]
		if later.verb == "dontKeep" and self.breaksKeep(later, thing) then return true
	end for
	return false
end function

// Would setting this thing down at this placement (see
// World.placementFor) break a Keep order?  We put it there for a moment
// to see, and then put it back.
Brain.placementProblem = function(thing, p)
	hasKeep = false
	for order in self.orders
		if order.verb == "keep" then hasKeep = true
	end for
	if not hasKeep then return null
	w = self.world
	saved = {"pos": thing.pos, "supporters": thing.supporters, "holding": w.hand.holding}
	thing.pos = [p.x, p.y, p.z]
	thing.supporters = p.supporters
	if refEquals(w.hand.holding, thing) then w.hand.holding = null
	problem = self.keepProblem
	thing.pos = saved.pos
	thing.supporters = saved.supporters
	w.hand.holding = saved.holding
	return problem
end function

// The reply when an order gets in the way, noting what we were doing (and
// what broke it) for command.
Brain.veto = function(order, goal, thing=null)
	reply = "I can't.  You told me " + order.said + "."
	if goal == null then goal = self.world.currentGoal
	self.vetoes[reply] = {"goal": goal, "thing": thing}
	return reply
end function

// Is this reply from the planner one of ours, about an order?
Brain.isOrderProblem = function(reply)
	return self.vetoes.hasIndex(reply)
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
	// "A steeple is a pyramid on top of a cube" describes an arrangement.
	pattern = self.patternOf(d)
	if pattern then
		def = self.definitions[word]
		def.pattern = pattern
		def.layerNames = []
		for v in pattern
			def.layerNames.push speech.withArticle(self.phraseFor(self.lookup(v), false))
		end for
	end if
	return "I understand."
end function

// "A pyramid on top of a cube" (x1 = a pyramid [on x2]; x2 = a cube) is an
// arrangement of things, one on another: a cube with a pyramid on it.  As
// a definition, that means the pair, not just the pyramid.  This returns
// the layers, bottom first, as variables for descriptions of each part on
// its own (a copy of "a pyramid" without its [on x2]); or null if the
// description isn't like that.
Brain.patternOf = function(d)
	layers = []
	while true
		link = null
		rest = []
		for c in d.props
			if (c.pred == "on" or c.pred == "above") and link == null and c.args.len == 1 and icl.isVar(c.args[0]) then
				link = c
			else
				rest.push c
			end if
		end for
		part = icl.description(d.det, d.head, false, rest)
		layers.insert 0, self.prog.add(part)
		if link == null then break
		d = self.lookup(link.args[0])
		if d == null or d.kind != "description" or isDefinite(d) then return null
	end while
	if layers.len < 2 then return null
	return layers
end function

//----------------------------------------------------------------------
// Words taught by example: "Call that a steeple."
//
// We keep just the shapes of the example, bottom first: for a stack of the
// large red block, the small red cube and the red pyramid, that's a block,
// a block and a pyramid.  Colors and sizes are left out, since they're
// likely just how this one happened to be made; the shapes and their order
// are what make it a steeple.  (Winograd's robot only learned words from
// descriptions.  How much of an example to keep is a guess, and this is
// ours.)
//----------------------------------------------------------------------

// "DefineLike x1, steeple"
Brain.defineLike = function(statement)
	if statement.args.len != 2 then return self.fail("(DefineLike needs a thing and a word.)")
	word = statement.args[1]
	if relations.nouns.indexOf(word) != null then return self.fail("I already know the word """ + word + """.")
	things = self.thingToName(statement.args[0])
	if things == null then return null
	if things.len != 1 then return self.fail("I can only learn a word from one example at a time.")
	example = things[0]
	// One particular thing ("Call the box a crate"): the word is for just
	// that one.  (For any box, say "Call a box a crate".)
	if example.shape != "stack" then
		self.definitions[word] = {"things": [example]}
		self.noteFocus statement.args[0], things
		self.focus.noun = word
		self.focus.nounAdjectives = []
		return "I understand."
	end if
	shapes = []
	if example.shape == "stack" then
		for p in example.parts
			shapes.push p.shape
		end for
	else
		shapes.push example.shape
	end if
	names = []
	for s in shapes
		names.push speech.withArticle(s)
	end for
	self.definitions[word] = {"example": shapes, "layerNames": names}
	self.noteFocus statement.args[0], things
	// The new word is the noun we're talking about: "Build another one."
	self.focus.noun = word
	self.focus.nounAdjectives = []
	return "I understand."
end function

// The things like an example: for one shape, things of that shape; for
// several, the stacks with just those shapes, in that order.
Brain.thingsLike = function(shapes)
	result = []
	if shapes.len == 1 then
		for t in self.world.things
			if t.shape == shapes[0] then result.push t
		end for
		return result
	end if
	for s in relations.stacks(self.world)
		if s.parts.len != shapes.len then continue
		same = true
		for i in shapes.indexes
			if s.parts[i].shape != shapes[i] then same = false
		end for
		if same then result.push s
	end for
	return result
end function

// Things to build one from, for a word in layers (see layeredDefinition):
// for each layer in turn, the thing that's least trouble to get (and not
// already picked).  We don't take apart one that's already built, if we
// can help it.  And the bottom one should already be on the table, if one
// is, so the new one stands on its own rather than on top of something
// else.
Brain.layerParts = function(def, word)
	layers = self.layerChoices(def)
	if layers == null then return null
	if layers.len < 2 then return self.fail("Sorry, I don't know how to build " + speech.withArticle(word) + ".")
	built = []
	if def.hasIndex("example") then existing = self.thingsLike(def.example) else existing = self.thingsMatching(def)
	for s in existing
		built += s.parts
	end for
	parts = []
	for i in layers.indexes
		choices = notIn(movableOnes(layers[i]), parts)
		if not choices then return self.fail("I don't see enough things to build " + speech.withArticle(word) + ".")
		if not notIn(choices, built) then
			return self.fail("I can't build another " + word + " without taking one apart.")
		end if
		choices = notIn(choices, built)
		if i == 0 then choices = preferring(choices, onTable(choices, self.world.table))
		parts.push self.leastTrouble(choices)[0]
	end for
	return parts
end function

// For each layer of a word in layers, bottom first, the things that could
// be that layer: things of the example's shape, or that fit the pattern's
// description of that layer.
Brain.layerChoices = function(def)
	result = []
	if def.hasIndex("example") then
		for shape in def.example
			things = []
			for t in self.world.things
				if t.shape == shape then things.push t
			end for
			result.push things
		end for
		return result
	end if
	saved = self.enter(def.prog)
	for v in def.pattern
		things = self.candidates(v)
		if things == null then break
		result.push things
	end for
	self.leave saved
	if self.problem then return null
	return result
end function

// The stacks whose top layers fit a pattern ("a pyramid on top of a cube"):
// the cube with the pyramid on it, wherever that cube is.
Brain.thingsMatching = function(def)
	result = []
	n = def.pattern.len
	for s in relations.stacks(self.world)
		if s.parts.len < n then continue
		top = s.parts[-n:]
		fits = true
		for i in top.indexes
			if not self.fitsDescription(top[i], {"prog": def.prog, "var": def.pattern[i]}) then fits = false
		end for
		if fits then result.push relations.stackOf(self.world, top)
	end for
	return result
end function

// The better choices if there are any, or else all of them.
preferring = function(all, better)
	if better then return better
	return all
end function

// The things not in a list.
notIn = function(things, list)
	result = []
	for t in things
		if not containsRef(list, t) then result.push t
	end for
	return result
end function

// The things resting on the table (and nothing else).
onTable = function(things, table)
	result = []
	for t in things
		if t.supporters.len == 1 and refEquals(t.supporters[0], table) then result.push t
	end for
	return result
end function

// The things a taught word fits: whatever fits its description, worked out
// in the program that defined it.
Brain.definedThings = function(word)
	if self.expanding.hasIndex(word) then
		return self.fail("(I went in circles: """ + word + """ is defined in terms of itself.)")
	end if
	def = self.definitions[word]
	if def.hasIndex("example") then return self.thingsLike(def.example)
	if def.hasIndex("pattern") then return self.thingsMatching(def)
	if def.hasIndex("things") then return def.things[:]
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
	// A word taught by example says the order too, bottom first.
	order = null
	if self.layeredDefinition(cmd.args[0]) then order = "ordered"
	problem = self.planner.achieve("stack", parts, order)
	root = self.world.goals[first]
	root.verb = cmd.verb
	self.focus.event = root
	if problem then return self.fail(problem)
	self.noteStack parts
	return "OK."
end function

// The stack these things make is "it" now (what we built, or stacked up).
Brain.noteStack = function(parts)
	for s in relations.stacks(self.world)
		if self.allIn(parts, s.parts) then
			self.focus.it = s
			self.focus.built = {"stack": s, "turn": self.world.turn}
		end if
	end for
	self.focus.them = null
end function

// We just put a thing on something (not the table or the box), so it's the
// top of a stack now.  Note that stack, in case the user names it next.
Brain.noteBuilt = function(thing)
	for s in relations.stacks(self.world)
		if refEquals(s.parts[-1], thing) then self.focus.built = {"stack": s, "turn": self.world.turn}
	end for
end function

// What "that", "it" or "this" means when naming something.  Right after
// we've made a stack (by stacking things up, or putting one thing on
// another), it's the whole stack: "Put the red cube on the blue block.
// Call that a tower."  Otherwise it's what it always is.
Brain.thingToName = function(var)
	d = self.lookup(var)
	if d == null then return null
	b = self.focus.built
	if d.kind == "description" and ["that", "it", "this"].indexOf(d.head) != null and
	  b and b.turn == self.world.turn - 1 and not self.selected then
		// (Only while it's still a stack.)
		for s in relations.stacks(self.world)
			if refEquals(s, b.stack) then return [s]
		end for
	end if
	return self.definite(var)
end function

// If a description's noun is a word for things in layers (taught by
// example, or as "a pyramid on a cube"), its definition; otherwise null.
Brain.layeredDefinition = function(var)
	d = self.lookup(var)
	if d == null or d.kind != "description" then return null
	word = d.head
	if word == "one" then word = self.antecedentNoun(d)
	if not self.definitions.hasIndex(word) then return null
	def = self.definitions[word]
	if def.hasIndex("example") or def.hasIndex("pattern") then return def
	return null
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
	if def.hasIndex("example") or def.hasIndex("pattern") then return self.layerParts(def, word)
	if def.hasIndex("things") then return self.fail("Sorry, I don't know how to build " + speech.withArticle(word) + ".")
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
