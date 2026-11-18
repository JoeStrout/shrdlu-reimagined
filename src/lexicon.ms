// lexicon.ms
//
// The words the robot knows, as data.  Each word has a list of entries,
// because some words do more than one job ("that" is a determiner, a
// pronoun, and a relative pronoun).  An entry is a map whose "cat" says what
// kind of word it is; the rest says what it means:
//
//   det          a determiner: {det, number}, as in ICL ("a", "the", "how-many"...)
//   noun         {head}: "block", "pyramid", "one" ...
//   pronoun      {head}: "it", "them", "this" ...; or {det, head} for
//                "something" (= a thing), "anything" (= any thing) ...
//   adj          {pred, value}: [color red], [size big]; or {pred} alone
//                for words like "littlest" and "clear"
//   comparative  {pred}: "taller" (than ...) gives [taller x2]
//   prep         {pred}: "on", "behind", "on top of" ...
//   relpro       a relative pronoun: "which", "that", "who"
//   be           "is", "are" ...
//   not          "not"
//   do           "do", "does", "did" (as in "which does not support...")
//   than         "than"
//   you          "you"
//   verb         {rel}: a verb that's a relation ("supports" gives [supports x2]);
//                {posture}: "sit", "rest" ("sitting on the table" means "on");
//                {held}: "hold", "grasp" (what you're holding is [held]);
//                {frames}: a command ("pick up", "put"); see below
//   particle     "up", "down", "off", "out": the second word of "pick up", "put down"...
//   attribute    {attr}: "color", "size", "shape", for "what color is it?"
//   whAdverb     {q}: "why", "how", "when"
//   modal        "will", "can", "would", "could" (as in "will you please...")
//   polite       "please"
//
// A command verb has a list of frames: the shapes it can take, and the ICL
// command each shape means.  In a shape, "thing" is a noun phrase; "on" or
// "in" is any preposition meaning that ("onto", "on top of", "into"...);
// and "up", "down", "off", "out" are particles, which may also come after the
// noun phrase ("pick up the block", "pick the block up", "pick it up").
//
// Phrases of several words ("on top of", "how many") are entered with
// spaces, and the parser's tokenizer joins them into a single word.
//
// Inflected forms come from rules (see lookup), so "blocks", "supports",
// and "holding" don't need entries of their own.  The entries returned by
// lookup carry a "form": "plural", "s", "ed", or "ing" when the word was
// inflected (or "base" when it wasn't).

import "icl"

words = {}       // word -> list of entries
phrases = []     // the multi-word entries, each a list of words, longest first

// Add an entry for a word (or phrase).
add = function(word, entry)
	if not words.hasIndex(word) then
		words[word] = []
		if word.indexOf(" ") != null then
			// Keep the longest phrases first, so "to the left of" is
			// found before "left of".
			parts = word.split(" ")
			i = 0
			while i < phrases.len and phrases[i].len >= parts.len
				i += 1
			end while
			phrases.insert i, parts
		end if
	end if
	words[word].push entry
end function

// Helpers that keep the tables below short and readable.
determiner = function(word, det, number=null, n=null)
	add word, {"cat": "det", "det": det, "number": number, "n": n}
end function
noun = function(word, head=null)
	if head == null then head = word
	add word, {"cat": "noun", "head": head}
end function
pronoun = function(word, head=null, det=null)
	if head == null then head = word
	add word, {"cat": "pronoun", "head": head, "det": det}
end function
adjective = function(word, pred, value=null)
	add word, {"cat": "adj", "pred": pred, "value": value}
end function
comparative = function(word, pred)
	add word, {"cat": "comparative", "pred": pred}
end function
preposition = function(word, pred, sense=null)
	entry = {"cat": "prep", "pred": pred}
	if sense then entry.sense = sense
	add word, entry
end function
verb = function(word, meaning)
	add word, {"cat": "verb"} + meaning
end function
simple = function(word, cat)
	add word, {"cat": cat}
end function

//----------------------------------------------------------------------
// The words.
//----------------------------------------------------------------------

// Determiners.  number says whether the noun must be singular ("sg") or
// plural ("pl"); null means either.
determiner "a", "a", "sg"
determiner "an", "a", "sg"
determiner "the", "the"
determiner "any", "any"
determiner "some", "a"
determiner "every", "every", "sg"
determiner "each", "every", "sg"
determiner "all", "every", "pl"
determiner "no", "no"
// "That cube" and "this cube" are "the cube", which prefers the one just
// mentioned or clicked on (see Brain.inFocus).
determiner "that", "the", "sg"
determiner "this", "the", "sg"
determiner "which", "which"
determiner "what", "which"
determiner "how many", "how-many", "pl"

