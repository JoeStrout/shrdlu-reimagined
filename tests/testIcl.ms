// testIcl.ms
//
// Tests for the ICL module: reading the printed form, the data it produces,
// and printing it back out.  Run from the repo root:
//
//   MS_IMPORT_PATH=src miniscript tests/testIcl.ms

import "icl"

failures = 0
checks = 0
check = function(condition, what)
	globals.checks += 1
	if condition then return
	globals.failures += 1
	print "FAILED: " + what
end function

nl = char(10)

// Read a program, complain about any errors, and check that printing it
// gives back exactly the same text.
roundTrip = function(text, what)
	prog = icl.read(text)
	check prog.errors.len == 0, what + " reads without errors: " + prog.errors
	out = prog.format
	check out == text, what + " prints back the same; got:" + nl + out
	return prog
end function

//----------------------------------------------------------------------
// Helpers
//----------------------------------------------------------------------

check icl.isVar("x1") and icl.isVar("e12"), "x1 and e12 are variables"
check not icl.isVar("b1") and not icl.isVar("x") and not icl.isVar("red"), "b1, x, red aren't"
check icl.singularize("blocks") == ["block", true], "blocks -> block"
check icl.singularize("boxes") == ["box", true], "boxes -> box"
check icl.singularize("cubes") == ["cube", true], "cubes -> cube"
check icl.singularize("ones") == ["one", true], "ones -> one"
check icl.singularize("box") == ["box", false], "box stays box"
// Irregular plurals, from assets/irregularPlurals.txt
check icl.singularize("dice") == ["die", true], "dice -> die"
check icl.singularize("dies") == ["die", true], "dies -> die too"
check icl.singularize("leaves") == ["leaf", true], "leaves -> leaf"
check icl.singularize("bus") == ["bus", false], "bus is singular"
check icl.singularize("buses") == ["bus", true], "buses -> bus"
check icl.singularize("sheep") == ["sheep", true], "sheep may be plural"
check icl.singularize("bodies") == ["body", true], "bodies -> body (a rule)"
check icl.singularize("pies") == ["pie", true], "pies -> pie (an exception to that rule)"
check icl.singularize("toys") == ["toy", true], "toys -> toy"
check icl.pluralize("die") == "dice", "die -> dice (the first plural listed)"
check icl.pluralize("body") == "bodies", "body -> bodies"
check icl.pluralize("toy") == "toys", "toy -> toys"
check icl.pluralize("box") == "boxes", "box -> boxes"
check icl.singularize("them") == ["them", true], "them is plural"
check icl.pluralize("box") == "boxes" and icl.pluralize("pyramid") == "pyramids", "pluralize"
check icl.tokenize("x1 = a block [on x2],x3") ==
  ["x1", "=", "a", "block", "[", "on", "x2", "]", ",", "x3"], "tokenize"

//----------------------------------------------------------------------
// Winograd sentences, in printed ICL
//----------------------------------------------------------------------

// "Pick up a big red block."
p = roundTrip("x1 = a block [color red] [size big]" + nl + "PickUp x1", "pick up a big red block")
x1 = p.lookup("x1")
check x1.kind == "description" and x1.det == "a" and x1.head == "block" and not x1.plural, "x1 is a block"
check x1.props.len == 2 and x1.props[0] == {"pred": "color", "args": ["red"]}, "x1 is red"
s = p.statements
check s.len == 1 and s[0].kind == "command" and s[0].verb == "pickUp" and s[0].args == ["x1"], "PickUp x1"

// "Find a block which is taller than the one you are holding and put it into the box."
text = [
  "x1 = a block [taller x2]",
  "x2 = the one [held]",
  "x3 = the box",
  "Find x1",
  "PutIn x1, x3"].join(nl)
p = roundTrip(text, "find a block taller than...")
check p.lookup("x2").props[0] == {"pred": "held", "args": []}, "[held] has no args"
check p.statements.len == 2 and p.statements[1].args == ["x1", "x3"], "PutIn has two args"

// "How many blocks are not in the box?"
p = roundTrip("x1 = how-many blocks [not [in x2]]" + nl + "x2 = the box" + nl + "Ask count x1", "how many blocks")
x1 = p.lookup("x1")
check x1.det == "how-many" and x1.head == "block" and x1.plural, "how-many blocks is plural"
neg = x1.props[0]
check neg.pred == "not" and neg.args[0] == {"pred": "in", "args": ["x2"]}, "not in the box"
check p.statements[0].q == "count" and p.statements[0].target == "x1", "Ask count"

