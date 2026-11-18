# SHRDLU Reimagined: Progress Log

## 2026-11-17

Project started as a successor to the 2008–09 *SHRDLU: The Next Generation* Python prototype (`../shrdlutng`, left unchanged for history). Decisions so far:

- **Platform:** MiniScript on raylib-miniscript, targeting the browser (web build) and desktop.
- **No runtime LLM.** All language understanding, reasoning, and replies are hand-written. LLM help is only at development time, to co-write code, grammar, and tests.
- **3D display** of the blocks world, with click-to-identify (so the user can say "this one") and an animated hand.
- **Simplified, deterministic physics:** a support graph plus stability rules (center of mass over the support area; nothing rests on a pyramid), and scripted animations when things topple.
- **ICL is kept** as the central meaning representation, but as structured data (maps and lists) rather than text that gets parsed again.
- **Planner:** goal-directed procedures (clear off, find space, move) instead of uniform-cost search. The goal tree is recorded so the robot can answer "why did you…?"
- **Acceptance test:** Winograd's published dialogue, run turn by turn from his starting scene.
- **"Under the hood" panel** showing the parse, ICL, reference resolution, goal tree, and reply generation.

Planned order:

1. World model and 3D scene (Winograd's starting layout, picking, animated hand doing hard-coded moves).
2. ICL as structured data, the brain, the planner, and the event history.
3. A grammar-based parser, then large expansion of grammar and tests.
4. Polish: the under-the-hood panel, the web build, documentation.

### Later the same day: world-model design decisions

Wrote `notes/design-world-and-icl.md`. Key decisions while reviewing it:

- **Multiple supporters.** A placed object comes straight down, and everything it touches at the highest point supports it. This allows arches and bridges. Two or more supporters must have exactly equal heights.
- **Stability by support polygon.** The convex hull of all contact regions must have nonzero area, and the object's center of mass must lie inside it. Pyramids *can* support things, as long as the polygon has area: one or two pyramids can't, but three pyramids, or a pyramid plus a block, can.
- **Only the placed object is checked** for stability, not the load on the objects beneath it (v1).
- **Cylinders from the start**, always standing upright.
- **Failed placements are never committed.** The object is animated tipping and falling, then warped back into the hand. Objects never change orientation.
- **Fixed front** for spatial words, with limited camera rotation.

### Later still: first code

Started milestone 1 in `src/`:

- `geometry.ms`: convex polygons in the table-top plane (clipping, hull, area, point-in-polygon).
- `world.ms`: Things (blocks, pyramids, cylinders, the box, the table), the support rules, the primitives `moveTo`, `grasp`, and `ungrasp` (with forced, failing placements), and the event history with snapshots.
- `scenes.ms`: a provisional Winograd scene and a "playground" scene for building arches.
- `display.ms` and `main.ms`: the 3D view, with a gantry robot arm, animation driven by the history, a limited orbit camera, click-to-select, and a placement preview showing the support polygon.

Tests: `tests/testWorld.ms` (59 checks) and `tests/testDisplay.ms` (13 checks, using a fake raylib) both pass from the command line. The app itself hasn't been run in a window yet, because Claude's sandbox can't open one.

### Later: ICL

Settled the printed form of ICL (design note §2.5) and wrote `src/icl.ms`: constructors for building ICL in code (for the parser), a printer, and a reader for the printed form (for tests, and for typing ICL directly). Changes from the first sketch in the design note:

- **One shape for every constraint:** `{pred, args}`. The old separate kinds (`rel`, `op`, `value`) are gone, and `not` and `or` are just predicates whose arguments are constraints.
- **Yes/no questions** are a target plus one constraint (`Ask yes-no x1 [narrower x2]`), the same pattern descriptions use.
- **Declarations** (`Define`, `Name`, `Own`) are written like commands, with their arguments as variables or words.
- **Variables** are `x` or `e` plus digits, so thing ids like `b1` can't be mistaken for them.

`tests/testIcl.ms` (66 checks) writes Winograd's sentences in ICL, checks the resulting data, round-trips them through the printer, and checks the error messages.

### Later: the brain, part 1 (references and questions)

Three new modules:

- `relations.ms`: every relation in design note §1.7, computed from the world: support (`on`, `supports`, `above`, `below`), `in` and `contains`, `touches`, `nextTo`, the four directions, comparisons, relative size words (`big` means the upper half of the volume range for that shape), and superlatives (`biggest`, `littlest`, `tallest`…). The direction words are first guesses, to be tuned against the dialogue.
- `speech.ms`: names objects the way Winograd's robot did, saying just enough to pick one out: "the red block", "the large green cube", and, if needed, "the red cube which is on the table". Also lists and number words.
- `brain.ms`: resolves descriptions in two stages (first every candidate that fits the noun and constraints, then the determiner decides), with quantifiers working the same way inside constraints ("on a cube" vs. "on the cube"). It handles "it", "them", "one" (borrowing a noun from earlier in the sentence or conversation), "this"/"that" for a clicked object, and names given with `Name`. It answers exists, count, which, attribute, and yes/no questions, and gives Winograd-style complaints: "I don't understand which pyramid you mean."

Decided along the way: "in the box" includes things stacked on things in the box (open question 1, provisionally).

`tests/testBrain.ms` (71 checks) covers the relations, the naming, and about 35 question-and-answer exchanges in the Winograd scene.

### Later: the brain, part 2 (commands, the planner, why/how/when)

- `planner.ms`: goal procedures `grasp`, `putOn`, `clearOff`, `getRidOf`, and `stack`, built from the three primitives. Every goal is recorded with its parent, children, and start and finish times, and the world stamps each primitive event with the goal it served. Free space is found by trying grid points nearest first, preferring spots with half a unit of elbow room. On the table the search starts near where the object already is. In the box it starts from the side nearest the object, so things pack toward the walls.
- The brain now carries out commands (pick up, put on/in, put down, clear off, get rid of, stack up, find). For "a block" it picks the least trouble: the one in the hand, then clear ones, then the nearest. That choice holds for the rest of the sentence, so "find a block… and put it in the box" means one block. `[commanded PickUp]` matches things the user explicitly told it to act on.
- "Why", "how", and "when" are answered from the goal record: why = the parent goal ("To get rid of it." … "Because you asked me to."), how = the children ("By picking it up, then setting it down on the table."), when = the user's command it was part of ("While I was stacking up…"). `e1 = event Do` means "that", the event just discussed, so "Why did you do that?" climbs the chain. Events can be constrained by `[before e2]`, `[after e2]`, `[while e2]`.

Lessons and decisions:

- **Never empty the box to put something into it.** The first version cleared out the blue pyramid to make room for the blue block. Now there's simply "no room" if it doesn't fit. Also moved the Winograd scene's blue pyramid off-center so the box can hold both.
- **Clearing off the object being moved is a step of `putOn`, not of `grasp`.** That way the goal chain reads as Winograd's does ("Why did you clear off that cube?" "To put it on…").
- **Names must count every object their noun fits.** "The red block" was ambiguous because the red cube is a block too. Objects are now named against everything the noun covers, which gives Winograd's own "the large red block".
- **Don't record goals that need no work** (grasping what's already held). They gave wrong answers to "why".

