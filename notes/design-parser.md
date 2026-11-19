# Design Note: The English Parser

Status: draft for review, 2026-11-17.

The parser turns an English sentence into ICL (see `design-world-and-icl.md`, Part 2), which the brain already understands. It decides what the sentence *says*. Which objects it *means* is still the brain's job (§2.4 of that note).

## Part 1: What we learned in 2008

The 2008 prototype mixed an NLTK grammar with template matching (`nl_to_icl.py`, `templateMatch.py`). By its last progress-log entry it converted 10 of 136 test sentences correctly. The problems were:

- **Templates don't compose.** Every new way of combining phrases needed a new pattern, and patterns for noun phrases had to renumber the variables of the patterns around them.
- **Word order defeated it.** "What are the red blocks?" worked but "What blocks are red?" didn't, because the description was split around "are". A grammar handles this naturally. (See §3.3.)
- **The meaning was produced as text**, then parsed again. That's fixed already: ICL is now data built with the constructors in `icl.ms`.

So this time the parser is all grammar, and readable.

## Part 2: How it works

```
"Put the littlest pyramid on top of it."
      │  tokenize          put the littlest pyramid on-top-of it
      │  look up words     verb, det, adj (superlative), noun, prep, pronoun
      │  grammar           every parse tree
      │  meaning           an ICL Program for each tree
      │  brain.check       which ones make sense in the world right now
      ▼
x1 = the pyramid [littlest]
x2 = it
PutOn x1, x2
```

### 2.1 Tokens

- Lowercase everything, and split off punctuation. A final `?` is kept as a token, because it helps tell questions from commands. Other punctuation is dropped, except quotation marks (see below).
- Expand contractions: "don't" → "do not", "can't" → "can not", "I'm" → "I am", "you're" → "you are".
- Join multi-word expressions, longest first, from a list in the lexicon: "on top of", "next to", "in front of", "to the left of", "at least", "get rid of", "as well as". These are treated as one word from then on.
- A word in quotation marks ("steeple", "superblock") is a **new word**, which a definition or a name is about to introduce. It's never "unknown".
- Once taught, a word is known. The brain passes `parse` the names it has learned ("superblock"), which become names, and the nouns it has learned ("steeple"), which become nouns, in the singular or the plural ("steeples").

Particle verbs ("pick up", "put down", "clear off", "stack up") are *not* joined at this stage, because the particle can move: "pick it up". The grammar handles them (§3.1).

### 2.2 The lexicon

`src/lexicon.ms` is data: a map from each word to its possible entries. Most words have one entry, but some have several ("block" is only a noun, but "that" is a determiner, a pronoun, and a relative pronoun).

```
"block":     [{"cat": "noun", "head": "block"}]
"thing":     [{"cat": "noun", "head": "thing"}]
"red":       [{"cat": "adj", "pred": "color", "value": "red"}]
"big":       [{"cat": "adj", "pred": "size", "value": "big"}]
"large":     [{"cat": "adj", "pred": "size", "value": "big"}]
"littlest":  [{"cat": "adj", "pred": "littlest"}]
"taller":    [{"cat": "comparative", "pred": "taller"}]
"on":        [{"cat": "prep", "pred": "on"}, {"cat": "particle"}]
"onto":      [{"cat": "prep", "pred": "on"}]
"behind":    [{"cat": "prep", "pred": "behind"}]
"it":        [{"cat": "pronoun", "head": "it"}]
```

Verbs list their **frames**: the shapes they can take, and the ICL each one means.

```
"put": [{"cat": "verb", "frames": [
           {"shape": "thing on thing",  "icl": "putOn"},
           {"shape": "thing in thing",  "icl": "putIn"},
           {"shape": "thing down",      "icl": "putDown"}]}]
"pick": [{"cat": "verb", "frames": [
           {"shape": "up thing",        "icl": "pickUp"}]}]
"grasp": [{"cat": "verb", "frames": [
           {"shape": "thing",           "icl": "pickUp"}]}]
```

