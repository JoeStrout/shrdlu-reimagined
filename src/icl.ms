// icl.ms
//
// ICL, the Intermediate Command Language: what a sentence means, as data.
//
// The parser turns English into ICL, and the brain acts on ICL.  Neither
// side needs the other to be tested: tests (and curious users) can write ICL
// directly in its printed form, which this module reads and prints.
//
// See notes/design-world-and-icl.md (Part 2), especially §2.5 for the
// printed form.  A short example:
//
//   x1 = a block [color red] [size big]     // "a big red block"
//   x2 = the box
//   PutIn x1, x2                            // "put it into the box"
//
// A program is a list of lines.  Each line is one of these, as a map:
//
//   description  {kind:"description", var, det, n, head, plural, props}
//                  A noun phrase: something to find in the world.
//                  det is "a", "the", "any", "every", "no", "which",
//                  "how-many", "number" (n says which), "at-least" (n says
//                  how many), or null (for "it", "them", and names).
//   event        {kind:"event", var, verb, args, props}
//                  Something that happened (or might have): "you picked it up".
//   command      {kind:"command", verb, args}
//   ask          {kind:"ask", q, target, attr, claim}
//                  A question.  q is "exists", "count", "which", "yes-no",
//                  "why", "how", "when", or "attribute" (attr says which).
//   declare      {kind:"declare", verb, args}
//                  Teaching the robot something: Define, Name, Own.
//
// Constraints (the bracketed parts) are all the same shape: {pred, args}.
// An arg is a variable name (like "x2"), a word ("red"), a number, or another
// constraint (as in [not [in x2]]).
//
// Verbs are stored in lower camel case ("putIn") and printed capitalized
// ("PutIn").

determiners = ["a", "the", "any", "every", "no", "which", "how-many"]

// Pronouns, and whether each one is plural.
pronouns = {"it": false, "that": false, "this": false, "them": true, "they": true}

// The kinds of question that aren't asking about an attribute.
questionKinds = ["exists", "count", "which", "yes-no", "why", "how", "when"]

// Statements that teach the robot something, rather than asking it to act.
declareVerbs = ["define", "name", "own"]

//----------------------------------------------------------------------
// Small helpers
//----------------------------------------------------------------------

isDigit = function(c)
	return c >= "0" and c <= "9"
end function

isUpper = function(c)
	return c >= "A" and c <= "Z"
end function

// Is this word a whole number, like "2"?
isNumber = function(word)
	if not word then return false
	for c in word
		if not isDigit(c) then return false
	end for
	return true
end function

// Is this word a variable name?  Variables are x or e followed by digits:
// x1, x2, ... for things, and e1, e2, ... for events.
isVar = function(word)
	if not (word isa string) or word.len < 2 then return false
	if word[0] != "x" and word[0] != "e" then return false
	return isNumber(word[1:])
end function

// "pickUp" -> "PickUp", and back.
capitalize = function(word)
	return word[0].upper + word[1:]
end function
uncapitalize = function(word)
	return word[0].lower + word[1:]
end function

// Split a noun into its singular form and whether it was plural:
// "blocks" -> ["block", true], "boxes" -> ["box", true], "box" -> ["box", false].
singularize = function(word)
	if pronouns.hasIndex(word) then return [word, pronouns[word]]
	if word.len > 3 and word[-2:] == "es" then
		stem = word[:-2]
		if stem[-1] == "x" or stem[-1] == "s" or stem[-2:] == "ch" or stem[-2:] == "sh" then
			return [stem, true]
		end if
	end if
	if word.len > 2 and word[-1] == "s" and word[-2] != "s" then return [word[:-1], true]
	return [word, false]
end function

// The reverse: "block" -> "blocks", "box" -> "boxes".
pluralize = function(word)
	if word[-1] == "x" or word[-1] == "s" or word[-2:] == "ch" or word[-2:] == "sh" then
		return word + "es"
	end if
	return word + "s"
end function

//----------------------------------------------------------------------
// Constructors, for building ICL in code (the parser will use these).
//----------------------------------------------------------------------