`tests/testPlanner.ms` (427 checks, most of them a check after every exchange that everything in the world is resting where it should) plays a Winograd-style conversation in ICL. `tests/testDisplay.ms` now also checks that the display plays a whole planned command through to the right final positions.

### Later: the ICL console

The app now has a console at the bottom of the window where you type ICL to the brain and read its replies, so everything from parts 1 and 2 can be tried in the 3D world. A `;` stands for a line break. Lines starting with `/` are console commands (`/help`, `/clear`, `/scene name`).

- `textInput.ms` is a one-line text field that knows nothing about ICL, so the English console can reuse it. It has the usual editing keys, a history (Up/Down), and paste.
- `console.ms` keeps the transcript (word-wrapped and scrollable) and holds each reply until the robot has finished acting it out. Lines typed meanwhile wait their turn.
- Typing always goes to the console, so the old single-key commands (P to pick up, 1 and 2 for scenes) are gone. Clicking still selects things, which makes them "this", and the mouse can still place a held object. Escape no longer quits; it clears the line.

`tests/testConsole.ms` (42 checks) drives both with fake key presses (added to `tests/fakeRaylib.ms`).


Follow-up after trying it: the placeholder's example, `x1 = a pyramid; Ask color x1`, got "I don't understand which pyramid you mean." "What color is a pyramid?" is about pyramids in general, so the robot now picks any one, the same way it does for "pick up a pyramid", answers about that one, and makes it "it". The `/help` examples are now a list that tells a short story in order, and `testConsole` checks that each one works. The ICL reader also explains its two most likely typos: a lowercase `ask` or command, and `Ask` with no kind of question after it.

### Later: the parser design note

Wrote `notes/design-parser.md` for review. The main decisions: a hand-written grammar, as readable MiniScript functions that return every parse; words and verb frames as data in a lexicon; a separate pass that turns trees into ICL; and a new `Brain.check` that picks the first parse that makes sense in the world (for "Put the blue pyramid on the block in the box"). The 2008 prototype's template matching reached 10 of 136 test sentences, mostly because templates don't compose, which is why it's all grammar this time.

Decided after review: `:` sends ICL from the console; when two readings both make sense, the robot says which it chose, Winograd style ("By 'the block in the box', I assume you mean…"); the grammar rules are code, kept readable with helper functions.

### Later: the parser, step 1 (noun phrases)