// Numbers, which are determiners too ("two pyramids").
numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
for i in range(1, numberWords.len - 1)
	if i == 1 then number = "sg" else number = "pl"
	determiner numberWords[i], "number", number, i
end for

// Nouns.  (These are the ones relations.nounFits understands, plus "one",
// which borrows its noun from something said earlier.)
for w in ["block", "cube", "pyramid", "cylinder", "box", "table", "thing", "object", "stack"]
	noun w
end for
noun "one"
noun "item", "object"

// Pronouns.
for w in ["it", "them", "they", "this", "that"]
	pronoun w
end for
pronoun "something", "thing", "a"
pronoun "anything", "thing", "any"
pronoun "everything", "thing", "every"
pronoun "nothing", "thing", "no"

// Adjectives.
for c in ["red", "green", "blue", "yellow", "white", "black"]
	adjective c, "color", c
end for
for w in ["big", "large", "huge"]
	adjective w, "size", "big"
end for
for w in ["small", "little", "tiny"]
	adjective w, "size", "small"
end for
for w in ["biggest", "largest", "smallest", "littlest", "tallest", "shortest", "widest", "narrowest"]
	add w, {"cat": "adj", "pred": w, "value": null, "superlative": true}
end for
// Tall, short, wide and narrow are relative, like big and small.
adjective "tall", "height", "tall"
adjective "short", "height", "short"
for w in ["wide", "broad", "fat"]
	adjective w, "breadth", "wide"
end for
for w in ["narrow", "thin", "skinny"]
	adjective w, "breadth", "narrow"
end for
adjective "clear", "clear"
adjective "empty", "empty"
adjective "supported", "supported"

// Ordinals, which go with superlatives: "the second tallest block".
ordinals = ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
for i in range(1, ordinals.len - 1)
	add ordinals[i], {"cat": "ordinal", "n": i}
end for

// "The top of the red cube" is just the red cube, as far as the robot can
// tell: "Is the top of the red cube clear?"  "Put it on top of..." is a
// preposition instead (see below).
for w in ["the top of", "the top surface of", "the surface of"]
	simple w, "topOf"
end for

// Comparatives ("taller than ...").
comparative "taller", "taller"
comparative "shorter", "shorter"
comparative "wider", "wider"
comparative "narrower", "narrower"
comparative "thinner", "narrower"
comparative "bigger", "bigger"
comparative "larger", "bigger"
comparative "smaller", "smaller"
comparative "littler", "smaller"
// "As wide as ..." needs no "than".
for pair in [["tall", "asTall"], ["wide", "asWide"], ["big", "asBig"], ["large", "asBig"]]
	add "as " + pair[0] + " as", {"cat": "comparative", "pred": pair[1], "as": true}
end for

// Prepositions.  Several words can mean the same relation.
for w in ["on", "onto", "upon", "supported by"]
	preposition w, "on"
end for
// "On top of" may mean directly on, or anywhere above.  Each sense says
// what it means, so that when it matters which one the user meant, the
// robot can ask (see Brain.senseQuestion).  In a command ("put it on top
// of the red block"), only "on" fits.
preposition "on top of", "on", "directly on the surface"
preposition "on top of", "above", "anywhere on top of"
for w in ["in", "into", "inside", "inside of", "within"]
	preposition w, "in"
end for
for w in ["under", "underneath", "below", "beneath"]
	preposition w, "below"
end for
for w in ["above", "over"]
	preposition w, "above"
end for
preposition "behind", "behind"
preposition "in front of", "inFrontOf"
for w in ["next to", "beside"]
	preposition w, "nextTo"
end for
for w in ["to the left of", "left of", "on the left of", "on the left side of", "at the left of", "to the left side of"]
	preposition w, "leftOf"
end for
for w in ["to the right of", "right of", "on the right of", "on the right side of", "at the right of", "to the right side of"]
	preposition w, "rightOf"
end for
// At the front or back of the table: see relations.tableSide.
for w in ["at the front of", "to the front of", "in the front of", "on the front of", "toward the front of", "towards the front of"]
	preposition w, "inFrontOf"
end for
for w in ["at the back of", "to the back of", "in the back of", "on the back of", "toward the back of", "towards the back of"]
	preposition w, "behind"
