// screenshots.ms
//
// Renders the display in a few situations and saves a screenshot of each,
// so the look of the scene can be checked without clicking around.
// Run from the repo root:
//
//   MS_IMPORT_PATH=src ./raylib-miniscript tests/screenshots.ms [outputDir]
//
// It closes the window and exits when done.

import "geometry"
import "world"
import "scenes"
import "display"

rl = raylib
// (Same window setup as main.ms; see the comment there.)
if not rl.IsWindowReady then
	rl.SetConfigFlags rl.FLAG_WINDOW_HIGHDPI + rl.FLAG_MSAA_4X_HINT
	rl.InitWindow 1280, 800, "SHRDLU Reimagined: screenshots"
end if
rl.SetTargetFPS 60
display.setup

outDir = "."
if shellArgs.len > 1 then outDir = shellArgs[1]

// Save the current screen as a PNG.
//
// On a HiDPI (Retina) screen, raylib's TakeScreenshot applies the scale
// twice: the file comes out twice as big as it should, with the real
// picture in its lower-left quarter.  So we crop it back to the render size.
save = function(name)
	path = outDir + "/" + name + ".png"
	rl.TakeScreenshot path
	img = rl.LoadImage(path)
	w = rl.GetRenderWidth
	h = rl.GetRenderHeight
	if img and img.width > w then
		rl.ImageCrop img, [0, img.height - h, w, h]
		rl.ExportImage img, path
	end if
	if img then rl.UnloadImage img
	print "saved " + name
end function

// Run the display until its animations finish (or for at least `minFrames`),
// then save a screenshot.
shoot = function(view, name, minFrames=10)
	frames = 0
	while frames < minFrames or view.isBusy
		view.update 1/30
		rl.BeginDrawing
		view.draw
		rl.EndDrawing
		yield
		frames += 1
		if frames > 3000 then break
	end while
	save name
end function

// Like shoot, but stop partway through a toppling animation, once the
// falling object is the given fraction of the way through its fall.
shootTumble = function(view, name, fraction)
	for i in range(1, 3000)
		view.update 1/30
		rl.BeginDrawing
		view.draw
		rl.EndDrawing
		yield
		if view.tumble and view.tumble.f >= fraction then break
	end for
	save name
end function

for name in scenes.names
	w = world.World.make
	w.load scenes.byName[name]
	shoot display.Display.make(w), "scene-" + name
end for

// Playground: build an arch, and show a placement preview.
w = world.World.make
w.load scenes.byName.playground
view = display.Display.make(w)
w.pickUp w.thing("b3")
w.putAt -3.5, -2
w.pickUp w.thing("b4")
view.selected = w.thing("b3")
shoot view, "arch"
view.preview = w.placementFor(w.hand.holding, -3.5, -2)
shoot view, "preview-on-arch", 2
// A forced placement that falls: on one pyramid tip.
w.putAt 0.75, -2, true
shootTumble view, "falling-1", 0.3
shootTumble view, "falling-2", 0.7
shoot view, "after-fall"

rl.CloseWindow
exit
