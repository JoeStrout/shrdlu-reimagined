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

### Later: the parser, step 6 begins (Winograd's dialogue)

`tests/testDialogue.ms` is the acceptance test: Winograd's dialogue in English, in order, from the starting scene. Each turn gives his robot's reply; a turn passes when ours says the same. Turns we can't do yet are known gaps, each with a reason (and, for gaps that change the world or the conversation, ICL to do instead, so later turns happen in the right world). Where our reply rightly differs, the turn says what we accept and why. The expected replies were written from memory of the transcript in *Understanding Natural Language* and should be checked against the book. (Winograd's SHRDLU page at Stanford, which had the dialogue, now returns 404.)

First run: 9 of 47 turns as Winograd's. Fixes since:

- "The pyramid", when several fit, now means the one clicked on, or "it", or one of "them" (Brain.inFocus). This gives Winograd's "What is the pyramid supported by?" → "The box." For an inner "the", the description around it gets the first say, and the focus only breaks a tie: otherwise, right after "Put the blue block in the box", the "it" (the blue block) would hijack "the block" in "the green pyramid on the block".
- "That cube" and "this cube" are "the cube", with the same preference ("Why did you clear off that cube?").
- "Is it supported?" → "Yes, by the table."
- "Call the biggest block 'superblock'." (a frame element for a name).
- "Thank you." → "You're welcome!"
- Unknown words: "Sorry, I don't know the word …", as Winograd's robot said.

Now 14 turns as Winograd's, 33 known gaps, no failures. The biggest single cause of gaps: our scene isn't Winograd's. His has two large green cubes, and his turn-17 stack used the one without the red pyramid; nine turns depend on that. Next: check the starting scene against his figure, then the remaining language gaps (announcing what "it" was taken to mean, ability questions, ownership, "on top of" clarification, past tense and time clauses, definitions and "build").

`notes/sentences.txt` in the 2008 project has 135 sentences from real SHRDLU dialogs (the dialogue plus many more), to use later as a coverage list.

### 2026-11-18: Winograd's sources

The book (*Understanding Natural Language*, Cognitive Psychology 1972) and the thesis (MIT AI TR-235, 1971) are now scanned in `references/`. Findings are in `references/winograd-scene-and-dialog.md`:

- The exact starting scene is thesis Appendix F, "PLANNER Data for Dialog in Section 1.3" (also the book's last page). It gives every object's position, colour, shape and support, but no sizes. The notes infer sizes from the support heights, the figures and the dialog.
- The scene has five blocks and three pyramids. Ours lacks the second large green cube, which sits on the large red block.
- The book's dialog has 44 turns. The thesis has 46: two more after turn 21 ("does the shortest thing the tallest pyramid's support supports…", "what color is it?"), and its turns 13–16 are about *liking* ("the blue pyramid is nice"), not owning.
- Our `testDialogue.ms`, written from memory, mixes the two versions. Its replies otherwise match the sources.

### 2026-11-18: Winograd's real scene, and his way of naming things

- **The scene.** `scenes.winograd` now follows Appendix F, using Winograd's own ids (b1 to b10, the box). There are two large green cubes; b7 sits on the large red block. The sizes are inferred: b10 is taller than b6, only b1 is narrower than b6, and b10 is bigger than every pyramid but not as wide as the box. The box is 4.5 wide and 3 deep, so b4 and b10 fit side by side.
- **The old scene is a test fixture.** The provisional scene is now `tests/fixtures.ms` (`earlyScene`). The brain and planner tests use it, because they test mechanics and some rely on its small green cube. Those two tests now run with `MS_IMPORT_PATH=src:tests`.
- **"Big" uses ratios.** A thing is big if its volume is above the geometric mean of the smallest and largest of its shape, rather than the average. With the average, Winograd's green cubes (volume 8, where the blocks range from 1 to 16) came out "small".
- **Naming follows Winograd (book §8.3.3).**
  - A thing gets its color and noun: "the red cube".
  - If that fits something else, its size goes on too, and when it doesn't matter which one we mean, it's "a large green cube".
  - "Which…" questions need a specific name. That uses the size if the size is enough. Otherwise it adds "which supports …", or "which is to the right of …".
  - A thing the user named is "the block named superblock".
  - Things alike are counted together in lists: "two large green cubes".
  - The question's own noun becomes "one": "a large red one, a large green cube and the blue one".
  - Answers to "what", yes-no questions and why/how/when all use the indefinite names. "Which" questions, the planner's messages, and "By …, I assume you mean" use the specific ones.
- **The dialogue test follows the book's 44 turns**, so turns 13–16 are about owning. The thesis's two extra turns are described in the file's header.

Now 19 turns as Winograd's, 26 known gaps, no failures. These pass for the first time:
- 7 ("Yes, the red cube.")
- 18 ("The large green one which supports the red pyramid.")
- 19 ("Yes, three of them: a large red one, a large green cube and the blue one.")
- 28 ("To put it on a large green cube.")
- 29 ("To stack up the red cube, a large red block and a large green cube.")

Turns 25–27 ("When did you pick it up?" and its whys) are about the time the robot picked up the green pyramid in turn 17. It's turn 24's "before…" clause that picks out that time, so they wait on turn 24. Turn 35 will need a decision. In Winograd's system the table had no size, so things on the table never counted as "not as wide as" it. In ours they do, so the large red block and the box would join the answer.

### 2026-11-18: ownership, and better names

**Rule from the user:** where we can give an answer most readers would agree is better than Winograd's (more useful, more natural), we do, and the dialogue test records it with `ours` and `why`. Turn 35 is the first example. In Winograd's system nothing on the table counted as "not as wide as" it, because his table had no size. Our table does have a size, so our answer will include those things too.

**Ownership (turns 13–16, all passing now):**
- **English.** "The blue pyramid is mine." "I own blocks which are not red, but I don't own anything which supports a pyramid." "Do I own the box?" "Is the red cube mine?" "Which blocks do I own?" "…blocks which I own…"
  - Statements are a new sentence kind, joined by "and" or "but".
  - The lexicon gained "own", "mine" and "but".
- **ICL.** `Own x1` and `DontOwn x1` are declarations; asking uses the predicate `[owned]`.
- **Brain.** The brain keeps a list of what it was told.
  - About one particular thing, it stores that thing.
  - About a kind of thing, it stores the description, checked against the world as it is when the question comes up (`Brain.fitsDescription`). So "I own blocks which are not red" covers a block that only later stops supporting a pyramid.
  - The newest statement that fits a thing decides. If none fits, the robot doesn't know: `[owned]` is false, but "Do I own the table?" gets "I don't know."
- **Counts in yes-no answers.** These now include a count when more than one thing matches, as Winograd's did: "Yes, two things: …" ("things" for "anything"/"something", otherwise "of them").

**Names, revised:**
- **"The" when there's only one.** A thing whose color, size and noun fit nothing else is "the large red block", even when it doesn't matter which. Winograd's robot said "a large red block" there, and ours deliberately doesn't. That changed turns 19, 24 and 29 to accepted differences.
- **Telling look-alikes apart.** The clause for this now picks one fact that's true of the thing and of none of its look-alikes. In order, it tries:
  1. what it supports (Winograd's choice)
  2. what it's on, or "in the box"
  3. a direction from something that isn't a look-alike

  The old rule listed everything to its left, which came out as "…which is to the left of a large green cube, the red pyramid, the blue block, the box and the blue pyramid".

Now 23 turns as Winograd's (or better), 22 known gaps, no failures.

### 2026-11-18: "Why did you move…?"

"Why did you move the red pyramid?" didn't parse: "move" only had frames with a place ("move it onto the box"). So the parser got as far as the "?" and complained about that.
- "Move" now also has a frame with no place, `Move x1`.
- As an event, it means any goal that carried the thing somewhere. A put-on or a get-rid-of is preferred, then a pick-up (`eventGoals` now lists kinds in order of preference).
- As a command, "Move the red pyramid." asks where to.

Noticed:
- "Which green cube did you move?" doesn't parse. We have no relative clauses about past actions yet ("the cube you moved").
- When a description fits nothing, the complaint still drops its constraints: "I don't see any green cubes."

### 2026-11-18: emptying the box

- **New phrasings.** "Empty the box", "empty out the box", "clear out the box" and "clean out the box" all mean `ClearOff`. "Out" is now a particle, so "clean the box out" and "empty it out" work too.
- **How the robot says it.** For the box, clearing off is "emptying": "To empty the box."
- **Matching the robot's goals.** Getting rid of something always puts it on the table. So "Why did you put X on the table?" and "Why did you put down X?" now find a get-rid-of goal as well as a put-on goal. That fixes the earlier note: "Why did you put down the big red block?" now gets "To pick up the blue block."
- **"Nothing."** "What does the box contain?" now gets "Nothing." when the box is empty, rather than "None."; "Which cube…?" still gets "None."

### 2026-11-18: turn 24 ("Had you touched any pyramid before…?")

Turns 24–27 now pass: 27 turns as Winograd's (or better), 18 known gaps.

- **Questions about whether the robot did something.**
  - Forms: "Did you pick up the red cube?" and "Had/Have you touched any pyramid?"
  - These can take a time clause: "…before/after you put the green one on the little cube".
  - The parser has `didQuestion` and `optionalTime`. `Parser.command` takes the verb form it wants: "base", or "ed" for "had you touched" and "before you put".
  - In ICL, this is `Ask exists e1`, with `e1 = event Touch x1 [before e2]`. The `[before]`, `[after]` and `[while]` constraints were already there.
- **Answers.**
  - "No." if nothing fits.
  - Otherwise the things that fill an indefinite argument: "Yes, the green one."
  - "Yes." if every argument is definite.
- **Touching.** The robot touches a thing by picking it up, or by putting something on it. (Winograd's turn 31 counts four objects touched during the turn-17 stack, including the large red block, which only had a cube put on it.)
  - `Brain.goalArg` says what fills each place of an event verb in a goal.
  - That covers stacks, getting rid of something (onto the table), and touching.
- **The event in focus.** The event just found becomes the one in focus, and a later question whose event description fits it means that event, rather than the most recent match (`Brain.findGoal`). That's how "When did you pick it up?" (turn 25) knows to mean the pick-up during turn 17, not the later one in turn 21.

Noticed: "Did you pick up the green pyramid before you put it in the box?" gets "No.", because the pick-up was *part of* putting it in the box, not before it. Loosening "before" to include sub-steps would break turn 25 (it would find the later pick-up), so it stays strict for now.

### 2026-11-18: turns 31 and 32 (what the robot touched, and the past)

Both pass now: 29 turns as Winograd's (or better), 16 known gaps.

- **Turn 31: "How many objects did you touch while you were doing it?"**
  - `[did e1]` is a new constraint. `x1 = how-many objects [did e1]`, `e1 = event Touch x1 [while e2]` means the things the robot did e1 to.
  - The brain tries the event with just the thing being tested in that place (`Brain.didWith`, with `Brain.bound`).
  - The same form gives "Which green cube did you move?" and "What did you put in the box?".
- **Time clauses.** These now also take "were stacking up…", "were doing it" (the event in focus) and "started to clean it off" (`Parser.pastAction`). Questions starting "what", "which" or "how many" can end in a time clause.
- **Turn 32: "What did the red cube support before you started to clean it off?"**
  - The time is wrapped around the constraint: `[before e1 [on x2]]`.
  - The brain sets the world back to how it was then, using `World.snapshotAt` and `World.restore`, tests, and restores the present.
- **Along the way:**
  - Failed attempts don't count as things the robot did. ("What did you put in the box?" after "There's no room…" is "Nothing.")
  - "While" includes the event itself: picking up a block touches it while picking it up.
  - "Thing" now includes the table, so "What is the small green cube on?" is "The table." rather than "Nothing.". "Object" still means only what's on the table. Left/right/behind/in front never apply to the table.

Noticed: "What did the box contain before you put the large red block in it?" gets "I don't remember doing that." That's because "it" means the block (the focus), not the box mentioned earlier in the same sentence. Pronouns pointing back within one sentence are still to do.

### 2026-11-18: "item", and turn 17 (joined noun phrases)

Turn 17 passes now, and so does turn 18, which depends on it: 30 turns as Winograd's (or better), 15 known gaps.

- **"Item"** means the same as "object".
- **Groups in ICL.** Noun phrases joined by "and" or "or" are a new kind of line, `x4 = x2 or x3`, which can be joined again (`x5 = x1 and x4`). See design note §2.2 and §2.5.
- **"Both"** is a determiner: "the", with a check that there are two ("I see three pyramids, not two."). The parser takes "both", "both the", "both of the" and "both of them".
- **Parser.** "X and Y", "X or Y", "both X and Y" and "either X or Y" are allowed where a command wants a thing and after a relation verb ("supports a pyramid and a block"). Lists with commas ("X, Y and Z") aren't, because the commas are gone by the time the parser sees the words. Two noun phrases in a row would otherwise be read as a list far too often ("Pick up the block the box").
- **Brain.**
  - In a command, "or" takes the first member the robot can find.
  - "A" won't pick something already picked in the same command. When that's the only kind there is, the robot says "I don't see another red cube.".
  - In the dialogue, "either a green cube or a pyramid" picks the green cube with nothing on it, then clears the green pyramid off the little red cube, as Winograd's robot did.

Noted for later (from the user): after "I don't understand which green cube you mean.", a reply like "The one supporting a pyramid." should settle the question and carry out the *previous* command. That's natural in conversation, though perhaps beyond what SHRDLU did.

### 2026-11-18: turn 35 ("…but is not as wide as the thing that supports it")

The turn now runs for real, with our better answer (see the turn's note): 31 turns as Winograd's (or better), 14 known gaps.

- **"As tall/wide/big as"** are comparisons with no "than": `[asTall]`, `[asWide]`, `[asBig]`, meaning "at least as".
- **Joined relative clauses.** After a relative clause, another may follow with "and" or "but" ("which is bigger than every pyramid but is not as wide as…"). Each becomes its own constraint.
- **"It" meaning the thing described.** Inside a clause about something else, "it" can mean the outer description: `x3 = the thing [supports x1]` inside x1. The brain tries each candidate with x1 bound to it. Descriptions that mention themselves used to be refused as "going in circles"; now they mean something.
- **A "the" that finds nothing** for a particular candidate makes the constraint false, and its negation false too. So the table, which nothing supports, isn't "not as wide as the thing that supports it".
- The robot doesn't announce "By 'the thing that supports it', I assume you mean…", since that phrase means a different thing for each candidate.

### 2026-11-18: turn 33 (a claim about the past)

"There were five blocks to the left of the box then." gets "No, only four of them: …", with our usual "the large red one". That makes 32 turns as Winograd's (or better), 13 known gaps.

- **Claims.** A new kind of statement: `Claim exists x1`. The robot checks it and answers "That's right.", "No, only N of them: …" or "No, none.". A number in a claim means exactly that many.
- **"Then"** is `[then c]`: c held at the moment we last talked about. `Brain.testThen` remembers that moment in `focus.time`. With no such moment, the robot says "I'm not sure when you mean by "then".".
- The parser takes "There is/are/was/were NP [then]".

### 2026-11-18: turns 9–11 (questions about ability)

All three pass: 35 turns as Winograd's (or better), 10 known gaps.

- **ICL.** `Ask can x1 [claim]` asks whether something could be so. `Ask can e1` asks whether something could be done, and the event's `[by x1]` says by what.
- **Answers.**
  - "Yes." if it's so right now (turn 10).
  - "No. Nothing will stay on top of a pyramid." if it breaks that rule. In turn 11 that's better than Winograd's "I don't know.", so it's recorded as ours. The rule's wording is shared with the planner as `planner.pyramidRule`.
  - "I don't know." otherwise.
  - "No." for anything but the robot doing something (turn 9).
- **Parser.** "Can/could NP [not] be <predicate>", "Can NP <verb phrase>", and "Can NP <command>". "Can you…?" stays a polite command.
- Not yet: "I don't know." for "Can a block be in the box?" is honest but weak. The robot could try the planner on a copy of the world.

### 2026-11-18: turn 41 ("since we began")

"Have you picked superblock up since we began?" gets "Yes.": 36 turns as Winograd's (or better), 9 known gaps. "Since we began" (also "since we started" and "since the beginning") means the whole conversation, which is everything the robot remembers, so it adds no time constraint and needs nothing new in ICL. The present perfect ("have you picked…") already worked.

### 2026-11-18: turns 37–40 (steeples) and 44

Teaching "steeple", asking about steeples and "Build one." all pass: 40 turns as Winograd's (or better), 5 known gaps.

- **Stacks** are worked out from the support graph (`relations.stacks`), not stored. "Stack" is a noun, and a `Stack` is a kind of Thing whose parts it contains.
- **Definitions.** "A "steeple" is a stack which contains two green cubes and a pyramid." is `Define steeple, x1`. The brain keeps the description, and passes the parser its taught nouns, so "steeples" parses too. A steeple is anything that fits the description.
- **Build.** "Build one" stacks up the parts the definition names, chosen as for a command. "One" alone is now a noun phrase, and "Are there any steeples now?" "No." leaves "steeple" as the noun to borrow. "Now" may end any sentence and adds nothing.
- **Choosing parts.** Something sitting on a part already chosen costs nothing extra, since it has to be moved anyway. So the robot uses the red pyramid on the green cube rather than fetching the blue one from the box. When stacking, of two things the same size, the one on the table goes at the bottom. The robot now does what Winograd describes: it clears the red cube and two pyramids off one green cube, then stacks the other green cube and the red pyramid on it.
- **Turn 44** is recorded as ours. The robot sets the red cube down on the left of the steeple, not the right, so the red cube isn't among the things to the right of the red pyramid.
- In the brain test, "either a green cube or a pyramid" now picks the small green cube already on the red block, and the check was loosened to suit.

### 2026-11-18: the last gaps (turns 3, 22–23, 31 and 43)

Every turn of the dialogue now passes: 45 of 45, with the turns that differ recorded as ours, and no known gaps.

- **Saying what "it" means** (turns 3 and 43). The robot says "By "it", I assume you mean …" in two cases:
  - When something else mentioned earlier in the same sentence could have been "it". In turn 3, that's the block the robot is holding.
  - When "it" came from an earlier sentence and the reply is a complaint.

  The phrase echoes the user's words, with "the" in front and "you" and "I" swapped. Questions about events ("Have you picked superblock up?") now make their object "it".
- **Drop.** "Drop" is its own verb now (`Drop x1`). The robot never drops anything, so "Why did you drop it?" gets "I can't explain a nonexistent event.", unless the user told it to drop something. "Why" and "how" about something that never happened say that too.
- **"How did you do it?"** (turn 31, recorded as ours). As the answer goes along, "it" moves to each step's main thing, and a thing already named "a large green cube" becomes "that cube". Our answer was "…then putting it on a large green cube", which read as a second cube. Now it's "By putting a large green cube on the large red block, then putting the red cube on it." Winograd's longer answer also had the red block moved first, which ours didn't need, and "letting go" steps, which we leave out.
- **"On top of"** (turns 22–23) has two senses: directly on, and anywhere above. When they'd mean different things, the robot asks which, listing the choices on separate lines. A bare number as the next input picks one. The dialogue test now treats line breaks as spaces.
- Not yet:
  - a three-item comma list in a command ("Stack up the blue block, the small green cube and the red cube.") doesn't parse
  - yes/no questions aren't asked about when the two senses of "on top of" give different answers