end for

// Verbs.
verb "support", {"rel": "supports"}
verb "contain", {"rel": "contains"}
verb "touch", {"rel": "touches"}
verb "sit", {"posture": true}
verb "rest", {"posture": true}
verb "lie", {"posture": true}
verb "stand", {"posture": true}
verb "hold", {"held": true}
verb "grasp", {"held": true}

// Owning: "I own blocks which are not red", "the blue pyramid is mine".
// (Only the user owns things, so far.)
verb "own", {"own": true}
add "mine", {"cat": "mine"}

// Command verbs, with their frames.  A shape of "" means the verb alone
// ("let go").
frame = function(shape, icl)
	if shape == "" then return {"shape": [], "icl": icl}
	return {"shape": shape.split(" "), "icl": icl}
end function
// A frame whose second noun phrase says where the first one is now:
// "take the green cube off the red block" means getting rid of the green
// cube which is on the red block.  `from` is that relation.  (The box
// counts too, since it supports what's in it, but "out of" is "in".)
fromFrame = function(shape, icl, from="on")
	f = frame(shape, icl)
	f.from = from
	return f
end function
command = function(word, frames)
	add word, {"cat": "verb", "frames": frames}
end function
// "To" goes with "move", "put" and so on, but not with "pick up": "move it
// to the box".
putFrames = [frame("thing on thing", "putOn"), frame("thing in thing", "putIn"), frame("down thing", "putDown"),
  frame("thing to thing", "putOn"), frame("down thing on thing", "putOn"), frame("down thing in thing", "putIn")]
// Putting something next to something, or to its left, and so on: it goes
// on whatever the other thing stands on (usually the table), at a spot
// where that's true.  "Put it to the left of the table" means on the left
// side of the table.
for rel in ["nextTo", "leftOf", "rightOf", "behind", "inFrontOf"]
	f = frame("thing " + rel + " thing", "putAt")
	f.relation = rel
	putFrames.push f
end for
// "Put it back": where it was before we last moved it.
putFrames.push frame("back thing", "putBack")
// Putting something under something else is putting that on it: "put the
// red cube under the green pyramid".  A frame with swap gives its two
// noun phrases the other way around.
underFrame = frame("thing below thing", "putOn")
underFrame.swap = true
putFrames.push underFrame
// Taking something off or out of something leaves it on the table.
takeFrames = [fromFrame("thing off thing", "getRidOf"), fromFrame("off thing thing", "getRidOf"),
  fromFrame("thing outOf thing", "getRidOf", "in"), fromFrame("thing from thing", "getRidOf")]

command "pick", [frame("up thing", "pickUp")]
command "lift", [frame("up thing", "pickUp"), frame("thing", "pickUp")] + takeFrames
command "grasp", [frame("thing", "pickUp")]
command "grab", [frame("thing", "pickUp")]
command "take", [frame("thing", "pickUp"), frame("up thing", "pickUp"), frame("down thing", "putDown")] + takeFrames
command "get", [frame("thing", "pickUp")] + takeFrames
command "hold", [frame("thing", "pickUp")]
command "put", putFrames
command "set", putFrames
command "stick", putFrames
command "place", putFrames[:2] + putFrames[3:]
// "Move" alone is for questions: "Why did you move the red pyramid?"
command "move", putFrames[:2] + putFrames[3:] + takeFrames + [frame("thing", "move")]
command "drop", [frame("thing", "drop"), frame("thing on thing", "putOn"), frame("thing in thing", "putIn")]
command "let go of", [frame("thing", "putDown")]
command "let go", [frame("", "putDown")]
command "release", [frame("thing", "putDown")]
command "clear", [frame("off thing", "clearOff"), frame("out thing", "clearOff"), frame("thing", "clearOff")]
command "clean", [frame("off thing", "clearOff"), frame("out thing", "clearOff"), frame("up thing", "clearOff")]
command "empty", [frame("thing", "clearOff"), frame("out thing", "clearOff")]     // (the box)
command "get rid of", [frame("thing", "getRidOf")]
command "remove", [frame("thing", "getRidOf"), fromFrame("thing from thing", "getRidOf")]
command "stack", [frame("up thing", "stack"), frame("thing", "stack"), frame("thing on thing", "putOn")]
command "pile", [frame("up thing", "stack")]
command "find", [frame("thing", "find")]
command "build", [frame("thing", "build"), frame("me thing", "build")]
command "make", [frame("thing", "build"), frame("me thing", "build")]
// "Bring me a cube": the robot can't reach you, but it can pick one up.
command "bring", [frame("me thing", "pickUp"), frame("thing", "pickUp")]
command "fetch", [frame("me thing", "pickUp"), frame("thing", "pickUp")]
command "call", [frame("thing name", "name")]
// "Count the blocks" is a question: how many are there?
command "count", [frame("thing", "count")]
// "Undo that": put back whatever we moved for the last thing we were asked.
command "undo", [frame("thing", "undo"), frame("", "undo")]
// "Show me the red cube" asks where it is.
simple "show", "show"
// "Touch" is only for questions so far: "Had you touched any pyramid...?"
command "touch", [frame("thing", "touch")]
command "name", [frame("thing name", "name")]

