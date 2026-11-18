// meaning.ms
//
// From parse trees (see parser.ms) to ICL (see icl.ms).  The grammar says
// what the phrases are; this says what they mean.
//
// Each noun phrase becomes a description with its own variable, and the
// words around the noun become its constraints:
//
//   "a big red block on the table"
//   x1 = a block [size big] [color red] [on x2]
//   x2 = the table
//
// Pronouns stay pronouns ("x1 = it"), and "one" stays "one"; the brain
// works out what they refer to.

import "icl"
import "parser"

Meaning = {}

Meaning.make = function
	m = new Meaning
	m.prog = icl.Program.make
	m.phrases = []     // {words, var} for each noun phrase, so the robot can
	                   // say "By 'the block in the box', I assume you mean..."
	return m
end function

// Add a description for a noun phrase (and any it mentions) to the
// program.  Returns its variable.
Meaning.describe = function(np)
	d = self.descriptionStart(np)
	var = self.prog.add(d)     // added first, so it gets the lowest number
	self.phrases.push {"words": parser.wordsOf(np), "var": var}
	for part in np.parts
		c = self.constraintFor(part)
		if c then d.props.push c
	end for
	return var
end function

// The description for a noun phrase's determiner and noun, before any
// constraints.
Meaning.descriptionStart = function(np)
	first = np.parts[0]
	if first.cat == "name" then return icl.description(null, first.word)
	if first.cat == "pronoun" then
		// "something" = a thing; "it", "them" stay as they are.
		e = first.entry
		if e.det then return icl.description(e.det, e.head)
		return icl.description(null, e.head, icl.pronouns[e.head])
	end if
	// [determiner] adjectives noun, or "at least one of them".
	det = null
	n = null
	if first.cat == "det" or first.cat == "DET" then
		info = parser.determinerInfo(first)
		det = info.det
		n = info.n
	end if
	nouns = parser.partsOfCat(np, "noun") + parser.partsOfCat(np, "pronoun")
	head = nouns[0]
	if head.cat == "pronoun" then
		d = icl.description(det, head.entry.head, true)
	else
		plural = head.entry.form == "plural"
		if det == null then det = "any"     // a bare plural: "blocks"
		d = icl.description(det, head.entry.head, plural)
	end if
	d.n = n
	return d
end function

// The constraint that a word or phrase adds to the noun it's part of, or
// null if it adds none (like the noun itself).
Meaning.constraintFor = function(tree)
	if tree.cat == "adj" then return self.adjectiveConstraint(tree)
	if tree.cat == "PP" or tree.cat == "CMP" then
		// "on the table" -> [on x2];  "taller than it" -> [taller x2]
		relation = tree.parts[0].entry.pred
		return icl.constraint(relation, [self.describe(tree.parts[-1])])
	end if
	if tree.cat == "VP" then return self.verbConstraint(tree)
	if tree.cat == "REL" or tree.cat == "WH" then return self.clauseConstraint(tree)
	if tree.cat == "CMD" then
		// "(the one which) I told you to pick up" -> [commanded PickUp]
		return icl.constraint("commanded", [icl.capitalize(tree.frame.icl)])
	end if
	return null
end function

// [color red], [size big], or just [littlest].
Meaning.adjectiveConstraint = function(tree)
	e = tree.entry
	if e.value == null then return icl.constraint(e.pred)
	return icl.constraint(e.pred, [e.value])
end function

// "supports a pyramid" -> [supports x2];  "sitting on the table" -> [on x2]
Meaning.verbConstraint = function(tree)
	verb = tree.parts[0].entry
	if verb.hasIndex("rel") then
		return icl.constraint(verb.rel, [self.describe(tree.parts[1])])
	end if
	return self.constraintFor(tree.parts[1])     // a posture verb and its place
end function

