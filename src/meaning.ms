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
	m.describing = []  // the descriptions being built, outermost first
	m.itTarget = null  // to take "it" as an earlier noun phrase: its index in phrases
	m.itOptions = null // the earlier noun phrases "it" could have meant (see itReadings)
	return m
end function

// Add a description for a noun phrase (and any it mentions) to the
// program.  Returns its variable.
Meaning.describe = function(np)
	if np.hasIndex("join") then return self.describeGroup(np)
	bound = self.boundPronoun(np)
	if bound then return bound
	// "one of the green cubes" -> x1 = 1 cube [oneOf x2]; x2 = the cubes [color green]
	if np.parts.len >= 2 and np.parts[0].cat == "DET" and np.parts[1].cat == "NP" then return self.describeSome(np)
	if isIt(np) then
		if self.itTarget != null then
			// This reading takes "it" to be an earlier noun phrase.
			var = self.phrases[self.itTarget].var
			self.itTarget = null
			return var
		end if
		if self.itOptions == null then self.itOptions = self.earlierPhrases
	end if
	d = self.descriptionStart(np)
	// "another block" is "a block", and an other one: [other]
	if np.parts[0].cat == "det" and np.parts[0].entry.hasIndex("other") then d.props.push icl.constraint("other")
	// "my blocks" are "the blocks [owned]"; "your pyramid", "the pyramid [owned you]"
	if np.parts[0].cat == "det" and np.parts[0].entry.hasIndex("owner") then d.props.push ownedBy(np.parts[0].entry.owner)
	var = self.prog.add(d)     // added first, so it gets the lowest number
	self.phrases.push {"words": parser.wordsOf(np), "var": var}
	self.describing.push var
	for part in np.parts
		c = self.constraintFor(part)
		if c then d.props.push c
	end for
	self.describing.pop
	return var
end function

// Some of a group: "one of the green cubes", "any of the blocks on the
// table".  The group is a description of its own, and this one is the
// same kind of thing, one of those.
Meaning.describeSome = function(np)
	info = parser.determinerInfo(np.parts[0])
	group = np.parts[1]
	head = parser.partsOfCat(group, "noun")[0].entry.head
	d = icl.description(info.det, head, info.n != 1)
	d.n = info.n
	var = self.prog.add(d)
	self.phrases.push {"words": parser.wordsOf(np), "var": var}
	self.describing.push var
	d.props.push icl.constraint("oneOf", [self.describe(group)])
	// Anything after the group says more about these ones.
	for part in np.parts[2:]
		c = self.constraintFor(part)
		if c then d.props.push c
	end for
	self.describing.pop
	return var
end function

// Is this noun phrase just "it"?
isIt = function(np)
	return np.parts.len == 1 and np.parts[0].cat == "pronoun" and np.parts[0].entry.head == "it"
end function

// The noun phrases so far that "it" could mean, as indexes into phrases,
// nearest first: ones about one particular thing ("the box"), and not the
// ones we're inside ("the box which supports it" can't be "it").
Meaning.earlierPhrases = function
	result = []
	for i in range(self.phrases.len - 1, 0, -1)
		var = self.phrases[i].var
		if self.describing.indexOf(var) != null then continue
		d = self.prog.lookup(var)
		if d.kind != "description" or d.det != "the" or d.plural then continue
		result.push i
	end for
	return result
end function

// "It" can mean the thing a description is about, when it's in a clause
// about something else inside that description.  In "anything which is
// not as wide as the thing that supports it", "it" is the anything:
//   x1 = a thing [not [asWide x2]]
//   x2 = the thing [supports x1]
// But it can't be the thing its own clause is about ("a block which is
// bigger than it" can't mean bigger than itself), so there must be a
// description in between.  Returns that variable, or null.
Meaning.boundPronoun = function(np)
	if np.parts.len != 1 or np.parts[0].cat != "pronoun" then return null
	if np.parts[0].entry.head != "it" or self.describing.len < 2 then return null
	around = self.prog.lookup(self.describing[-2])
	if icl.pronouns.hasIndex(around.head) then return null
	return around.var
end function

// Noun phrases joined by "and" or "or": a description for each, and a
// group that joins them.
//   "the red cube and either a pyramid or the box"
//   x1 = the cube [color red]
//   x2 = a pyramid
//   x3 = the box
//   x4 = x2 or x3
//   x5 = x1 and x4
Meaning.describeGroup = function(np)
	members = []
	for part in np.parts
		if part.cat == "NP" then members.push self.describe(part)
	end for
	return self.prog.add(icl.group(np.join, members))
end function

