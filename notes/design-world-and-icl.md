# Design Note: World Model and ICL

*Draft, 2026-11-17. This is a working document; it will change as we build.*

This note pins down the two central data structures of SHRDLU Reimagined:

1. **The world model:** what exists, where it is, what rests on what, and what has happened.
2. **ICL (Intermediate Command Language):** the meaning of a user's sentence, as structured data.

Everything else connects these two. The parser produces ICL. The brain reads ICL, consults and changes the world model, and records history. The renderer only *displays* the world model and never decides anything.

```
English ──parser──▶ ICL ──brain──▶ world model changes + reply
                                 ▲            │
                                 └── history ◀┘   (events, goals, past states)
```

---

## Part 1: The World Model

### 1.1 Guiding simplifications

These keep the world easy for the robot to reason about, and easy for readers of the code to understand.

- **Everything is axis-aligned.** Objects never rotate around the vertical axis. Winograd's world worked the same way. Each object is described by a position and a size `[width, height, depth]`.
- **Positions snap to a grid** (proposal: 0.25 units). This makes "find a free spot" a simple search, lets two world states be compared exactly, and avoids floating-point surprises.
- **Objects come straight down.** A placed object descends until it touches something, and whatever it touches supports it. That may be one object or several, as with a lintel across two posts in an arch. Objects never tilt or slide while being placed.
- **The world model is the single source of truth.** Animation is purely cosmetic. The model changes at once, and the renderer catches up visually.

### 1.2 Coordinates and units

- raylib convention: **Y is up**. The table top is at `y = 0`.
- **X runs left to right** and **Z runs back to front**, *as seen from the canonical viewpoint*.
- One unit is roughly a hand's width. A small cube is 1×1×1, and the table is about 12 × 8 units (to be tuned).
- An object's `pos` is the **center of its bottom face**: `[x, y, z]`. This makes "resting on" trivial: the object's `pos.y` equals the top surface of each of its supporters.

**A fixed front.** "Behind," "in front of," "left of," and "right of" need a point of view. The user can orbit the camera, but the words are always interpreted from a fixed **front side of the table**. That's where the user is notionally sitting, and where the camera starts. The robot arm is mounted at the back. This matches Winograd (his scene had one fixed view) and keeps answers stable while the camera moves. *(To avoid confusion, we may restrict camera rotation to some small range, so the front of the table is always in front visually.)*

### 1.3 Objects

All physical things share one prototype, `Thing`. Kinds are distinguished by `shape`.

| field | type | notes |
|---|---|---|
| `id` | string | internal, stable: `"b1"`, `"p2"`, `"box"`, `"table"` (shown in the under-the-hood view) |
| `shape` | string | `"block"`, `"pyramid"`, `"cylinder"`, `"box"`, `"table"` (later perhaps `"ball"`) |
| `color` | string | `"red"`, `"green"`, `"blue"`, `"yellow"`, `"white"`… |
| `size` | `[w, h, d]` | in units; for a cylinder, `w = d` = its diameter |
| `pos` | `[x, y, z]` | center of bottom face |
| `supporters` | list of Thing | what it rests on: usually one thing, two or more for a bridge or arch; empty only for the table, and while held |
| `names` | list | names the user has given it ("call it superblock") |

**Derived properties (computed, never stored):**

