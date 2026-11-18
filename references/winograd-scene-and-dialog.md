# Winograd's starting scene and sample dialog: notes from the sources

## Sources

- **Thesis**: Terry Winograd, "Procedures as a Representation for Data in a
  Computer Program for Understanding Natural Language", MIT AI Technical
  Report 235, 1971. MIT DSpace has a scan:
  <https://dspace.mit.edu/handle/1721.1/7095>
- **Book**: Terry Winograd, "Understanding Natural Language", *Cognitive
  Psychology* 3(1), 1972, pp. 1–191.
  <https://doi.org/10.1016/0010-0285(72)90002-3>

Both are copyrighted, so they aren't in the repository. If you have copies,
put them in this directory under the file names below; `.gitignore` keeps
the PDFs, and the text extracted from them, out of git.

Notes taken 2026-11-18 from the two scans in this directory:

- **Book**: `Winograd-1972-Understanding-Natural-Language.pdf`. This is the
  *Cognitive Psychology* 3(1), 1972 printing of "Understanding Natural
  Language", 191 PDF pages. It has a (rough) text layer.
  - The sample dialog is §1.3, printed pages 8–15 (PDF pages 8–15).
  - The scene figures are Figs. 3, 4 and 5 (PDF pages 8, 9 and 12).
  - The world model is §7 (printed p. 117ff).
  - The PLANNER data is on the last page (p. 191). The text layer is badly
    garbled there.
- **Thesis**: `Winograd-thesis.pdf`, MIT AI TR-235 (1971), "Procedures as a
  Representation for Data in a Computer Program for Understanding Natural
  Language". It has 461 PDF pages, images only, with no text layer.
  - The sample dialog is §1.3, starting at thesis page 35.
  - The BLOCKS world is §3.4, starting at p. 260.
  - **Appendix F, "PLANNER Data for Dialog in Section 1.3"**, is thesis
    p. 457 (PDF page 456). It's clean enough to read reliably; the
    transcription below is from that page, checked by eye.

Searchable text, for grep (both are rough; check anything important against
the scan):
- `Winograd-1972-Understanding-Natural-Language.txt` is the book's own text
  layer.
- `Winograd-thesis-ocr.txt` is a tesseract OCR of every thesis page, with
  "=== PDF page N" markers. Printed page numbers are about one more than PDF
  page numbers in the back half (Appendix F, printed p. 457, is PDF p. 456).

Tools that worked:
- `mutool` (already installed) extracts the book's text layer and renders
  pages to PNG: `mutool draw -r 200 -o out.png file.pdf N`.
- `tesseract` OCRs the thesis pages. Run it from the image's own directory
  (`cd dir && tesseract page.png -`); in the sandbox it failed on absolute
  paths.

---------------------------------------------------------------------------

## 1. The starting scene: Appendix F, verbatim

These are the exact initial assertions, with the two printed columns merged
and grouped by kind. The book's p. 191 has the same data.

