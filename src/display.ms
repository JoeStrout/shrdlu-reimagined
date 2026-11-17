// display.ms
//
// The 3D view of the world: drawing the table, the objects, and the robot
// arm; animating the arm; letting the user orbit the camera and click on
// things.
//
// The display never decides anything about the world.  The world model
// (world.ms) changes instantly when the robot acts; the display then *catches
// up*, turning each new event in the world's history into a little animation
// of the hand moving, lowering, gripping, and so on.  That's why the display
// keeps its own idea of where each thing is drawn (`shownPos`), which matches
// the world model again once the animations finish.

import "geometry"
import "world"

rl = raylib

//======================================================================
// Appearance
//======================================================================

colors = {
	"red": "#D23C32", "green": "#3C9B46", "blue": "#3A62C8",
	"yellow": "#E6BE2E", "white": "#E8E4DA", "gray": "#9A9A9A",
	"wood": "#A0784B", "floor": "#3A3F47", "metal": "#8C949E",
	"background": "#1E2228", "selection": "#FFF27A",
	"previewOk": "#40FF60", "previewTip": "#FFA020", "previewBlocked": "#FF4040",
	"text": "#E8E8E8", "dimText": "#9AA3AD", "panel": "#00000099"}

colorOf = function(thing)
	if colors.hasIndex(thing.color) then return colors[thing.color]
	return colors.gray
end function

// Animation speeds, in units per second.
travelSpeed = 10    // hand moving across the table
liftSpeed = 7       // hand moving up or down
tumbleTime = 1.1    // seconds for a toppling object to fall

//======================================================================
// Little vector helpers (3D points are [x, y, z] lists).
//======================================================================

toList = function(v)
	if v isa map then return [v.x, v.y, v.z]
	return v
end function

add3 = function(a, b); return [a[0]+b[0], a[1]+b[1], a[2]+b[2]]; end function
sub3 = function(a, b); return [a[0]-b[0], a[1]-b[1], a[2]-b[2]]; end function
lerp3 = function(a, b, t)
	return [a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t, a[2] + (b[2]-a[2])*t]
end function
cross3 = function(a, b)
	return [a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0]]
end function
normalize3 = function(v)
	length = sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
	if length == 0 then return v
	return [v[0]/length, v[1]/length, v[2]/length]
end function
distance3 = function(a, b)
	d = sub3(a, b)
	return sqrt(d[0]*d[0] + d[1]*d[1] + d[2]*d[2])
end function

// Ease in and out: starts slow, speeds up, slows down at the end.
smooth = function(t)
	return t * t * (3 - 2 * t)
end function

//======================================================================
// Models: one unit-sized model per shape, centered on the origin.  Each
// object is drawn by scaling one of these to the object's size.
//======================================================================

models = {}
shader = null

// A pyramid with a 1x1 base, 1 unit tall, centered on the origin.  We build
// it by hand (rather than using a 4-sided cone) so that each face is flat
// and its base is square to the x and z axes.
makePyramidMesh = function
	a = [-0.5, -0.5, -0.5]; b = [0.5, -0.5, -0.5]
	c = [0.5, -0.5, 0.5];   d = [-0.5, -0.5, 0.5]
	apex = [0, 0.5, 0]
	// Each triangle is listed counterclockwise as seen from outside.
	triangles = [[d, c, apex], [c, b, apex], [b, a, apex], [a, d, apex],  // sides
	             [a, b, c], [a, c, d]]                                    // base
	vertices = []; normals = []; texcoords = []
	for tri in triangles
		n = normalize3(cross3(sub3(tri[1], tri[0]), sub3(tri[2], tri[0])))
		for v in tri
			vertices += v
			normals += n
			texcoords += [0, 0]
		end for
	end for
	return rl.MakeMesh(vertices, null, texcoords, normals)
end function

// Load the shader and build the models.  Call once, after the window is open.
setup = function
	outer.shader = rl.LoadShader("assets/shaders/lit.vs", "assets/shaders/lit.fs")
	rl.SetShaderValue shader, rl.GetShaderLocation(shader, "uLightDir"), [0.45, 1.0, 0.7], rl.SHADER_UNIFORM_VEC3

	models.cube = rl.LoadModelFromMesh(rl.GenMeshCube(1, 1, 1))
	models.pyramid = rl.LoadModelFromMesh(makePyramidMesh)
	models.cylinder = rl.LoadModelFromMesh(rl.GenMeshCylinder(0.5, 1, 24))
	// raylib's cylinder sits on the origin; shift it down to center it.
	rl.SetModelTransform models.cylinder, rl.MatrixTranslate(0, -0.5, 0)
	for m in models.values
		rl.SetModelMaterialShader m, 0, shader
	end for