- `isCube`: a block with w = h = d. "Cube" is a word for a *kind of block*, not a separate shape.
- `top`: `pos.y + h`, the height of its upper surface (for a pyramid, its apex).
- `footprint`: the region it covers in the x/z plane, as a **convex polygon**. It's a rectangle for blocks and pyramids, and a regular polygon approximating the circle (say 16 sides) for cylinders.
- `topSurface`: the region of its top, as a convex polygon at height `top`. It's a rectangle for a block, a circle-polygon for a cylinder, and a **single point** (the apex) for a pyramid. For the box, it's the interior of its floor.
- `centerOfMass`: its x/z balance point. For every shape we have, this is the center of the footprint, but stability code uses `centerOfMass` explicitly, so an asymmetric shape could be added later.
- `volume`, `height`, and `width` (the larger horizontal dimension; a cylinder's diameter), used by comparatives.

**Cylinders always stand on a flat end.** They never lie on their side, roll, or tip over, which keeps them as easy to reason about as blocks. Their round footprint is the only difference.

**Size words are relative, not stored.** "Big," "small," "tall," "narrow," "littlest" and so on are judged against the other objects of the same kind. "Big" means bigger than the typical object of its shape, and "littlest pyramid" means the minimum over the pyramids. This is how people actually use those words, and it means the robot never needs a fixed "big" flag. (The 2008 prototype had a stored `BIG`/`SMALL` size, which can't cope with "the bigger of the two small blocks.")

**Special objects:**

- **The table** is a Thing with `shape: "table"`. It can support things but can't be picked up. (SHRDLU: "Can the table pick up blocks?" "No.")
- **The box** is an open-topped container. Objects inside rest on its floor (their `supporters` include the box), and "in the box" means exactly that. Its walls block placement, so a footprint must fit inside its interior. It can't be picked up.
- **The hand** is not a Thing on the table. It's a small record: `hand.holding` (a Thing or null) and `hand.pos` (for animation and to estimate movement cost).

### 1.4 The support graph and stability

`supporters` links form a **directed acyclic graph** rooted at the table. Usually it's a simple tree, but a lintel across two posts has two supporters. Everything about "on," "supports," "clear," stacks, and arches comes from it.

- `X.supports(Y)` means `X` is in `Y.supporters`
- `X.isClear` means nothing rests on `X`
- **Stacks:** follow `supporters` links downward, or "supports" links upward.

Because a thing that supports anything is not clear, and only clear things can be grasped, the robot can never pull a post out from under a lintel. It must remove the lintel first. No special rule is needed.

**Where a placed object comes to rest.** Given a footprint (an x/z position), the object comes straight down:

1. Find every object whose `topSurface` overlaps the footprint (including the table and the box floor). For a pyramid, that means its apex lies inside the footprint.
2. The object comes to rest at the **highest** of those top surfaces.
3. Its **supporters** are all the objects whose top is at exactly that height (with the grid, "exactly" is safe).

**What may rest on what (the stability rules)**, deliberately simple and deterministic:

1. **The footprint must be clear at that height.** Nothing else may already occupy the space the object would fill. For the box, the footprint must fit inside the walls.
2. **No resting on a slope.** If the footprint overlaps a pyramid's base but *not* its apex, and that apex is higher than the resting height, the object would land on the pyramid's sloping side. The robot rejects that placement. (This is slightly conservative, which is fine.)
3. **The support polygon must have area.** Each supporter contributes a *contact region*: its `topSurface` clipped to our footprint. That's a polygon for a flat top, or a single point for a pyramid's apex. The **support polygon** is the convex hull of all the contact regions, and it must have nonzero area.
4. **The center of mass must be inside the support polygon**, or the object would tip.

Rules 3 and 4 treat pyramids correctly without any special case:

| supporters | support polygon | result |
|---|---|---|
| one pyramid | a point | rejected: no area. ("Stack up two pyramids." → "I can't.") |
| two pyramids | a line segment | rejected: no area |
| three pyramids | a triangle between the apexes | stands, if the center of mass is inside the triangle |
| a pyramid and a block | the hull of a point and a rectangle (often a pentagon) | stands, if the center of mass is inside it |
| two posts (an arch) | spans the gap between the posts | stands, which is why an arch works |
| one block | the overlap rectangle | stands, if the center isn't overhanging |

(Whenever there are two or more supporters, of any shapes, their tops must be at exactly the same height. A pyramid's apex has to be level with the block's top, for example, and two posts under a lintel must be equally tall. The scenes will include enough objects of matching heights to make interesting structures possible. See §1.8.)

All of this uses three classic, readable algorithms on small convex polygons: clipping one polygon to another (Sutherland–Hodgman), the convex hull (gift wrapping or monotone chain), and point-in-polygon. Each is a few dozen lines.

The planner only ever chooses placements that satisfy all four rules, so in normal operation nothing falls.

**Failed placements: fall, then reset.** An unstable placement only happens when the user insists ("put it there anyway"), or perhaps later from "push" commands. An unstable placement is **never committed to the world model**:

- The renderer plays a **scripted animation**: the object tips about its supporting edge, or slides off a point or line it can't balance on, and falls toward the table. The animation doesn't check for collisions with anything else on the way down, since it's only for show.
- The object is then **warped back into the robot's hand**, where it was just before the attempt. (Every placement starts from `ungrasp`, so the hand is always the right place to return it to.) The world model never changes, so there's no need to work out where a falling object would really end up, or whether it would knock anything else over.
- The attempt is recorded as an **event** (`action: "failedPlace"`), so the robot can later answer "What happened when you put the block on the pyramid?" with "It fell off."

As a result, objects never change orientation. Blocks never end up lying on their sides, and pyramids are never left fallen over.

### 1.5 Primitive actions

Every change to the world goes through three primitives. These are the only things the planner can ultimately *do*, and each is recorded in history.

| primitive | precondition | effect |
|---|---|---|
| `grasp(X)` | hand empty, X is clear, X is movable | `hand.holding = X`, `X.supporters = []` |
| `moveTo(pos)` | none | `hand.pos = pos` (and the held object travels with it) |
| `ungrasp(x, z)` | holding X, and the placement at footprint (x, z) is legal (§1.4) | X comes to rest per §1.4; hand empty |

Higher-level actions (`putOn`, `clearOff`, `getRidOf`, `stack`…) are **goal procedures** in the brain, built from these primitives. See §1.6.

### 1.6 History: events, goals, and the past

This is what lets the robot answer "Why did you do that?", "When did you pick it up?", and "What did the red cube support before you started to clean it off?" None of that is possible in the 2008 prototype.

**Time** is a pair: `[turn, step]`. The turn number increases with each user sentence, and the step number increases with each primitive action within a turn.

**Goals.** When the brain works on something, it creates a goal record:

```
Goal
  id        "g17"
  kind      "putOn"           // putOn, clearOff, getRidOf, grasp, stack, findSpace…
  args      [b3, b1]
  parent    g16 or null        // null = this goal came directly from the user
  turn      7                  // the user command that started the chain
  status    "done" / "failed" / "active"
  start     [7, 0]
  finish    [7, 5]               // ("end" is a MiniScript keyword)
```

Goal procedures create sub-goals as they work (`putOn(X, Y)` → `clearOff(Y)` → `getRidOf(Z)` → …). The result is a **goal tree**, and that tree *is* the explanation:

- "Why did you pick up Z?" → find the grasp event's goal, go to its parent, and say it: "To get rid of it."
- "Why?" (again) → go up one more level: "To clean off the red cube."
- At the root: "Because you asked me to."
- "How did you do it?" → go *down* the tree and list the children.

**Events** are the primitive actions, plus failed placements, plus definitions and namings:

```
Event
  time   [7, 3]
  action "grasp"
  args   [b4]
  goal   g19
```

**Past states.** To answer questions about the past ("What did the red cube support before…?"), each event also stores a **snapshot of every object's supporters and position** from just before it happened. That's a small map from id to `[supporters, pos]`. With a few dozen objects, keeping every snapshot is cheap, and it lets the brain run any spatial query "as of" any past time with exactly the same code as for the present.

### 1.7 Spatial relations

All of these are **computed from geometry and the support graph**, never stored. They are the vocabulary that ICL relations refer to.

| relation | meaning |
|---|---|
| `on(X, Y)` | Y is one of X's supporters (directly) |
| `above(X, Y)` / `below` | Y is reachable by following X's supporters downward (and the reverse) |
| `supports(X, Y)` | on(Y, X) |
| `touches(X, Y)` | their solids meet: one rests on the other, or their footprints touch while their vertical ranges overlap (needed for "two blocks which do not touch") |
| `in(X, box)` | the box is one of X's supporters. *Proposal:* also true for X stacked on something in the box |
| `nextTo(X, Y)` | resting at the same height, and footprints within ~0.5 units of each other |
| `behind(X, Y)` / `inFrontOf` | X's footprint lies wholly further back (smaller z) / further forward, with their x-ranges overlapping. *To be tuned against the Winograd dialogue* |
| `leftOf` / `rightOf` | the same idea on the x-axis |
| `held(X)` | hand.holding == X |
| `taller`, `shorter`, `wider`, `narrower`, `bigger`, `smaller` | compare height, horizontal width, or volume |

Notes:
- The old prototype's "under" was "directly under." Here, `below` is transitive and `directlyUnder` is the inverse of `on`. The grammar decides which one an English word means.
- "Behind" in the Winograd dialogue ("Is there a large block behind a pyramid?" → "Yes, three of them…") is generous. Matching his answers is a useful calibration test for our definitions.

### 1.8 The starting scene

We'll recreate Winograd's starting arrangement as closely as the published dialogue and figure allow. The dialogue itself constrains it. For example:

- Two red blocks, one large. A green cube initially sits on the large red block, so "pick up a big red block" requires clearing it off first.
- Three pyramids: "Grasp the pyramid" → "I don't understand which pyramid you mean."
- The box contains the blue pyramid and the blue block.
- The large green cube supports the red pyramid.
- Exactly four blocks are not in the box (after the first few moves).

**Done (2026-11-18):** the scene in `src/scenes.ms` now follows Winograd's own data (thesis Appendix F), with his ids. He never published sizes, so those are inferred from the support heights and the dialogue; see `references/winograd-scene-and-dialog.md`.

Scenes are plain data files: a list of `{id, shape, color, size, pos}`. Supporters are worked out by dropping each object into place, so a scene file can't describe an impossible arrangement. That makes it easy to add other scenes for tests and demos.

**Matching heights.** Arches, bridges, and mixed supports need supporters of exactly equal height (§1.4). Every scene should therefore include several objects of the same height, such as pairs of equal blocks, a pyramid whose apex is as high as some block, and cylinders as tall as a common block. Then interesting structures are actually possible. Choosing all sizes from a small set of grid multiples helps.

---

## Part 2: ICL (Intermediate Command Language)

### 2.1 What changes from the 2008 ICL

The 2008 ICL was **text** (`obj1 = objspec( qty=1, color=red, called=block )`), which the brain then parsed *again* with templates. That was fragile. The new ICL is:

- **Structured data:** MiniScript maps and lists, built by the parser and read by the brain directly.
- **Printable:** a pretty-printer renders it in a compact text form close to the old ICL style. That form appears in the under-the-hood panel and in test files. (A reader for the printed form also lets tests be written by hand.)
- **Unified:** the old `position(...)` and `comparison(...)` become one thing, *relations*, as the 2008 spec itself suggested ("Maybe we should unify them?").
- **Richer:** it adds determiners and quantifiers, negation, plurals, relative clauses, references to past events, and definitions.

### 2.2 Three kinds of structure

**Descriptions** (noun phrases): something to be found in the world.

```
Description
  var      "x1"                // a variable name, for cross-references and printing
  det      "a" / "the" / "any" / "every" / "no" / "which" / "how-many" / 2 / …
  plural   true / false
  head     "block" / "pyramid" / "cube" / "thing" / "one" / "it" / "box" / "table" / name
  props    list of Constraints  // adjectives and relative clauses
```

**Constraints**: conditions on a description's referent. Every constraint has the same shape, a predicate and a list of arguments: `{pred, args}`. The referent is always the implied first argument. An argument is a variable naming another description (`"x2"`), a word, a number, or another constraint:

```
{pred: "color", args: ["red"]}
{pred: "size", args: ["big"]}                           // relative; see §1.3
{pred: "on", args: ["x2"]}                              // "on a green cube" (x2 = a cube [color green])
{pred: "taller", args: ["x2"]}                          // "taller than the one you hold"
{pred: "held", args: []}                                // "the one you are holding"
{pred: "commanded", args: ["PickUp"]}                   // "the one which I told you to pick up"
{pred: "not", args: [<Constraint>]}
{pred: "or",  args: [<Constraint>, …]}                  // "red or green"
```

One uniform shape (rather than separate kinds for relations, comparisons, and logic) means the brain can test a constraint by looking up its predicate in a single table of functions.

**Statements**: what the user wants done or known. One sentence may produce several (as in "Find a block which… and put it into the box").

| kind | examples | form |
|---|---|---|
| command | pick up, put, stack, clear off, find, drop | `{kind:"command", verb:"putIn", args:["x1", "x2"]}` |
| existence | "Is there a…?" | `{kind:"ask", q:"exists", target:"x1"}` |
| yes/no question | "Is it supported?", "Is at least one of them narrower…?" | `{kind:"ask", q:"yes-no", target:"x1", claim: <Constraint>}` |
| wh-question | "What does the box contain?", "Which cube…?" | `{kind:"ask", q:"which", target:"x1"}` |
| count | "How many blocks are not in the box?" | `{kind:"ask", q:"count", target:"x1"}` |
| attribute | "What color is it?" | `{kind:"ask", q:"attribute", attr:"color", target:"x1"}` |
| history | "Why did you…?", "When…?", "How…?" | `{kind:"ask", q:"why", target:"e1"}` |
| ability | "Can the table pick up blocks?" | not yet designed |
| declaration | "Call it superblock.", "I own…", "A steeple is…" | `{kind:"declare", verb:"name", args:["x1", "superblock"]}`, and likewise `own`, `dontOwn` and `define` |

A yes/no question is a target plus a constraint, the same pattern a description uses, so "Does x1 support x2?" is `{target:"x1", claim:{pred:"supports", args:["x2"]}}`. An **event** (`{kind:"event", var, verb, args, props}`) is a pattern: a verb with argument descriptions, plus optional time constraints (`[before e2]`, `[after e2]`, `[while e2]`), matched against the event history.

### 2.3 Variables and the printed form

Descriptions get variables (`x1`, `x2`, …) so they can refer to each other, and so the printed form stays flat and readable. Some examples using Winograd sentences:

**"Pick up a big red block."**
```
x1 = a block [size big] [color red]
PickUp x1
```

**"Find a block which is taller than the one you are holding and put it into the box."**
```
x1 = a block [taller x2]
x2 = the one [held]
x3 = the box
Find x1
PutIn x1, x3                    // "it" was resolved to x1 by the parser
```

**"How many blocks are not in the box?"**
```
x1 = how-many blocks [not [in x2]]
x2 = the box
Ask count x1
```

**"Is at least one of them narrower than the one which I told you to pick up?"**
```
x1 = at-least-1 of them         // "them": the set from the previous answer
x2 = the one [commanded PickUp]
Ask yes-no x1 [narrower x2]
```

**"Why did you pick it up?"**
```
x1 = it
e1 = event PickUp x1
Ask why e1
```

**"A 'steeple' is a stack which contains two green cubes and a pyramid."**
```
x1 = a stack [contains x2] [contains x3]
x2 = 2 cubes [color green]
x3 = a pyramid
Define steeple, x1
```

The pretty-printer is part of the deliverable. It's what curious users will see, so it must be clear.

### 2.4 Reference resolution: the brain's first job

The parser does **not** decide which actual objects a description means. It produces descriptions, and the brain resolves them against the world and the conversation. The resolver's output is shown in the under-the-hood panel:

```
x1 = a block [size big] [color red]
     candidates: b6 (large red block), b1 (small red block → fails "big")
     chosen: b6
```

**Rules**, drawing on the 2008 progress-log lessons:

- **"the X"** must match exactly one object, after context narrowing. Zero matches: "I don't see any…". More than one: "I don't understand which pyramid you mean."
- **"a X"** may match any. For commands, the planner prefers the cheapest. For questions, it's existential.
- **"it" / "that"** names a *specific object*: the most recent focus. For example, the last thing commanded, found, or answered about. (This is the 2008 `definite_set`, kept and generalized.)
- **"one" / "ones"** borrows a *description*: "a red one" takes the head noun (and other constraints, per the 2008 survey) from the previous description and overrides the adjectives that are stated. **"the X one"** then resolves that combined description definitely.
- **"them" / "they"** names the most recent *set*.
- **Clicked objects:** "this one" and "that" while an object is selected resolve to the clicked object. Deixis was something SHRDLU couldn't do.
- **Assumptions are announced** when they're not obvious: "By 'it', I assume you mean the block which is taller than the one I am holding." Winograd's robot did this, and it's a big part of why it felt like a conversation.

The **focus history** (recent descriptions, sets, and objects) is part of the brain's conversational state, alongside the world history.

### 2.5 The printed form, precisely

`src/icl.ms` reads and prints this form; `tests/testIcl.ms` has many examples. One item per line. `//` starts a comment, and blank lines are ignored.

**Variables** are `x` or `e` followed by digits: `x1`, `x2` for descriptions, `e1`, `e2` for events. A variable may be used before the line that defines it (as in `x1 = a block [taller x2]`, with `x2` defined next), but it must be defined somewhere in the program, and only once.

**Descriptions:** `var = [determiner] noun constraint…`

- Determiners: `a` (`an` is accepted), `the`, `any`, `every`, `no`, `which`, `how-many`, a number (`2 cubes`), or `at-least-N`.
- The noun is written as English, singular or plural (`block`, `blocks`, `boxes`). The reader stores the singular form plus a plural flag, and the printer puts the plural back.
- Pronouns (`it`, `that`, `this`, `them`, `they`) take no determiner, except for partitives: `at-least-1 of them`.
- A word with no determiner that isn't a pronoun is a **name** (`x2 = superblock`), and is left as written.

**Constraints:** `[predicate arg…]`. Arguments are separated by spaces (commas are allowed). Each argument is a variable, a word, a number, or a nested constraint: `[color red]`, `[on x2]`, `[held]`, `[not [in x4]]`, `[or [on x2] [in x3]]`. The shorthand `[color red|green]` means `[or [color red] [color green]]`, and the printer uses the shorthand whenever it can.

**Events:** `var = event Verb arg, arg… constraint…`, as in `e2 = event PickUp x2 [while e1]`.

**Commands:** `Verb arg, arg…`, where the verb is capitalized: `PickUp x1`, `PutOn x1, x2`, `ClearOff x1`, `Stack x1, x2`, `Find x1`. In the data, verbs are lower camel case (`putOn`).

**Events in descriptions, and the past.** `[did e1]` on a description means "a thing the robot did e1 to", where e1's argument is that description itself: "How many objects did you touch while you were doing it?" is `x1 = how-many objects [did e1]`, `e1 = event Touch x1 [while e2]`, `e2 = event Do`. A time around a constraint, `[before e1 [on x2]]`, means the constraint held just before e1 began (`[after e1 …]`: just after it ended). The brain puts the world back as it was then (`World.snapshotAt`, `World.restore`), tests, and restores the present. Descriptions inside keep their present meaning.

**Declarations** look like commands but teach rather than act: `Define steeple, x1`, `Name x1, superblock`, `Own x1`, `DontOwn x1`. Ownership isn't stored on the things. The brain keeps a list of what it was told. For one thing ("the blue pyramid"), that's the thing; for a kind ("any blocks [not [color red]]"), it's the description, checked against the world whenever ownership matters. The newest entry that fits a thing decides, and if none does, the robot doesn't know (`[owned]` is false, and "Do I own the table?" gets "I don't know.").

**Questions:** `Ask kind target [claim]`

- `Ask exists x1`, `Ask count x1`, `Ask which x1`.
- `Ask color x1`, or any other attribute name, for an attribute question.
- `Ask yes-no x1 [narrower x2]`: the claim is a single constraint on the target.
- `Ask why e1`, `Ask how e1`, `Ask when e1`: the target is an event.

The reader is strict about structure but reports problems instead of stopping: each bad line produces a message like `line 3: missing ]`, and the rest of the program is still read.

---

## Part 3: Open questions

### Decided

- **Falls are never committed** (§1.4). A failed placement is animated, then the object is warped back into the hand. This settles what fallen objects look like, since there aren't any.
- **A fixed front** for "behind," "left," and similar words, with camera rotation restricted to a small range so the front of the table always faces the viewer (§1.2).
- **Cylinders are included from the start** and always stand upright (§1.3). Other shapes, like balls, wait until after the Winograd dialogue passes.
- **Two or more supporters must have equal heights**, and scenes will include enough matching heights to allow interesting builds (§1.4, §1.8).
- **Weight from above:** for now, only the object being placed is checked. See below.

### Still open

1. **`in` the box:** is a block stacked on a block inside the box "in the box"? (Proposal: yes. Implemented that way in `relations.ms`; revisit if the dialogue disagrees.)
2. **Grid size** (0.25?) and **table size** (12 × 8?). These are to be tuned visually.
3. **Arches.** These are supported by the multiple-supporter rules in §1.4. "Arch" is a natural word for the user to *teach*, in the way Winograd's dialogue taught "steeple": "An arch is a block supported by two blocks which do not touch each other." Building one needs a planner procedure that places two posts with the right gap and then the lintel. That procedure is a good stretch goal, after the Winograd dialogue passes. (Historical note: arches are most famously from Winston's 1970 arch-learning program in the same MIT blocks world; whether SHRDLU itself could build them is worth checking.)
4. **Weight from above** (decided for v1, revisit later). The rules in §1.4 check only the object being placed. In reality, adding weight on top can make a structure *below* tip. For example, stacking more blocks on the overhanging end of a block that is itself only just balanced. A fuller check would test, for each object under the new one, the combined center of mass of everything it carries. That's straightforward for simple stacks, but ill-defined when the load is shared (as with a lintel on two posts, where real physics can't say how much weight each post bears without more detail). Decision: v1 checks only the placed object, and we revisit if the results look wrong.

