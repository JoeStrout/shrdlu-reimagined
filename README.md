# SHRDLU Reimagined

A spiritual successor to Terry Winograd's [SHRDLU](https://en.wikipedia.org/wiki/SHRDLU) (1968–70), written from scratch for the modern browser.

Type to a robot arm in a 3D world of blocks, pyramids, and a box. Ask it questions, give it commands, teach it new words, and ask it why it did what it did, just as people did with SHRDLU more than fifty years ago.

### ▶ [Try it in your browser: joestrout.github.io/shrdlu-reimagined](https://joestrout.github.io/shrdlu-reimagined/)

**This is not a port or emulation of the original.** If you want to run Winograd's actual code, see [www-shrdlu](https://github.com/tsgouros/www-shrdlu). SHRDLU Reimagined is a clean-sheet reimplementation of the same ideas, and it aims to match and then surpass the original's abilities.

## Principles

- **All hand-written.** No machine-learning models or LLMs are used at runtime. Parsing, reasoning, planning, and replies are all explicit code and grammar rules that you can read. The point is to show what early conversational AI was like at its best.
- **Easy to run.** It runs in any modern browser, with nothing to install: [try it here](https://joestrout.github.io/shrdlu-reimagined/).
- **Easy to understand.** An "under the hood" view shows each step: the parse, the meaning representation, how references were resolved, the planner's goal tree, and how the reply was built. The source is written to be read.
- **Predictable physics.** Blocks rest on each other and can topple, but by simple deterministic rules rather than a full rigid-body simulation, so the robot can reason reliably about its world.

## Technology

Written in [MiniScript](https://miniscript.org) using [raylib-miniscript](https://github.com/JoeStrout/raylib-miniscript) for 3D graphics, on desktop and on the web.

## Project layout

```
src/                MiniScript source: main.ms, world model, display, brain, planner, console, English parser
assets/             data files: shaders (later: grammar rules, fonts)
tests/              test scripts, including Winograd's dialogue and the coverage test
notes/              design notes and progress log
docs/               the web version, served by GitHub Pages (index.html is hand-written; the rest comes from scripts/update-web.sh)
scripts/            update-web.sh, which rebuilds the web version in docs/
logs/               session logs, written by the desktop app (not kept in git)
```

## Running

During development, run it from the repo root with a desktop build of [raylib-miniscript](https://github.com/JoeStrout/raylib-miniscript). It's convenient to make a symlink to that executable in the repo root (it's ignored by git). For example, if raylib-miniscript is cloned next to this repo:

```
ln -s ../raylib-miniscript/build/raylib-miniscript raylib-miniscript
./raylib-miniscript src/main.ms
```

Talk to the robot in English in the console at the bottom of the window, for example "Pick up a big red block." Type `/help` for more examples. Click on something to make it "this". `/icl` shows the ICL (the robot's internal language) for each sentence, and a line starting with `:` is typed in ICL directly, with `;` between lines: `: x1 = a pyramid; Ask color x1`.

The tests run without a window, using command-line MiniScript 2:

```
MS_IMPORT_PATH=src miniscript tests/testWorld.ms
MS_IMPORT_PATH=src:tests miniscript tests/testDisplay.ms
MS_IMPORT_PATH=src miniscript tests/testIcl.ms
MS_IMPORT_PATH=src:tests miniscript tests/testBrain.ms
MS_IMPORT_PATH=src:tests miniscript tests/testPlanner.ms
MS_IMPORT_PATH=src:tests miniscript tests/testConsole.ms
MS_IMPORT_PATH=src miniscript tests/testParser.ms
MS_IMPORT_PATH=src miniscript tests/testDialogue.ms
MS_IMPORT_PATH=src miniscript tests/testCoverage.ms
```

`testDialogue.ms` plays Winograd's dialogue; `testCoverage.ms` checks the many other ways people might say things.

## History

This project grew out of *SHRDLU: The Next Generation*, a Python prototype from 2008–09 that translated English into an intermediate command language (ICL) and executed it against a 2D world of block columns.