constraint = function(pred, args=null)
	if args == null then args = []
	return {"pred": pred, "args": args}
end function

description = function(det, head, plural=false, props=null)
	if props == null then props = []
	return {"kind": "description", "var": null, "det": det, "n": null,
	  "head": head, "plural": plural, "props": props}
end function

event = function(verb, args=null, props=null)
	if args == null then args = []
	if props == null then props = []
	return {"kind": "event", "var": null, "verb": verb, "args": args, "props": props}
end function

command = function(verb, args=null)
	if args == null then args = []
	kind = "command"
	if declareVerbs.indexOf(verb) != null then kind = "declare"
	return {"kind": kind, "var": null, "verb": verb, "args": args}
end function

// A question.  For an attribute question, q is the attribute ("color").
// For a yes/no question, claim is a constraint on the target.
ask = function(q, target, claim=null)
	result = {"kind": "ask", "var": null, "q": q, "target": target, "attr": null, "claim": claim}
	if questionKinds.indexOf(q) == null then
		result.q = "attribute"
		result.attr = q
	end if
	return result
end function

//----------------------------------------------------------------------
// Program: an ordered list of ICL lines, plus a map from each variable to
// the line that defines it.
//----------------------------------------------------------------------

Program = {}
Program.lines = null
Program.vars = null
Program.errors = null   // problems found while reading the printed form

Program.make = function
	p = new Program
	p.lines = []
	p.vars = {}
	p.errors = []
	return p
end function

// A fresh variable name with the given prefix ("x" or "e").
Program.newVar = function(prefix="x")
	i = 1
	while self.vars.hasIndex(prefix + i)
		i += 1
	end while
	return prefix + i
end function

// Add a line.  Descriptions and events get a variable if they don't have one.
// Returns the line's variable (or null for statements).
Program.add = function(item)
	if item.kind == "description" or item.kind == "event" then
		if not item.var then
			prefix = "x"
			if item.kind == "event" then prefix = "e"
			item.var = self.newVar(prefix)
		end if
		self.vars[item.var] = item
	end if
	self.lines.push item
	return item.var
end function

// The line defining the given variable (or null).
Program.lookup = function(var)
	if self.vars.hasIndex(var) then return self.vars[var]
	return null
end function

// Just the statements (commands, questions, and declarations), in order.
Program.statements = function
	result = []
	for item in self.lines
		if item.kind != "description" and item.kind != "event" then result.push item
	end for
	return result
end function

//----------------------------------------------------------------------
// Printing
//----------------------------------------------------------------------

formatArg = function(arg)
	if arg isa map then return formatConstraint(arg)
	return str(arg)
end function

formatConstraint = function(c)
	// An "or" of the same predicate with one simple value each prints
	// compactly: [color red|green].
	if c.pred == "or" and c.args.len > 1 then
		values = []
		for alt in c.args
			if not (alt isa map) or alt.pred != c.args[0].pred or alt.args.len != 1 then break
			if alt.args[0] isa map then break
			values.push str(alt.args[0])
		end for
		if values.len == c.args.len then return "[" + c.args[0].pred + " " + values.join("|") + "]"
	end if
	parts = [c.pred]
	for arg in c.args
		parts.push formatArg(arg)
	end for
	return "[" + parts.join(" ") + "]"
end function

formatProps = function(props)
	result = ""
	for c in props
		result += " " + formatConstraint(c)
	end for
	return result
end function

formatArgs = function(args)
	parts = []
	for arg in args
		parts.push formatArg(arg)
	end for
	return parts.join(", ")
end function

// The determiner and noun of a description, like "a block" or "3 pyramids".
formatNounPhrase = function(d)
	parts = []
	if d.det == "number" then
		parts.push str(d.n)
	else if d.det == "at-least" then
		parts.push "at-least-" + d.n
	else if d.det then
		parts.push d.det
	end if
	head = d.head
	if pronouns.hasIndex(head) then
		if d.det then parts.push "of"     // "at-least-1 of them"
	else if d.plural then
		head = pluralize(head)
	end if
	parts.push head
	return parts.join(" ") + formatProps(d.props)