for w in ["up", "down", "off", "out", "back"]
	simple w, "particle"
end for
// Words that a frame's shape names by their category: "out of", "from",
// "to", "me".
simple "out of", "outOf"
simple "from", "from"
simple "me", "me"

// Question words.
for w in ["color", "colour", "size", "shape"]
	add w, {"cat": "attribute", "attr": w.replace("colour", "color")}
end for
for w in ["why", "how", "when"]
	add w, {"cat": "whAdverb", "q": w}
end for
// "Where is the red cube?"  "Where did it go?"
simple "where", "where"
simple "go", "go"
// "How big is it?" asks its size.
for w in ["how big", "how large"]
	add w, {"cat": "howAttr", "attr": "size"}
end for
pronoun "what", "thing", "which"
pronoun "which", "thing", "which"     // "Which is taller, ...?"
simple "there", "there"
simple "now", "now"
// "Do you see a red pyramid?" asks whether there is one.
verb "see", {"see": true}
// "Blocks colored red or blue"
for w in ["colored", "coloured"]
	simple w, "colored"
end for
// "What is that block's color?"  (The tokenizer splits off the "'s".)
simple "'s", "poss"
// What the robot is holding is in its hand: "What's in your hand?"
adjective "in your hand", "held"
// "Is your hand empty?"  (The hand isn't a thing in the world, so this is a
// question about what's held: see Parser.handQuestion.)
simple "your hand", "yourHand"
adjective "full", "full"

// Words that may start a command without changing what it means: "Now put
// it in the box", "First pick up the red cube, then...".
for w in ["now", "first", "next", "then", "so", "ok", "okay", "also"]
	simple w, "lead"
end for
// Ways of asking for something, before the command itself: "I want you to
// pick up a block", "Go find a block", "Try to find a red pyramid".
for w in ["i want you to", "i would like you to", "i need you to", "try to", "go", "go and", "please"]
	simple w, "request"
end for
// Words that may end a sentence without changing what it means.
simple "again", "again"
for w in ["right now", "at the moment", "currently"]
	simple w, "now"
end for
// "Have you ever touched...?"  ("Ever" adds nothing: the robot only
// remembers since the conversation began.)
simple "ever", "ever"

// Social niceties.  Each is a whole sentence, and the robot answers with
// the reply named here (see Brain.chat).
chat = function(words, reply)
	for w in words
		add w, {"cat": "chat", "reply": reply}
	end for
end function
chat ["thank you", "thanks", "thanks a lot", "thank you very much", "many thanks"], "thanks"
chat ["hello", "hi", "hi there", "hey", "hello there", "good morning", "good afternoon", "good evening"], "hello"
chat ["good job", "well done", "nice work", "nice job", "great", "good", "nice", "excellent", "good robot"], "praise"
chat ["sorry", "i am sorry", "oops", "my mistake"], "sorry"
// (Careful: these are joined into one word wherever they appear, so "what
// are you" would break "what are you holding".)
chat ["help", "what can you do", "what can i say", "how do i use this"], "help"
chat ["who are you"], "who"
chat ["stop", "wait", "never mind", "cancel"], "stop"
chat ["goodbye", "bye", "good bye", "see you later"], "bye"
chat ["yes", "no", "ok", "okay"], "ok"

// Little words.
for w in ["which", "that", "who"]
	simple w, "relpro"
end for
for w in ["is", "are", "was", "were", "be"]
	simple w, "be"
end for
simple "not", "not"
for w in ["do", "does", "did", "done"]
	simple w, "do"
end for
// "What did you do last?"  "What have you just done?"
simple "last", "last"
simple "just", "just"
for w in ["have", "has", "had"]
	simple w, "have"
