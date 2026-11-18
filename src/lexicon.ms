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
//   particle     "up", "down", "off": the second word of "pick up", "put down"...
//   attribute    {attr}: "color", "size", "shape", for "what color is it?"
//   whAdverb     {q}: "why", "how", "when"
//   modal        "will", "can", "would", "could" (as in "will you please...")
//   polite       "please"
//
// A command verb has a list of frames: the shapes it can take, and the ICL
// command each shape means.  In a shape, "thing" is a noun phrase; "on" or
// "in" is any preposition meaning that ("onto", "on top of", "into"...);
// and "up", "down", "off" are particles, which may also come after the
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
preposition = function(word, pred)
	add word, {"cat": "prep", "pred": pred}
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
for w in ["block", "cube", "pyramid", "cylinder", "box", "table", "thing", "object"]
	noun w
end for
noun "one"

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
	adjective w, w
end for
adjective "clear", "clear"
adjective "supported", "supported"

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

// Prepositions.  Several words can mean the same relation.
for w in ["on", "onto", "on top of", "upon", "supported by"]
	preposition w, "on"
end for
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
for w in ["to the left of", "left of"]
	preposition w, "leftOf"
end for
for w in ["to the right of", "right of"]
	preposition w, "rightOf"
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

// Command verbs, with their frames.
frame = function(shape, icl)
	return {"shape": shape.split(" "), "icl": icl}
end function
command = function(word, frames)
	add word, {"cat": "verb", "frames": frames}
end function
putFrames = [frame("thing on thing", "putOn"), frame("thing in thing", "putIn"), frame("down thing", "putDown")]

command "pick", [frame("up thing", "pickUp")]
command "lift", [frame("up thing", "pickUp"), frame("thing", "pickUp")]
command "grasp", [frame("thing", "pickUp")]
command "grab", [frame("thing", "pickUp")]
command "put", putFrames
command "set", putFrames
command "place", putFrames[:2]
command "move", putFrames[:2]
command "drop", [frame("thing", "putDown")]
command "clear", [frame("off thing", "clearOff")]
command "clean", [frame("off thing", "clearOff")]
command "get rid of", [frame("thing", "getRidOf")]
command "stack", [frame("up thing", "stack"), frame("thing", "stack")]
command "find", [frame("thing", "find")]
command "call", [frame("thing name", "name")]
command "name", [frame("thing name", "name")]

for w in ["up", "down", "off"]
	simple w, "particle"
end for

// Question words.
for w in ["color", "colour", "size", "shape"]
	add w, {"cat": "attribute", "attr": w.replace("colour", "color")}
end for
for w in ["why", "how", "when"]
	add w, {"cat": "whAdverb", "q": w}
end for
pronoun "what", "thing", "which"
simple "there", "there"

// Social niceties.
add "thank you", {"cat": "thanks"}
add "thanks", {"cat": "thanks"}

// Little words.
for w in ["which", "that", "who"]
	simple w, "relpro"
end for
for w in ["is", "are", "was", "were", "be"]
	simple w, "be"
end for
simple "not", "not"
for w in ["do", "does", "did"]
	simple w, "do"
end for
simple "than", "than"
simple "you", "you"
simple "i", "i"
simple "to", "to"
simple "and", "and"
simple "but", "but"
simple "then", "then"
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
  "what's": "what is", "there's": "there is", "that's": "that is"}

// Irregular verb forms: form -> [stem, form].
irregular = {
  "held": ["hold", "ed"], "told": ["tell", "ed"], "did": ["do", "ed"],
  "sat": ["sit", "ed"], "lay": ["lie", "ed"], "lying": ["lie", "ing"],
  "stood": ["stand", "ed"], "began": ["begin", "ed"], "built": ["build", "ed"],
  "got": ["get", "ed"], "set": ["set", "ed"], "put": ["put", "ed"]}

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