end function

// Draw a lit box with the given center and size.
drawBox = function(center, size, color)
	rl.DrawModelEx models.cube, center, [0, 1, 0], 0, size, color
end function

//======================================================================
// CameraRig: an orbiting camera with limited range, so that the front of
// the table always faces the viewer.  (Words like "behind" and "left of"
// are always meant from the front; see the design note, section 1.2.)
//======================================================================

CameraRig = {}
CameraRig.yaw = 0              // radians; 0 = looking straight from the front
CameraRig.pitch = 0.6          // radians above horizontal
CameraRig.distance = 23
CameraRig.target = [0, 2.5, -0.5]
CameraRig.minYaw = -0.7;    CameraRig.maxYaw = 0.7
CameraRig.minPitch = 0.2;   CameraRig.maxPitch = 1.2
CameraRig.minDistance = 10; CameraRig.maxDistance = 34

CameraRig.camera = function
	cp = cos(self.pitch)
	offset = [self.distance * sin(self.yaw) * cp, self.distance * sin(self.pitch), self.distance * cos(self.yaw) * cp]
	return {"position": add3(self.target, offset), "target": self.target,
	  "up": [0, 1, 0], "fovy": 40, "projection": rl.CAMERA_PERSPECTIVE}
end function

clamp = function(x, lo, hi)
	if x < lo then return lo
	if x > hi then return hi
	return x
end function

// Turn the camera by a mouse movement (in pixels).
CameraRig.orbit = function(dx, dy)
	self.yaw = clamp(self.yaw - dx * 0.006, self.minYaw, self.maxYaw)
	self.pitch = clamp(self.pitch + dy * 0.006, self.minPitch, self.maxPitch)
end function

CameraRig.zoom = function(wheel)
	self.distance = clamp(self.distance - wheel * 1.2, self.minDistance, self.maxDistance)
end function

//======================================================================
// Display: shows one World.
//======================================================================

Display = {}

Display.make = function(theWorld)
	d = new Display
	d.world = theWorld
	d.rig = new CameraRig
	d.shownPos = {}                     // thing id -> where it's drawn
	for t in theWorld.things
		d.shownPos[t.id] = t.pos[:]
	end for
	d.handPos = theWorld.hand.pos[:]    // where the hand is drawn
	d.carried = theWorld.hand.holding   // what's drawn in the hand
	d.tumble = null                     // a falling object, if any
	d.steps = []                        // animation steps waiting to play
	d.nextEvent = theWorld.history.len  // the next history event to animate
	d.selected = null                   // the thing the user clicked on
	d.preview = null                    // a placement to show (see drawPreview)
	d.messages = []                     // recent lines of text to show
	return d
end function

Display.say = function(text)
	self.messages.push text
	if self.messages.len > 6 then self.messages.pull
end function

// Is an animation still playing (or waiting to play)?
Display.isBusy = function
	return self.steps.len > 0 or self.nextEvent < self.world.history.len
end function

//----------------------------------------------------------------------
// Animation.
//
// Each world event becomes a few simple steps, played one after another:
//   "hand"    move the hand smoothly to a point
//   "attach"  the hand grips a thing (it's drawn in the hand from now on)
//   "detach"  the hand lets go of a thing, leaving it at a given position
//   "tumble"  a thing topples off where it was put, and falls
//   "pause"   wait a moment
//----------------------------------------------------------------------