// The description for a noun phrase's determiner and noun, before any
// constraints.
Meaning.descriptionStart = function(np)
	first = np.parts[0]
	if first.cat == "name" then return icl.description(null, first.word)
	if first.cat == "mine" then
		// "Mine" as a noun phrase is "my ones": the ones I own, borrowing
		// the noun from what we were talking about, as "one" does.  ("Which
		// blocks are green?  Put mine in the box.")  "Yours" is the robot's.
		// (The [owned] comes from "mine" itself: see constraintFor.)
		return icl.description("the", "one", true)
	end if
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
	if tree.cat == "mine" then return ownedBy(tree.entry.owner)     // "is mine" -> [owned]
	if tree.cat == "PP" or tree.cat == "CMP" then
		// "on the table" -> [on x2];  "taller than it" -> [taller x2]
		relation = tree.parts[0].entry.pred
		var = self.describe(tree.parts[-1])
		// "Taller than any pyramid" means taller than every one of them.
		d = self.prog.lookup(var)
		if tree.cat == "CMP" and d.kind == "description" and d.det == "any" then d.det = "every"
		return icl.constraint(relation, [var])
	end if
	if tree.cat == "ADJP" then return self.adjectiveConstraint(tree.parts[-1])     // "the biggest"
	if tree.cat == "ADJ" then
		// "second tallest" -> [tallest 2]
		return icl.constraint(tree.parts[1].entry.pred, [tree.parts[0].entry.n])
	end if
	if tree.cat == "PREDS" then return self.joinedConstraint(tree)
	if tree.cat == "COLORED" then
		// "colored red or blue" -> [color red|blue]
		colors = []
		for p in parser.partsOfCat(tree, "adj")
			colors.push self.adjectiveConstraint(p)
		end for
		if colors.len == 1 then return colors[0]
		return icl.constraint("or", colors)
	end if
	// "(Is the red cube) the tallest block?" -> [oneOf x2]
	if tree.cat == "NP" then return icl.constraint("oneOf", [self.describe(tree)])
	if tree.cat == "VP" then return self.verbConstraint(tree)
	if tree.cat == "REL" or tree.cat == "WH" then return self.clauseConstraint(tree)
	if tree.cat == "CMD" then
		// "(the one which) I told you to pick up" -> [commanded PickUp]
		return icl.constraint("commanded", [icl.capitalize(tree.frame.icl)])
	end if
	return null
end function

// Predicates joined by "and" or "but": "red and on the table", "green but
// not on the table" -> [and [color red] [on x2]].  ("But" means the same
// as "and" here; it only says the second part is a surprise.)
Meaning.joinedConstraint = function(tree)
	parts = []
	negate = false
	for p in tree.parts
		if p.cat == "and" or p.cat == "but" then continue
		if p.cat == "not" then
			negate = true
			continue
		end if
		c = self.constraintFor(p)
		if negate then c = icl.constraint("not", [c])
		parts.push c
		negate = false
	end for
	return icl.constraint("and", parts)
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
	// "have anything on it" -> [supports x2];  "in it" -> [contains x2]
	if tree.parts[0].cat == "have" then
		if tree.parts[2].entry.pred == "on" then relation = "supports" else relation = "contains"
		return icl.constraint(relation, [self.describe(tree.parts[1])])
	end if
	if verb.hasIndex("rel") then
		return icl.constraint(verb.rel, [self.describe(tree.parts[1])])
	end if
	return self.constraintFor(tree.parts[1])     // a posture verb and its place
end function

// A relative clause means whatever its last part means ("which is red",
// "which supports a pyramid"), possibly with "not".  "You are holding"
// means [held], and "I own" means [owned].
Meaning.clauseConstraint = function(tree)
	last = tree.parts[-1]
	if (last.cat == "verb" and last.entry.hasIndex("held")) or (last.cat == "have" and tree.parts[0].cat == "you") or
	  (last.cat == "adj" and last.entry.pred == "held") then
		// "you are holding", "do you have", "do you have ... in your hand"
		c = icl.constraint("held")
	else if last.cat == "verb" and last.entry.hasIndex("attitude") then
		// "which I own" -> [owned];  "which you own" -> [owned you]
		c = icl.constraint(icl.attitudes[last.entry.attitude])
		if parser.partsOfCat(tree, "you") then c.args.push "you"
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

// The superlative that goes with each comparative: "Which is taller, A or
// B?" asks which is the tallest of them.
superlativeOf = {"taller": "tallest", "shorter": "shortest", "wider": "widest",
  "narrower": "narrowest", "bigger": "biggest", "smaller": "smallest"}