In a shape, `thing` is a noun phrase. `on` matches any preposition whose `pred` is `on` (so "on", "onto", and "on top of" all count). `up` and `down` are particles, which may come before or after the object: "pick up the block", "pick the block up". (A pronoun object has to come first, "pick it up", but there's no need to enforce that.) Synonyms are just more entries: "grasp" and "pick up" both mean `pickUp`.

**Inflections** come from a few rules rather than separate entries. Plurals are handled by `icl.singularize` and `icl.pluralize`: the usual rules (-s, -es, consonant + y → -ies), plus the irregular nouns listed in `assets/irregularPlurals.txt` ("die"/"dice", "leaf"/"leaves", "bus"/"buses", "sheep"/"sheep"). That covers words the user teaches too. Verbs ending in -s, -ed, and -ing are reduced to their stems. A short table covers the irregular ones (held, told, did, put, began, built), and comparatives and superlatives are listed in full, since there are only a few. The token remembers its form (plural, past, -ing), because agreement and tense help the grammar ("is" vs. "are"; "did you pick" vs. "pick").

### 2.3 The grammar

The grammar is in `src/parser.ms` as ordinary MiniScript functions, one for each kind of phrase. Each function takes a position in the token list and returns **every** way its phrase can match there, as a list of `[tree, nextPosition]`:

```
// A noun phrase: a determiner, adjectives, a noun, then any number of
// prepositional phrases and relative clauses.
Parser.nounPhrase = function(pos)
    results = []
    for d in self.determiner(pos)            // includes "no determiner"
        for a in self.adjectives(d.next)
            for n in self.noun(a.next)
                results += self.modifiers(...)  // PPs and relative clauses
    ...
```

This is a top-down parser that backs up: it simply tries everything. That's exponential in theory. In practice, sentences are short and the vocabulary is small, and remembering each function's results at each position (`self.memo`) keeps it fast if it ever needs to be. Each rule stays a few readable lines, and a parse can be traced by hand.

A **tree** is a map: `{"cat": "NP", "parts": [...], "word": ..., "entry": ...}`. Trees print as indented brackets for tests and for the under-the-hood panel:

```
(S command
  (V put)
  (NP the (ADJ littlest) (N pyramid))
  (PP on-top-of (NP (PRO it))))
```

The grammar's order of alternatives is its order of **preference**. When two parses both make sense, the first one wins (§4).

### 2.4 Meaning

`src/meaning.ms` walks a tree and builds an ICL `Program`, using the constructors in `icl.ms`. Keeping this separate from the grammar means each part reads cleanly: the grammar says what the phrases are, and the meaning pass says what they mean. It also means the panel can show both.

- Each noun phrase becomes a description with a new variable. Adjectives and modifiers become its constraints.
- Pronouns stay pronouns (`x2 = it`). The brain's focus already resolves them, including within one sentence ("find a block … and put it into the box"), and only the brain can announce "By 'it', I assume you mean…". (This changes the plan in the world note, §2.3, which had the parser linking "it".)
- "One" stays `one` (`x1 = a one [size small]`), and the brain borrows the noun, as it does now.

## Part 3: What the grammar covers

### 3.1 Commands

- **Verb and arguments, by frame:** "pick up a big red block", "put it into the box", "clear off the red cube", "get rid of it", "stack up two pyramids", "find a block which…", "put the blue block down", "drop it".
- **Politeness** is skipped: "please", "will you", "would you", "can you", "could you" before a command. ("Can the table pick up blocks?" is a different thing, a question about ability, because its subject isn't "you".)
- **Several commands joined by "and"**: "find a block … and put it into the box" gives two statements.

### 3.2 Noun phrases

- **Determiners:** a, an, the, any, every, each, no, some, which, what, numbers ("two pyramids"), "how many", "at least one of".
- **Adjectives:** color, size, and superlatives ("the littlest pyramid", "the biggest block").
- **Nouns** and **pronouns** (it, that, this, them, they, one, ones, something, anything). "One" alone ("Build one.") means "one one", borrowing its noun from earlier.
- **Prepositional phrases:** "on the table", "in the box", "behind a pyramid", "to the left of the box", "on top of green cubes".
- **Relative clauses**, with "which", "that", or nothing: "which is taller than…", "which supports a pyramid", "(that) you are holding", "which I told you to pick up". Their meaning is a constraint on the noun phrase: `[taller x2]`, `[supports x3]`, `[held]`, `[commanded PickUp]`.
- **Comparatives:** "taller than the one…", "narrower than…", "bigger than every pyramid".

### 3.3 Questions

The rule that fixes the 2008 word-order problem: in a question with "is/are", **the predicate becomes a constraint on the thing asked about**. "What blocks are red?", "What are the red blocks?", and "Which blocks are red?" all become `x1 = which blocks [color red]; Ask which x1`.

| English | ICL |
|---|---|
| Is there a large block behind a pyramid? | `x1 = a block [size big] [behind x2]` … `Ask exists x1` |
| How many blocks are not in the box? | `x1 = how-many blocks [not [in x2]]` … `Ask count x1` |
| Which cube is sitting on the table? | `x1 = which cube [on x2]` … `Ask which x1` |
| What does the box contain? | `x1 = which thing [in x2]; x2 = the box; Ask which x1` |
| What is the pyramid supported by? | `x1 = which thing [supports x2]` … `Ask which x1` |
| What color is it? | `x1 = it; Ask color x1` |
| Is it supported? | `Ask yes-no x1 [supported]` (a new one-place relation) |
| Is at least one of them narrower than…? | `Ask yes-no x1 [narrower x2]` |
| Why did you pick it up? | `e1 = event PickUp x1; Ask why e1` |
| When / How did you…? | the same, with `Ask when` or `Ask how` |
| Why? | `e1 = event Do; Ask why e1` (that is, why did you do that) |

Verbs used in questions about the world ("contain", "support", "sit on") map to relations through the lexicon, the same way command verbs map to commands. A stranded preposition at the end ("supported *by*", "what is it sitting *on*") is handled by the question rules.

### 3.4 Later

These are in Winograd's dialogue but come after the first round:

- **Noun-phrase conjunction:** "both of the red blocks and either a green cube or a pyramid". *(Done: `Parser.nounPhrases`, used for command arguments and the objects of relation verbs. Joined phrases become ICL groups.)*
- **Ability questions:** "Can a pyramid support a pyramid?" *(Done: `Parser.canQuestion`, giving `Ask can`.)*
- **Definitions, names, and ownership:** "A 'steeple' is a stack which contains…", "Call the biggest block 'superblock'", "I own blocks which are not red…", "The blue pyramid is mine." *(Done. A definition is `Parser.defineStatement`: "a", the quoted word, "is", and a noun phrase, giving `Define steeple, x1`.)*
- **Questions about the past with tense:** "Had you touched any pyramid before you put the green one on the little cube?", "What did the red cube support before you started to clean it off?"
- **Social replies:** "Thank you." (This one is easy and may come early, just for fun.)

### 3.5 Breadth: other ways of saying things

After the dialogue, the grammar grew to cover the many other ways people say the same things (`tests/testCoverage.ms`). Most of this is data: more words and more frames. The rules added were:

- **Commands.**
  - More verbs and frames: take, get, hold, grab, remove, stick, pile up, bring, make, let go (of), release, clear (without "off"), clean up.
  - Frames that say where the thing is now ("take the green cube *off* the red block", "*out of* the box", "remove it *from* the box"). These add a constraint to the thing, rather than another argument.
  - "Put X under Y" swaps the two, to mean putting Y on X.
  - "Put X next to / to the left of / behind Y" gives `PutAt x1, nextTo, x2`. Next to the table's sides ("at the front of the table"), it means that third of the table.
  - "Put it back" and "Undo that".
  - "Count the blocks" is a question.
  - An unknown word may be a new name where a frame wants one ("Call it Bert").
- **Before a command.** A word like "now", "first" or "then", the politeness from before, and a request like "I want you to", "try to" or "go".
- **Joining.**
  - Commands joined by just "then".
  - Lists with commas ("the blue block, the red cube and the green pyramid"). The tokenizer drops commas but marks the next word as coming after one, so only lists need to know.
- **Noun phrases.**
  - "all the X"
  - "something green"
  - "the second tallest block"
  - "the top of X" (which just means X)
  - "-ing" clauses without "which is" ("the one supporting a pyramid")
  - "colored red or blue"
- **After "is".**
  - Predicates joined by "and" or "but" ("red and on the table", "green but not on the table"): `[and ...]`.
  - "the biggest"
  - A noun phrase ("Is it a block?", "Is it the tallest block?"): `[oneOf x2]`.
- **Questions.**
  - "What is it?" (`Ask identify`)
  - "Where is X?", "Where did X go?", "Show me X", "Tell me where X is" (`Ask where`)
  - "What are you holding?", "Are you holding X?", "Is your hand empty?"
  - "Do/can you see X?" (whether there is one)
  - "What is X's color?", "What is the color of X?", "How big is X?"
  - "Which is taller, A or B?": `x3 = which thing [oneOf group] [tallest]`
  - "What did you do last?" (`Ask what`, of `event Do [last]`)
  - "What did you have to move to do that?": `[for e2]`
  - "How do you build a steeple?" (`Ask method`)
  - "How many blocks can you pick up?" (`[could e1]`)
- **Social.** Greetings, thanks, praise, "help", "who are you?" and so on, each a whole sentence (`Chat hello`).
- **Small talk** (`lexicon.smallTalk`, `Parser.smallTalk`). Fixed sentence patterns, matched against the whole sentence so their words aren't joined elsewhere ("what are you" vs. "what are you holding"). A `<name>` slot takes one to three words; `<Name>` takes only capitalized ones, so "I'm Joe" names the user but "I'm tired" doesn't. Each pattern gives its ICL, with the user as `me` and the robot as `you`: `Name me, Joe`, `Name you, Bob`, `Ask name me`, `Ask yes-no you [named Bob]`, `Chat about`. A greeting, a lead word or "please" may come first ("Hi, I'm Joe").
- **Speaking to the robot by name.** The robot's name (default "Robot") may start or end a sentence ("Bob, pick up the red cube", "Thanks, Bob"), or stand alone ("Robot?"). A capitalized unknown word in either place, when the sentence parses without it, is taken as the wrong name ("Fred, what's in the box?"), and the robot corrects it before answering.
- **Naming and teaching words.** What "Call X Y" means depends on the determiners (`Meaning.naming`):
  - "Call the biggest block superblock": a name for one thing: `Name x1, superblock`.
  - "Call the box a crate": a word for that one thing: `DefineLike x1, crate`. "The crate" and "Is the box a crate?" work.
  - "Call that a steeple", where "that" is a stack: also `DefineLike`, but the brain learns the kind by example (the shapes, bottom first).
  - "Call a box a crate", "Call all boxes crates": a kind of thing, from the description: `Define crate, x1`, as with Winograd's definition.
  - "That is a steeple" and "This is called a steeple" are like "call that a steeple".
  - Right after a stack is made, "that", "it" and "this" in naming mean the whole stack (`Brain.thingToName`).
  - Names keep the case they were typed in ("Bob"), and match in any case.
- **Definitions that are arrangements.** "A "steeple" is a pyramid on top of a cube" defines the pair, not the pyramid. The brain keeps it as layers, bottom first: a cube, then a pyramid (`Brain.patternOf`). A steeple is then any stack whose top layers fit, and "Make one" builds it in that order. Words taught by example are layers too, of shapes.
- **"Other" and "another".** "The other green cube" is `[other]`: not something referred to in this sentence or the last. "Another" is "a" with `[other]`.
- **"Add X"** puts X where the things just talked about are: `AddTo x1`. "Add X to Y" is `PutOn`.

## Part 4: Ambiguity

Winograd's dialogue includes "Put the blue pyramid on the block in the box." It has two parses:

1. Put [the blue pyramid] on [the block in the box].
2. Put [the blue pyramid on the block] in [the box].

The grammar returns both, and the meaning pass turns each into ICL. Then the brain decides which make sense:

- **`Brain.check(program)`** (new) resolves every description without doing anything, and returns the problem it would report, or null. It never moves anything and doesn't change the focus.
- **A "the" inside a description is settled by the description around it.** In "the green pyramid on the block" there are several blocks, but only one that the green pyramid is on, so that's the one meant. The brain lets such an inner "the" have several candidates while it tests the outer description, and then requires the survivors to be related to just one of them. Without this, the second reading of the sentence above would always fail with "I don't understand which block you mean."
- The parser takes the **first parse (in grammar order) that checks clean**. If none do, it reports the problem from the first parse, since that's the most likely reading.
- When more than one parse checks clean and they mean different things, the robot takes the first, and **says which reading it chose**, Winograd style, before its reply. It names the noun phrase that differs between the readings, and what it took that phrase to mean: `By "the block in the box", I assume you mean the large red block.` (The name comes from `speech.ms`, as in the robot's other replies.) The under-the-hood panel will list the other readings.
- **"It" in the same sentence.** "It" means what we were talking about before, unless that makes no sense. Then the brain tries the readings where "it" is an earlier noun phrase in the same sentence, nearest first. In "What did the box contain before you put the red cube in it?", "it" is the box, and the robot says so (`meaning.itReadings`).
- **"What about X?"** (also "How about X?", "And X?") isn't parsed into ICL of its own. The brain copies the last program it acted on (by printing and reading back its ICL), and puts X in place of part of it (`Brain.whatAbout`):
  - A place ("on the table") replaces a place, preferring the same preposition.
  - A noun phrase replaces one with the same noun, or else one of the same sort (definite or not), or else what the sentence was about.
  - A question's "which" or "how many" stays, and "ones" borrows the old noun.
- **Saying which one.** After "I don't understand which green cube you mean.", a noun phrase on its own ("The one supporting a pyramid.", "Any one.") is added to that description, and the robot tries again (`Brain.settle`).
- **Some words the robot asks about instead.** "On top of" has two senses in the lexicon, each with a description: directly on (`[on]`), and anywhere above (`[above]`). When readings that use different senses would mean different things, the robot asks, as Winograd's did: `I'm not sure what you mean by "on top of" in the phrase "on top of green cubes".  Do you mean: 1 - directly on the surface 2 - anywhere on top of?` (one choice per line). If the next thing the user types is just a number, it picks that reading and the robot carries it out; anything else drops the question. In a command ("put it on top of the red block"), only the "on" sense fits the verb's shape, so there's nothing to ask. A yes/no question ("Is the green pyramid on top of the blue block?") is asked about when the two senses give different answers, since a yes/no question's answer is part of what its reading means.

## Part 5: When it doesn't understand

The robot should say *what* it didn't understand. In order of how specific it can be:

1. **An unknown word:** `I don't know the word "frobnicate".` (A word in quotes is never unknown; see §2.1.)
2. **No parse:** the parser remembers how far any rule got, and complains about the next word: `I didn't understand the part starting with "upside".` This is usually close to the real problem.
3. **A parse, but no meaning:** for example, a verb with the wrong shape ("put the block"). The meaning pass says `I don't know how to put something without somewhere to put it.` These messages come from the frames, so they're written once per verb rather than per sentence.

There is no spelling correction in v1.

## Part 6: The English console

- The console sends **English** by default, and reuses `textInput.ms` as it is.
- A line starting with **`:`** is sent as ICL, as now (`: x1 = a pyramid; Ask color x1`).
- **`/icl`** turns on showing the ICL for each English sentence, dimmed, between your sentence and the robot's reply. Later, the under-the-hood panel will show the tree and the brain's notes as well.
- The `/help` examples become English.

## Part 7: Modules and tests

| file | contents |
|---|---|
| `src/lexicon.ms` | the words, as data; multi-word expressions; contractions; inflection rules |
| `src/parser.ms` | the tokenizer, the grammar functions, trees and their printer, "how far did it get" |
| `src/meaning.ms` | trees → ICL Programs; error messages for verbs with the wrong shape |
| `src/brain.ms` | adds `check(program)` |
| `src/console.ms` | English by default, `:` for ICL, `/icl` |

A small top-level function ties them together: `understand(text, brain)` returns the chosen Program, plus the trees and other Programs for the panel, or a complaint.

Tests:

- **`tests/testParser.ms`:** tokens and inflections, a few tree shapes, and mostly **English → printed ICL**, compared as strings. Many of the expected ICL strings already exist in `tests/testIcl.ms`, written for Winograd's sentences. It also covers the ambiguity choice and the error messages.
- **`tests/testDialogue.ms`:** the acceptance test. It plays Winograd's dialogue in English, in order, from his starting scene, and checks each reply. Turns we can't handle yet are listed as known gaps, and the list should shrink until it's empty. (`tests/testPlanner.ms` already plays most of the first half in ICL, so this is mostly a matter of putting the English in front.)

## Part 8: Order of work

1. Tokenizer, lexicon, inflections, and noun phrases (determiners, adjectives, PPs, relative clauses, comparatives, superlatives, pronouns, "one") → descriptions.
2. Commands: frames, particles, politeness, "and".
3. Questions: exists, count, which, attribute, yes-no, why/how/when, "Why?".
4. `Brain.check` and choosing among parses.
5. The English console.
6. Winograd's dialogue, turn by turn, extending the grammar as each turn needs (including the items in §3.4).

## Part 9: Decided after review

1. **`:` sends ICL** from the console, and `/icl` toggles showing the ICL for each English sentence.
2. **The robot says which reading it chose** when two make sense, Winograd style (§4).
3. **The phrase rules are code**, with helper functions wherever they make the rules cleaner to read. The verb frames and the words are data.