Display.queueEvent = function(event)
	cruise = world.World.cruiseHeight
	if event.action == "moveTo" then
		self.steps.push {"kind": "hand", "to": event.to, "speed": travelSpeed}
	else if event.action == "grasp" then
		t = event.thing; p = event.from
		self.steps.push {"kind": "hand", "to": [p[0], p[1] + t.height, p[2]], "speed": liftSpeed}
		self.steps.push {"kind": "attach", "thing": t}
		self.steps.push {"kind": "hand", "to": [p[0], cruise, p[2]], "speed": liftSpeed}
	else if event.action == "ungrasp" then
		t = event.thing; p = event.to
		self.steps.push {"kind": "hand", "to": [p[0], p[1] + t.height, p[2]], "speed": liftSpeed}
		self.steps.push {"kind": "detach", "thing": t, "pos": p}
		self.steps.push {"kind": "hand", "to": [p[0], cruise, p[2]], "speed": liftSpeed}
	else if event.action == "failedPlace" then
		// Set it down, watch it fall, then (since the world never changed)
		// it's simply back in the hand, which goes back up.
		t = event.thing; pl = event.placement
		p = [pl.x, pl.y, pl.z]
		self.steps.push {"kind": "hand", "to": [p[0], p[1] + t.height, p[2]], "speed": liftSpeed}
		self.steps.push {"kind": "detach", "thing": t, "pos": p}
		self.steps.push {"kind": "tumble", "thing": t, "placement": pl, "duration": tumbleTime}
		self.steps.push {"kind": "pause", "duration": 0.4}
		self.steps.push {"kind": "attach", "thing": t}
		self.steps.push {"kind": "hand", "to": [p[0], cruise, p[2]], "speed": liftSpeed}
	end if
end function

Display.update = function(dt)
	// Turn any new events in the world's history into animation steps.
	while self.nextEvent < self.world.history.len
		self.queueEvent self.world.history[self.nextEvent]
		self.nextEvent += 1
	end while
	if not self.steps then return

	step = self.steps[0]
	if not step.hasIndex("elapsed") then self.startStep step
	step.elapsed += dt
	if step.duration > 0 then f = step.elapsed / step.duration else f = 1
	if f > 1 then f = 1
	self.applyStep step, f
	if f >= 1 then self.steps.pull
end function

Display.startStep = function(step)
	step.elapsed = 0
	if not step.hasIndex("duration") then step.duration = 0
	if step.kind == "hand" then
		step.from = self.handPos[:]
		step.duration = distance3(step.from, step.to) / step.speed
	else if step.kind == "tumble" then
		self.startTumble step
	end if
end function

Display.applyStep = function(step, f)
	if step.kind == "hand" then
		self.handPos = lerp3(step.from, step.to, smooth(f))
	else if step.kind == "attach" then
		self.carried = step.thing
		self.tumble = null
	else if step.kind == "detach" then
		self.carried = null
		self.shownPos[step.thing.id] = step.pos[:]
	else if step.kind == "tumble" then
		self.tumble.f = f
	end if
end function

// Work out how a thing that won't balance should topple.
//
// It tips toward its center of mass, as seen from the middle of whatever was
// holding it up, pivoting about the far edge of its support.  Then it drops
// to the table.  (It's purely for show: we don't check what it might hit on
// the way down, since afterward it goes straight back into the hand.)
Display.startTumble = function(step)
	t = step.thing; pl = step.placement
	com = t.centerOfMassAt(pl.x, pl.z)
	support = pl.supportPoly
	if not support then support = [com]

	// The middle of the support.
	cx = 0; cz = 0
	for p in support
		cx += p[0]; cz += p[1]
	end for
	cx /= support.len; cz /= support.len

	// Which way to tip: from the middle of the support toward the center of
	// mass.  If those are the same spot (say, balanced on a single point),
	// it just tips toward the viewer.
	dir = [com[0] - cx, com[1] - cz]
	length = sqrt(dir[0]*dir[0] + dir[1]*dir[1])
	if length < 0.01 then dir = [0, 1] else dir = [dir[0]/length, dir[1]/length]

	// The pivot: the support's farthest extent in that direction.
	reach = 0
	for p in support
		along = (p[0] - cx) * dir[0] + (p[1] - cz) * dir[1]
		if along > reach then reach = along
	end for
	self.tumble = {"thing": t, "f": 0,
	  "pivot": [cx + dir[0] * reach, pl.y, cz + dir[1] * reach],
	  "axis": [dir[1], 0, -dir[0]],      // horizontal, at right angles to the tipping direction
	  "dropHeight": pl.y,
	  "slide": [dir[0], 0, dir[1]],
	  "restCenter": [pl.x, pl.y + t.height / 2, pl.z]}
end function

//----------------------------------------------------------------------
// Where and how each thing is drawn right now.
//----------------------------------------------------------------------

// The position (center of bottom face) where a thing is drawn.
Display.drawnPos = function(t)
	if refEquals(t, self.carried) then
		return [self.handPos[0], self.handPos[1] - t.height, self.handPos[2]]
	end if
	return self.shownPos[t.id]
end function

