// fixtures.ms
//
// Scenes for the unit tests.
//
// earlyScene is the provisional guess at Winograd's scene that the brain
// and planner tests were first written against, before we had his real
// data (see scenes.winograd).  It's kept so those tests check how things
// work, without depending on the details of his scene; it also has things
// his scene doesn't, like a small green cube, which some tests use.  The
// dialogue test (testDialogue.ms) uses the real scene.

earlyScene = [
	{"id": "b1", "kind": "block",   "color": "red",   "size": [1, 1, 1],     "at": [-4, 1.5]},
	{"id": "p1", "kind": "pyramid", "color": "green", "size": [1, 1, 1],     "at": [-4, 1.5]},
	{"id": "b2", "kind": "block",   "color": "green", "size": [2, 2, 2],     "at": [-1.5, -1.5]},
	{"id": "p2", "kind": "pyramid", "color": "red",   "size": [1, 1.5, 1],   "at": [-1.5, -1.5]},
	{"id": "b3", "kind": "block",   "color": "red",   "size": [3, 2, 2],     "at": [1.5, 1.5]},
	{"id": "b4", "kind": "block",   "color": "green", "size": [1, 1, 1],     "at": [1.5, 1.5]},
	{"id": "b5", "kind": "block",   "color": "blue",  "size": [1, 3, 1],     "at": [-3.5, -2]},
	{"id": "box", "kind": "box",    "color": "white", "size": [3, 1.5, 3],   "at": [4, -2]},
	{"id": "p3", "kind": "pyramid", "color": "blue",  "size": [1, 1.5, 1],   "at": [3.25, -2]}]