```
(#IS :B1 #BLOCK)      (#IS :B2 #PYRAMID)   (#IS :B3 #BLOCK)
(#IS :B4 #PYRAMID)    (#IS :B5 #PYRAMID)   (#IS :B6 #BLOCK)
(#IS :B7 #BLOCK)      (#IS :B10 #BLOCK)
(#IS :BOX #BOX)       (#IS :TABLE #TABLE)
(#IS :SHRDLU #ROBOT)  (#IS :FRIEND #PERSON) (#IS :HAND #HAND)
(#IS #RED #COLOR) (#IS #BLUE #COLOR) (#IS #GREEN #COLOR)
(#IS #WHITE #COLOR) (#IS #BLACK #COLOR)
(#IS #RECTANGULAR #SHAPE) (#IS #ROUND #SHAPE) (#IS #POINTED #SHAPE)

(#AT :B1  (100 100 0))
(#AT :B2  (100 100 100))
(#AT :B3  (400 0 0))
(#AT :B4  (640 640 1))
(#AT :B5  (500 100 200))
(#AT :B6  (0 300 0))
(#AT :B7  (0 240 300))
(#AT :B10 (300 640 0))
(#AT :BOX (600 600 0))

(#SUPPORT :B1 :B2)        (#SUPPORT :B3 :B5)       (#SUPPORT :B6 :B7)
(#SUPPORT :TABLE :B1)     (#SUPPORT :TABLE :B3)    (#SUPPORT :TABLE :B6)
(#SUPPORT :TABLE :B10)    (#SUPPORT :TABLE :BOX)   (#SUPPORT :BOX :B4)
(#CONTAIN :BOX :B4)

(#CLEARTOP :B2) (#CLEARTOP :B4) (#CLEARTOP :B5) (#CLEARTOP :B7) (#CLEARTOP :B10)
(#MANIP :B1) ... (#MANIP :B7) (#MANIP :B10)        ; all eight toys

(#SHAPE :B1 #RECTANGULAR) (#SHAPE :B2 #POINTED)  (#SHAPE :B3 #RECTANGULAR)
(#SHAPE :B4 #POINTED)     (#SHAPE :B5 #POINTED)  (#SHAPE :B6 #RECTANGULAR)
(#SHAPE :B7 #RECTANGULAR) (#SHAPE :B10 #RECTANGULAR)

(#COLOR :B1 #RED)   (#COLOR :B2 #GREEN) (#COLOR :B3 #GREEN) (#COLOR :B4 #BLUE)
(#COLOR :B5 #RED)   (#COLOR :B6 #RED)   (#COLOR :B7 #GREEN) (#COLOR :B10 #BLUE)
(#COLOR :BOX #WHITE) (#COLOR :TABLE #BLACK)

(#CALL :SHRDLU SHRDLU) (#CALL :FRIEND YOU)
```

Footnote on the page: "Some of the data is entered initially. The rest can
be deduced and asserted by simple antecedent theorems."

**Coordinates** (book §7.1):
- Each axis runs 0–1200.
- (0 0 0) is the *front lower left* corner of the scene: x runs left to
  right, y from front to back, and z up.
- `#AT` gives an object's front lower left corner, and `#SIZE` its three
  dimensions (x y z).
- Objects never rotate.
- Support (§7.2): "an object is supported by whatever is directly below its
  center of gravity, at the level of its bottom face". So a thing has
  exactly one supporter.

**Note: no `#SIZE` assertions are published**, in either the thesis or the
book. The one example in the text is `(#SIZE :B5 (100 100 300))` (book §7.1,
with `(#AT :B5 (400 600 200))`, which is clearly just an illustration). Sizes
must therefore be inferred; see §3.

There's no B8 or B9. The numbering jumps from B7 to B10.

## 2. What each object is

