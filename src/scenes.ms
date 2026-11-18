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
// PROVISIONAL: a best guess, not yet checked against Winograd's figure.  The
// dialogue requires, for example, that a green cube sits on the large red
// block, that there are three pyramids, that the box holds the blue pyramid (off to one side, leaving room
// for the blue block),
// that the large green cube supports the red pyramid, and that a blue block
// is taller than the large red block.  We'll tune this until the whole
// dialogue runs correctly.
winograd = [
	{"id": "b1", "kind": "block",   "color": "red",   "size": [1, 1, 1],     "at": [-4, 1.5]},
	{"id": "p1", "kind": "pyramid", "color": "green", "size": [1, 1, 1],     "at": [-4, 1.5]},
	{"id": "b2", "kind": "block",   "color": "green", "size": [2, 2, 2],     "at": [-1.5, -1.5]},
	{"id": "p2", "kind": "pyramid", "color": "red",   "size": [1, 1.5, 1],   "at": [-1.5, -1.5]},
	{"id": "b3", "kind": "block",   "color": "red",   "size": [3, 2, 2],     "at": [1.5, 1.5]},
	{"id": "b4", "kind": "block",   "color": "green", "size": [1, 1, 1],     "at": [1.5, 1.5]},
	{"id": "b5", "kind": "block",   "color": "blue",  "size": [1, 3, 1],     "at": [-3.5, -2]},
	{"id": "box", "kind": "box",    "color": "white", "size": [3, 1.5, 3],   "at": [4, -2]},
	{"id": "p3", "kind": "pyramid", "color": "blue",  "size": [1, 1.5, 1],   "at": [3.25, -2]}]

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