end for
simple "doing", "doing"     // "while you were doing it"
verb "start", {"start": true}
verb "begin", {"start": true}
// Time clauses: "before you put the green one on the little cube".
for w in ["before", "after", "while"]
	add w, {"cat": "timeWord", "time": w}
end for
simple "than", "than"
simple "you", "you"
simple "i", "i"
simple "to", "to"
simple "and", "and"
simple "or", "or"
simple "either", "either"    // "either a green cube or a pyramid"
simple "both", "both"        // "both of the red blocks", "both X and Y"
simple "but", "but"
simple "then", "then"
// "Since we began": the whole conversation, which is all the robot remembers.
for w in ["since we began", "since we started", "since the beginning"]
	simple w, "sinceStart"
end for
simple "please", "polite"
for w in ["will", "would", "can", "could"]
	simple w, "modal"
end for
verb "tell", {"tell": true}
verb "ask", {"tell": true}
simple "of", "of"
simple "at least", "atLeast"
simple "?", "punct"

// Contractions, expanded before anything else.
contractions = {
  "don't": "do not", "doesn't": "does not", "didn't": "did not",
  "can't": "can not", "cannot": "can not", "won't": "will not",
  "isn't": "is not", "aren't": "are not", "wasn't": "was not",
  "i'm": "i am", "you're": "you are", "it's": "it is",
  "what's": "what is", "there's": "there is", "that's": "that is",
  "where's": "where is", "i'd": "i would", "haven't": "have not",
  "hasn't": "has not", "hadn't": "had not", "you've": "you have"}

// Irregular verb forms: form -> [stem, form].
irregular = {
  "held": ["hold", "ed"], "told": ["tell", "ed"], "did": ["do", "ed"],
  "sat": ["sit", "ed"], "lay": ["lie", "ed"], "lying": ["lie", "ing"],
  "stood": ["stand", "ed"], "began": ["begin", "ed"], "built": ["build", "ed"],
  "got": ["get", "ed"], "set": ["set", "ed"], "put": ["put", "ed"],
  "took": ["take", "ed"], "taken": ["take", "ed"], "made": ["make", "ed"],
  "stuck": ["stick", "ed"], "saw": ["see", "ed"], "seen": ["see", "ed"]}

//----------------------------------------------------------------------
// Looking words up, with inflections.
//----------------------------------------------------------------------

// Copies of a word's entries, each marked with the form it was found in.
// kinds limits them to certain categories (as when "blocks" is looked up
// as the plural of "block": only nouns can be plural).
entriesFor = function(word, form, kinds=null)
	result = []
	if not words.hasIndex(word) then return result
	for e in words[word]
		if kinds == null or kinds.indexOf(e.cat) != null then
			found = e + {"form": form, "stem": word}
			if not hasEntry(result, found) then result.push found
		end if
	end for
	return result
end function

// The ways a verb ending might have been added to a stem: "holding" could
// be "hold" + "ing"; "sitting" is "sit" + "t" + "ing"; "placed" is "place" + "d".
stemsFor = function(word, ending)
	if word.len <= ending.len + 1 or word[-ending.len:] != ending then return []
	stem = word[:-ending.len]
	result = [stem, stem + "e"]
	if stem.len > 2 and stem[-1] == stem[-2] then result.push stem[:-1]   // sitting
	return result
end function

// Is an equal entry already in the list?  ("uses" is "use" + "s", but also
// "use" + "es"; that shouldn't make two entries.)
hasEntry = function(list, entry)
	for e in list
		if e == entry then return true
	end for
	return false
end function

// Every entry a word could have, including inflected forms: "blocks" is a
// plural noun, "supports" a verb with an -s, "holding" a verb with -ing.
lookup = function(word)
	result = entriesFor(word, "base")
	if irregular.hasIndex(word) then
		result += entriesFor(irregular[word][0], irregular[word][1], ["verb"])
	end if
	// Plural nouns (and pronouns like "ones").
	sp = icl.singularize(word)
	if sp[1] then result += entriesFor(sp[0], "plural", ["noun"])
	// Verb endings.
	for ending in ["s", "es", "ed", "ing"]
		form = ending
		if ending == "es" then form = "s"
		for stem in stemsFor(word, ending)
			for e in entriesFor(stem, form, ["verb"])
				if not hasEntry(result, e) then result.push e
			end for
		end for
	end for
	return result
end function