Combining the data with Fig. 3 (the starting scene; the text says "Figures
are included to show the state of the scene at various points, beginning
with Fig. 3"):

| id   | what                       | at (x y z)     | on      | notes |
|------|----------------------------|----------------|---------|-------|
| B1   | small red cube ("the red cube") | 100 100 0 | table   | front left; height 100 (B2 sits at z=100) |
| B2   | small green pyramid        | 100 100 100    | B1      | on the red cube |
| B3   | large green cube           | 400 0 0        | table   | front centre; height 200 (B5 sits at z=200) |
| B5   | tall red pyramid           | 500 100 200    | B3      | "the red pyramid"; book example size 100×100×300 |
| B6   | large red block            | 0 300 0        | table   | back left; height 300 (B7 sits at z=300). This is "a big red block" of turn 1 |
| B7   | large green cube           | 0 240 300      | B6      | the second large green cube; overhangs B6 toward the front (y 240 < 300) |
| B10  | tall blue block            | 300 640 0      | table   | back centre; taller than B6 (turn 3) |
| BOX  | white box                  | 600 600 0      | table   | back right |
| B4   | blue pyramid               | 640 640 1      | box     | inside the box (z=1: on the box floor) |
| TABLE| black table                |                |         |       |

That's 5 blocks (B1, B3, B6, B7, B10) and 3 pyramids (B2, B4, B5). Turn 2
gives "three pyramids". Turn 6 ("how many blocks are not in the box?" →
"four") comes after B10 has gone into the box.

## 3. Sizes: inferred, not published

These follow from the support heights, Fig. 3, and the dialog's answers.
Treat them as a best fit, not as data. Values are (x y z) = (width, depth,
height).

| id  | inferred size   | evidence |
|-----|-----------------|----------|
| B1  | 100 100 100     | B2 at z=100; called "the red cube" and "the little cube"; the one block narrower than B6 (turn 7) |
| B2  | 100 100 100     | small pyramid, same footprint as B1 in Fig. 3 |
| B3  | 200 200 200     | B5 at z=200; a "large green cube" |
| B5  | 100 100 300     | the book's #SIZE example; "the tall red pyramid" (turn 39 commentary); tallest pyramid in Fig. 3 |
| B6  | 200 300 300 (?) | B7 at z=300. Turn 7 says neither green cube is narrower than it, so its width is ≤ 200; with B3 and B7 at 200, the width is 200. Fig. 3 draws it deeper than wide. |
| B7  | 200 200 200     | a "large green cube"; its centre (100, 340) must lie over B6 (y 300–600) |
| B10 | 200 200 400 (?) | taller than B6 (turn 3: "the block which is taller than the one I am holding"); bigger than every pyramid but "not as wide as" the box (turn 35); fits in the box beside B4 |
| B4  | 200 200 200 (?) | Fig. 3 draws a wide, low pyramid in the box. Turn 35 needs B10 to be bigger than it |
| BOX | 400 400 300 (?) | footprint from (600 600) toward the back right corner. It must hold B4 and B10 side by side, and a stack can't fit in it |

The (?) rows are the least certain. The dialog checks these facts:
- **Turn 3**: B10 is taller than B6.
- **Turn 7**: of the four blocks outside the box, only B1 is narrower than
  B6.
- **Turn 19**: exactly three *large* blocks are behind some pyramid: "a
  large red one, a large green cube, and the blue one". This is after turn
  17, so it uses the post-turn-17 positions.
- **Turn 35**: B10 is bigger than every pyramid but not as wide as the box.
- **Turn 33**: after turn 32, four blocks are left of the box: B1, B3, B7
  and B6.
- **Turn 43**: the box, B1, B4 and B10 ("superblock") are right of the red
  pyramid.

## 4. The sample dialog: book version (44 numbered turns)

This is the authoritative wording, from the book's §1.3. The user's lines are
lower case; SHRDLU's replies are converted from capitals. Comments in
parentheses are Winograd's commentary, abridged.

1. pick up a big red block.
   → OK.
   (To pick it up, it had to clear it off, finding a space for the green
   cube and moving it away.)
2. grasp the pyramid.
   → I don't understand which pyramid you mean.
   (There are three pyramids.)
3. find a block which is taller than the one you are holding and put it
   into the box.
   → By "it", I assume you mean the block which is taller than the one I am
   holding.
   → OK.
   (The hand has to set down the red block to pick up the taller blue one.
   Fig. 4 shows the result. The caption of Fig. 4 misquotes the command as
   "bigger".)
4. what does the box contain?
   → The blue pyramid and the blue block.
5. what is the pyramid supported by?
   → The box.
   ("The pyramid" is now the one just mentioned.)
6. how many blocks are not in the box?
   → Four of them.
7. is at least one of them narrower than the one which I told you to pick
   up?
   → Yes, the red cube.
8. is it supported?
   → Yes, by the table.
9. can the table pick up blocks?
   → No.
   (A semantically nonsensical question, therefore false.)
10. can a pyramid be supported by a block?
    → Yes.
    (An actual example exists.)
11. can a pyramid support a pyramid?
    → I don't know.
12. stack up two pyramids.
    → I can't.
    (It tries and fails.)
13. the blue pyramid is mine.
    → I understand.
14. I own blocks which are not red, but I don't own anything which supports
    a pyramid.
    → I understand.
15. do I own the box?
    → No.
    (The box supports what it contains, including a pyramid.)
16. do I own anything in the box?
    → Yes, two things: the blue block and the blue pyramid.
17. will you please stack up both of the red blocks and either a green cube
    or a pyramid?
    → OK.
    (It puts a green cube on the large red block, choosing *the green cube
    with nothing on it*. It then removes the small pyramid from the little
    red cube and uses that cube to complete the stack. Result: Fig. 5.)
18. which cube is sitting on the table?
    → The large green one which supports the red pyramid.
19. is there a large block behind a pyramid?
    → Yes, three of them: a large red one, a large green cube and the blue
    one.
20. put a small one onto the green cube which supports a pyramid.
    → OK.
    ("A small one" contrasts with "a large block": a small block.)
21. put the littlest pyramid on top of it.
    → OK.
22. how many things are on top of green cubes?
    → I'm not sure what you mean by "on top of" in the phrase "on top of
    green cubes".
    → Do you mean:
    → 1 - directly on the surface
    → 2 - anywhere on top of?
    The user then types **2**.
    → Three of them.
23. had you touched any pyramid before you put the green one on the little
    cube?
    → Yes, the green one.
24. when did you pick it up?
    → While I was stacking up the red cube, a large red block and a large
    green cube.
25. why?
    → To get rid of it.
26. why did you do that?
    → To clean off the red cube.
27. why did you clear off that cube?
    → To put it on a large green cube.
28. why did you do that?
    → To stack up the red cube, a large red block and a large green cube.
29. why did you do that?
    → Because you asked me to.
30. how did you do it?
    → By putting a large red block on the table; then letting go of it; then
    putting a large green cube on it; then letting go of that cube; then
    putting the red cube on that cube; then letting go of that cube.
31. how many objects did you touch while you were doing it?
    → Four of them.
32. what did the red cube support before you started to clean it off?
    → The green pyramid.
33. there were five blocks to the left of the box then.
    → No, only four of them: the red cube, two large green cubes and a large
    red block.
34. put the blue pyramid on the block in the box.
    → OK.
35. is there anything which is bigger than every pyramid but is not as wide
    as the thing that supports it?
    → Yes, the blue block.
36. does a steeple
    → Sorry, I don't know the word "steeple".
    (It interrupts as soon as it sees the unknown word.)
37. a "steeple" is a stack which contains two green cubes and a pyramid.
    → I understand.
38. are there any steeples now?
    → No.
39. build one.
    → OK.
    (One of the large green cubes is cleared off by removing the red cube
    and two pyramids. Then the two green cubes and the tall red pyramid are
    stacked.)
40. call the biggest block "superblock".
    → OK.
41. have you picked up superblock since we began?
    → Yes.
42. why did you drop it?
    → By "it", I assume you mean the superblock.
    → I can't explain a nonexistent event.
43. is there anything to the right of the red pyramid?
    → Yes, four things: the box, the red cube, the blue pyramid and the
    block named superblock.
44. thank you.
    → You're welcome!

## 5. Scene changes during the dialog (from the figures)

- **Fig. 3** (start, captioned with turn 1):
  - The red block B6 stands back left, with green cube B7 on it.
  - The small red cube B1 is front left, with green pyramid B2 on it.
  - The large green cube B3 is front centre, with the tall red pyramid B5
    on it.
  - The tall blue block B10 is behind.
  - The box is back right, with blue pyramid B4 inside.
  - The hand is at the left.
- **Fig. 4** (after turn 3):
  - B7 has moved to the table, right of B3.
  - B6 has been set down on the table.
  - B10 is held above the box, being put in it.
- **Fig. 5** (after turn 17):
  - The stack is B6 (bottom), then B7, then B1 (top).
  - B2 (the green pyramid) is now on the table, in front of the box.
  - B3 still holds B5.
  - B10 and B4 are in the box.

## 6. The thesis version of the dialog (TR-235, §1.3, pp. 35–55)

The thesis has the same dialog with a few differences. It has 46 numbered
turns: the book's 44, plus two inserted after turn 21. Our
`tests/testDialogue.ms` was written from memory and mostly follows the
thesis.

These are the differences, in book turn numbers.

**Turns 13–16 are about *liking*, not owning:**
- 13: "the blue pyramid is nice." → I understand.
- 14: "I like blocks which are not red, but I don't like anything which
  supports a pyramid." → I understand.
- 15: "do I like the box?" → No.
- 16: "do I like anything in the box?" → Yes, two things: the blue block and
  the blue pyramid.

  The commentary adds: "Presumably we like anything which is nice, and the
  blue block is certainly not red." So the thesis version needs a rule
  that nice things are liked.

**After turn 21, the thesis has two more turns (thesis 22–23):**
- 22: "does the shortest thing the tallest pyramid's support supports
  support anything green?" → Yes, the green pyramid.

  The commentary says the grammar handles words like "support" that are
  both verbs and nouns, and handles possessives.
- 23: "what color is it?" → By "it", I assume you mean the shortest thing
  the tallest pyramid's support supports. → Red.

  The commentary says: "If we had asked 'what size is it?', the system would
  have assumed that 'it' meant the green pyramid, but nobody would ask the
  color of something which was just called 'the green pyramid', so it had
  to look farther for the reference of 'it'."

**Other differences:**
- Turn 36: the reply is "Sorry, I don't know the word "steeple". Please type
  two spaces." The two spaces cleared the input buffer, a teletype detail
  that's probably not worth reproducing.
- Turn 42: "non-existent" with a hyphen. The book drops the hyphen.
- The thesis has many more scene figures than the book:
  - Fig. 4 is the start, the same as the book's Fig. 3.
  - Figs. 5–6 cover turn 1.
  - Figs. 8–11 show the steps of turn 17.
  - Fig. 12 is after turn 21; Fig. 13 is for its turn 22.
  - Figs. 14–15 are around its turn 36 (book 34).
  - Figs. 16–19 show "build one".

  They could help pin down sizes if needed. They are on PDF pages 36–38,
  43–47, 49, 53–54 and 56–58.

All other replies match the book's word for word.

## 7. Checks against our current `tests/testDialogue.ms`

- **Turns.** Ours has 47 turns: the thesis's 46, plus "2" as its own turn.
  - Turns 13–16 use the book's *own/mine* wording.
  - Our two "shortest thing … supports" turns are the thesis's 22–23.
  - So our script is a mix of the two versions. Decide which to follow:
    either the book's 44 turns, or the thesis's 46 with "like/nice".
- **Turn 42.** "non-existent" matches the thesis; the book says
  "nonexistent".
- **Turn 4.** The order of "the blue pyramid and the blue block" differs
  (already noted in the test as an accepted difference).
- **Other replies.** Every other reply in our test matches both sources.
- **Starting scene.**
  - Ours lacks B7, the second large green cube on the large red block.
  - Ours has a small green cube there instead.
  - Several sizes and positions differ; see §1–§3.
  - Fixing this is what the nine "scene" gaps in the test are waiting on.

Suggested mapping into our scene format (`src/scenes.ms`):
- Winograd's 0–1200 coordinates, with y as depth and z as up.
- Divide by 100 and centre the table at the origin.
- Convert each object's front-left corner to its centre.
- Keep Winograd's ids in a comment (B1…B10), so these notes stay easy to
  cross-check.