// "Is at least one of them narrower than the one which I told you to pick up?"
text = [
  "x1 = at-least-1 of them",
  "x2 = the one [commanded PickUp]",
  "Ask yes-no x1 [narrower x2]"].join(nl)
p = roundTrip(text, "at least one of them")
x1 = p.lookup("x1")
check x1.det == "at-least" and x1.n == 1 and x1.head == "them" and x1.plural, "at-least-1 of them"
q = p.statements[0]
check q.q == "yes-no" and q.target == "x1" and q.claim == {"pred": "narrower", "args": ["x2"]}, "yes-no claim"

// "What color is it?"
p = roundTrip("x1 = it" + nl + "Ask color x1", "what color is it")
check p.lookup("x1").det == null and p.lookup("x1").head == "it", "it has no determiner"
check p.statements[0].q == "attribute" and p.statements[0].attr == "color", "attribute question"

// "Why did you pick it up?"
p = roundTrip("x1 = it" + nl + "e1 = event PickUp x1" + nl + "Ask why e1", "why did you pick it up")
e1 = p.lookup("e1")
check e1.kind == "event" and e1.verb == "pickUp" and e1.args == ["x1"], "the event"
check p.statements[0].q == "why" and p.statements[0].target == "e1", "Ask why"

// "When did you pick it up?" ... "While you were stacking up the red cube..."
text = [
  "x1 = the cube [color red]",
  "e1 = event Stack x1",
  "e2 = event PickUp x2 [while e1]",
  "x2 = it",
  "Ask when e2"].join(nl)
p = roundTrip(text, "event with a time constraint")
check p.lookup("e2").props[0] == {"pred": "while", "args": ["e1"]}, "while e1"

// "A steeple is a stack which contains two green cubes and a pyramid."
text = [
  "x1 = a stack [contains x2] [contains x3]",
  "x2 = 2 cubes [color green]",
  "x3 = a pyramid",
  "Define steeple, x1"].join(nl)
p = roundTrip(text, "define steeple")
check p.lookup("x2").det == "number" and p.lookup("x2").n == 2, "2 cubes"
d = p.statements[0]
check d.kind == "declare" and d.verb == "define" and d.args == ["steeple", "x1"], "Define is a declaration"

// "Call it superblock."  Then refer to it by name.
p = roundTrip("x1 = it" + nl + "Name x1, superblock" + nl + "x2 = superblock" + nl + "PickUp x2", "naming")
check p.lookup("x2").head == "superblock" and p.lookup("x2").det == null, "a name, not a plural"

//----------------------------------------------------------------------
// Shorthand and leniency
//----------------------------------------------------------------------

// [color red|green] is an "or".
p = roundTrip("x1 = every block [color red|green]" + nl + "Ask which x1", "red or green")
c = p.lookup("x1").props[0]
check c.pred == "or" and c.args.len == 2 and c.args[1] == {"pred": "color", "args": ["green"]}, "| makes an or"

// Spelled out the long way, it still prints the short way.
p = icl.read("x1 = a block [or [color red] [color green]]")
check icl.format(p.lines[0]) == "x1 = a block [color red|green]", "or prints compactly"
// But an or of different predicates prints the long way.
roundTrip "x1 = a block [or [on x2] [in x2]]" + nl + "x2 = the box", "mixed or"

// Comments and blank lines are ignored; "an" becomes "a"; commas are optional.
p = icl.read("// a comment" + nl + nl + "x1 = an object   // trailing" + nl + "x2 = the box" + nl + "PutIn x1 x2")
check p.errors.len == 0 and p.lines.len == 3, "comments and blanks skipped"
check p.lookup("x1").det == "a", "an -> a"
check icl.format(p.lines[2]) == "PutIn x1, x2", "commas added when printing"

//----------------------------------------------------------------------
// Building ICL in code (the way the parser will)
//----------------------------------------------------------------------

p = icl.Program.make
box = p.add(icl.description("the", "box"))
blocks = p.add(icl.description("every", "block", false, [icl.constraint("not", [icl.constraint("in", [box])])]))
p.add icl.command("putIn", [blocks, box])
p.add icl.ask("count", blocks)
expected = [
  "x1 = the box",
  "x2 = every block [not [in x1]]",
  "PutIn x2, x1",
  "Ask count x2"].join(nl)
