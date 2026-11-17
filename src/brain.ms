// brain.ms
//
// The robot's brain: it takes a sentence's meaning (as ICL), works out what
// the user is talking about, and answers or acts.
//
// This part covers understanding references and answering questions:
//
//   - Reference resolution: which actual objects does "the big red block",
//     "it", "them", or "the one you are holding" mean?  (Design note §2.4.)
//   - Questions: is there..., how many..., which..., what color..., and
//     yes/no questions like "is it taller than the blue block?"
//
// Commands, planning, and questions about the past (why, how, when) come next.
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

Brain = {}
Brain.world = null

// What we've been talking about, for "it", "them", and "one".
Brain.focus = null      // {it: Thing, them: list of Things, noun: string}

// The object the user last clicked on, for "this" and "that".
Brain.selected = null

// Per-sentence working state.
Brain.prog = null       // the ICL program being handled
Brain.cache = null      // var -> candidates, so each is only worked out once
Brain.busy = null       // vars being resolved right now (to catch loops)
Brain.problem = null    // a reply explaining what went wrong, or null

Brain.make = function(theWorld)
	b = new Brain
	b.world = theWorld
	b.focus = {"it": null, "them": null, "noun": null}
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
	replies = []
	for statement in prog.statements
		self.cache = {}
		self.busy = {}
		self.problem = null
		reply = self.handle(statement)
		if self.problem then
			replies.push self.problem
			break
		end if
		replies.push reply
	end for
	return replies.join(" ")
end function

Brain.handle = function(statement)
	if statement.kind == "ask" then return self.answer(statement)
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
	if q.q == "why" or q.q == "how" or q.q == "when" then
		return "Sorry, I can't answer questions about the past yet."
	end if
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
	things = self.definite(var)
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