// A relative clause means whatever its last part means ("which is red",
// "which supports a pyramid"), possibly with "not".  "You are holding"
// means [held].
Meaning.clauseConstraint = function(tree)
	last = tree.parts[-1]
	if last.cat == "verb" and last.entry.hasIndex("held") then
		c = icl.constraint("held")
	else if tree.cat == "WH" and (last.cat == "verb" or last.cat == "prep") then
		c = self.turnedAround(tree)
	else
		c = self.constraintFor(last)
	end if
	if c == null then return null
	if parser.partsOfCat(tree, "not") then c = icl.constraint("not", [c])
	return c
end function

// Relations seen from the other side: if a is on b, then b supports a.
inverses = {
  "on": "supports", "supports": "on", "in": "contains", "contains": "in",
  "above": "below", "below": "above", "behind": "inFrontOf", "inFrontOf": "behind",
  "leftOf": "rightOf", "rightOf": "leftOf", "nextTo": "nextTo", "touches": "touches"}

// "What does the box contain?" asks for the things x such that the box
// contains x: that is, the things in the box.  "What is the pyramid
// supported by?" asks for the things x such that the pyramid is on x:
// the things that support it.  Either way the question's thing is the
// object of the relation, so we turn the relation around.
Meaning.turnedAround = function(tree)
	np = parser.partsOfCat(tree, "NP")[0]
	last = tree.parts[-1]
	if last.cat == "verb" then relation = last.entry.rel else relation = last.entry.pred
	return icl.constraint(inverses[relation], [self.describe(np)])
end function

//----------------------------------------------------------------------
// Sentences
//----------------------------------------------------------------------

// Add the ICL for a whole sentence to the program.
Meaning.sentence = function(s)
	if s.kind == "command" then
		for part in parser.partsOfCat(s, "CMD")
			self.prog.add self.command(part)
		end for
	else if s.kind == "exists" then
		self.prog.add icl.ask("exists", self.describe(s.parts[-1]))
	else if s.kind == "wh" then
		// The question word's noun phrase, constrained by the rest:
		// "how many blocks" + "are not in the box".
		np = s.parts[0]
		var = self.describe(np)
		c = self.constraintFor(s.parts[1])
		if c then self.prog.lookup(var).props.push c
		self.prog.add icl.ask(parser.whKind(np), var)
	else if s.kind == "attribute" then
		attr = parser.partsOfCat(s, "attribute")[0].entry.attr
		self.prog.add icl.ask(attr, self.describe(s.parts[-1]))
	else if s.kind == "yes-no" then
		var = self.describe(s.parts[1])
		self.prog.add icl.ask("yes-no", var, self.constraintFor(s.parts[2]))
	else if s.kind == "event" then
		q = s.parts[0].entry.q
		self.prog.add icl.ask(q, self.event(s))
	end if
end function

// The ICL command for a CMD node: its frame's verb, with a variable for
// each noun phrase.
Meaning.command = function(cmd)
	return icl.command(cmd.frame.icl, self.arguments(cmd))
end function

Meaning.arguments = function(cmd)
	args = []
	for np in parser.partsOfCat(cmd, "NP")
		args.push self.describe(np)
	end for
	return args
end function

// The event a why/how/when question asks about.  Plain "Why?" and "Why
// did you do that?" mean the event we were just talking about: "event Do".
Meaning.event = function(s)
	cmds = parser.partsOfCat(s, "CMD")
	if cmds then
		e = icl.event(cmds[0].frame.icl, self.arguments(cmds[0]))
	else
		e = icl.event("do")
	end if
	return self.prog.add(e)
end function

// The ICL for every reading of a sentence: {programs, trees, phrases,
// error}.  The lists are in the same order, best first; phrases[i] lists
// the noun phrases of reading i, with their words and variables.
understand = function(text, names=null)
	r = parser.parse(text, names)
	programs = []
	phrases = []
	for tree in r.trees
		m = Meaning.make
		m.sentence tree
		programs.push m.prog
		phrases.push m.phrases
	end for
	return {"programs": programs, "trees": r.trees, "phrases": phrases, "error": r.error}
end function

// The ICL for a noun phrase by itself (for testing): a Program of
// descriptions.
programForNounPhrase = function(np)
	m = Meaning.make
	m.describe np
	return m.prog
end function