- `lexicon.ms`: the words as data, built with small helper functions (`determiner`, `noun`, `adjective`, `preposition`…). Multi-word phrases ("on top of", "to the left of", "how many"), contractions, and inflections by rule ("blocks", "supports", "sitting", plus a short table of irregular verbs).
- `parser.ms`: the tokenizer (quoted words and taught names become names) and the noun-phrase grammar: determiners (including "at least one of them"), adjectives, nouns, pronouns, prepositional phrases, comparisons ("taller than…"), and relative clauses ("which is not in the box", "which supports a pyramid", "which is sitting on the table", "(that) you are holding"). Every rule returns all its parses.
- `meaning.ms`: noun-phrase trees → ICL descriptions. A bare plural ("blocks") gets the determiner `any`.

Lesson: a modifier after a noun phrase can attach to more than one noun, as in "taller than the one you are holding". Ordering each noun phrase's parses longest first makes the parser prefer the nearest noun, which is nearly always right; the other reading is still returned for the brain to check.

`tests/testParser.ms` (58 checks): tokens, inflections, about 35 noun phrases, the order of ambiguous readings, a tree, and the complaints ("I don't know the word…", "I didn't understand the part starting with…").

Known limitations, kept as commented-out tests in `tests/testParser.ms` so they aren't forgotten: bare plurals ("blocks which are not red" can mean all, any, or blocks in general, depending on the sentence), and "this"/"that" used as determiners ("that block").

### Later: the parser, steps 2 and 3 (commands and questions)

- **Commands.** Command verbs have frames in the lexicon (`put`: "thing on thing" → `putOn`, "thing in thing" → `putIn`, "down thing" → `putDown`). Particles may come before or after the object ("pick up the block", "pick it up"). Polite openings ("will you please", "can you") are skipped, and commands joined by "and" become several statements.
- **Questions:** is there…; how many / which / what … (the rest of the question becomes a constraint on the thing asked about, so "What blocks are red?" works); what color/size/shape is…; yes/no with "is" or "does"; why/how/when did you…, "Why?", and "Why did you do that?".
- "What does the box contain?" and "What is the pyramid supported by?" ask about the *object* of a relation, so the meaning pass turns the relation around (contains → in, supported by → supports).
- "The one which I told you to pick up" → `[commanded PickUp]`, using the command frames with the object left out.
- New relation `[supported]` ("Is it supported?").
- Brain fix found by trying English: answering "when" didn't set the event focus, so a following "Why?" asked about the wrong event. Winograd's "When did you pick it up?" … "Why?" now works.

Played the first half of Winograd's dialogue in English through the brain (taking each sentence's first parse): nearly every turn gives a sensible reply. Still to do: choosing among parses (step 4), and in the brain, "the pyramid" should mean the one just mentioned when that settles it ("What is the pyramid supported by?" right after the box's contents were listed).

`tests/testParser.ms`: 104 checks.

### Later: the parser, step 4 (choosing among readings)

- `Brain.check(program)` works out what every statement refers to without doing anything, and leaves the brain as it was (focus included). It returns the complaint it would make, plus a summary of what the reading means (each statement and the ids of the things it's about).
- `Brain.hear(text)` parses, checks every reading, and acts on the first that makes sense; if none do, it acts on the first, so the user hears what's wrong with the likeliest reading. If another sensible reading means something different, the robot says which it assumed: `By "the block in the box", I assume you mean the blue block. OK.` The phrase it names is the longest noun phrase the chosen reading has and the other doesn't, which is where the readings part ways.
- **Inner "the".** "Put the green pyramid on the block in the box" (with no block in the box) has only one sensible reading, but the brain rejected it too: "the block" in "the green pyramid on the block" was ambiguous on its own. Now a "the" inside a description is settled by the description around it: the survivors must all be related to the same one of its candidates. "The pyramid on the cube" is still ambiguous when both cubes have pyramids.
- Meaning now records the words of each noun phrase with its variable; the parser has `wordsOf(tree)`.

Noticed: when nothing fits, "I don't see any blocks." should say "any blocks in the box" (speech.descriptionPhrase leaves out the constraints). And "the pyramid" still doesn't use what was just mentioned.

`tests/testBrain.ms`: 90 checks (the inner "the", the two ambiguity cases, that checking changes nothing, and English with a taught name).

### Later: the parser, step 5 (the English console)

The console now takes English: each line goes to `Brain.hear`. A line starting with `:` is ICL, as before (`: x1 = a pyramid; Ask color x1`). `/icl` toggles showing, in green under each sentence, the ICL the robot acted on (and which reading it was, when there were several). The `/help` examples are now English and tell a short story in order (pick up a big red block; find a taller block and put it into the box; what does the box contain; why did you pick up the blue block; why; …), and `testConsole` checks that each gets a sensible reply. The input field's hint is English.

Noticed: "Why did you put down the big red block?" (after it was set down to free the hand for another block) gets "I don't remember doing that." That setting-down step doesn't seem to be recorded as a goal; to look at with the Winograd dialogue.

`tests/testConsole.ms`: 57 checks.
