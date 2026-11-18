// main.ms
//
// SHRDLU Reimagined: main program.
//
// The world and its display, with the console (console.ms) for talking to
// the robot in English (or in ICL, its internal language).  You can also
// operate the hand directly with the mouse,
// to try out the world model, the stability rules, and the animation.
//
// Run from the repo root:   ./raylib-miniscript src/main.ms

import "geometry"
import "world"
import "scenes"
import "display"
import "brain"
import "console"
import "sessionLog"
import "uiText"

rl = raylib

// Open the window.  The HIGHDPI flag lets Retina screens render at full
// resolution while we keep working in ordinary screen points.  (Without it,
// on a Mac's built-in display we saw only the lower-left quarter of the
// scene.)  The MSAA flag smooths jagged edges.  Flags must be set before the
// window opens, so we open it at the right size instead of resizing later.
if not rl.IsWindowReady then
	rl.SetConfigFlags rl.FLAG_WINDOW_HIGHDPI + rl.FLAG_MSAA_4X_HINT
	rl.InitWindow 1280, 800, "SHRDLU Reimagined"
end if
rl.SetWindowTitle "SHRDLU Reimagined"
rl.SetTargetFPS 60
rl.SetExitKey rl.KEY_NULL    // Escape clears the console's line instead
display.setup
uiText.load "assets/DejaVuSans.ttf"

// The current world, the display showing it, and the console for talking
// to the robot.  (A new scene gets a new world and a new brain; the console
// and its transcript carry on.)
theWorld = null
view = null
con = console.Console.make
// On the desktop, keep a log of the session (see sessionLog.ms).
con.log = sessionLog.SessionLog.make

// The layout: the console down the left side, a third of the window
// wide, and the 3D view in the rest.
consoleWidth = function
	return round(rl.GetScreenWidth / 3)
end function

loadScene = function(name)
	globals.theWorld = world.World.make
	problems = theWorld.load(scenes.byName[name])
	globals.view = display.Display.make(theWorld)
	con.brain = brain.Brain.make(theWorld)
	con.say "Scene: " + name
	for p in problems
		con.say "Problem loading scene: " + p
	end for
end function

// "/scene name" in the console.
sceneCommand = function(c, name)
	if not scenes.byName.hasIndex(name) then
		c.say "Scenes: " + scenes.names.join(", ")
		return
	end if
	if view.isBusy then
		c.say "(Wait until the robot has finished.)"
		return
	end if
	loadScene name
end function
con.addCommand "scene", @sceneCommand, "/scene name: load a scene (" + scenes.names.join(", ") + ")"

con.say "Welcome!  Talk to the robot below, or type /help for examples."
if con.log then con.say "(This session is being logged to " + con.log.path + ".)"
loadScene scenes.names[0]

//----------------------------------------------------------------------
// Operating the hand directly with the mouse.  Each action is a new "turn",
// just as each sentence is.
//----------------------------------------------------------------------

// Put down whatever is held, centered over the given point.  With force,
// do it even if it won't balance (it will fall off, and come back to the hand).
putDownAt = function(point, force)
	x = geometry.snap(point[0])
	z = geometry.snap(point[2])
	theWorld.beginTurn
	problem = theWorld.putAt(x, z, force)
	if problem then con.say problem, "robot" else con.say "OK.", "robot"
end function

// What a click means depends on whether the hand is holding something.
handleClick = function(mousePos)
	hit = view.pick(mousePos)
	if theWorld.hand.holding then
		if hit then putDownAt hit.point, rl.IsKeyDown(rl.KEY_LEFT_SHIFT) or rl.IsKeyDown(rl.KEY_RIGHT_SHIFT)
	else if hit and hit.thing.movable then
		view.selected = hit.thing
	else
		view.selected = null
	end if
end function

//----------------------------------------------------------------------
// The main loop.
//----------------------------------------------------------------------

pressPos = null     // where the left mouse button went down
dragging = false    // whether that press has turned into a drag

while not rl.WindowShouldClose
	view.update rl.GetFrameTime

	// The console: typing always goes there.  The brain needs to know what's
	// selected, for "this".
	con.brain.selected = view.selected
	con.update view.isBusy

	// Mouse: a left click selects or places; a drag (left or right) turns the
	// view.  Over the console, the mouse is the console's.  (Mouse controls
	// are explained on the web page around the app.)
	mouse = rl.GetMousePosition
	delta = rl.GetMouseDelta
	overConsole = con.contains(mouse)
	if rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT) and not overConsole then
		pressPos = mouse
		dragging = false
	end if
	if rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT) and pressPos then
		if abs(mouse.x - pressPos.x) + abs(mouse.y - pressPos.y) > 5 then dragging = true
		if dragging then view.rig.orbit delta.x, delta.y
	end if
	if rl.IsMouseButtonReleased(rl.MOUSE_BUTTON_LEFT) then
		if pressPos and not dragging and not view.isBusy then handleClick mouse
		pressPos = null
	end if
	if rl.IsMouseButtonDown(rl.MOUSE_BUTTON_RIGHT) and not overConsole then view.rig.orbit delta.x, delta.y
	wheel = rl.GetMouseWheelMove
	if overConsole then con.scrollBy round(wheel * 3) else view.rig.zoom wheel

	// While holding something, preview where it would land under the mouse.
	view.preview = null
	if theWorld.hand.holding and not view.isBusy and not dragging and not overConsole then
		hit = view.pick(mouse)
		if hit then
			view.preview = theWorld.placementFor(theWorld.hand.holding,
			  geometry.snap(hit.point[0]), geometry.snap(hit.point[2]))
		end if
	end if

	rl.BeginDrawing
	rl.ClearBackground "#000000"
	cw = consoleWidth
	sh = rl.GetScreenHeight
	con.draw 0, 0, cw, sh
	view.draw cw, 0, rl.GetScreenWidth - cw, sh
	rl.EndDrawing
	yield
end while
