// fakeRaylib.ms
//
// A stand-in for the `raylib` module, for running display code from the
// plain command line (with no window).  Drawing calls just count themselves;
// the few calls that compute something do it for real, simply.
//
// Use it by assigning it to globals.raylib before importing display:
//   import "fakeRaylib"
//   globals.raylib = fakeRaylib.module

module = {}
module.calls = {}   // function name -> number of times called

count = function(name)
	if not module.calls.hasIndex(name) then module.calls[name] = 0
	module.calls[name] += 1
end function

module.CAMERA_PERSPECTIVE = 0
module.SHADER_UNIFORM_VEC3 = 2

module.LoadShader = function(vs, fs); count "LoadShader"; return {"shader": 1}; end function
module.GetShaderLocation = function(shader, name); return 0; end function
module.SetShaderValue = function(shader, loc, value, uniformType); count "SetShaderValue"; end function
module.GenMeshCube = function(w, h, d); return {"mesh": "cube"}; end function
module.GenMeshCylinder = function(r, h, slices); return {"mesh": "cylinder"}; end function
module.MakeMesh = function(vertices, indices=null, texcoords=null, normals=null)
	if vertices.len != normals.len then print "MakeMesh: vertex/normal count mismatch"
	if vertices.len / 3 != texcoords.len / 2 then print "MakeMesh: texcoord count mismatch"
	return {"mesh": "made", "vertexCount": vertices.len / 3}
end function
module.LoadModelFromMesh = function(mesh); return {"model": mesh}; end function
module.SetModelTransform = function(model, m); end function
module.SetModelMaterialShader = function(model, index, shader); end function
module.MatrixTranslate = function(x, y, z); return [x, y, z]; end function

module.ClearBackground = function(color); count "ClearBackground"; end function
module.BeginMode3D = function(camera); count "BeginMode3D"; end function
module.EndMode3D = function; count "EndMode3D"; end function
module.DrawModelEx = function(model, pos, axis, angle, scale, tint)
	count "DrawModelEx"
	if pos.len != 3 or scale.len != 3 or axis.len != 3 then print "DrawModelEx: bad vector"
end function
module.DrawCubeWiresV = function(pos, size, color); count "DrawCubeWiresV"; end function
module.DrawLine3D = function(a, b, color); count "DrawLine3D"; end function
module.DrawSphere = function(pos, r, color); count "DrawSphere"; end function
module.DrawText = function(text, x, y, size, color); count "DrawText"; end function
module.DrawRectangle = function(x, y, w, h, color); count "DrawRectangle"; end function
module.GetScreenWidth = function; return 1280; end function
module.GetScreenHeight = function; return 800; end function

// Rotate v about a unit axis by an angle in radians (Rodrigues' formula).
module.Vector3RotateByAxisAngle = function(v, axis, angle)
	c = cos(angle); s = sin(angle)
	k = axis
	kv = k[0]*v[0] + k[1]*v[1] + k[2]*v[2]
	kxv = [k[1]*v[2] - k[2]*v[1], k[2]*v[0] - k[0]*v[2], k[0]*v[1] - k[1]*v[0]]
	result = []
	for i in range(0, 2)
		result.push v[i]*c + kxv[i]*s + k[i]*kv*(1 - c)
	end for
	return {"x": result[0], "y": result[1], "z": result[2]}
end function

// Picking: a ray straight down from above the given screen "position",
// which (in this fake) is interpreted as table coordinates {x, y=z}.
module.GetScreenToWorldRay = function(pos, camera)
	return {"position": [pos.x, 50, pos.y], "direction": [0, -1, 0]}
end function
module.GetRayCollisionBox = function(ray, box)
	p = ray.position
	inside = p[0] >= box.min[0] and p[0] <= box.max[0] and p[2] >= box.min[2] and p[2] <= box.max[2]
	if not inside then return {"hit": false, "distance": 0, "point": [0,0,0]}
	return {"hit": true, "distance": p[1] - box.max[1], "point": {"x": p[0], "y": box.max[1], "z": p[2]}}
end function

//----------------------------------------------------------------------
// Text and keyboard, for testing text input.  A test "types" by filling
// typed (characters) and setting keysPressed / keysDown (key codes), then
// calls the widget's update; endFrame clears what was pressed.
//----------------------------------------------------------------------

keyNames = ["LEFT_ALT", "RIGHT_ALT", "LEFT_CONTROL", "RIGHT_CONTROL", "LEFT_SUPER",
  "RIGHT_SUPER", "LEFT_SHIFT", "RIGHT_SHIFT", "A", "E", "K", "U", "V", "LEFT", "RIGHT",
  "UP", "DOWN", "HOME", "END", "BACKSPACE", "DELETE", "ESCAPE", "ENTER", "KP_ENTER",
  "PAGE_UP", "PAGE_DOWN"]
for i in keyNames.indexes
	module["KEY_" + keyNames[i]] = 1000 + i
end for

module.typed = []           // characters waiting to be read
module.keysPressed = []     // keys pressed this frame
module.keysDown = []        // keys held down
module.clipboard = ""
module.time = 0

module.type = function(s)
	for c in s
		module.typed.push c.code
	end for
end function
module.press = function(keyName)
	module.keysPressed.push module["KEY_" + keyName]
end function
module.endFrame = function
	module.typed = []
	module.keysPressed = []
end function

module.GetCharPressed = function
	if not module.typed then return 0
	return module.typed.pull
end function
module.IsKeyPressed = function(key); return module.keysPressed.indexOf(key) != null; end function
module.IsKeyPressedRepeat = function(key); return false; end function
module.IsKeyDown = function(key); return module.keysDown.indexOf(key) != null; end function
module.GetClipboardText = function; return module.clipboard; end function
module.GetTime = function; return module.time; end function
// The default font is about half as wide as it is tall.
module.MeasureText = function(text, size); return floor(text.len * size / 2); end function
module.DrawRectangleLines = function(x, y, w, h, color); count "DrawRectangleLines"; end function
module.BeginScissorMode = function(x, y, w, h); count "BeginScissorMode"; end function
module.EndScissorMode = function; count "EndScissorMode"; end function
