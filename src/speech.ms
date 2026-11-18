// speech.ms
//
// Turning things back into English: names for objects ("the red cube", "a
// large green cube"), lists ("the blue pyramid and the blue block"), and
// numbers.
//
// We name things the way Winograd's robot did (see "Understanding Natural
// Language", section 8.3.3):
//
//   - The box and the table are "the box" and "the table", and something
//     the user has named is "the block named superblock".
//   - Anything else gets its noun and color.  If that fits nothing else,
//     it's "the red cube".
//   - If not, the size goes on too: "the large red block".
//   - If that still fits something else, then when it doesn't matter which
//     one we mean, it's "a large green cube": "What does the box contain?",
//     or "To put it on a large green cube."
//   - When it does matter (answering "Which cube...?"), we say more: "the
//     large green cube which supports the red pyramid" (see whichClause).
//
// (Winograd's robot said "a large red block" even when there was only one,
// apparently because "red block" alone wasn't enough.  "The large red
// block" is better, so we say that.)
//
// A thing whose noun is the one in the question is called "one": "Is there
// a large block behind a pyramid?"  "Yes, three of them: a large red one, a
// large green cube and the blue one."

import "relations"
import "icl"
import "world"

containsRef = @world.containsRef

numberWords = ["none", "one", "two", "three", "four", "five", "six",
  "seven", "eight", "nine", "ten", "eleven", "twelve"]

numberWord = function(n)
	if n >= 0 and n < numberWords.len then return numberWords[n]
	return str(n)
end function

// Capitalize the first letter, for the start of a reply.
capitalize = function(s)
	if not s then return s
	return s[0].upper + s[1:]
end function

// "a", "a and b", "a, b and c"
listPhrase = function(parts, conjunction="and")
	if parts.len == 0 then return ""
	if parts.len == 1 then return parts[0]
	return parts[:-1].join(", ") + " " + conjunction + " " + parts[-1]
end function

// The size word to use for a thing, if any ("large", "small").
sizeWord = function(theWorld, thing)
	c = relations.sizeClass(theWorld, thing)
	if c == "big" then return "large"
	if c == "small" then return "small"
	return null
end function

// The name for a thing.  `specific` says whether it must pick out just
// this thing (see above).  `noun` is the question's noun, if any, to be
// replaced by "one".
nameFor = function(theWorld, thing, specific=true, noun=null)
	if thing.shape == "table" or thing.shape == "box" then return "the " + thing.shape
	if thing.shape == "stack" and thing.names then return "the stack named " + thing.names[0]
	if thing.shape == "stack" then return "the stack of " + namesFor(theWorld, thing.parts)
	myNoun = thing.noun
	if myNoun == noun then myNoun = "one"
	if thing.names then return "the " + myNoun + " named " + thing.names[0]
	words = [thing.color, myNoun]
	rivals = lookalikes(theWorld, thing)
	if not rivals then return "the " + words.join(" ")
	size = sizeWord(theWorld, thing)
	if size then words.insert 0, size
	sameSize = []
	for t in rivals
		if sizeWord(theWorld, t) == size then sameSize.push t
	end for
	if not sameSize then return "the " + words.join(" ")
	if not specific then return withArticle(words.join(" "))
	return "the " + words.join(" ") + whichClause(theWorld, thing, sameSize)
end function

// The other things that this thing's color and noun fit.  (A cube is a
// block too, so "red block" fits a red cube.)
lookalikes = function(theWorld, thing)
	result = []
	for t in theWorld.things
		if refEquals(t, thing) then continue
		if t.color == thing.color and relations.nounFits(t, thing.noun) then result.push t
	end for
	return result
end function

// "a large green cube", "an orange block"
withArticle = function(phrase)
	if "aeiou".indexOf(phrase[0]) != null then return "an " + phrase
	return "a " + phrase
end function

// What tells a thing apart from its rivals (the other things its name
// would fit): " which I am holding", " which supports the red pyramid"
// (Winograd's robot's favorite), " which is on the large red block", or
// " which is to the right of the blue block" (or left of, behind, or in
// front of).  We use the first that's true of this thing and of none of
// its rivals.
whichClause = function(theWorld, thing, rivals)
	if refEquals(theWorld.hand.holding, thing) then return " which I am holding"
	for c in clauseChoices(theWorld, thing, rivals)
		related = @relations.binary[c[0]]
		if not related(theWorld, thing, c[1]) then continue
		unique = true
		for r in rivals
			if related(theWorld, r, c[1]) then unique = false
		end for
		if unique then return " which " + c[2] + " " + nameFor(theWorld, c[1], false)
	end for
	return ""
