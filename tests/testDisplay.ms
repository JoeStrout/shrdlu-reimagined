// testDisplay.ms
//
// Runs the display code without a window, using a stand-in for raylib, to
// check that animations play through and drawing doesn't hit errors.
// Run from the repo root:
//
//   MS_IMPORT_PATH=src:tests miniscript tests/testDisplay.ms

import "fakeRaylib"
globals.raylib = fakeRaylib.module

import "geometry"
import "world"
import "scenes"
import "display"
import "brain"

failures = 0
checks = 0
check = function(condition, what)
	globals.checks += 1
	if condition then return
	globals.failures += 1
	print "FAILED: " + what
end function

near3 = function(a, b)
	return abs(a[0]-b[0]) + abs(a[1]-b[1]) + abs(a[2]-b[2]) < 0.001
end function

// Play animations to the end, drawing every frame.  Returns the frame count.
playOut = function(view)
	frames = 0
	while view.isBusy and frames < 5000
		view.update 1/30
		view.draw
		frames += 1
	end while
	view.draw
	return frames
end function

display.setup

for name in scenes.names
	w = world.World.make
	w.load scenes.byName[name]
	view = display.Display.make(w)
	view.draw
	check fakeRaylib.module.calls.DrawModelEx > 10, "scene " + name + " draws its models"
end for

// Pick something up and put it down; the display should end up matching
// the world.
w = world.World.make
w.load scenes.byName.playground
view = display.Display.make(w)
b3 = w.thing("b3")
w.pickUp b3
w.putAt -3.5, -2
frames = playOut(view)
check frames > 30, "the move takes a while to animate (" + frames + " frames)"
check not view.isBusy, "animation finishes"
check near3(view.drawnPos(b3), b3.pos), "the lintel is drawn where the world says it is"
check view.carried == null, "nothing drawn in the hand"

// Select it, then preview a placement and draw that.
view.selected = b3
w.pickUp w.thing("b4")
playOut view
check refEquals(view.carried, w.thing("b4")), "the held block is drawn in the hand"
view.preview = w.placementFor(w.hand.holding, -3.5, -2)
check view.preview.ok, "the preview on the arch is ok"
view.draw

// A placement that falls: the tumble plays, and then it's back in the hand.
w.putAt 0.75, -2, true
sawTumble = false
for i in range(1, 400)
	view.update 1/30
	view.draw
	if view.tumble then sawTumble = true
	if not view.isBusy then break
end for
check sawTumble, "a failed placement shows a tumble"
check refEquals(view.carried, w.thing("b4")), "after the tumble, it's back in the hand"
check near3(view.handPos, w.hand.pos), "the hand ends up where the world says"

// Picking (the fake ray points straight down at table coordinates x, z).
hit = view.pick({"x": -3.5, "y": -2})
check hit != null and hit.thing.id == "b3", "picking finds the lintel on top of the arch"
hit = view.pick({"x": 5.5, "y": 3.5})
check hit != null and hit.thing.id == "table", "picking empty space finds the table"

// A planned command, with many steps (clearing things off, stacking): the
// display plays them all and ends up matching the world.
w = world.World.make
w.load scenes.byName.winograd
view = display.Display.make(w)
b = brain.Brain.make(w)
reply = b.respond("x1 = 2 blocks [color red]" + char(10) + "x2 = a cube [color green]" + char(10) + "Stack x1, x2")
check reply == "OK.", "the stacking command works: " + reply
playOut view
allMatch = true
for t in w.movableThings
	if not near3(view.drawnPos(t), t.pos) then allMatch = false
end for
check allMatch, "after a planned command, everything is drawn where the world says"

print checks + " checks, " + failures + " failures."
// Exit with a nonzero code if anything failed, so scripts can tell.
exit (failures > 0)