// Add the ICL for a whole sentence to the program.
Meaning.sentence = function(s)
	if s.kind == "command" then
		for part in parser.partsOfCat(s, "CMD")
			self.prog.add self.command(part)
		end for
	else if s.kind == "define" then
		// "A "steeple" is a stack which ..." -> Define steeple, x1
		word = parser.partsOfCat(s, "name")[0].word
		var = self.describe(parser.partsOfCat(s, "NP")[0])
		self.prog.add icl.command("define", [word, var])
	else if s.kind == "exists" then
		self.prog.add icl.ask("exists", self.describe(s.parts[-1]))
	else if s.kind == "claim" then
		// "There were five blocks to the left of the box then": the
		// constraints are about then, the time we were talking about.
		var = self.describe(parser.partsOfCat(s, "NP")[0])
		if parser.partsOfCat(s, "then") then
			d = self.prog.lookup(var)
			for i in d.props.indexes
				d.props[i] = icl.constraint("then", [d.props[i]])
			end for
		end if
		self.prog.add icl.claim("exists", var)
	else if s.kind == "wh" then
		// The question word's noun phrase, constrained by the rest:
		// "how many blocks" + "are not in the box".
		np = s.parts[0]
		var = self.describe(np)
		wh = s.parts[1]
		times = parser.partsOfCat(s, "TIME")
		cmds = parser.partsOfCat(wh, "CMD")
		if cmds and parser.partsOfCat(wh, "modal") then
			// "How many blocks can you pick up?" -> [could e1], with
			//   e1 = event PickUp x1
			e = icl.event(cmds[0].frame.icl, [var] + self.arguments(cmds[0]))
			c = icl.constraint("could", [self.prog.add(e)])
		else if cmds then
			// "How many objects did you touch (while you were doing it)?"
			// "What did you have to move to do that?"
			c = self.didConstraint(var, cmds[0], times, parser.partsOfCat(wh, "PURPOSE"))
		else
			c = self.constraintFor(wh)
			// "What did the red cube support before you started to clean
			// it off?" asks about then, not now.
			if c then
				for t in times
					c = icl.constraint(t.parts[0].entry.time, [self.timeEvent(t), c])
				end for
			end if
		end if
		if c then self.prog.lookup(var).props.push c
		// "(What is in the box) that I don't own?"
		for rel in parser.partsOfCat(s, "REL")
			c = self.constraintFor(rel)
			if c then self.prog.lookup(var).props.push c
		end for
		self.prog.add icl.ask(parser.whKind(np), var)
	else if s.kind == "attribute" then
		if s.hasIndex("attr") then
			attr = s.attr     // "what is it called": its name
		else
			words = parser.partsOfCat(s, "attribute") + parser.partsOfCat(s, "howAttr")
			attr = words[0].entry.attr
		end if
		self.prog.add icl.ask(attr, self.describe(s.parts[-1]))
	else if s.kind == "identify" then
		// "What is it?" -> Ask identify x1
		self.prog.add icl.ask("identify", self.describe(s.parts[-1]))
	else if s.kind == "where" then
		// "Where is the red cube?" -> Ask where x1
		self.prog.add icl.ask("where", self.describe(parser.partsOfCat(s, "NP")[0]))
	else if s.kind == "choice" then
		// "Which is taller, the red cube or the blue block?" ->
		//   x1 = the cube [color red];  x2 = the block [color blue]
		//   x3 = x1 or x2
		//   x4 = which thing [oneOf x3] [tallest]
		//   Ask which x4
		group = self.describe(s.parts[-1])
		comparative = s.parts[2].entry.pred
		d = icl.description("which", "thing", false,
		  [icl.constraint("oneOf", [group]), icl.constraint(superlativeOf[comparative])])
		self.prog.add icl.ask("which", self.prog.add(d))
	else if s.kind == "yes-no" then
		var = self.describe(s.parts[1])
		self.prog.add icl.ask("yes-no", var, self.constraintFor(s.parts[2]))
	else if s.kind == "can" then
		// "Can a pyramid be supported by a block?" -> Ask can x1 [on x2]
		var = self.describe(s.parts[1])
		self.prog.add icl.ask("can", var, self.constraintFor(s.parts[2]))
	else if s.kind == "canDo" then
		// "Can the table pick up blocks?" -> Ask can e1, with
		//   e1 = event PickUp x2 [by x1]
		actor = self.describe(s.parts[1])
		cmd = s.parts[2]
		e = icl.event(cmd.frame.icl, self.arguments(cmd), [icl.constraint("by", [actor])])
		self.prog.add icl.ask("can", self.prog.add(e))
	else if s.kind == "event" then
		q = s.parts[0].entry.q
		self.prog.add icl.ask(q, self.event(s))
	else if s.kind == "whatDone" then
		// "What did you do last?" -> e1 = event Do [last]; Ask what e1
		// ("What did you do?" and "What have you just done?" mean the same.)
		e = icl.event("do", [], [icl.constraint("last")])
		self.prog.add icl.ask("what", self.prog.add(e))
	else if s.kind == "hand" then
		// "Is your hand empty?" -> x1 = no thing; Ask yes-no x1 [held]
		// "Is your hand full?"  -> x1 = a thing;  Ask yes-no x1 [held]
		if s.parts[-1].entry.pred == "empty" then det = "no" else det = "a"
		self.prog.add icl.ask("yes-no", self.prog.add(icl.description(det, "thing")), icl.constraint("held"))
	else if s.kind == "method" then
		// "How do you build a steeple?" -> e1 = event Build x1; Ask method e1
		cmd = parser.partsOfCat(s, "CMD")[0]
		self.prog.add icl.ask("method", self.prog.add(icl.event(cmd.frame.icl, self.arguments(cmd))))
	else if s.kind == "did" then
		// "Did you pick it up?" asks whether there was such an event.
		self.prog.add icl.ask("exists", self.event(s))
	else if s.kind == "statement" then
		for part in parser.partsOfCat(s, "OWN")
			self.prog.add self.ownership(part)
		end for
	else if s.kind == "defineLike" then
		// "That is a steeple." -> DefineLike x1, steeple
		name = parser.partsOfCat(s, "name")[0].word
		self.prog.add icl.command("defineLike", [self.describe(s.parts[0]), name])
	else if s.kind == "nameIt" then
		// "That cube's name is Bob." -> Name x1, Bob
		name = parser.typedWord(parser.partsOfCat(s, "name")[0])
		self.prog.add icl.command("name", [self.describe(s.parts[0]), name])
	else if s.kind == "chat" then
		// "Thank you." -> Chat thanks
		self.prog.add icl.command("chat", [s.parts[0].entry.reply])
	end if