end function

// The clauses whichClause can choose from, best first: [relation, other
// thing, words].  (Not "to the left of a red cube" for a red cube, though:
// a direction is from something other than its rivals.)
clauseChoices = function(theWorld, thing, rivals)
	choices = []
	for t in theWorld.thingsOn(thing)
		choices.push ["supports", t, "supports"]
	end for
	for t in thing.supporters
		if t.shape == "box" then choices.push ["in", t, "is in"] else choices.push ["on", t, "is on"]
	end for
	directions = [["rightOf", "is to the right of"], ["leftOf", "is to the left of"],
	  ["behind", "is behind"], ["inFrontOf", "is in front of"]]
	for d in directions
		for t in theWorld.things
			if t.shape == "table" or refEquals(t, thing) or containsRef(rivals, t) then continue
			choices.push [d[0], t, d[1]]
		end for
	end for
	return choices
end function

// Names for a list of things: "the blue pyramid and the blue block".
// These don't need to say which is which, so things alike are counted
// together: "the red cube, two large green cubes and a large red block".
namesFor = function(theWorld, things, noun=null)
	names = []
	counts = {}
	for t in things
		name = nameFor(theWorld, t, false, noun)
		if counts.hasIndex(name) then
			counts[name] += 1
		else
			counts[name] = 1
			names.push name
		end if
	end for
	parts = []
	for name in names
		n = counts[name]
		if n == 1 then parts.push name else parts.push numberWord(n) + " " + pluralPhrase(name)
	end for
	return listPhrase(parts)
end function

// "a large green cube" -> "large green cubes"
pluralPhrase = function(name)
	words = name.split(" ")[1:]
	words[-1] = icl.pluralize(words[-1])
	return words.join(" ")
end function

// Names that pick out each thing: "the large green cube which supports
// the red pyramid".
specificNamesFor = function(theWorld, things, noun=null)
	parts = []
	for t in things
		parts.push nameFor(theWorld, t, true, noun)
	end for
	return listPhrase(parts)
end function

// A rough English rendering of an ICL description, for messages like
// "I don't see any red pyramids."  It uses only the noun and the simple
// adjectives (color and size); that's enough for those messages.
descriptionPhrase = function(desc, plural=null)
	if plural == null then plural = desc.plural
	words = []
	for c in desc.props
		if (c.pred == "color" or c.pred == "size") and c.args.len == 1 then words.push c.args[0]
	end for
	noun = desc.head
	if noun == "one" then noun = "thing"
	if plural then noun = icl.pluralize(noun)
	words.push noun
	return words.join(" ")
end function

//----------------------------------------------------------------------
// Talking about goals, for "why", "how", and "when" questions.
//----------------------------------------------------------------------

// The verb for each kind of goal: [to-form, ing-form, particle, past].
// Verbs like "pick up" have a particle that moves after a pronoun: we say
// "pick up the red cube" but "pick it up".
goalVerbs = {
  "grasp":    ["pick", "picking", "up", "picked"],
  "putOn":    ["put", "putting", "", "put"],
  "clearOff": ["clean", "cleaning", "off", "cleaned"],
  "getRidOf": ["get rid of", "getting rid of", "", "got rid of"],
  "stack":    ["stack", "stacking", "up", "stacked"]}
emptyVerb = ["empty", "emptying", "", "emptied"]

// Which of a goal verb's forms to use.
formIndex = {"to": 0, "ing": 1, "ed": 3}

// A phrase for a goal: "get rid of it", "putting the red cube in the box",
// "picked up the red cube".  `form` is "to", "ing" or "ed".  Whatever the conversation is focused on (`it`)
// is called "it", as a person would.  To tell of several steps in a row,
// pass a Teller instead, which names things as the story goes along.
goalPhrase = function(theWorld, goal, form, it=null, teller=null)
	if teller == null then teller = Teller.make(theWorld, it)
	entry = goalVerbs[goal.kind]
	verb = entry[formIndex[form]]
	if goal.kind == "putOn" and goal.near and goal.near.hasIndex("rel") then
		// "put the red cube next to the blue block"
		return verb + " " + teller.name(goal.args[0]) + " " + relationPhrase(theWorld, goal.near.rel, goal.near.other)
	end if
	if goal.kind == "putOn" then return verb + " " + teller.name(goal.args[0]) + placePhrase(theWorld, goal.args[1], teller)
	names = []
	for t in goal.args
		// ("It" only for one thing alone, not in a list: "stack up the red
		// cube, it and the box" would be confusing.)
		if goal.kind == "stack" then names.push nameFor(theWorld, t, false) else names.push teller.name(t)
	end for
	// Clearing off the box is emptying it.
	if goal.kind == "clearOff" and goal.args[0].shape == "box" then entry = emptyVerb
	verb = entry[formIndex[form]]
	particle = entry[2]
	object = listPhrase(names)
	if not particle then return verb + " " + object
	if object == "it" then return verb + " it " + particle
	return verb + " " + particle + " " + object