// Draw one object (not the table) at the given bottom-center position,
// optionally rotated by `angle` degrees about `axis`.
Display.drawThing = function(t, pos, axis=null, angle=0, center=null)
	if t.shape == "box" then
		// The box is drawn as its floor and four walls.
		for solid in t.solidsAt(pos[0], pos[1], pos[2])
			xs = []; zs = []
			for p in solid.poly
				xs.push p[0]; zs.push p[1]
			end for
			xs.sort; zs.sort
			h = solid.top - solid.bottom
			drawBox [(xs[0] + xs[-1])/2, solid.bottom + h/2, (zs[0] + zs[-1])/2],
			  [xs[-1] - xs[0], h, zs[-1] - zs[0]], colorOf(t)
		end for
		return
	end if
	model = models.cube
	if models.hasIndex(t.shape) then model = models[t.shape]
	if axis == null then axis = [0, 1, 0]
	if center == null then center = [pos[0], pos[1] + t.height / 2, pos[2]]
	rl.DrawModelEx model, center, axis, angle, t.size, colorOf(t)
end function

// Draw a thing that's in the middle of toppling over.
Display.drawTumble = function
	tb = self.tumble
	f = tb.f
	if f < 0.55 then
		// Tipping: rotate about the pivot, slowly at first, then faster.
		g = f / 0.55
		angle = 90 * g * g
		drop = 0
	else
		// Falling: drop to the table, sliding outward a little.
		angle = 90
		g = (f - 0.55) / 0.45
		drop = tb.dropHeight * g * g
	end if
	radians = angle * pi / 180
	offset = toList(rl.Vector3RotateByAxisAngle(sub3(tb.restCenter, tb.pivot), tb.axis, radians))
	center = add3(tb.pivot, offset)
	center[1] -= drop
	center = add3(center, [tb.slide[0] * drop * 0.3, 0, tb.slide[2] * drop * 0.3])
	self.drawThing tb.thing, null, tb.axis, angle, center
end function

//----------------------------------------------------------------------
// The table, and the robot arm (a gantry mounted on rails along the sides
// of the table, carrying the hand).
//----------------------------------------------------------------------

Display.drawTable = function
	t = self.world.table
	w = t.width; d = t.depth
	drawBox [0, -0.15, 0], [w, 0.3, d], colors.wood
	for sx in [-1, 1]
		for sz in [-1, 1]
			drawBox [sx * (w/2 - 0.5), -1.65, sz * (d/2 - 0.5)], [0.4, 2.7, 0.4], colors.wood
		end for
	end for
	drawBox [0, -3.05, 0], [60, 0.1, 40], colors.floor
end function

Display.drawArm = function
	t = self.world.table
	w = t.width; d = t.depth
	h = self.handPos
	railY = world.World.cruiseHeight + 2.5
	// Two rails, one along each side of the table.
	for sx in [-1, 1]
		drawBox [sx * (w/2 + 0.6), railY, 0], [0.3, 0.3, d + 1.5], colors.metal
		drawBox [sx * (w/2 + 0.6), railY / 2 - 1.5, -d/2 - 0.6], [0.3, railY + 3, 0.3], colors.metal  // back posts
	end for
	// The bridge across the rails, which slides front to back.
	drawBox [0, railY, h[2]], [w + 1.5, 0.35, 0.45], colors.metal
	// The carriage on the bridge, which slides left to right, and the
	// vertical rod down to the hand.
	drawBox [h[0], railY - 0.3, h[2]], [0.7, 0.4, 0.7], colors.metal
	rodTop = railY - 0.5
	rodBottom = h[1] + 0.35
	drawBox [h[0], (rodTop + rodBottom) / 2, h[2]], [0.15, rodTop - rodBottom, 0.15], colors.metal
	// The hand: a palm and two fingers, which close on whatever it holds.
	gap = 0.9
	if self.carried then gap = self.carried.width + 0.1
	drawBox [h[0], h[1] + 0.175, h[2]], [gap + 0.35, 0.35, 0.55], "#5A626C"
	for side in [-1, 1]
		drawBox [h[0] + side * (gap/2 + 0.06), h[1] - 0.3, h[2]], [0.12, 0.6, 0.45], "#5A626C"
	end for
end function

//----------------------------------------------------------------------
// Picking: which thing is under the mouse?
//----------------------------------------------------------------------

// The axis-aligned box a thing currently occupies on screen.
Display.boundsOf = function(t)
	p = self.drawnPos(t)
	return {"min": [p[0] - t.width/2, p[1], p[2] - t.depth/2],
	        "max": [p[0] + t.width/2, p[1] + t.height, p[2] + t.depth/2]}
