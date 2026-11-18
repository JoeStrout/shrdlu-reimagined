// scenes.ms
//
// Starting arrangements for the world.  Each scene is a list of object
// specs (see World.load in world.ms).  Only x and z are given: objects are
// dropped into place in the order listed, so stacks are listed bottom-up.
//
// The table runs from x = -6 (left) to 6 (right), and from z = -4 (back,
// where the robot is) to 4 (front, where you are).
//
// Sizes are [width, height, depth].  They're all chosen from a few simple
// values, so that there are plenty of things of equal height to build arches
// and bridges with.

// Winograd's starting scene.
//
// From the PLANNER data in his thesis (Appendix F) and the book's Fig. 3;
// see references/winograd-scene-and-dialog.md.  The ids are Winograd's own
// (B1 to B10, with no B8 or B9), so this is easy to check against the
// sources.  His table is 1200 units each way, with y running from front to
// back; ours is 12 by 8, with z running from back to front.  Sizes here
// are his divided by 100.  The positions keep his layout (what's left of,
// behind, and on what), but are moved a little to fit our smaller table,
// and the box is less deep than he seems to have drawn it.
//
// Winograd never published the sizes, so these are inferred from where
// things sit and from what the dialogue says about them:
//   - b10 is taller than b6 (turn 3)
//   - of the blocks outside the box, only b1 is narrower than b6 (turn 7)
//   - b10 is bigger than every pyramid, but not as wide as the box (turn 35)
//   - the box holds b4 and b10 side by side (turn 3)
//   - b7 overhangs b6 a little toward the front, as in Fig. 3
winograd = [
	{"id": "b1",  "kind": "block",   "color": "red",   "size": [1, 1, 1],     "at": [-3.5, 2.5]},  // the red cube
	{"id": "b2",  "kind": "pyramid", "color": "green", "size": [1, 1, 1],     "at": [-3.5, 2.5]},  // on the red cube
	{"id": "b3",  "kind": "block",   "color": "green", "size": [2, 2, 2],     "at": [0, 3]},       // a large green cube
	{"id": "b5",  "kind": "pyramid", "color": "red",   "size": [1, 3, 1],     "at": [0.5, 2.5]},   // the tall red pyramid, on b3
	{"id": "b6",  "kind": "block",   "color": "red",   "size": [2, 3, 2],     "at": [-4, 0]},      // the large red block
	{"id": "b7",  "kind": "block",   "color": "green", "size": [2, 2, 2],     "at": [-4, 0.5]},    // the other large green cube, on b6
	{"id": "b10", "kind": "block",   "color": "blue",  "size": [2, 4, 2],     "at": [-1, -2.5]},   // the tall blue block
	{"id": "box", "kind": "box",     "color": "white", "size": [4.5, 1.5, 3], "at": [3, -2.5]},
	{"id": "b4",  "kind": "pyramid", "color": "blue",  "size": [2, 1.5, 2],   "at": [2, -2.5]}] // in the box, at the left

// A playground for trying out building: posts and lintels for arches,
// cylinders, and pyramids whose tips are level with block tops.
playground = [
	{"id": "b1", "kind": "block",    "color": "red",    "size": [1, 2, 1],   "at": [-4.5, -2]},
	{"id": "b2", "kind": "block",    "color": "red",    "size": [1, 2, 1],   "at": [-2.5, -2]},
	{"id": "b3", "kind": "block",    "color": "blue",   "size": [3, 0.5, 1], "at": [-3.5, 0.5]},
	{"id": "b4", "kind": "block",    "color": "green",  "size": [1, 1, 1],   "at": [-1, 2]},
	{"id": "b5", "kind": "block",    "color": "green",  "size": [1, 1, 1],   "at": [0.5, 2]},
	{"id": "b6", "kind": "block",    "color": "yellow", "size": [2, 1, 2],   "at": [3, 2]},
	{"id": "c1", "kind": "cylinder", "color": "yellow", "size": [1, 2, 1],   "at": [-0.5, -2]},
	{"id": "c2", "kind": "cylinder", "color": "blue",   "size": [1, 1, 1],   "at": [-4.5, 2.5]},
	{"id": "p1", "kind": "pyramid",  "color": "green",  "size": [1, 2, 1],   "at": [0.75, -2]},
	{"id": "p2", "kind": "pyramid",  "color": "red",    "size": [1, 2, 1],   "at": [2, -2]},
	{"id": "p3", "kind": "pyramid",  "color": "blue",   "size": [1, 1, 1],   "at": [-2.5, 2.5]},
	{"id": "box", "kind": "box",     "color": "white",  "size": [3, 1.5, 3], "at": [4.25, -1.5]}]

// All the scenes, by name (in the order the display offers them).
names = ["winograd", "playground"]
byName = {"winograd": winograd, "playground": playground}
