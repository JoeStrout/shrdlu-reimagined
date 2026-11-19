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
//           when), or "chat".
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

// Split text into words: [text, quoted, afterComma, original] lists.
// Lowercases everything, drops punctuation except "?", and notes which
// words were in quotes.  A comma isn't kept as a word, but the word after
// it remembers that it came after one; only lists ("the blue block, the
// red cube and the box") need to know.  Each word also keeps how it was
// typed, for names: "Call it Bob" names it Bob, not bob.
splitWords = function(text)
	typed = text.replace("“", """").replace("”", """").replace("‘", "'").replace("’", "'")
	s = typed.lower
	result = []
	word = ""
	original = ""
	quoting = false
	comma = false
	for i in s.indexes
		c = s[i]
		if i + 1 < s.len then nextChar = s[i+1] else nextChar = ""
		// An apostrophe inside a word ("don't") is part of it; otherwise
		// it's a quotation mark.
		if isLetter(c) or (c == "'" and word != "" and isLetter(nextChar)) then
			word += c
			original += typed[i]
			continue
		end if
		if word != "" then
			result.push [word, quoting, comma, original]
			comma = false
		end if
		word = ""
		original = ""
		if c == """" or c == "'" then quoting = not quoting
		if c == "," then comma = true
		if c == "?" then result.push ["?", false, false, "?"]
	end for
	if word != "" then result.push [word, quoting, comma, original]
	return result
end function

// Expand contractions: "don't" -> "do", "not".  A possessive "'s" that
// isn't a contraction becomes a word of its own: "block's" -> "block", "'s".
expandContractions = function(words)
	result = []
	for w in words
		if not w[1] and lexicon.contractions.hasIndex(w[0]) then
			comma = w[2]
			for part in lexicon.contractions[w[0]].split(" ")
				result.push [part, false, comma, part]
				comma = false
			end for
		else if not w[1] and w[0].len > 2 and w[0][-2:] == "'s" then
			result.push [w[0][:-2], false, w[2], w[3][:-2]]
			result.push ["'s", false, false, "'s"]
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
				result.push [phrase.join(" "), false, words[i][2], phrase.join(" ")]
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

// "On the left" is joined into one word, a side ("the block on the left").
// But in "put it on the left red block", "left" describes the block, and
// the words are "on", "the", "left red block".  So a side followed by an
// adjective or a noun ("red", "block", "one") is split back into its words.
splitSides = function(words)
	result = []
	for i in words.indexes
		w = words[i]
		if not w[1] and i + 1 < words.len and hasCat(lexicon.lookup(w[0]), "side") then
			following = lexicon.lookup(words[i+1][0])
			if hasCat(following, "adj") or hasCat(following, "noun") or words[i+1][0] == "one" then
				comma = w[2]
				for part in w[0].split(" ")
					result.push [part, false, comma, part]
					comma = false
				end for
				continue
			end if
		end if
		result.push w
	end for
	return result
end function

// Does any of these lexicon entries have the category?
hasCat = function(entries, cat)
	for e in entries
		if e.cat == cat then return true
	end for
	return false
end function

// Turn text into tokens.  names is a list of names the robot has been
// taught (like "superblock"), which are treated as names when they appear.
// nouns is a list of nouns it has been taught (like "steeple"), which may
// appear in the singular or the plural.  robotName is the robot's own name
// ("Robot", or what the user renamed it), which marks a word as speaking to
// the robot: "Robot, pick up the red cube."
tokenize = function(text, names=null, nouns=null, robotName=null)
	tokens = []
	// (Names are kept as they were typed, but match in any case.)
	lowerNames = []
	if names then
		for n in names
			lowerNames.push n.lower
		end for
	end if
	for w in splitSides(joinPhrases(expandContractions(splitWords(text))))
		t = {"text": w[0], "quoted": w[1], "afterComma": w[2], "original": w[3], "entries": []}
		if t.quoted or (lowerNames and lowerNames.indexOf(t.text) != null) then
			t.entries.push {"cat": "name", "form": "base", "stem": t.text}
		end if
		if not t.quoted then
			t.entries += lexicon.lookup(t.text)
			if nouns then t.entries += learnedNounEntries(t.text, nouns)
		end if
		if robotName and t.text == robotName.lower then t.entries.push {"cat": "vocative"}
		// A word nobody knows might be a new name, as in "Call it Bert"
		// (no quotation marks).  It's marked "unknown", and only a frame
		// that gives a name will take it; anywhere else, the parse fails,
		// and the robot says it doesn't know the word.
		t.unknown = not t.entries
		if t.unknown then t.entries.push {"cat": "name", "form": "base", "stem": t.text, "unknown": true}
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
		if t.unknown then return t.text
	end for
	return null
end function

//----------------------------------------------------------------------
// Trees and results
//----------------------------------------------------------------------

leaf = function(token, entry)
	result = {"cat": entry.cat, "word": token.text, "entry": entry}
	if token.hasIndex("original") then result.original = token.original
	return result
end function

// A name as the user typed it: "Bob".
typedWord = function(tree)
	if tree.hasIndex("original") then return tree.original
	return tree.word
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
	p.expectingName = false   // did the robot just ask the user's name?  (see smallTalk)
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
	// "The top of the red cube" means the red cube.
	for t in self.word(pos, "topOf")
		results += self.nounPhrase(t.next)
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
// "X and Y and Z", "X, Y and Z", "both X and Y", "either X or Y".  These
// are allowed where a command or a verb wants a thing, and nowhere else
// (yet).  A joined phrase is an NP node whose parts are the NPs and the
// joining words, with a "join" of "and" or "or".
Parser.nounPhrases = function(pos)
	key = "NPS:" + pos
	if self.memo.hasIndex(key) then return self.memo[key]
	results = self.nounPhrase(pos)
	for first in self.conjunct(pos)
		results += self.listRest(first.next, [first.tree])
	end for
	results = longestFirst(results)
	self.memo[key] = results
	return results
end function

// The rest of a list, after the items so far: more items after commas, then
// "and" or "or" and the last item.  ("X, Y" with no "and" isn't a list.
// Without the commas, two noun phrases in a row would be taken as a list
// far too often: "Pick up the block the box".)
Parser.listRest = function(pos, items)
	results = self.joinedRest(pos, items)
	if pos < self.tokens.len and self.tokens[pos].afterComma then
		for c in self.conjunct(pos)
			results += self.listRest(c.next, items + [c.tree])
		end for
	end if
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
		if not p.tree.entry.det then continue
		results.push result(node("NP", [p.tree]), p.next)
		// "something green", "anything red": adjectives after the pronoun
		adj = self.adjectives(p.next)
		if adj.trees then results.push result(node("NP", [p.tree] + adj.trees), adj.next)
	end for
	for n in self.word(pos, "name")
		if n.tree.entry.hasIndex("unknown") then continue     // (see tokenize)
		results.push result(node("NP", [n.tree]), n.next)
	end for
	// "Put mine in the box": the ones I own (see Meaning.descriptionStart)
	for m in self.word(pos, "mine")
		results.push result(node("NP", [m.tree]), m.next)
	end for
	// "Build one": the number one, standing for a noun said earlier.  (It's
	// read as "one one", and "one" as a noun borrows from what came before.)
	for d in self.word(pos, "det")
		if d.tree.entry.det != "number" or d.tree.entry.n != 1 then continue
		for n in self.word(pos, "noun")
			if n.tree.entry.head == "one" then results.push result(node("NP", [d.tree, n.tree]), n.next)
		end for
	end for
	// "How many are there?": how many of the things we were just talking
	// about.  It's read as "how many ones", and "ones" borrows its noun from
	// what came before, as "one" does.
	for d in self.word(pos, "det")
		if d.tree.entry.det != "how-many" then continue
		ones = {"cat": "noun", "word": "ones", "entry": {"cat": "noun", "head": "one", "form": "plural", "stem": "one"}}
		results.push result(node("NP", [d.tree, ones]), d.next)
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

// "at least one of" + "them", or "one of" + "the green cubes": some of a
// group we already know about.
Parser.partitive = function(d)
	results = []
	for p in self.word(d.next, "pronoun")
		if icl.pronouns.hasIndex(p.tree.word) and icl.pronouns[p.tree.word] then
			results.push result(node("NP", [d.tree, p.tree]), p.next)
		end if
	end for
	// ("Both of the red blocks" is just "both red blocks": see Parser.both.)
	if determinerInfo(d.tree).det == "both" then return results
	for np in self.nounPhrase(d.next)
		first = np.tree.parts[0]
		if first.cat != "det" or first.entry.det != "the" then continue
		nouns = partsOfCat(np.tree, "noun")
		if not nouns or nouns[0].entry.form != "plural" then continue
		results.push result(node("NP", [d.tree, np.tree]), np.next)
	end for
	return results
end function

// The possible determiners here, including none at all (a null tree).
Parser.determinerPhrase = function(pos)
	results = [result(null, pos)]
	results += self.word(pos, "det")
	results += self.both(pos)
	results += self.allThe(pos)
	// "any of", "one of", "which of", "none of"... (+ "them" or "the cubes")
	for d in self.word(pos, "det")
		if ["the", "a", "both"].indexOf(d.tree.entry.det) != null and d.tree.word != "one" then continue
		for o in self.word(d.next, "of")
			tree = node("DET", [d.tree, o.tree])
			tree.info = d.tree.entry + {"partitive": true, "number": null}
			results.push result(tree, o.next)
		end for
	end for
	// "the three red objects": the, with a count
	for t in self.word(pos, "det")
		if t.tree.word != "the" then continue
		for n in self.word(t.next, "det")
			if n.tree.entry.det != "number" or n.tree.entry.n < 2 then continue
			tree = node("DET", [t.tree, n.tree])
			tree.info = {"det": "the", "n": n.tree.entry.n, "number": "pl", "partitive": false}
			results.push result(tree, n.next)
		end for
	end for
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

// "all the" and "all of the" (+ cubes) mean "the", with a plural: "Where
// are all the cubes?"  ("All cubes" is "every cube": see the lexicon.)
Parser.allThe = function(pos)
	results = []
	for a in self.word(pos, "det")
		if a.tree.word != "all" then continue
		for o in self.optionalWord(a.next, "of")
			for t in self.word(o.next, "det")
				if t.tree.entry.det != "the" or t.tree.word != "the" then continue
				tree = node("DET", [a.tree] + o.tree + [t.tree])
				tree.info = {"det": "the", "n": null, "number": "pl", "partitive": false}
				results.push result(tree, t.next)
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
// is safe, since no adjective is also a noun.)  An ordinal goes with the
// superlative after it: "the second tallest block" has an ADJ node for
// "second tallest".
Parser.adjectives = function(pos)
	trees = []
	while true
		ranked = null
		for o in self.word(pos, "ordinal")
			for a in self.wordWith(o.next, "adj", "superlative")
				ranked = result(node("ADJ", [o.tree, a.tree]), a.next)
			end for
		end for
		if ranked then
			found = [ranked]
		else
			found = self.word(pos, "adj")
		end if
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
	return self.prepPhrase(pos) + self.comparison(pos) + self.relativeClause(pos) + self.ingClause(pos) +
	  self.coloredPhrase(pos) + self.word(pos, "side")
end function

// "(blocks) colored red", "colored red or blue": a COLORED node with the
// colors (and the "or"s).
Parser.coloredPhrase = function(pos)
	results = []
	for c in self.word(pos, "colored")
		parts = [c.tree]
		next = c.next
		while true
			found = null
			for a in self.word(next, "adj")
				if a.tree.entry.pred == "color" then found = a
			end for
			if found == null then break
			parts.push found.tree
			results.push result(node("COLORED", parts[:]), found.next)
			ors = self.word(found.next, "or")
			if not ors then break
			parts.push ors[0].tree
			next = ors[0].next
		end while
	end for
	return results
end function

// "(the one) supporting a pyramid", "(the block) sitting on the table": a
// relative clause without "which is".
Parser.ingClause = function(pos)
	results = []
	for v in self.verbPhrase(pos)
		if v.tree.parts[0].entry.form == "ing" then results.push result(node("REL", [v.tree]), v.next)
	end for
	return results
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
		for p in self.predicates(b.next)
			results.push result([b.tree] + p.tree, p.next)
		end for
	end for
	// "you are holding", "are you holding" (in "what are you holding")
	for b in self.word(pos, "be")
		for y in self.word(b.next, "you")
			for v in self.wordWith(y.next, "verb", "held")
				results.push result([b.tree, y.tree, v.tree], v.next)
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

// What can follow "is", with or without "not", and perhaps several joined
// by "and" or "but": "red", "not in the box", "red and on the table",
// "green but not on the table".  A list of results whose trees are lists of
// parts: [not] predicate, or a PREDS node for several.
Parser.predicates = function(pos)
	results = []
	for n in self.optionalNot(pos)
		for p in self.predicate(n.next)
			results.push result(n.tree + [p.tree], p.next)
			for more in self.morePredicates(p.next, n.tree + [p.tree])
				results.push result([more.tree], more.next)
			end for
		end for
	end for
	return results
end function

// "and on the table", "but not in the box", after the predicates so far
// (a list of parts): PREDS nodes.
Parser.morePredicates = function(pos, items)
	results = []
	for j in self.word(pos, "and") + self.word(pos, "but")
		for n in self.optionalNot(j.next)
			for p in self.predicate(n.next)
				parts = items + [j.tree] + n.tree + [p.tree]
				results.push result(node("PREDS", parts), p.next)
				results += self.morePredicates(p.next, parts)
			end for
		end for
	end for
	return results
end function

// What can follow "is": an adjective, a place (or a side: "on the left"), a comparison, a posture
// with a place ("sitting on the table"), or "the" and a superlative ("the
// biggest").
Parser.predicate = function(pos)
	results = []
	results += self.word(pos, "adj")
	results += self.coloredPhrase(pos)     // "(is) colored green"
	for t in self.word(pos, "det")
		if t.tree.entry.det != "the" then continue
		for a in self.wordWith(t.next, "adj", "superlative")
			results.push result(node("ADJP", [t.tree, a.tree]), a.next)
		end for
	end for
	// "(is) the tallest block", "(is) a cube", "(are) crates": what it is.
	for np in self.nounPhrase(pos)
		first = np.tree.parts[0]
		if first.cat == "det" and (first.entry.det == "the" or first.entry.det == "a") then
			results.push np
		else if first.cat == "noun" and first.entry.form == "plural" then
			results.push np
		end if
	end for
	results += self.word(pos, "mine")
	results += self.prepPhrase(pos)
	results += self.word(pos, "side")     // "(is) on the left"
	results += self.comparison(pos)
	for v in self.wordWith(pos, "verb", "posture")
		if v.tree.entry.form != "ing" then continue
		for p in self.prepPhrase(v.next)
			results.push result(node("VP", [v.tree, p.tree]), p.next)
		end for
	end for
	// "(is) supporting a pyramid", "(is) touching the box"
	for v in self.wordWith(pos, "verb", "rel")
		if v.tree.entry.form != "ing" then continue
		for np in self.nounPhrases(v.next)
			results.push result(node("VP", [v.tree, np.tree]), np.next)
		end for
	end for
	return results
end function

// A verb that's a relation, with its object ("supports a pyramid"), or a
// posture verb with a place ("sits on the table"), or "have" something "on
// it" (or "in it"), which is to support (or contain) it.
Parser.verbPhrase = function(pos)
	results = []
	for h in self.word(pos, "have")
		if h.tree.word == "had" then continue
		for np in self.nounPhrase(h.next)
			for p in self.word(np.next, "prep")
				if p.tree.entry.pred != "on" and p.tree.entry.pred != "in" then continue
				for it in self.plainPronoun(p.next)
					if it.tree.parts[0].word != "it" then continue
					results.push result(node("VP", [h.tree, np.tree, p.tree, it.tree]), it.next)
				end for
			end for
		end for
	end for
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

// "I own", "I don't own", "I like", "I also hate": a list of parts.  (See
// icl.attitudes.)
//
// The subject may be "you" (the robot) too: "you own the blue block".
// With outerDo, a "do" came before the subject ("What do I not own?"), so
// "not" may follow it directly.
Parser.iOwn = function(pos, outerDo=false)
	results = []
	for i in self.word(pos, "i") + self.word(pos, "you")
		for a in self.optionalWord(i.next, "lead")     // "I also own..."
			if a.tree and a.tree[0].word != "also" then continue
			for d in self.optionalWord(a.next, "do")
				for n in self.optionalNot(d.next)
					if n.tree and not d.tree and not outerDo then continue     // "I not own"
					for v in self.wordWith(n.next, "verb", "attitude")
						results.push result([i.tree] + a.tree + d.tree + n.tree + [v.tree], v.next)
					end for
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

particles = ["up", "down", "off", "out", "back"]

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
	// "on top" means "on top of it": "put the blue block on top".
	if shape[i] == "on" and i + 1 < shape.len and shape[i+1] == "thing" then
		for t in self.word(pos, "onTop")
			it = node("NP", [leaf({"text": "it"}, {"cat": "pronoun", "head": "it", "det": null})])
			for rest in self.shape(t.next, shape, i + 2)
				results.push result([t.tree, it] + rest.tree, rest.next)
			end for
		end for
	end if
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
		// Or a word of that category: "to", "from", "out of", "me".
		results += self.word(pos, element)
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
		// "Put it in the box, then pick up the red cube"
		for t in self.word(c.next, "then")
			for more in self.commands(t.next)
				results.push result([c.tree, t.tree] + more.tree, more.next)
			end for
		end for
	end for
	return results
end function

// What may come before a command without changing what it asks for: a
// list of parts.  In order, each of these is optional:
//   a word like "now", "first", "then"
//   "will you", "can you", "could you"...
//   "please"
//   "I want you to", "try to", "go"...
// So "Now could you please try to find a red pyramid" is a command to find
// a red pyramid.
Parser.politeness = function(pos)
	results = []
	for lead in self.optionalWord(pos, "lead")
		starts = [lead]
		for m in self.word(lead.next, "modal")
			for y in self.word(m.next, "you")
				starts.push result(lead.tree + [m.tree, y.tree], y.next)
			end for
		end for
		for s in starts
			for p in self.optionalWord(s.next, "polite")
				for r in self.optionalWord(p.next, "request")
					results.push result(s.tree + p.tree + r.tree, r.next)
				end for
			end for
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
	return self.smallTalk(pos) + self.commandSentence(pos) + self.statementSentence(pos) +
	  self.thereStatement(pos) + self.defineStatement(pos) + self.existsQuestion(pos) + self.seeQuestion(pos) + self.handQuestion(pos) +
	  self.whQuestion(pos) + self.identifyQuestion(pos) + self.choiceQuestion(pos) + self.whereQuestion(pos) +
	  self.attributeQuestion(pos) + self.yesNoQuestion(pos) + self.canQuestion(pos) +
	  self.didQuestion(pos) + self.eventQuestion(pos) + self.whatDoneQuestion(pos) + self.chat(pos) + self.tellMe(pos) +
	  self.showMe(pos) + self.methodQuestion(pos) + self.nameStatement(pos) + self.exampleStatement(pos) +
	  self.whatAbout(pos) + self.calledByName(pos)
end function

// "Tell me what you are holding."  "Can you tell me where the red cube is?"
// A question asked as a command; it means the question.  (The question
// here has the order of a statement: "what you are holding", "where the
// red cube is".)
Parser.tellMe = function(pos)
	results = []
	for p in self.politeness(pos)
		for t in self.wordWith(p.next, "verb", "tell")
			if t.tree.entry.form != "base" then continue
			for m in self.word(t.next, "me")
				for q in self.whQuestion(m.next) + self.embeddedWhere(m.next)
					results.push q
				end for
			end for
		end for
	end for
	return results
end function

// "Show me the red cube", "Please show me where the box is": where is it?
Parser.showMe = function(pos)
	results = []
	for p in self.politeness(pos)
		for s in self.word(p.next, "show")
			for m in self.word(s.next, "me")
				for np in self.nounPhrase(m.next)
					results.push result(sentenceNode("where", [s.tree, m.tree, np.tree]), np.next)
				end for
				results += self.embeddedWhere(m.next)
			end for
		end for
	end for
	return results
end function

// "where the red cube is"
Parser.embeddedWhere = function(pos)
	results = []
	for w in self.word(pos, "where")
		for np in self.nounPhrase(w.next)
			for b in self.word(np.next, "be")
				results.push result(sentenceNode("where", [w.tree, np.tree, b.tree]), b.next)
			end for
		end for
	end for
	return results
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
		for np in self.nounPhrases(o.next)     // ("I own the red cube and the box")
			results.push result(node("OWN", o.tree + [np.tree]), np.next)
		end for
	end for
	for np in self.nounPhrase(pos)
		if whKind(np.tree) then continue     // ("Which cubes are mine?" is a question.)
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

// "That cube's name is Bob."  "Its name is Bob."  "The blue block is called
// Bob."  Giving something a name, as "Call it Bob" does.  (The name may be a
// word nobody knows: see tokenize.)
Parser.nameStatement = function(pos)
	results = []
	for np in self.nounPhrase(pos)
		for s in self.word(np.next, "poss")
			for n in self.word(s.next, "nameNoun")
				for b in self.word(n.next, "be")
					for name in self.word(b.next, "name")
						results.push result(sentenceNode("nameIt", [np.tree, s.tree, n.tree, b.tree, name.tree]), name.next)
					end for
				end for
			end for
		end for
		for b in self.word(np.next, "be")
			for v in self.word(b.next, "verb")
				if v.tree.entry.form != "ed" or ["call", "name"].indexOf(v.tree.entry.stem) == null then continue
				for name in self.word(v.next, "name")
					results.push result(sentenceNode("nameIt", [np.tree, b.tree, v.tree, name.tree]), name.next)
				end for
			end for
		end for
	end for
	return results
end function

// "That is a steeple."  "This is called a steeple."  Teaching a word from
// an example, as "Call that a steeple" does.  The word is a name (in
// quotes, or a word nobody knows yet).
Parser.exampleStatement = function(pos)
	results = []
	for np in self.nounPhrase(pos)
		for b in self.word(np.next, "be")
			for v in self.optionalWord(b.next, "verb")
				if v.tree and (v.tree[0].entry.form != "ed" or ["call", "name"].indexOf(v.tree[0].entry.stem) == null) then continue
				for d in self.word(v.next, "det")
					if d.tree.entry.det != "a" then continue
					for name in self.word(d.next, "name")
						results.push result(sentenceNode("defineLike", [np.tree, b.tree] + v.tree + [d.tree, name.tree]), name.next)
					end for
				end for
			end for
		end for
	end for
	return results
end function

// "What about the table?"  "How about on the table?"  "And the green
// pyramid?"  The phrase stands in for part of what was said last; the brain
// works out which part (see Brain.whatAbout).
Parser.whatAbout = function(pos)
	results = []
	for w in self.word(pos, "whatAbout") + self.word(pos, "and")
		for x in self.nounPhrases(w.next) + self.prepPhrase(w.next)
			results.push result(sentenceNode("whatAbout", [w.tree, x.tree]), x.next)
		end for
	end for
	return results
end function

// "Thank you."  "Hello."  "Help."  Social niceties, each a whole sentence.
Parser.chat = function(pos)
	results = []
	for t in self.word(pos, "chat")
		results.push result(sentenceNode("chat", [t.tree]), t.next)
	end for
	return results
end function

// Small talk: "My name is Joe."  "What's your name?"  "How do you work?"
// Each is a whole sentence in one of the fixed forms listed in the lexicon
// (lexicon.smallTalk), perhaps after a greeting ("Hi, I'm Joe"), a lead word
// ("Actually, call me Joseph", "From now on, your name is Bob") or "please".
// The sentence node keeps the pattern's ICL and the name, if it has one.
//
// Some patterns are only answers to the robot's "What is it?" about the
// user's name ("Joe."); they're tried only when expectingName is set.
Parser.smallTalk = function(pos)
	results = []
	for g in self.optionalWord(pos, "chat")
		if g.tree and g.tree[0].entry.reply != "hello" then continue
		// ("Hi Bob, my name is Al": after a greeting, the robot's name.)
		for v in self.optionalWord(g.next, "vocative")
		if v.tree and not g.tree then continue     // (a name first is in parse)
		for lead in self.optionalWord(v.next, "lead")
			for p in self.optionalWord(lead.next, "polite")
				start = p.next
				for pattern in lexicon.smallTalk
					if pattern.answer and not self.expectingName then continue
					for m in self.matchTalk(start, pattern.words)
						parts = g.tree + v.tree + lead.tree + p.tree
						for i in range(start, m.next - 1)
							parts.push leaf(self.tokens[i], {"cat": "talk"})
						end for
						s = sentenceNode("smallTalk", parts)
						s.icl = pattern.icl
						s.name = m.name
						results.push result(s, m.next)
					end for
				end for
			end for
		end for
		end for
	end for
	return results
end function

// Every way the words of a small-talk pattern match the tokens starting at
// pos: a list of {next, name}, where name is the words a <name> slot took,
// as they were typed.  A token may be several words ("from now on"), which
// must all match.  A slot takes one word or more, fewest first, so "Your
// name is Bob now" leaves "now" for the end of the sentence.
Parser.matchTalk = function(pos, words)
	if not words then return [{"next": pos, "name": null}]
	w = words[0]
	if w == "<name>" or w == "<Name>" then
		results = []
		taken = []
		for t in range(pos, pos + 2)
			if t >= self.tokens.len then break
			token = self.tokens[t]
			if token.text == "?" then break
			if w == "<Name>" and not icl.isUpper(token.original[0]) then break
			taken.push token.original
			for r in self.matchTalk(t + 1, words[1:])
				results.push {"next": r.next, "name": taken.join(" ")}
			end for
		end for
		return results
	end if
	if pos >= self.tokens.len then return []
	tokenWords = self.tokens[pos].text.split(" ")
	if self.tokens[pos].quoted or words[:tokenWords.len] != tokenWords then return []
	return self.matchTalk(pos + 1, words[tokenWords.len:])
end function

// "Robot?"  "Bob."  Just the robot's name: are you there?
Parser.calledByName = function(pos)
	results = []
	for v in self.word(pos, "vocative")
		s = sentenceNode("smallTalk", [v.tree])
		s.icl = "Chat here"
		s.name = null
		results.push result(s, v.next)
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

// "Is your hand empty?"  "Is your hand full?"
Parser.handQuestion = function(pos)
	results = []
	for b in self.word(pos, "be")
		for h in self.word(b.next, "yourHand")
			for a in self.word(h.next, "adj")
				if a.tree.entry.pred != "empty" and a.tree.entry.pred != "full" then continue
				results.push result(sentenceNode("hand", [b.tree, h.tree, a.tree]), a.next)
			end for
		end for
	end for
	return results
end function

// "Do you see a red pyramid?"  "Can you see the box?"  These ask whether
// there is one, as "Is there...?" does.  (The robot sees everything.)
Parser.seeQuestion = function(pos)
	results = []
	// ("Have you ever seen a blue pyramid?" too: it has seen whatever is
	// here now.)
	for d in self.word(pos, "do") + self.word(pos, "modal") + self.word(pos, "have")
		for y in self.word(d.next, "you")
			for e in self.optionalWord(y.next, "ever")
				for v in self.wordWith(e.next, "verb", "see")
					for np in self.nounPhrase(v.next)
						results.push result(sentenceNode("exists", [d.tree, y.tree] + e.tree + [v.tree, np.tree]), np.next)
					end for
				end for
			end for
		end for
	end for
	return results
end function

// "What is it?"  "Which is the tallest block?"  "What are the things in the
// box?"  These ask the robot to say what the noun phrase means.
Parser.identifyQuestion = function(pos)
	results = []
	for w in self.word(pos, "pronoun")
		if w.tree.entry.det != "which" then continue
		for b in self.word(w.next, "be")
			for np in self.nounPhrase(b.next)
				if whKind(np.tree) then continue
				results.push result(sentenceNode("identify", [w.tree, b.tree, np.tree]), np.next)
			end for
		end for
	end for
	return results
end function

// "Which is taller, the red cube or the blue block?"  The answer is
// whichever of them is the tallest.
Parser.choiceQuestion = function(pos)
	results = []
	for w in self.word(pos, "pronoun")
		if w.tree.entry.det != "which" then continue
		for b in self.word(w.next, "be")
			for c in self.word(b.next, "comparative")
				if c.tree.entry.hasIndex("as") then continue
				for np in self.nounPhrases(c.next)
					if not np.tree.hasIndex("join") then continue
					results.push result(sentenceNode("choice", [w.tree, b.tree, c.tree, np.tree]), np.next)
				end for
			end for
		end for
	end for
	return results
end function

// "Where is the red cube?"  "Where are all the cubes?"  "Where did the red
// cube go?"
Parser.whereQuestion = function(pos)
	results = []
	for w in self.word(pos, "where")
		for b in self.word(w.next, "be")
			for np in self.nounPhrase(b.next)
				results.push result(sentenceNode("where", [w.tree, b.tree, np.tree]), np.next)
			end for
		end for
		for d in self.word(w.next, "do")
			for np in self.nounPhrase(d.next)
				for g in self.word(np.next, "go")
					results.push result(sentenceNode("where", [w.tree, d.tree, np.tree, g.tree]), g.next)
				end for
			end for
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
	results = self.defineAs(pos)
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

// "Define a "steeple" as a pyramid on top of a block."  "Let's define..."
// The same as "A "steeple" is...", in the order of a command.
Parser.defineAs = function(pos)
	results = []
	for p in self.politeness(pos)
		for v in self.word(p.next, "define")
			for d in self.optionalWord(v.next, "det")
				if d.tree and d.tree[0].entry.det != "a" then continue
				for n in self.word(d.next, "name")
					for a in self.word(n.next, "as")
						for np in self.nounPhrase(a.next)
							parts = p.tree + [v.tree] + d.tree + [n.tree, a.tree, np.tree]
							results.push result(sentenceNode("define", parts), np.next)
						end for
					end for
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
	// "which of the pyramids", "how many of them"
	if first.cat == "DET" and first.hasIndex("info") then
		if first.info.det == "which" then return "which"
		if first.info.det == "how-many" then return "count"
		return null
	end if
	if first.cat != "det" and first.cat != "pronoun" then return null
	if first.entry.det == "which" then return "which"
	if first.entry.det == "how-many" then return "count"
	return null
end function

// "How many blocks are not in the box?"  "Which cube is sitting on the
// table?"  "What does the box contain?"  "What is the pyramid supported by?"
//
// A relative clause at the end may be about the question word, though
// it comes after the rest: "What is in the box that I don't own?" asks for
// the things in the box that I don't own.  It could also be about the box,
// but "the box" already says which box, so that's not likely.  We try the
// question word first, and the brain falls back on the other reading if
// that one makes no sense.  (In "What is on the block that is red?", with
// several blocks, "the block" alone makes no sense, so the clause is about
// the block.)
Parser.whQuestion = function(pos)
	moved = []     // the readings with a clause at the end, about the question word
	results = []
	for np in self.nounPhrase(pos)
		if whKind(np.tree) == null then continue
		for rest in self.whRest(np.next)
			// ("What is the tallest thing?" is identifyQuestion's.  But "Which
			// pyramids are bricks?" is ours.)
			if rest.tree.parts.len == 2 and rest.tree.parts[0].cat == "be" and rest.tree.parts[1].cat == "NP" and
			  rest.tree.parts[1].parts[0].cat == "det" then continue
			for t in self.optionalTime(rest.next)
				results.push result(sentenceNode("wh", [np.tree, rest.tree] + t.tree), t.next)
			end for
			for rel in self.relativeClause(rest.next)
				moved.push result(sentenceNode("wh", [np.tree, rest.tree, rel.tree]), rel.next)
			end for
		end for
	end for
	return moved + results
end function

// Nothing, or "have to": a list of parts.
Parser.haveTo = function(pos)
	results = [result([], pos)]
	for h in self.word(pos, "have")
		if h.tree.word != "have" then continue
		for t in self.word(h.next, "to")
			results.push result([h.tree, t.tree], t.next)
		end for
	end for
	return results
end function

// Nothing, or what something was done for: "to do that", "to put the red
// cube in the box".  A list of parts: a PURPOSE node, or nothing.
Parser.optionalPurpose = function(pos)
	results = [result([], pos)]
	for t in self.word(pos, "to")
		for c in self.command(t.next)
			results.push result([node("PURPOSE", [t.tree, c.tree])], c.next)
		end for
		for d in self.word(t.next, "do")
			if d.tree.word != "do" then continue
			for p in self.plainPronoun(d.next)
				results.push result([node("PURPOSE", [t.tree, d.tree, p.tree])], p.next)
			end for
		end for
	end for
	return results
end function

// "What did you do last?"  "What did you just do?"  "What have you done?"
// Asks what the robot did most recently (that the user asked for).
Parser.whatDoneQuestion = function(pos)
	results = []
	for w in self.word(pos, "pronoun")
		if w.tree.entry.det != "which" or w.tree.word != "what" then continue
		for a in self.word(w.next, "do") + self.word(w.next, "have")
			for y in self.word(a.next, "you")
				for j in self.optionalWord(y.next, "just")
					for d in self.word(j.next, "do")
						if d.tree.word != "do" and d.tree.word != "done" then continue
						for l in self.optionalWord(d.next, "last")
							parts = [w.tree, a.tree, y.tree] + j.tree + [d.tree] + l.tree
							results.push result(sentenceNode("whatDone", parts), l.next)
						end for
					end for
				end for
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
	// the question's noun phrase as its object.  "... did you have to move
	// to do that": the same, done for the sake of something else.
	for d in self.word(pos, "do")
		for y in self.word(d.next, "you")
			for h in self.haveTo(y.next)
				for c in self.command(h.next, true)
					for p in self.optionalPurpose(c.next)
						results.push result(node("WH", [d.tree, y.tree] + h.tree + [c.tree] + p.tree), p.next)
					end for
				end for
			end for
		end for
	end for
	// "... can you pick up": what the robot could do
	for m in self.word(pos, "modal")
		if m.tree.word != "can" and m.tree.word != "could" then continue
		for y in self.word(m.next, "you")
			for c in self.command(y.next, true)
				results.push result(node("WH", [m.tree, y.tree, c.tree]), c.next)
			end for
		end for
	end for
	// "... have you picked up", "... have you ever moved"
	for h in self.word(pos, "have")
		for y in self.word(h.next, "you")
			for e in self.optionalWord(y.next, "ever")
				for c in self.command(e.next, true, "ed")
					results.push result(node("WH", [h.tree, y.tree] + e.tree + [c.tree]), c.next)
				end for
			end for
		end for
	end for
	// "... do I own", "... don't I own", "... do I not own"
	for d in self.word(pos, "do")
		for n in self.optionalNot(d.next)
			for o in self.iOwn(n.next, true)
				results.push result(node("WH", [d.tree] + n.tree + o.tree), o.next)
			end for
		end for
	end for
	// "... does the box contain", "... is the large red block supporting"
	for d in self.word(pos, "do") + self.word(pos, "be")
		for np in self.nounPhrase(d.next)
			for v in self.wordWith(np.next, "verb", "rel")
				if d.tree.cat == "be" and v.tree.entry.form != "ing" then continue
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

// "What color is the pyramid?"  "What is that block's color?"  "What is the
// color of the box?"  "How big is it?"  The noun phrase is always the last
// part.
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
	for w in self.word(pos, "pronoun")
		if w.tree.entry.det != "which" then continue
		for b in self.word(w.next, "be")
			// "what is that block's color"
			for np in self.nounPhrase(b.next)
				for s in self.word(np.next, "poss")
					for a in self.word(s.next, "attribute")
						results.push result(sentenceNode("attribute", [w.tree, b.tree, s.tree, a.tree, np.tree]), a.next)
					end for
				end for
			end for
			// "what is the color of the box"
			for t in self.word(b.next, "det")
				if t.tree.entry.det != "the" then continue
				for a in self.word(t.next, "attribute")
					for o in self.word(a.next, "of")
						for np in self.nounPhrase(o.next)
							results.push result(sentenceNode("attribute", [w.tree, b.tree, t.tree, a.tree, o.tree, np.tree]), np.next)
						end for
					end for
				end for
			end for
		end for
	end for
	// "what is that cube called", "what is it named": its name
	for w in self.word(pos, "pronoun")
		if w.tree.entry.det != "which" then continue
		for b in self.word(w.next, "be")
			for np in self.nounPhrase(b.next)
				for v in self.word(np.next, "verb")
					if v.tree.entry.form != "ed" or ["call", "name"].indexOf(v.tree.entry.stem) == null then continue
					s = sentenceNode("attribute", [w.tree, b.tree, v.tree, np.tree])
					s.attr = "name"
					results.push result(s, v.next)
				end for
			end for
		end for
	end for
	// "how big is it"
	for h in self.word(pos, "howAttr")
		for b in self.word(h.next, "be")
			for np in self.nounPhrase(b.next)
				results.push result(sentenceNode("attribute", [h.tree, b.tree, np.tree]), np.next)
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
			for p in self.predicates(np.next)
				claim = node("REL", p.tree)
				results.push result(sentenceNode("yes-no", [b.tree, np.tree, claim]), p.next)
			end for
		end for
	end for
	// "Do you have anything in your hand?"  "Do you have the red cube?"
	// Having something is holding it.
	for d in self.word(pos, "do")
		for y in self.word(d.next, "you")
			for h in self.word(y.next, "have")
				if h.tree.word != "have" then continue
				for np in self.nounPhrase(h.next)
					for a in self.optionalWord(np.next, "adj")
						if a.tree and a.tree[0].entry.pred != "held" then continue
						results.push result(sentenceNode("yes-no", [d.tree, np.tree, node("REL", [y.tree, h.tree] + a.tree)]), a.next)
					end for
				end for
			end for
		end for
	end for
	// "Are you holding the red cube?"  (Again the claim comes after the noun
	// phrase in the parts.)
	for b in self.word(pos, "be")
		for y in self.word(b.next, "you")
			for v in self.wordWith(y.next, "verb", "held")
				for np in self.nounPhrase(v.next)
					results.push result(sentenceNode("yes-no", [b.tree, np.tree, node("REL", [y.tree, v.tree])]), np.next)
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
		for o in self.iOwn(d.next, true)
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
			for e in self.optionalWord(y.next, "ever")
				for c in self.command(e.next, false, form)
					for t in self.optionalTime(c.next)
						results.push result(sentenceNode("did", [a.tree, y.tree] + e.tree + [c.tree] + t.tree), t.next)
					end for
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

// "Why did you pick it up?"  "How did you do it?"  "Why?"  ("How do you
// build a steeple?", in the present, asks how it's done in general: see
// methodQuestion.)
Parser.eventQuestion = function(pos)
	results = []
	for w in self.word(pos, "whAdverb")
		results.push result(sentenceNode("event", [w.tree]), w.next)
		for d in self.word(w.next, "do")
			if d.tree.word == "do" and w.tree.entry.q == "how" then continue
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

// "How do you build a steeple?"  "How would you build one?"  How the robot
// goes about something, in general.
Parser.methodQuestion = function(pos)
	results = []
	for w in self.word(pos, "whAdverb")
		if w.tree.entry.q != "how" then continue
		for d in self.word(w.next, "do") + self.word(w.next, "modal")
			if d.tree.word != "do" and d.tree.word != "would" and d.tree.word != "can" then continue
			for y in self.word(d.next, "you")
				for c in self.command(y.next)
					results.push result(sentenceNode("method", [w.tree, d.tree, y.tree, c.tree]), c.next)
				end for
			end for
		end for
	end for
	return results
end function

// What may end a sentence: the robot's name ("Thanks, Bob"), "again",
// "now", "please", a question mark.
Parser.ending = function(pos)
	results = []
	for v in self.optionalWord(pos, "vocative")
		results += self.endingAfterName(v.next)
	end for
	return results
end function

Parser.endingAfterName = function(pos)
	results = []
	for a in self.optionalWord(pos, "again")
		for n in self.optionalWord(a.next, "now")
			for p in self.optionalWord(n.next, "polite")
				results += self.optionalWord(p.next, "punct")
			end for
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
//
// context may give:
//   robotName       the robot's name, which may start or end a sentence
//                   ("Robot, what is in the box?")
//   expectingName   true if the robot just asked the user's name, so that
//                   a name alone ("Joe.") is an answer
parse = function(text, names=null, nouns=null, context=null)
	if context == null then context = {}
	robotName = null
	if context.hasIndex("robotName") then robotName = context.robotName
	tokens = tokenize(text, names, nouns, robotName)
	expectingName = context.hasIndex("expectingName") and context.expectingName
	p = parseTokens(tokens, expectingName)
	if p.trees then return {"trees": p.trees, "error": null, "wrongName": null}
	// Maybe the user called the robot by some other name: "Fred, what is
	// in the box?", "Thanks, Fred."  A capitalized word we don't know, at
	// the start or the end, may be that.  If the sentence makes sense
	// without it, it was; the robot will say what its name really is.
	for i in [0, tokens.len - 1]
		if tokens[-1].text == "?" and i == tokens.len - 1 then i -= 1
		if tokens.len < 2 or i < 0 or not tokens[i].unknown or not icl.isUpper(tokens[i].original[0]) then continue
		saved = tokens[i].entries
		tokens[i].entries = [{"cat": "vocative"}]
		p2 = parseTokens(tokens, expectingName)
		tokens[i].entries = saved
		if p2.trees then return {"trees": p2.trees, "error": null, "wrongName": tokens[i].original}
	end for
	// A word we don't know is most likely the trouble.
	word = unknownWord(tokens)
	if word then return {"trees": [], "error": "Sorry, I don't know the word """ + word + """.", "wrongName": null}
	return {"trees": [], "error": p.complaint, "wrongName": null}
end function

// Parse tokens as a whole sentence.  Returns the parser, with its trees:
// every parse that covers all the tokens, best first.
parseTokens = function(tokens, expectingName=false)
	p = Parser.make(tokens)
	p.expectingName = expectingName
	p.trees = []
	// The sentence starts at the beginning, or after the robot's name.
	starts = [0]
	if tokens.len > 1 and p.word(0, "vocative") then starts.push 1
	p.parseFrom starts
	// If that doesn't work, maybe it starts with a word that just links it
	// to what came before: "Now how many are there?", "So what is in the
	// box?", "And now, what are you holding?"  (Commands and small talk
	// take these words themselves; this is for everything else.)
	if not p.trees then
		later = []
		for start in starts
			for a in p.optionalWord(start, "and")
				pos = a.next
				if a.tree then later.push pos
				while p.word(pos, "lead")
					pos += 1
					later.push pos
				end while
			end for
		end for
		p.parseFrom later
	end if
	return p
end function

// Add to self.trees every parse of a whole sentence from any of these
// starting positions to the end.
Parser.parseFrom = function(starts)
	for start in starts
		for r in self.sentence(start)
			for e in self.ending(r.next)
				if e.next == self.tokens.len then
					self.trees.push r.tree
					break
				end if
			end for
		end for
	end for
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