end function

// "I own blocks which are not red" -> Own x1, with x1 = any block [not
// [color red]].  "I don't own..." -> DontOwn x1.  "I like..." -> Like x1.
// ("The blue pyramid is mine" is owning.)
//
// The robot's attitudes name it: "You own the box" -> Own x1, you.  ("The
// box is yours" too.)
Meaning.ownership = function(own)
	verb = "own"
	verbs = parser.partsOfCat(own, "verb")
	if verbs then verb = verbs[0].entry.attitude
	if parser.partsOfCat(own, "not") then verb = "dont" + icl.capitalize(verb)
	args = [self.describe(parser.partsOfCat(own, "NP")[0])]
	mine = parser.partsOfCat(own, "mine")
	if parser.partsOfCat(own, "you") or (mine and mine[0].entry.owner == "you") then args.push "you"
	return icl.command(verb, args)
end function

// [owned] (the user's), or [owned you] (the robot's).
ownedBy = function(owner)
	if owner == "you" then return icl.constraint("owned", ["you"])
	return icl.constraint("owned")
end function

// The ICL command for a CMD node: its frame's verb, with a variable for
// each noun phrase.  ("Count the blocks" is really a question.)
Meaning.command = function(cmd)
	if cmd.frame.icl == "count" then return icl.ask("count", self.arguments(cmd)[0])
	if cmd.frame.icl == "name" or cmd.frame.icl == "defineLike" then return self.naming(cmd)
	return icl.command(cmd.frame.icl, self.arguments(cmd))
end function

// "Call ... ...": what it means depends on the determiners.
//   "Call the biggest block superblock"  names one thing:   Name x1, superblock
//   "Call the box a crate"               a word for it:     DefineLike x1, crate
//   "Call that a steeple"                (that, a stack:    DefineLike x1, steeple,
//                                          which the brain learns by example)
//   "Call a box a crate", "Call all boxes crates"
//                                        a kind of thing:   Define crate, x1
// That is, the first noun phrase says whether it's one particular thing,
// or any thing like that; and "a" before the word says it's a noun, not
// a name.
Meaning.naming = function(cmd)
	args = self.arguments(cmd)
	d = self.prog.lookup(args[0])
	particular = d.kind == "description" and (d.det == null or d.det == "the" or d.det == "both")
	if not particular then
		// (The word may be plural, as in "call all boxes crates".)
		return icl.command("define", [icl.singularize(args[1].lower)[0], args[0]])
	end if
	// ("Call it the superblock" isn't teaching a word, so only "a" will do.)
	dets = parser.partsOfCat(cmd, "det")
	if dets and dets[0].entry.det == "a" then return icl.command("defineLike", [args[0], args[1].lower])
	return icl.command("name", args)
