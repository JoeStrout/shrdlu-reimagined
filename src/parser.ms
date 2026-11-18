// parser.ms
//
// The English parser: from a sentence to parse trees.  (meaning.ms turns
// the trees into ICL.)  See notes/design-parser.md.
//
// The grammar is a set of ordinary functions, one for each kind of phrase.
// Each takes a position in the list of tokens and returns EVERY way its
// phrase can match there, as a list of results: {tree, next}, where next is
// the position just after the phrase.  So ambiguous sentences simply give
// more than one parse, and the order of the alternatives in each rule is the
// order of preference.
//
// A tree is either a leaf, for one word:
//     {cat, word, entry}        (entry is the word's lexicon entry)
// or a node, for a phrase:
//     {cat, parts}              (parts is a list of trees)
//
// The phrase categories so far:
//     NP    a noun phrase: [determiner] adjectives noun modifiers...
//           (or a pronoun, or a name)
//     DET   a determiner of several words: "at least one (of)"
//     PP    a prepositional phrase: "on the table"
//     CMP   a comparison: "taller than the one you are holding"
//     REL   a relative clause: "which is red", "which supports a pyramid",
//           "(that) you are holding"
//     VP    a verb and what follows it, inside a clause: "supports a
//           pyramid", "sitting on the table"
//     CMD   a command verb and its arguments: "put the block in the box".
//           It remembers which of the verb's frames it matched.
//     S     a whole sentence.  Its "kind" says what sort: "command",
//           "exists", "wh", "attribute", "yes-no", "event" (why, how,
//           when), or "thanks".
//     WH    the part of a wh-question after the wh-word: "are not in the
//           box", "does the box contain", "is the pyramid supported by"

import "lexicon"
import "icl"

//----------------------------------------------------------------------
// Tokens
//----------------------------------------------------------------------

// A token is one word: {text, quoted, entries}.  Multi-word phrases from
// the lexicon ("on top of") become a single token.  A word in quotation
// marks is a new word being introduced ("steeple"), and so is a name the
// robot has been taught.  Both get a "name" entry.