end function

// One line of ICL, in printed form.
format = function(item)
	if item.kind == "description" then
		return item.var + " = " + formatNounPhrase(item)
	else if item.kind == "event" then
		s = item.var + " = event " + capitalize(item.verb)
		if item.args then s += " " + formatArgs(item.args)
		return s + formatProps(item.props)
	else if item.kind == "command" or item.kind == "declare" then
		s = capitalize(item.verb)
		if item.args then s += " " + formatArgs(item.args)
		return s
	else if item.kind == "ask" then
		q = item.q
		if q == "attribute" then q = item.attr
		s = "Ask " + q + " " + item.target
		if item.claim then s += " " + formatConstraint(item.claim)
		return s
	end if
	return "?? " + str(item)
end function

// A whole program, one line per item.
Program.format = function
	result = []
	for item in self.lines
		result.push format(item)
	end for
	return result.join(char(10))
end function

//----------------------------------------------------------------------
// Reading the printed form
//----------------------------------------------------------------------

// Split a line into tokens: words, and the punctuation [ ] , =
tokenize = function(line)
	tokens = []
	word = ""
	for c in line
		if c == " " or c == char(9) or "[],=".indexOf(c) != null then
			if word then tokens.push word
			word = ""
			if c != " " and c != char(9) then tokens.push c
		else
			word += c
		end if
	end for
	if word then tokens.push word
	return tokens
end function

// A Reader works through the tokens of one line.  When something is wrong it
// records an error (the first one only) and the line is discarded.
Reader = {}
Reader.tokens = null
Reader.pos = 0
Reader.error = null

Reader.make = function(tokens)
	r = new Reader
	r.tokens = tokens
	return r
end function

Reader.peek = function
	if self.pos < self.tokens.len then return self.tokens[self.pos]
	return null
end function

Reader.next = function
	tok = self.peek
	self.pos += 1
	return tok
end function

Reader.atEnd = function
	return self.pos >= self.tokens.len
end function

Reader.fail = function(message)
	if not self.error then self.error = message
	return null
end function

// Is the next token a plain word (not punctuation, not the end)?
Reader.atWord = function
	tok = self.peek
	return tok != null and "[],=".indexOf(tok) == null
end function

// A single argument value: a number or a word (including variables).
Reader.readAtom = function
	if not self.atWord then return self.fail("expected a word but found " + self.describeNext)
	tok = self.next
	if isNumber(tok) then return val(tok)
	return tok
end function

Reader.describeNext = function
	if self.atEnd then return "the end of the line"
	return """" + self.peek + """"
end function

// [pred arg arg ...]
Reader.readConstraint = function
	if self.next != "[" then return self.fail("expected [")
	if not self.atWord then return self.fail("expected a predicate after [")
	pred = self.next
	args = []
	while not self.error
		tok = self.peek
		if tok == null then return self.fail("missing ]")
		if tok == "]" then break
		if tok == "," then
			self.next
		else if tok == "[" then
			args.push self.readConstraint
		else
			args.push self.readAtom
		end if
	end while
	self.next   // the ]
	if self.error then return null
	if (pred == "not" and args.len != 1) or (pred == "or" and args.len < 2) then
		return self.fail("[" + pred + "] has the wrong number of parts")
	end if
	// [color red|green] is short for [or [color red] [color green]].
	if args.len == 1 and args[0] isa string and args[0].indexOf("|") != null then
		alternatives = []
		for value in args[0].split("|")
			alternatives.push constraint(pred, [value])
		end for
		return constraint("or", alternatives)
	end if
	return constraint(pred, args)
end function

// Zero or more constraints, running to the end of the line.
Reader.readProps = function
	props = []
	while not self.atEnd and not self.error
		if self.peek != "[" then return self.fail("expected [ but found " + self.describeNext)
		props.push self.readConstraint
	end while
	return props
end function

// Arguments to a verb: words separated by commas (commas are optional),
// up to the first [ or the end of the line.
Reader.readArgs = function
	args = []
	while not self.atEnd and not self.error and self.peek != "["
		if self.peek == "," then
			self.next
		else
			args.push self.readAtom
		end if
	end while
	return args