end function

// A command's arguments: a variable for each noun phrase, and a name as
// itself ("call it 'superblock'" -> Name x1, superblock).
//
// Some frames say where the thing is now ("take the green cube off the red
// block"): then the second noun phrase isn't an argument, but tells which
// thing the first one means:
//   x1 = the cube [color green] [on x2]
//   x2 = the block [color red]
//   GetRidOf x1
Meaning.arguments = function(cmd)
	args = []
	for part in cmd.parts
		if part.cat == "NP" then args.push self.describe(part)
		if part.cat == "name" then args.push parser.typedWord(part)
	end for
	// "Put the red cube next to the blue block" -> PutAt x1, nextTo, x2
	if cmd.frame.hasIndex("relation") and args.len == 2 then args = [args[0], cmd.frame.relation, args[1]]
	// "Put the red cube under the green pyramid" -> PutOn x2, x1
	if cmd.frame.hasIndex("swap") and args.len == 2 then args = [args[1], args[0]]
	if cmd.frame.hasIndex("from") and args.len == 2 then
		d = self.prog.lookup(args[0])
		if d.kind == "description" then
			d.props.push icl.constraint(cmd.frame.from, [args[1]])
			args = args[:1]
		end if
	end if
	return args
end function

// The event a sentence asks about, with its time: "you touched any
// pyramid before you put the green one on the little cube" ->
//   e1 = event Touch x1 [before e2]
// Plain "Why?" and "Why did you do that?" mean the event we were just
// talking about: "event Do".
Meaning.event = function(s)
	cmds = parser.partsOfCat(s, "CMD")
	if cmds then
		e = icl.event(cmds[0].frame.icl, self.arguments(cmds[0]))
	else
		e = icl.event("do")
	end if
	var = self.prog.add(e)
	self.addTimes e, parser.partsOfCat(s, "TIME")
	return var
end function

// Time constraints on an event, from TIME nodes: [before e2].
Meaning.addTimes = function(e, times)
	for t in times
		e.props.push icl.constraint(t.parts[0].entry.time, [self.timeEvent(t)])
	end for
end function

// The event a time clause mentions: "(before) you put the green one on the
// little cube" -> e2 = event PutOn x2, x3.  "(While you were) doing it" is
// the event we were talking about: e2 = event Do.
Meaning.timeEvent = function(t)
	cmds = parser.partsOfCat(t, "CMD")
	if not cmds then return self.prog.add(icl.event("do"))
	return self.prog.add(icl.event(cmds[0].frame.icl, self.arguments(cmds[0])))
end function

// "(objects which) you touched while you were doing it" -> [did e1], with
//   e1 = event Touch x1 [while e2]
// where x1 is the thing being described: it's a thing that, put in the
// command's missing place, makes e1 something the robot did.
//
// What it was done for ("to do that") is [for e2]: a step of doing e2.
Meaning.didConstraint = function(var, cmd, times, purposes=null)
	e = icl.event(cmd.frame.icl, [var] + self.arguments(cmd))
	eVar = self.prog.add(e)
	self.addTimes e, times
	if purposes then
		for p in purposes
			e.props.push icl.constraint("for", [self.timeEvent(p)])
		end for
	end if
	return icl.constraint("did", [eVar])
end function

// The ICL for every reading of a sentence: {programs, trees, phrases,
// error}.  The lists are in the same order, best first; phrases[i] lists
// the noun phrases of reading i, with their words and variables.
understand = function(text, names=null, nouns=null)
	r = parser.parse(text, names, nouns)
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

// Other readings of a sentence, where the first "it" means a noun phrase
// earlier in the same sentence, rather than what we were talking about
// before: "What did the box contain before you put the red cube in it?"
// The brain tries these when no ordinary reading makes sense.  Returns an
// understanding like the one from understand, with each reading's
// "itMeans" (the words "it" was taken to mean).
itReadings = function(r)
	result = {"programs": [], "trees": [], "phrases": [], "itMeans": [], "error": null}
	for tree in r.trees
		m = Meaning.make
		m.sentence tree
		if not m.itOptions then continue
		for option in m.itOptions
			m2 = Meaning.make
			m2.itTarget = option
			m2.sentence tree
			result.programs.push m2.prog
			result.trees.push tree
			result.phrases.push m2.phrases
			result.itMeans.push m2.phrases[option].words
		end for
	end for
	return result
end function

// The ICL for a noun phrase by itself (for testing): a Program of
// descriptions.
programForNounPhrase = function(np)
	m = Meaning.make
	m.describe np
	return m.prog
end function