isLetter = function(c)
	return (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-"
end function

// Split text into words: [text, quoted] pairs.  Lowercases everything,
// drops punctuation except "?", and notes which words were in quotes.
splitWords = function(text)
	s = text.lower
	s = s.replace("“", """").replace("”", """").replace("‘", "'").replace("’", "'")
	result = []
	word = ""
	quoting = false
	for i in s.indexes
		c = s[i]
		if i + 1 < s.len then nextChar = s[i+1] else nextChar = ""
		if isLetter(c) then
			word += c
			continue
		end if
		// An apostrophe inside a word ("don't") is part of it; otherwise
		// it's a quotation mark.
		if c == "'" and word != "" and isLetter(nextChar) then
			word += c
			continue
		end if
		if word != "" then result.push [word, quoting]
		word = ""
		if c == """" or c == "'" then quoting = not quoting
		if c == "?" then result.push ["?", false]
	end for
	if word != "" then result.push [word, quoting]
	return result
end function

// Expand contractions: "don't" -> "do", "not".
expandContractions = function(words)
	result = []
	for w in words
		if not w[1] and lexicon.contractions.hasIndex(w[0]) then
			for part in lexicon.contractions[w[0]].split(" ")
				result.push [part, false]
			end for
		else
			result.push w
		end if
	end for
	return result
end function

// Does the multi-word phrase start at position i of the word list?
phraseAt = function(words, i, phrase)
	if i + phrase.len > words.len then return false
	for j in phrase.indexes
		if words[i+j][1] or words[i+j][0] != phrase[j] then return false
	end for
	return true
end function

// Join multi-word phrases into single words, longest first.
joinPhrases = function(words)
	result = []
	i = 0
	while i < words.len
		joined = false
		for phrase in lexicon.phrases
			if phraseAt(words, i, phrase) then
				result.push [phrase.join(" "), false]
				i += phrase.len
				joined = true
				break
			end if
		end for
		if not joined then
			result.push words[i]
			i += 1
		end if
	end while
	return result
end function

// Turn text into tokens.  names is a list of names the robot has been
// taught (like "superblock"), which are treated as names when they appear.
// nouns is a list of nouns it has been taught (like "steeple"), which may
// appear in the singular or the plural.
tokenize = function(text, names=null, nouns=null)
	tokens = []
	for w in joinPhrases(expandContractions(splitWords(text)))
		t = {"text": w[0], "quoted": w[1], "entries": []}
		if t.quoted or (names and names.indexOf(t.text) != null) then
			t.entries.push {"cat": "name", "form": "base", "stem": t.text}
		end if
		if not t.quoted then
			t.entries += lexicon.lookup(t.text)
			if nouns then t.entries += learnedNounEntries(t.text, nouns)
		end if
		tokens.push t
	end for
	return tokens
end function

// Entries for a word that's one of the nouns the robot was taught, or the
// plural of one.
learnedNounEntries = function(word, nouns)
	result = []
	if nouns.indexOf(word) != null then
		result.push {"cat": "noun", "head": word, "form": "base", "stem": word}
	end if
	sp = icl.singularize(word)
	if sp[1] and nouns.indexOf(sp[0]) != null then
		result.push {"cat": "noun", "head": sp[0], "form": "plural", "stem": sp[0]}
	end if
	return result
end function

// The first word nobody knows, or null.
unknownWord = function(tokens)
	for t in tokens
		if not t.entries then return t.text
	end for
	return null
end function

//----------------------------------------------------------------------
// Trees and results
//----------------------------------------------------------------------

leaf = function(token, entry)
	return {"cat": entry.cat, "word": token.text, "entry": entry}
end function

node = function(cat, parts)
	return {"cat": cat, "parts": parts}
end function

result = function(tree, next)
	return {"tree": tree, "next": next}
end function

isLeaf = function(tree)
	return tree.hasIndex("word")
end function

// The parts of a node with the given category (leaves or nodes).
partsOfCat = function(tree, cat)
	result = []
	for p in tree.parts
		if p.cat == cat then result.push p
	end for
	return result
end function

// The words of a tree, as they were typed (well, lowercased): "the block
// in the box".
wordsOf = function(tree)
	if tree == null then return ""
	if isLeaf(tree) then return tree.word
	words = []
	for p in tree.parts
		w = wordsOf(p)
		if w != "" then words.push w
	end for
	return words.join(" ")
end function

// Print a tree on one line: (NP the (ADJ littlest) (N pyramid)).
// Little words print as themselves; content words get a tag.
tags = {"noun": "N", "adj": "ADJ", "pronoun": "PRO", "verb": "V", "name": "NAME", "comparative": "ADJ"}
formatTree = function(tree)
	if tree == null then return "()"
	if isLeaf(tree) then
		if tags.hasIndex(tree.cat) then return "(" + tags[tree.cat] + " " + tree.word + ")"
		return tree.word
	end if
	parts = [tree.cat]
	if tree.hasIndex("kind") then parts.push tree.kind
	for p in tree.parts
		parts.push formatTree(p)
	end for
	return "(" + parts.join(" ") + ")"
end function

//----------------------------------------------------------------------
// The parser
//----------------------------------------------------------------------

Parser = {}

Parser.make = function(tokens)
	p = new Parser
	p.tokens = tokens
	p.memo = {}        // "rule:position" -> results, so no work is done twice
	p.furthest = 0     // the furthest position any rule looked at
	return p
end function

// Every leaf for a word of the given category at this position.
Parser.word = function(pos, cat)
	if pos > self.furthest then self.furthest = pos
	results = []
	if pos >= self.tokens.len then return results
	token = self.tokens[pos]
	for e in token.entries
		if e.cat == cat then results.push result(leaf(token, e), pos + 1)
	end for
	return results
end function

// Like word, but only entries that pass a test on one field, such as verbs
// whose entry has "rel", or nouns in the plural form.
Parser.wordWith = function(pos, cat, field)
	results = []
	for r in self.word(pos, cat)
		if r.tree.entry.hasIndex(field) and r.tree.entry[field] then results.push r
	end for
	return results
end function

// Zero or one "not": a list of results whose trees are lists of leaves.
Parser.optionalNot = function(pos)
	results = [result([], pos)]
	for n in self.word(pos, "not")
		results.push result([n.tree], n.next)
	end for
	return results
end function

// Zero or one word of the category, the same way.
Parser.optionalWord = function(pos, cat)
	results = [result([], pos)]
	for w in self.word(pos, cat)
		results.push result([w.tree], w.next)
	end for
	return results
end function

//----------------------------------------------------------------------
// Noun phrases
//----------------------------------------------------------------------

Parser.nounPhrase = function(pos)
	key = "NP:" + pos
	if self.memo.hasIndex(key) then return self.memo[key]
	results = []
	results += self.plainPronoun(pos)
	for core in self.nounCore(pos)
		results += self.withModifiers(core)
	end for
	results = longestFirst(results)
	self.memo[key] = results
	return results
end function

// The same results, longest first (and otherwise in the same order).
// This is what makes a modifier go with the nearest noun by preference:
// in "taller than the one you are holding", the noun phrase "the one you
// are holding" is tried before "the one", so "you are holding" describes
// "the one" rather than whatever came before.
longestFirst = function(results)
	sorted = []
	for r in results
		i = sorted.len
		while i > 0 and sorted[i-1].next < r.next
			i -= 1
		end while
		sorted.insert i, r
	end for
	return sorted
end function

// Noun phrases joined by "and" or "or": "the red cube and a pyramid",
// "X and Y and Z", "both X and Y", "either X or Y".  (Not "X, Y and Z" yet,
// since the commas are gone by now, and without them two noun phrases in a
// row would be taken as a list far too often.)  These are allowed where a command or a verb wants a
// thing, and nowhere else (yet).  A joined phrase is an NP node whose parts
// are the NPs and the joining words, with a "join" of "and" or "or".
Parser.nounPhrases = function(pos)
	key = "NPS:" + pos
	if self.memo.hasIndex(key) then return self.memo[key]
	results = self.nounPhrase(pos)
	for first in self.conjunct(pos)
		results += self.joinedRest(first.next, [first.tree])
	end for
	results = longestFirst(results)
	self.memo[key] = results
	return results
end function

// The rest of a joined phrase, after the conjuncts so far: "and" or "or"
// and another conjunct, perhaps followed by more of the same word.
Parser.joinedRest = function(pos, items, join=null)
	results = []
	for c in self.word(pos, "and") + self.word(pos, "or")
		if join and c.tree.word != join then continue
		for last in self.conjunct(c.next)
			parts = items + [c.tree, last.tree]
			results.push result(joined(parts, c.tree.word), last.next)
			results += self.joinedRest(last.next, parts, c.tree.word)
		end for
	end for
	return results
end function

// One of the things joined: a noun phrase, or "either X or Y", or "both X
// and Y".
Parser.conjunct = function(pos)
	results = self.nounPhrase(pos)
	pairs = [["either", "or"], ["both", "and"]]
	for pair in pairs
		for w in self.word(pos, pair[0])
			for a in self.nounPhrase(w.next)
				for j in self.word(a.next, pair[1])
					for b in self.nounPhrase(j.next)
						tree = joined([w.tree, a.tree, j.tree, b.tree], pair[1])
						results.push result(tree, b.next)
					end for
				end for
			end for
		end for
	end for
	return results
end function

joined = function(parts, join)
	tree = node("NP", parts)
	tree.join = join
	return tree
end function

// "it", "them", "this", "this one": pronouns that stand alone.
Parser.plainPronoun = function(pos)
	results = []
	for p in self.word(pos, "pronoun")
		if p.tree.entry.det then continue      // "something" etc.; see nounCore
		results.push result(node("NP", [p.tree]), p.next)
		if p.tree.word == "this" or p.tree.word == "that" then
			for one in self.word(p.next, "noun")
				if one.tree.word == "one" then
					results.push result(node("NP", [p.tree, one.tree]), one.next)
				end if
			end for
		end if
	end for
	return results
end function

// The start of a noun phrase, before any modifiers: "a big red block",
// "blocks", "the one", "something", "superblock", "at least one of them".
Parser.nounCore = function(pos)
	results = []
	for p in self.word(pos, "pronoun")
		if p.tree.entry.det then results.push result(node("NP", [p.tree]), p.next)
	end for
	for n in self.word(pos, "name")
		results.push result(node("NP", [n.tree]), n.next)
	end for
	// "Build one": the number one, standing for a noun said earlier.  (It's
	// read as "one one", and "one" as a noun borrows from what came before.)
	for d in self.word(pos, "det")
		if d.tree.entry.det != "number" or d.tree.entry.n != 1 then continue
		for n in self.word(pos, "noun")
			if n.tree.entry.head == "one" then results.push result(node("NP", [d.tree, n.tree]), n.next)
		end for
	end for
	for d in self.determinerPhrase(pos)
		if d.tree and determinerInfo(d.tree).partitive then
			results += self.partitive(d)
			continue
		end if
		adj = self.adjectives(d.next)
		for n in self.word(adj.next, "noun")
			if not agrees(d.tree, n.tree) then continue
			parts = []
			if d.tree then parts.push d.tree
			parts += adj.trees
			parts.push n.tree
			results.push result(node("NP", parts), n.next)
		end for
	end for
	return results
end function

// "at least one of" + "them".
Parser.partitive = function(d)
	results = []
	for p in self.word(d.next, "pronoun")
		if icl.pronouns.hasIndex(p.tree.word) and icl.pronouns[p.tree.word] then
			results.push result(node("NP", [d.tree, p.tree]), p.next)
		end if
	end for
	return results
end function

// The possible determiners here, including none at all (a null tree).
Parser.determinerPhrase = function(pos)
	results = [result(null, pos)]
	results += self.word(pos, "det")
	results += self.both(pos)
	// "at least two", "at least one of"
	for a in self.word(pos, "atLeast")
		for n in self.word(a.next, "det")
			if n.tree.entry.det != "number" then continue
			tree = node("DET", [a.tree, n.tree])
			tree.info = {"det": "at-least", "n": n.tree.entry.n, "number": null, "partitive": false}
			results.push result(tree, n.next)
			for o in self.word(n.next, "of")
				tree = node("DET", [a.tree, n.tree, o.tree])
				tree.info = {"det": "at-least", "n": n.tree.entry.n, "number": null, "partitive": true}
				results.push result(tree, o.next)
			end for
		end for
	end for
	return results
end function

// "both", "both the", "both of the" (+ red blocks), and "both of" (+ them).
// Each means "the", with just two of them.
Parser.both = function(pos)
	results = []
	for b in self.word(pos, "both")
		results.push bothResult([b.tree], b.next)
		for t in self.word(b.next, "det")
			if t.tree.entry.det == "the" then results.push bothResult([b.tree, t.tree], t.next)
		end for
		for o in self.word(b.next, "of")
			results.push bothResult([b.tree, o.tree], o.next, true)
			for t in self.word(o.next, "det")
				if t.tree.entry.det == "the" then results.push bothResult([b.tree, o.tree, t.tree], t.next)
			end for
		end for
	end for
	return results
end function

bothResult = function(parts, next, partitive=false)
	tree = node("DET", parts)
	tree.info = {"det": "both", "n": 2, "number": "pl", "partitive": partitive}
	return result(tree, next)
end function

// What a determiner means: {det, n, number, partitive}.
determinerInfo = function(tree)
	if tree.hasIndex("info") then return tree.info
	return tree.entry + {"partitive": false}
end function

// Does the noun's number fit the determiner?  ("a blocks" doesn't.)  With
// no determiner, only a plural will do: "blocks", but not "block".
agrees = function(detTree, nounTree)
	plural = nounTree.entry.form == "plural"
	if detTree == null then return plural
	number = determinerInfo(detTree).number
	if number == "sg" and plural then return false
	if number == "pl" and not plural then return false
	return true
end function

// All the adjectives in a row from here: {trees, next}.  (Taking them all
// is safe, since no adjective is also a noun.)
Parser.adjectives = function(pos)
	trees = []
	while true
		found = self.word(pos, "adj")
		if not found then break
		trees.push found[0].tree
		pos = found[0].next
	end while
	return {"trees": trees, "next": pos}
end function

// A noun phrase, and the same with each possible run of modifiers after it.
// After a relative clause, another may follow with "and" or "but": "which
// is bigger than every pyramid but is not as wide as the box".
Parser.withModifiers = function(np)
	results = [np]
	more = []
	if np.tree.parts[-1].cat == "REL" then more = self.moreClause(np.next)
	for m in self.modifier(np.next) + more
		longer = node("NP", np.tree.parts + [m.tree])
		results += self.withModifiers(result(longer, m.next))
	end for
	return results
end function

// What can follow a noun to say more about it.
Parser.modifier = function(pos)
	return self.prepPhrase(pos) + self.comparison(pos) + self.relativeClause(pos)
end function

// "on the table"
Parser.prepPhrase = function(pos)
	results = []
	for p in self.word(pos, "prep")
		for np in self.nounPhrase(p.next)
			results.push result(node("PP", [p.tree, np.tree]), np.next)
		end for
	end for
	return results
end function

// "taller than the pyramid", "as wide as the box"
Parser.comparison = function(pos)
	results = []
	for c in self.word(pos, "comparative")
		if c.tree.entry.hasIndex("as") then
			for np in self.nounPhrase(c.next)
				results.push result(node("CMP", [c.tree, np.tree]), np.next)
			end for
			continue
		end if
		for t in self.word(c.next, "than")
			for np in self.nounPhrase(t.next)
				results.push result(node("CMP", [c.tree, t.tree, np.tree]), np.next)
			end for
		end for
	end for
	return results
end function

//----------------------------------------------------------------------
// Relative clauses
//----------------------------------------------------------------------

// "which is red", "that supports a pyramid", "which you are holding", and
// (with no "which") "you are holding".
Parser.relativeClause = function(pos)
	results = []
	for rp in self.word(pos, "relpro")
		for c in self.clauseBody(rp.next)
			results.push result(node("REL", [rp.tree] + c.tree), c.next)
		end for
	end for
	for c in self.youHold(pos) + self.toldYou(pos) + self.iOwn(pos)
		results.push result(node("REL", c.tree), c.next)
	end for
	return results
end function

// "and is red", "but which is not on the table": another relative clause,
// after the first.
Parser.moreClause = function(pos)
	results = []
	for j in self.word(pos, "and") + self.word(pos, "but")
		for rp in self.optionalWord(j.next, "relpro")
			for c in self.clauseBody(rp.next)
				results.push result(node("REL", [j.tree] + rp.tree + c.tree), c.next)
			end for
		end for
	end for
	return results
end function

// What can follow "which": a list of results whose trees are lists of parts.
Parser.clauseBody = function(pos)
	results = []
	// "is [not] red", "is [not] on the table", "is taller than ...",
	// "is sitting on the table"
	for b in self.word(pos, "be")
		for n in self.optionalNot(b.next)
			for p in self.predicate(n.next)
				results.push result([b.tree] + n.tree + [p.tree], p.next)
			end for
		end for
	end for
	// "supports a pyramid", "does not support a pyramid", "sits on the table"
	for d in self.optionalWord(pos, "do")
		for n in self.optionalNot(d.next)
			if n.tree and not d.tree then continue     // "not supports"
			for v in self.verbPhrase(n.next)
				results.push result(d.tree + n.tree + [v.tree], v.next)
			end for
		end for
	end for
	results += self.youHold(pos)
	results += self.toldYou(pos)
	results += self.iOwn(pos)
	return results
end function

// What can follow "is": an adjective, a place, a comparison, or a posture
// with a place ("sitting on the table").
Parser.predicate = function(pos)
	results = []
	results += self.word(pos, "adj")
	results += self.word(pos, "mine")
	results += self.prepPhrase(pos)
	results += self.comparison(pos)
	for v in self.wordWith(pos, "verb", "posture")
		if v.tree.entry.form != "ing" then continue
		for p in self.prepPhrase(v.next)
			results.push result(node("VP", [v.tree, p.tree]), p.next)
		end for
	end for
	return results
end function

// A verb that's a relation, with its object ("supports a pyramid"), or a
// posture verb with a place ("sits on the table").
Parser.verbPhrase = function(pos)
	results = []
	for v in self.wordWith(pos, "verb", "rel")
		for np in self.nounPhrases(v.next)
			results.push result(node("VP", [v.tree, np.tree]), np.next)
		end for
	end for
	for v in self.wordWith(pos, "verb", "posture")
		for p in self.prepPhrase(v.next)
			results.push result(node("VP", [v.tree, p.tree]), p.next)
		end for
	end for
	return results
end function

// "you are holding", "you hold", "you are grasping": a list of parts.
Parser.youHold = function(pos)
	results = []
	for y in self.word(pos, "you")
		for b in self.optionalWord(y.next, "be")
			for v in self.wordWith(b.next, "verb", "held")
				results.push result([y.tree] + b.tree + [v.tree], v.next)
			end for
		end for
	end for
	return results
end function

// "I own", "I don't own": a list of parts.
Parser.iOwn = function(pos)
	results = []
	for i in self.word(pos, "i")
		for d in self.optionalWord(i.next, "do")
			for n in self.optionalNot(d.next)
				if n.tree and not d.tree then continue     // "I not own"
				for v in self.wordWith(n.next, "verb", "own")
					results.push result([i.tree] + d.tree + n.tree + [v.tree], v.next)
				end for
			end for
		end for
	end for
	return results
end function

// "I told you to pick up": a list of parts, ending with a command that's
// missing its object (the thing the clause describes).
Parser.toldYou = function(pos)
	results = []
	for i in self.word(pos, "i")
		for t in self.wordWith(i.next, "verb", "tell")
			if t.tree.entry.form != "ed" then continue
			for y in self.word(t.next, "you")
				for toWord in self.word(y.next, "to")
					for c in self.command(toWord.next, true)
						results.push result([i.tree, t.tree, y.tree, toWord.tree, c.tree], c.next)
					end for
				end for
			end for
		end for
	end for
	return results
end function

//----------------------------------------------------------------------
// Commands
//----------------------------------------------------------------------

particles = ["up", "down", "off", "out"]

// The ways a frame's shape can be said.  A particle right before the
// object may also come after it: "pick up the block", "pick the block up".
shapesFor = function(shape)
	result = [shape]
	if shape.len >= 2 and particles.indexOf(shape[0]) != null and shape[1] == "thing" then
		result.push [shape[1], shape[0]] + shape[2:]
	end if
	return result
end function

// The shape without its first noun phrase: "up thing" -> "up".  (For "the
// one which I told you to pick up", where the object is the one described.)
withoutObject = function(shape)
	i = shape.indexOf("thing")
	if i == null then return null
	return shape[:i] + shape[i+1:]
end function

// A command verb with everything one of its frames calls for:
// "put the block in the box".  With missingObject, the frame's first noun
// phrase is left out: "pick up".  `form` is the verb's form: "base" for a
// command, or "ed" for "had you touched" and "before you put".
Parser.command = function(pos, missingObject=false, form="base")
	results = []
	for v in self.wordWith(pos, "verb", "frames")
		if v.tree.entry.form != form then continue
		for f in v.tree.entry.frames
			if missingObject then
				shapes = [withoutObject(f.shape)]
				if shapes[0] == null then continue
			else
				shapes = shapesFor(f.shape)
			end if
			for shape in shapes
				for r in self.shape(v.next, shape)
					tree = node("CMD", [v.tree] + r.tree)
					tree.frame = f
					results.push result(tree, r.next)
				end for
			end for
		end for
	end for
	return results
end function

// Match the elements of a shape, from the i'th on.  Each result's tree is
// a list of parts.
Parser.shape = function(pos, shape, i=0)
	if i >= shape.len then return [result([], pos)]
	results = []
	for first in self.element(pos, shape[i])
		for rest in self.shape(first.next, shape, i + 1)
			results.push result([first.tree] + rest.tree, rest.next)
		end for
	end for
	return results
end function

// One element of a shape: "thing" is a noun phrase, a particle is that
// particle, and anything else is a preposition meaning that ("on" matches
// "on", "onto", "on top of"...).
Parser.element = function(pos, element)
	if element == "thing" then return self.nounPhrases(pos)
	if element == "name" then return self.word(pos, "name")
	results = []
	if particles.indexOf(element) != null then
		for p in self.word(pos, "particle")
			if p.tree.word == element then results.push p
		end for
	else
		for p in self.word(pos, "prep")
			if p.tree.entry.pred == element then results.push p
		end for
	end if
	return results
end function

// One or more commands joined by "and" (or "and then"): a list of parts.
Parser.commands = function(pos)
	results = []
	for c in self.command(pos)
		results.push result([c.tree], c.next)
		for a in self.word(c.next, "and")
			for t in self.optionalWord(a.next, "then")
				for more in self.commands(t.next)
					results.push result([c.tree, a.tree] + t.tree + more.tree, more.next)
				end for
			end for
		end for
	end for
	return results
end function

// "Will you please", "can you", "please", or nothing: a list of parts.
Parser.politeness = function(pos)
	starts = [result([], pos)]
	for m in self.word(pos, "modal")
		for y in self.word(m.next, "you")
			starts.push result([m.tree, y.tree], y.next)
		end for
	end for
	results = []
	for s in starts
		for p in self.optionalWord(s.next, "polite")
			results.push result(s.tree + p.tree, p.next)
		end for
	end for
	return results
end function

//----------------------------------------------------------------------
// Sentences
//----------------------------------------------------------------------

// A sentence node of the given kind.
sentenceNode = function(kind, parts)
	s = node("S", parts)
	s.kind = kind
	return s
end function

// Every way to read a whole sentence starting here.
Parser.sentence = function(pos)
	return self.commandSentence(pos) + self.statementSentence(pos) +
	  self.thereStatement(pos) + self.defineStatement(pos) + self.existsQuestion(pos) + self.whQuestion(pos) +
	  self.attributeQuestion(pos) + self.yesNoQuestion(pos) + self.canQuestion(pos) +
	  self.didQuestion(pos) + self.eventQuestion(pos) + self.thanks(pos)
end function

// Telling the robot something: "The blue pyramid is mine."  "I own blocks
// which are not red, but I don't own anything which supports a pyramid."
Parser.statementSentence = function(pos)
	results = []
	for c in self.statements(pos)
		results.push result(sentenceNode("statement", c.tree), c.next)
	end for
	return results
end function

// One or more statements, joined by "and" or "but": a list of results
// whose trees are lists of parts.
Parser.statements = function(pos)
	results = []
	for c in self.ownStatement(pos)
		results.push result([c.tree], c.next)
		for j in self.word(c.next, "and") + self.word(c.next, "but")
			for rest in self.statements(j.next)
				results.push result([c.tree, j.tree] + rest.tree, rest.next)
			end for
		end for
	end for
	return results
end function

// "I [don't] own blocks which are not red", "the blue pyramid is [not]
// mine": an OWN node.
Parser.ownStatement = function(pos)
	results = []
	for o in self.iOwn(pos)
		for np in self.nounPhrase(o.next)
			results.push result(node("OWN", o.tree + [np.tree]), np.next)
		end for
	end for
	for np in self.nounPhrase(pos)
		for b in self.word(np.next, "be")
			for n in self.optionalNot(b.next)
				for m in self.word(n.next, "mine")
					results.push result(node("OWN", [np.tree, b.tree] + n.tree + [m.tree]), m.next)
				end for
			end for
		end for
	end for
	return results
end function

// "Thank you."
Parser.thanks = function(pos)
	results = []
	for t in self.word(pos, "thanks")
		results.push result(sentenceNode("thanks", [t.tree]), t.next)
	end for
	return results
end function

// "Will you please pick up a block and put it in the box"
Parser.commandSentence = function(pos)
	results = []
	for p in self.politeness(pos)
		for c in self.commands(p.next)
			results.push result(sentenceNode("command", p.tree + c.tree), c.next)
		end for
	end for
	return results
end function

// "Is there a block behind a pyramid?"  "Are there any red blocks?"
Parser.existsQuestion = function(pos)
	results = []
	for b in self.word(pos, "be")
		for t in self.word(b.next, "there")
			for np in self.nounPhrase(t.next)
				results.push result(sentenceNode("exists", [b.tree, t.tree, np.tree]), np.next)
			end for
		end for
	end for
	return results
end function

// "There were five blocks to the left of the box (then)": a claim, for the
// robot to check.
Parser.thereStatement = function(pos)
	results = []
	for t in self.word(pos, "there")
		for b in self.word(t.next, "be")
			for np in self.nounPhrase(b.next)
				for th in self.optionalWord(np.next, "then")
					results.push result(sentenceNode("claim", [t.tree, b.tree, np.tree] + th.tree), th.next)
				end for
			end for
		end for
	end for
	return results
end function

// Teaching a new word: "A "steeple" is a stack which contains two green
// cubes and a pyramid."  The new word is in quotes, so it comes to us as a
// name.
Parser.defineStatement = function(pos)
	results = []
	for d in self.optionalWord(pos, "det")
		if d.tree and d.tree[0].entry.det != "a" then continue
		for n in self.word(d.next, "name")
			for b in self.word(n.next, "be")
				for np in self.nounPhrase(b.next)
					results.push result(sentenceNode("define", d.tree + [n.tree, b.tree, np.tree]), np.next)
				end for
			end for
		end for
	end for
	return results
end function

// Is this noun phrase a question word, like "which cube", "how many
// blocks", or "what"?  Returns the kind of question it asks, or null.
whKind = function(np)
	first = np.parts[0]
	if first.cat != "det" and first.cat != "pronoun" then return null
	if first.entry.det == "which" then return "which"
	if first.entry.det == "how-many" then return "count"
	return null
end function

// "How many blocks are not in the box?"  "Which cube is sitting on the
// table?"  "What does the box contain?"  "What is the pyramid supported by?"
Parser.whQuestion = function(pos)
	results = []
	for np in self.nounPhrase(pos)
		if whKind(np.tree) == null then continue
		for rest in self.whRest(np.next)
			for t in self.optionalTime(rest.next)
				results.push result(sentenceNode("wh", [np.tree, rest.tree] + t.tree), t.next)
			end for
		end for
	end for
	return results
end function

// What follows the question word: a WH node.
Parser.whRest = function(pos)
	results = []
	// "... are not in the box", "... supports the pyramid", "... are there"
	for c in self.clauseBody(pos)
		results.push result(node("WH", c.tree), c.next)
	end for
	for b in self.word(pos, "be")
		for t in self.word(b.next, "there")
			results.push result(node("WH", [b.tree, t.tree]), t.next)
		end for
	end for
	// "... did you touch", "... did you put in the box": a command with
	// the question's noun phrase as its object.
	for d in self.word(pos, "do")
		for y in self.word(d.next, "you")
			for c in self.command(y.next, true)
				results.push result(node("WH", [d.tree, y.tree, c.tree]), c.next)
			end for
		end for
	end for
	// "... do I own"
	for d in self.word(pos, "do")
		for o in self.iOwn(d.next)
			results.push result(node("WH", [d.tree] + o.tree), o.next)
		end for
	end for
	// "... does the box contain"
	for d in self.word(pos, "do")
		for np in self.nounPhrase(d.next)
			for v in self.wordWith(np.next, "verb", "rel")
				results.push result(node("WH", [d.tree, np.tree, v.tree]), v.next)
			end for
		end for
	end for
	// "... is the pyramid supported by", "... is the pyramid sitting on"
	for b in self.word(pos, "be")
		for np in self.nounPhrase(b.next)
			for v in self.optionalWord(np.next, "verb")
				if v.tree and not v.tree[0].entry.hasIndex("posture") then continue
				for p in self.word(v.next, "prep")
					results.push result(node("WH", [b.tree, np.tree] + v.tree + [p.tree]), p.next)
				end for
			end for
		end for
	end for
	return results
end function

// "What color is the pyramid?"
Parser.attributeQuestion = function(pos)
	results = []
	for w in self.word(pos, "det")
		if w.tree.entry.det != "which" then continue
		for a in self.word(w.next, "attribute")
			for b in self.word(a.next, "be")
				for np in self.nounPhrase(b.next)
					results.push result(sentenceNode("attribute", [w.tree, a.tree, b.tree, np.tree]), np.next)
				end for
			end for
		end for
	end for
	return results
end function

// "Is it supported?"  "Is at least one of them narrower than the box?"
// "Does the box contain a pyramid?"  The claim is a REL node, as in a
// relative clause.
Parser.yesNoQuestion = function(pos)
	results = []
	for b in self.word(pos, "be")
		for np in self.nounPhrase(b.next)
			for n in self.optionalNot(np.next)
				for p in self.predicate(n.next)
					claim = node("REL", n.tree + [p.tree])
					results.push result(sentenceNode("yes-no", [b.tree, np.tree, claim]), p.next)
				end for
			end for
		end for
	end for
	for d in self.word(pos, "do")
		for np in self.nounPhrase(d.next)
			for n in self.optionalNot(np.next)
				for v in self.verbPhrase(n.next)
					claim = node("REL", n.tree + [v.tree])
					results.push result(sentenceNode("yes-no", [d.tree, np.tree, claim]), v.next)
				end for
			end for
		end for
	end for
	// "Do I own the box?"  (The claim comes before the noun phrase here,
	// but the parts are in the same order as above.)
	for d in self.word(pos, "do")
		for o in self.iOwn(d.next)
			for np in self.nounPhrase(o.next)
				results.push result(sentenceNode("yes-no", [d.tree, np.tree, node("REL", o.tree)]), np.next)
			end for
		end for
	end for
	return results
end function

// "Can a pyramid be supported by a block?"  "Can a pyramid support a
// pyramid?"  "Can the table pick up blocks?"  Questions about what could
// be so, or what something could do.  ("Can you pick up...?" is a polite
// command instead; see politeness.)
Parser.canQuestion = function(pos)
	results = []
	for m in self.word(pos, "modal")
		if m.tree.word != "can" and m.tree.word != "could" then continue
		for np in self.nounPhrase(m.next)
			for n in self.optionalNot(np.next)
				for b in self.word(n.next, "be")
					if b.tree.word != "be" then continue
					for p in self.predicate(b.next)
						claim = node("REL", n.tree + [b.tree, p.tree])
						results.push result(sentenceNode("can", [m.tree, np.tree, claim]), p.next)
					end for
				end for
				for v in self.verbPhrase(n.next)
					claim = node("REL", n.tree + [v.tree])
					results.push result(sentenceNode("can", [m.tree, np.tree, claim]), v.next)
				end for
			end for
			for c in self.command(np.next)
				results.push result(sentenceNode("canDo", [m.tree, np.tree, c.tree]), c.next)
			end for
		end for
	end for
	return results
end function

// "Did you pick up the red cube?"  "Had you touched any pyramid before
// you put the green one on the little cube?"  Whether the robot did
// something (at some time).
Parser.didQuestion = function(pos)
	results = []
	for a in self.word(pos, "do") + self.word(pos, "have")
		if a.tree.cat == "do" then form = "base" else form = "ed"
		for y in self.word(a.next, "you")
			for c in self.command(y.next, false, form)
				for t in self.optionalTime(c.next)
					results.push result(sentenceNode("did", [a.tree, y.tree, c.tree] + t.tree), t.next)
				end for
			end for
		end for
	end for
	return results
end function

// Nothing, or a time clause: a list of results whose trees are lists of
// parts (a TIME node, or nothing).
Parser.optionalTime = function(pos)
	results = [result([], pos)]
	// "Since we began" covers everything the robot remembers, so it adds no
	// time constraint (meaning.ms looks only for TIME nodes).
	for s in self.word(pos, "sinceStart")
		results.push result([node("SINCE", [s.tree])], s.next)
	end for
	for w in self.word(pos, "timeWord")
		for y in self.word(w.next, "you")
			for r in self.pastAction(y.next)
				results.push result([node("TIME", [w.tree, y.tree] + r.tree)], r.next)
			end for
		end for
	end for
	return results
end function

// What can follow "before you" or "while you": a list of parts, ending
// with a CMD node (or "doing it", for whatever we were talking about).
//   "put the green one on the little cube"
//   "were stacking up the red cube..."
//   "started to clean it off" (which means the same as "cleaned it off":
//      "before" and "while" go by when an action started anyway)
//   "were doing it"
Parser.pastAction = function(pos)
	results = []
	for c in self.command(pos, false, "ed")
		results.push result([c.tree], c.next)
	end for
	for b in self.word(pos, "be")
		for c in self.command(b.next, false, "ing")
			results.push result([b.tree, c.tree], c.next)
		end for
		for d in self.word(b.next, "doing")
			for p in self.plainPronoun(d.next)
				results.push result([b.tree, d.tree, p.tree], p.next)
			end for
		end for
	end for
	for s in self.wordWith(pos, "verb", "start")
		if s.tree.entry.form != "ed" then continue
		for t in self.word(s.next, "to")
			for c in self.command(t.next)
				results.push result([s.tree, t.tree, c.tree], c.next)
			end for
		end for
	end for
	return results
end function

// "Why did you pick it up?"  "How did you do it?"  "Why?"
Parser.eventQuestion = function(pos)
	results = []
	for w in self.word(pos, "whAdverb")
		results.push result(sentenceNode("event", [w.tree]), w.next)
		for d in self.word(w.next, "do")
			for y in self.word(d.next, "you")
				for c in self.command(y.next)
					results.push result(sentenceNode("event", [w.tree, d.tree, y.tree, c.tree]), c.next)
				end for
				// "do that", "do it": whatever we were just talking about
				for d2 in self.word(y.next, "do")
					for p in self.plainPronoun(d2.next)
						results.push result(sentenceNode("event", [w.tree, d.tree, y.tree, d2.tree, p.tree]), p.next)
					end for
				end for
			end for
		end for
	end for
	return results
end function

// What may end a sentence: "please", a question mark.
Parser.ending = function(pos)
	results = []
	for n in self.optionalWord(pos, "now")
		for p in self.optionalWord(n.next, "polite")
			results += self.optionalWord(p.next, "punct")
		end for
	end for
	return results
end function

//----------------------------------------------------------------------
// Parsing a whole input
//----------------------------------------------------------------------

// The complaint when no parse covers the whole input.
Parser.complaint = function
	if self.furthest >= self.tokens.len then return "That seems to stop in the middle."
	return "I didn't understand the part starting with """ + self.tokens[self.furthest].text + """."
end function

// Parse a sentence.  Returns {trees, error}: every parse that covers the
// whole text, best first, or an error message if there are none.
parse = function(text, names=null, nouns=null)
	tokens = tokenize(text, names, nouns)
	word = unknownWord(tokens)
	if word then return {"trees": [], "error": "Sorry, I don't know the word """ + word + """."}
	p = Parser.make(tokens)
	trees = []
	for r in p.sentence(0)
		for e in p.ending(r.next)
			if e.next == tokens.len then
				trees.push r.tree
				break
			end if
		end for
	end for
	if trees then return {"trees": trees, "error": null}
	return {"trees": [], "error": p.complaint}
end function

// Parse text as a noun phrase (for testing the noun-phrase grammar).
// Returns {trees, error}: every parse that covers the whole text, best
// first, or an error message if there are none.
parseNounPhrase = function(text, names=null, nouns=null)
	tokens = tokenize(text, names, nouns)
	word = unknownWord(tokens)
	if word then return {"trees": [], "error": "Sorry, I don't know the word """ + word + """."}
	p = Parser.make(tokens)
	trees = []
	for r in p.nounPhrase(0)
		if r.next == tokens.len then trees.push r.tree
	end for
	if trees then return {"trees": trees, "error": null}
	return {"trees": [], "error": p.complaint}
end function