end function

// Return {"thing": t, "point": [x,y,z]} for the nearest thing under the
// mouse (the table counts), or null if there's nothing there.
Display.pick = function(mousePos)
	ray = rl.GetScreenToWorldRay(mousePos, self.rig.camera)
	best = null
	bestDistance = 999999
	for t in self.world.things
		if refEquals(t, self.carried) then continue
		if t.shape == "table" then
			box = {"min": [-t.width/2, -0.3, -t.depth/2], "max": [t.width/2, 0, t.depth/2]}
		else
			box = self.boundsOf(t)
		end if
		hit = rl.GetRayCollisionBox(ray, box)
		if hit.hit and hit.distance < bestDistance then
			bestDistance = hit.distance
			best = {"thing": t, "point": toList(hit.point)}
		end if
	end for
	return best
end function

//----------------------------------------------------------------------
// Placement preview: while the hand holds something, show where it would
// land, the polygon that would support it, and its center of mass.
// Green means it would stay; orange means it would topple; red means it
// can't go there at all.
//----------------------------------------------------------------------

Display.drawPreview = function
	pl = self.preview
	if pl == null or self.carried == null then return
	t = self.carried
	if pl.ok then
		color = colors.previewOk
	else if pl.reason == "unbalanced" or pl.reason == "noArea" then
		color = colors.previewTip
	else
		color = colors.previewBlocked
	end if
	rl.DrawCubeWiresV [pl.x, pl.y + t.height/2, pl.z], t.size, color
	y = pl.y + 0.03
	poly = pl.supportPoly
	for i in poly.indexes
		a = poly[i]; b = poly[(i + 1) % poly.len]
		rl.DrawLine3D [a[0], y, a[1]], [b[0], y, b[1]], color
	end for
	com = t.centerOfMassAt(pl.x, pl.z)
	rl.DrawSphere [com[0], y, com[1]], 0.08, color
end function

//----------------------------------------------------------------------
// Drawing everything.
//----------------------------------------------------------------------

Display.draw = function
	rl.ClearBackground colors.background
	rl.BeginMode3D self.rig.camera
	self.drawTable
	for t in self.world.things
		if t.shape == "table" then continue
		if self.tumble and refEquals(t, self.tumble.thing) then continue
		self.drawThing t, self.drawnPos(t)
	end for
	if self.tumble then self.drawTumble
	self.drawArm
	if self.selected then
		b = self.boundsOf(self.selected)
		center = lerp3(b.min, b.max, 0.5)
		size = add3(sub3(b.max, b.min), [0.08, 0.08, 0.08])
		rl.DrawCubeWiresV center, size, colors.selection
	end if
	self.drawPreview
	rl.EndMode3D
	self.drawOverlay
end function

// Text drawn over the 3D view: what's selected, recent messages, and help.
Display.drawOverlay = function
	sw = rl.GetScreenWidth
	sh = rl.GetScreenHeight
	rl.DrawText "SHRDLU Reimagined", 16, 12, 24, colors.text

	// Recent messages, bottom left.
	y = sh - 24 * self.messages.len - 12
	for m in self.messages
		rl.DrawText m, 16, y, 20, colors.text
		y += 24
	end for

	// About the selected thing, top right.
	if self.selected then
		t = self.selected
		lines = [t.description + "  (" + t.id + ")",
		  "size " + t.size.join(" x "),
		  "at " + t.pos.join(", ")]
		on = []
		for s in t.supporters
			on.push s.id
		end for
		if refEquals(t, self.world.hand.holding) then
			lines.push "in the hand"
		else
			lines.push "on " + on.join(", ")
		end if
		above = []
		for s in self.world.thingsOn(t)
			above.push s.id
		end for
		if above then lines.push "supports " + above.join(", ")
		x = sw - 300
		rl.DrawRectangle x - 12, 8, 300, 24 * lines.len + 12, colors.panel
		y = 14
		for line in lines
			rl.DrawText line, x, y, 20, colors.text
			y += 24
		end for
	end if

	// Help, top left under the title.
	help = ["Click: select   P: pick up   Click (holding): put down",
	  "Shift-click: put down even if it won't balance",
	  "Drag or right-drag: turn view   Wheel: zoom   1/2: scene"]
	y = 42
	for line in help
		rl.DrawText line, 16, y, 16, colors.dimText
		y += 20
	end for
end function