end function

// After "x1 =": determiner, noun, constraints.
Reader.readDescription = function
	if not self.atWord then return self.fail("expected a noun phrase")
	d = description(null, null)
	w = self.next
	if w == "an" then w = "a"
	if determiners.indexOf(w) != null then
		d.det = w
		w = null
	else if isNumber(w) then
		d.det = "number"
		d.n = val(w)
		w = null
	else if w.len > 9 and w[:9] == "at-least-" and isNumber(w[9:]) then
		d.det = "at-least"
		d.n = val(w[9:])
		w = null
	end if
	if w == null then
		if not self.atWord then return self.fail("expected a noun after the determiner")
		w = self.next
		if w == "of" and self.atWord then w = self.next   // "at-least-1 of them"
	end if
	if d.det or pronouns.hasIndex(w) then
		sp = singularize(w)
		d.head = sp[0]
		d.plural = sp[1]
	else
		d.head = w     // a name, like "superblock": leave it alone
	end if
	d.props = self.readProps
	return d
end function

// After "e1 = event": a verb, its arguments, and constraints.
Reader.readEvent = function
	if not self.atWord then return self.fail("expected a verb after 'event'")
	e = event(uncapitalize(self.next))
	e.args = self.readArgs
	e.props = self.readProps
	return e
end function

// After "Ask": the kind of question, its target, and (for yes-no) a claim.
Reader.readAsk = function
	if not self.atWord then return self.fail("expected a kind of question after Ask")
	q = self.next
	if not self.atWord then return self.fail("expected what the question is about")
	result = ask(q, self.next)
	if q == "yes-no" then
		if self.peek != "[" then return self.fail("a yes-no question needs a [claim]")
		result.claim = self.readConstraint
	end if
	if not self.atEnd then self.fail("unexpected " + self.describeNext)
	return result
end function

// One whole line.
Reader.readLine = function
	first = self.peek
	if self.tokens.len > 1 and self.tokens[1] == "=" then
		if not isVar(first) then return self.fail("""" + first + """ isn't a variable name (like x1 or e1)")
		self.pos = 2
		if self.peek == "event" then
			self.next
			item = self.readEvent
		else
			item = self.readDescription
		end if
		if item then item.var = first
		return item
	end if
	if first == "Ask" then
		self.next
		return self.readAsk
	end if
	if first != null and isUpper(first[0]) then
		self.next
		item = command(uncapitalize(first), self.readArgs)
		if not self.atEnd then self.fail("unexpected " + self.describeNext)
		return item
	end if
	return self.fail("don't know what to do with """ + first + """")
end function

// Every variable a line refers to (not counting the one it defines).
varsUsedIn = function(item, result=null)
	if result == null then result = []
	if item isa string then
		if isVar(item) then result.push item
	else if item isa list then
		for x in item
			varsUsedIn x, result
		end for
	else if item isa map then
		for key in ["args", "props", "target", "claim"]
			if item.hasIndex(key) then varsUsedIn item[key], result
		end for
	end if
	return result
end function

// Read a program in printed form.  Problems are listed in the result's
// errors (as "line 3: ..."); lines with problems are left out.
read = function(text)
	prog = Program.make
	lineNum = 0
	for line in text.split(char(10))
		lineNum += 1
		cut = line.indexOf("//")
		if cut != null then line = line[:cut]
		tokens = tokenize(line.replace(char(13), ""))
		if not tokens then continue
		r = Reader.make(tokens)
		item = r.readLine
		if not r.error and item.var and prog.vars.hasIndex(item.var) then
			r.fail item.var + " is defined twice"
		end if
		if r.error then
			prog.errors.push "line " + lineNum + ": " + r.error
		else
			prog.add item
		end if
	end for
	// Variables may be used before they're defined (as in "a block taller
	// than x2", with x2 on the next line), so check them all at the end.
	for item in prog.lines
		for v in varsUsedIn(item)
			if not prog.vars.hasIndex(v) then prog.errors.push v + " is used but never defined"
		end for
	end for
	return prog
end function