end function

// Where something is in relation to another thing, for "There's no room
// next to the blue block for the red cube": "next to the blue block", "to
// the left of the box", "at the front of the table".
relationWords = {"nextTo": "next to", "leftOf": "to the left of", "rightOf": "to the right of",
  "behind": "behind", "inFrontOf": "in front of"}
tableSideWords = {"nextTo": "on", "leftOf": "on the left of", "rightOf": "on the right of",
  "behind": "at the back of", "inFrontOf": "at the front of"}
relationPhrase = function(theWorld, rel, other)
	if other.shape == "table" then return tableSideWords[rel] + " the table"
	return relationWords[rel] + " " + nameFor(theWorld, other)
end function

// " on the red block", or " in the box".
placePhrase = function(theWorld, target, teller=null)
	if teller then name = teller.name(target) else name = nameFor(theWorld, target, false)
	if target.shape == "box" then return " in " + name
	return " on " + name
end function

// Naming things while telling of several steps ("How did you do it?"):
//   "By putting a large green cube on the large red block, then putting
//    the red cube on it."
// The thing we're talking about is "it", and after each step, that step's
// main thing is.  Something already mentioned as "a large green cube" is
// "that cube" after that, so it doesn't sound like another one.
Teller = {}
Teller.world = null
Teller.it = null
Teller.mentioned = null

Teller.make = function(theWorld, it=null)
	t = new Teller
	t.world = theWorld
	t.it = it
	t.mentioned = []
	return t
end function

Teller.name = function(thing)
	if refEquals(thing, self.it) then return "it"
	name = nameFor(self.world, thing, false)
	if containsRef(self.mentioned, thing) then
		if name.indexOf("a ") == 0 or name.indexOf("an ") == 0 then return "that " + thing.noun
	else
		self.mentioned.push thing
	end if
	return name
end function

// One step of the story, as an "-ing" phrase.
Teller.step = function(goal)
	phrase = goalPhrase(self.world, goal, "ing", null, self)
	if goal.kind != "stack" then self.it = goal.args[0]
	return phrase
end function

// The last step of putting something somewhere: "setting it down on the table".
settingDownPhrase = function(theWorld, target, teller=null)
	return "setting it down" + placePhrase(theWorld, target, teller)
end function

//----------------------------------------------------------------------
// Echoing the user's words
//----------------------------------------------------------------------

// The user's words for something, as the robot would say them back:
// "a block which is taller than the one you are holding" becomes "the
// block which is taller than the one I am holding", and "superblock"
// becomes "the superblock".  (This is how Winograd's robot said what it
// took "it" to mean.)  "You" is "I" before a verb, and "me" after one.
echoSwaps = {"i": "you", "me": "you", "my": "your", "mine": "yours",
  "myself": "yourself", "your": "my", "yours": "mine", "yourself": "myself"}
echoAfterYou = {"are": "am", "were": "was"}
echoAfterI = {"am": "are", "was": "were"}
echoObjectAfter = ["told", "asked", "to", "for", "by", "with", "than", "gave", "showed"]
echoPhrase = function(words)
	result = swapPersons(words).split(" ")
	// It's one particular thing now, so it's "the" whatever it was.
	if ["a", "an", "any", "some", "the"].indexOf(result[0]) != null then
		result[0] = "the"
	else
		result.insert 0, "the"
	end if
	return result.join(" ")
end function

// The user's words as the robot would say them: "the one you are holding"
// becomes "the one I am holding".
swapPersons = function(words)
	list = words.split(" ")
	result = []
	previous = ""
	for w in list
		said = w
		if echoSwaps.hasIndex(w) then said = echoSwaps[w]
		if w == "you" then
			said = "I"
			if echoObjectAfter.indexOf(previous) != null then said = "me"
		end if
		if previous == "you" and echoAfterYou.hasIndex(w) then said = echoAfterYou[w]
		if previous == "i" and echoAfterI.hasIndex(w) then said = echoAfterI[w]
		result.push said
		previous = w
	end for
	return result.join(" ")
end function
