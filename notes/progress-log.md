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
