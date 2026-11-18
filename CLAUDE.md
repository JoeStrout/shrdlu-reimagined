# SHRDLU Reimagined: notes for Claude

A spiritual successor to Winograd's SHRDLU, written in MiniScript on raylib-miniscript (sibling repo: `../raylib-miniscript`; its `API_DOC.md` lists every raylib binding). Read `README.md` for the goals.

## Hard constraints

- **No LLMs or ML at runtime, ever.** Everything that ships is hand-written code and grammar data. Claude's role is at development time only: co-writing that code, the grammar rules, and large test suites. Don't propose API calls, embeddings, or similar in the program itself.
- **Readability is a feature.** Curious users are expected to read the source. Prefer clear, well-commented, data-driven code over clever or compact code. Comments should explain the *linguistic* reasoning, not just the mechanics.
- **Deterministic physics.** Use a symbolic support graph plus simple stability rules and scripted animations. Don't use a rigid-body solver.
- **A successor, not a port.** Don't imitate or copy Winograd's code. Using his published dialogue as a test, and his ideas (goal-directed planning, episodic memory for "why" questions), is the intent.

## Architecture (planned)

English → parser (grammar in `assets/grammar/`) → ICL, as structured MiniScript maps, not text → brain (reference resolution, question answering, a goal-directed planner that keeps a goal and event history) → reply generator. The world model is the single source of truth; the renderer only displays it.

## Prior art

The 2008–09 Python prototype is in `../shrdlutng` (kept unchanged for history). Its `notes/progress-log.txt` records useful lessons, especially on resolving "one" versus "it", and on why uniform-cost search planning didn't scale.

## Conventions

- **Never commit** (or push). The user commits at the times they choose.
- Keep `notes/progress-log.md` up to date with dated entries for notable progress and decisions.
- Code lives in `src/` (modules are imported by bare name from there); data such as shaders lives in `assets/`. Run everything from the repo root.
- Run the app: `./raylib-miniscript src/main.ms` (a symlink to the desktop build).
- Tests without a window, using the MiniScript 2 command line (`../raylib-miniscript/MiniScript2/build/cpp/miniscript`):
  - `MS_IMPORT_PATH=src miniscript tests/testWorld.ms`
  - `MS_IMPORT_PATH=src:tests miniscript tests/testDisplay.ms` (uses `tests/fakeRaylib.ms` in place of raylib)
  - `MS_IMPORT_PATH=src miniscript tests/testIcl.ms`
  - `MS_IMPORT_PATH=src miniscript tests/testBrain.ms`
  - `MS_IMPORT_PATH=src miniscript tests/testPlanner.ms`
- Claude's sandbox can't open a window, so it can't run the app or `tests/screenshots.ms`. Ask the user to run them; `tests/screenshots.ms` saves PNGs that Claude can then look at.
- MiniScript gotchas: `outer` and `end` are keywords (don't use them as names, even as `x.end`); `indexOf` and `==` compare maps by value, so use `refEquals` for identity; there's no built-in `max`/`min`; a function literal nested inside a module's function can't see that module's top-level names (only its enclosing function's locals and true globals), so use plain loops instead of little lambdas.