check p.format == expected, "built in code; got:" + nl + p.format
check icl.read(p.format).format == p.format, "and it reads back"
check p.newVar("e") == "e1", "event variables are numbered separately"

// "Stack up both of the red blocks and either a green cube or a pyramid."
// Joined noun phrases are groups, which can be joined again.
p = roundTrip([
  "x1 = both blocks [color red]",
  "x2 = a cube [color green]",
  "x3 = a pyramid",
  "x4 = x2 or x3",
  "x5 = x1 and x4",
  "Stack x5"].join(nl), "stack up both red blocks and either a green cube or a pyramid")
x4 = p.lookup("x4")
check x4.kind == "group" and x4.join == "or" and x4.members == ["x2", "x3"], "x4 is x2 or x3"
check p.lookup("x1").det == "both" and p.lookup("x1").plural, "both blocks"
check p.statements.len == 1, "groups aren't statements"
roundTrip "x1 = it" + nl + "x2 = the box" + nl + "x3 = a pyramid" + nl + "x4 = x1 and x2 and x3" + nl + "Stack x4", "three things joined"

// "There were five blocks to the left of the box then."  A claim to check.
p = roundTrip("x1 = 5 blocks [then [leftOf x2]]" + nl + "x2 = the box" + nl + "Claim exists x1", "a claim about then")
check p.statements[0].kind == "claim" and p.statements[0].q == "exists", "Claim exists x1 is a claim"

// Questions about ability: what could be so, and what could be done (and
// by what).
roundTrip "x1 = a pyramid" + nl + "x2 = a block" + nl + "Ask can x1 [on x2]", "can a pyramid be supported by a block"
p = roundTrip("x1 = the table" + nl + "x2 = any blocks" + nl + "e1 = event PickUp x2 [by x1]" + nl + "Ask can e1", "can the table pick up blocks")
check p.statements[0].q == "can" and p.statements[0].claim == null, "Ask can e1 has no claim"

//----------------------------------------------------------------------
// Errors
//----------------------------------------------------------------------

errorsFor = function(text)
	return icl.read(text).errors
end function

e = errorsFor("x1 = a block [color red")
check e.len == 1 and e[0].indexOf("missing ]") != null, "missing ]: " + e
e = errorsFor("ask color x1")
check e.len == 1 and e[0].indexOf("capital letter") != null, "lowercase ask: " + e
e = errorsFor("Ask [color x1]")
check e.len == 1 and e[0].indexOf("as in") != null, "Ask needs a kind of question: " + e
e = errorsFor("b1 = a block")
check e.len == 1 and e[0].indexOf("variable") != null, "bad variable name: " + e
e = errorsFor("PickUp x9")
check e.len == 1 and e[0].indexOf("x9") != null, "undefined variable: " + e
e = errorsFor("x1 = it" + nl + "x1 = the box")
check e.len == 1 and e[0].indexOf("line 2") != null and e[0].indexOf("twice") != null, "defined twice: " + e
e = errorsFor("x1 = it" + nl + "Ask yes-no x1")
check e.len == 1 and e[0].indexOf("claim") != null, "yes-no without a claim: " + e
e = errorsFor("x1 = a block [not [on x1] [in x1]]")
check e.len == 1 and e[0].indexOf("wrong number") != null, "not with two parts: " + e
e = errorsFor("x1 = the block red")
check e.len == 1 and e[0].indexOf("expected [") != null, "a stray word: " + e
e = errorsFor("x1 = it" + nl + "x2 = the box" + nl + "x3 = x1 and x2 or x1")
check e.len == 1 and e[0].indexOf("mix") != null, "and with or: " + e
e = errorsFor("x1 = it" + nl + "x2 = x1 and red")
check e.len == 1 and e[0].indexOf("variable") != null, "a group of a word: " + e
e = errorsFor("x1 = it" + nl + "x2 = x1 and x7")
check e.len == 1 and e[0].indexOf("x7") != null, "a group with an undefined variable: " + e
e = errorsFor("pick up x1")
check e.len == 1 and e[0].indexOf("line 1") != null, "lowercase verb: " + e

print checks + " checks, " + failures + " failures."
exit (failures > 0)
