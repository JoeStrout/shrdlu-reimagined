// speech.ms
//
// Turning things back into English: names for objects ("the large green
// cube"), lists ("the red block and the blue pyramid"), and numbers.
//
// A good name for an object says just enough to pick it out, the way a person
// would: "the red block" if there's only one, "the large green cube" if there
// are two green cubes, "the green cube which is on the red block" if size
// doesn't settle it either.

import "relations"
import "icl"

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

// A definite name for a thing, like "the large green cube".
// `depth` limits how far we go with "which is on..." clauses.
nameFor = function(theWorld, thing, depth=0)
	if thing.shape == "table" then return "the table"
	words = [thing.noun]
	// Everything else it might be confused with: everything else its noun
	// fits.  (A cube is a block too, so "the red block" has to rule out a
	// red cube.)
	rivals = []
	for t in theWorld.things
		if refEquals(t, thing) or t.shape == "table" then continue
		if relations.nounFits(t, thing.noun) then rivals.push t
	end for
	// The box has no rivals, and "the white box" would sound odd; everything
	// else gets its color, which is how Winograd's robot talked.
	if rivals or thing.shape != "box" then
		words.insert 0, thing.color
		sameColor = []
		for t in rivals
			if t.color == thing.color then sameColor.push t
		end for
		rivals = sameColor
	end if
	if rivals then
		size = sizeWord(theWorld, thing)
		if size then
			sameSize = []
			for t in rivals
				if sizeWord(theWorld, t) == size then sameSize.push t
			end for
			if sameSize.len < rivals.len then
				words.insert 0, size
				rivals = sameSize
			end if
		end if
	end if
	name = "the " + words.join(" ")
	if rivals and depth < 2 then name += whereClause(theWorld, thing, depth)
	return name
end function

// A clause saying where a thing is, like " which is on the red block".
whereClause = function(theWorld, thing, depth)
	if refEquals(theWorld.hand.holding, thing) then return " which I am holding"
	if not thing.supporters then return ""
	under = thing.supporters[0]
	if under.shape == "box" then return " which is in the box"
	return " which is on " + nameFor(theWorld, under, depth + 1)
end function

// Names for a list of things: "the red block and the blue pyramid".
namesFor = function(theWorld, things)
	parts = []
	for t in things
		parts.push nameFor(theWorld, t)
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

// The verb for each kind of goal: [to-form, ing-form, particle].  Verbs
// like "pick up" have a particle that moves after a pronoun: we say "pick
// up the red cube" but "pick it up".
goalVerbs = {
  "grasp":    ["pick", "picking", "up"],
  "putOn":    ["put", "putting", ""],
  "clearOff": ["clean", "cleaning", "off"],
  "getRidOf": ["get rid of", "getting rid of", ""],
  "stack":    ["stack", "stacking", "up"]}

// A phrase for a goal: "get rid of it", "putting the red cube in the box".
// `form` is "to" or "ing".  Whatever the conversation is focused on (`it`)
// is called "it", as a person would.
goalPhrase = function(theWorld, goal, form, it=null)
	names = []
	for t in goal.args
		// ("It" only for one thing alone, not in a list: "stack up the red
		// cube, it and the box" would be confusing.)
		if refEquals(t, it) and goal.kind != "stack" then names.push "it" else names.push nameFor(theWorld, t)
	end for
	entry = goalVerbs[goal.kind]
	verb = entry[form == "ing"]
	particle = entry[2]
	if goal.kind == "putOn" then return verb + " " + names[0] + placePhrase(theWorld, goal.args[1])
	object = listPhrase(names)
	if not particle then return verb + " " + object
	if object == "it" then return verb + " it " + particle
	return verb + " " + particle + " " + object
end function

// " on the red block", or " in the box".
placePhrase = function(theWorld, target)
	if target.shape == "box" then return " in " + nameFor(theWorld, target)
	return " on " + nameFor(theWorld, target)
end function

// The last step of putting something somewhere: "setting it down on the table".
settingDownPhrase = function(theWorld, target)
	return "setting it down" + placePhrase(theWorld, target)
end function