## Part 4: Modules (initial plan)

| file | contents |
|---|---|
| `src/geometry.ms` | convex polygons (clipping, hull, area, point-in-polygon), footprints, overlap, grid snapping, free-space search |
| `src/world.ms` | Thing, the table, the box, the hand, the support graph, stability rules, primitives |
| `src/relations.ms` | the spatial and comparative relations of §1.7, including "as of time t" |
| `src/speech.ms` | English output: names for objects ("the large green cube"), lists, numbers |
| `src/brain.ms` | reference resolution, question answering, commands, and why/how/when |
| `src/planner.ms` | Goal, and the goal procedures: grasp, putOn, clearOff, getRidOf, stack, plus finding free space |
| (`src/world.ms`) | events and snapshots live with the world; querying the past is in `brain.ms` (a separate `history.ms` turned out not to be needed yet) |
| `src/icl.ms` | ICL constructors, the pretty-printer, and the reader for the printed form |
| `src/display.ms` | the raylib 3D scene: drawing, camera, picking, the hand animation |
| `src/scenes.ms` | the starting scenes, as data |
| `src/textInput.ms` | a one-line text field (editing keys, history, paste), reusable by any console |
| `src/console.ms` | the console: transcript, `/` commands, English to `Brain.hear` (or ICL after `:`); to grow into the "under the hood" panel |
| `src/lexicon.ms`, `src/parser.ms`, `src/meaning.ms` | the English parser: see `notes/design-parser.md` |

The first milestone (done) was `world.ms` + `geometry.ms` + `display.ms` + the scenes: a visible, clickable world in which hard-coded `grasp`/`moveTo`/`ungrasp` sequences animate correctly. These modules are what the language side will build on.
