// geometry.ms
//
// Flat (two-dimensional) geometry on the table top.
//
// Everything in the blocks world stands upright, so most questions about
// where things fit and what holds them up are really questions about shapes
// in the x/z plane, seen from above: footprints, top surfaces, and the
// "support polygon" that decides whether something balances.
//
// Points are two-element lists [x, z].  Polygons are lists of points, always
// convex, listed counterclockwise as seen from above.  (With x to the right
// and z toward the viewer, that ordering gives a positive area by the
// shoelace formula below.)
//
// This module knows nothing about blocks or raylib; it's plain geometry.

// Tolerance for floating-point comparisons.  Positions and sizes are on a
// 0.25-unit grid, so anything smaller than this is just rounding noise.
epsilon = 0.0001

// The spacing of the grid that all positions snap to.
gridSize = 0.25

// Round a coordinate to the nearest grid point.
snap = function(v)
	return round(v / gridSize) * gridSize
end function

// The cross product of the vectors o→a and o→b.  Positive means b lies to the
// left of the line from o through a (a counterclockwise turn), negative means
// to the right, and zero means the three points are in a line.
cross = function(o, a, b)
	return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
end function

// Squared distance between two points (cheaper than the true distance, and
// fine for comparing which of two points is farther).
dist2 = function(a, b)
	dx = a[0] - b[0]
	dz = a[1] - b[1]
	return dx*dx + dz*dz
end function

// Are two points the same, within tolerance?
samePoint = function(a, b)
	return abs(a[0] - b[0]) < epsilon and abs(a[1] - b[1]) < epsilon
end function

// A rectangle centered at (cx, cz), w wide (in x) and d deep (in z).
rectPoly = function(cx, cz, w, d)
	x0 = cx - w/2
	x1 = cx + w/2
	z0 = cz - d/2
	z1 = cz + d/2
	return [[x0, z0], [x1, z0], [x1, z1], [x0, z1]]
end function

// A regular polygon approximating a circle of radius r centered at (cx, cz).
// Sixteen sides is plenty for deciding what a cylinder rests on.
circlePoly = function(cx, cz, r, sides=16)
	poly = []
	for i in range(0, sides - 1)
		angle = 2 * pi * i / sides
		poly.push [cx + r * cos(angle), cz + r * sin(angle)]
	end for
	return poly
end function

// The area of a polygon, by the "shoelace" formula.  (For a polygon listed
// clockwise the raw sum is negative, so we return its absolute value.)
polyArea = function(poly)
	if poly.len < 3 then return 0
	sum = 0
	for i in poly.indexes
		a = poly[i]
		b = poly[(i + 1) % poly.len]
		sum += a[0] * b[1] - b[0] * a[1]
	end for
	return abs(sum) / 2
end function

// Where the segment p1→p2 crosses the (infinite) line through a and b.
// Only called when p1 and p2 are on opposite sides of that line.
lineIntersection = function(p1, p2, a, b)
	d1 = cross(a, b, p1)
	d2 = cross(a, b, p2)
	t = d1 / (d1 - d2)
	return [p1[0] + t * (p2[0] - p1[0]), p1[1] + t * (p2[1] - p1[1])]
end function

// Clip one polygon to another (the Sutherland-Hodgman algorithm), returning
// the region they have in common.  The clipping polygon must be convex.
//
// The idea: each edge of the clipping polygon defines a line, and the inside
// of the clipping polygon is to the left of every one of those lines.  So we
// trim the subject polygon by one line at a time, keeping only what is on the
// left, and adding new corners wherever an edge of the subject crosses the line.
clipPolygon = function(subject, clipper)
	result = subject[:]
	for i in clipper.indexes
		if result.len == 0 then return result
		a = clipper[i]
		b = clipper[(i + 1) % clipper.len]
		previousResult = result
		result = []
		for j in previousResult.indexes
			current = previousResult[j]
			previous = previousResult[j - 1]    // (index -1 wraps around to the last point)
			currentInside = cross(a, b, current) >= -epsilon
			previousInside = cross(a, b, previous) >= -epsilon
			if currentInside then
				if not previousInside then result.push lineIntersection(previous, current, a, b)
				result.push current
			else if previousInside then
				result.push lineIntersection(previous, current, a, b)
			end if
		end for
	end for
	return result
end function

// Do two polygons overlap by more than just touching along an edge?
polysOverlap = function(a, b)
	return polyArea(clipPolygon(a, b)) > epsilon
end function

// The signed distance from point p to the line through a and b: positive on
// the left (inside, for a counterclockwise polygon), negative on the right.
signedDistance = function(p, a, b)
	length = sqrt(dist2(a, b))
	if length < epsilon then return 0
	return cross(a, b, p) / length
end function

// Is point p inside a convex polygon?  With margin = 0, a point exactly on
// the edge counts as inside.  A positive margin requires the point to be at
// least that far inside every edge; a negative margin is more forgiving.
pointInPoly = function(p, poly, margin=0)
	if poly.len < 3 then return false
	for i in poly.indexes
		if signedDistance(p, poly[i], poly[(i + 1) % poly.len]) < margin - epsilon then return false
	end for
	return true
end function

// Is every corner of polygon `part` inside polygon `container`?  (For convex
// polygons, that means all of `part` is inside.)
polyInside = function(part, container)
	for p in part
		if not pointInPoly(p, container) then return false
	end for
	return true
end function

// Remove duplicate points from a list.
uniquePoints = function(points)
	result = []
	for p in points
		isNew = true
		for q in result
			if samePoint(p, q) then
				isNew = false
				break
			end if
		end for
		if isNew then result.push p
	end for
	return result
end function

// The convex hull of a set of points: the smallest convex polygon containing
// them all.  Think of stretching a rubber band around pins at each point.
//
// This uses "gift wrapping" (the Jarvis march), which is easy to follow:
// start at the leftmost point, then repeatedly find the next point such that
// every other point lies to its left, until we're back at the start.  It's
// slow for thousands of points, but we only ever have a few dozen.
//
// The result is counterclockwise.  Points lying along an edge are left out.
// If all the points lie on one line, the "hull" is just its two end points
// (a polygon with no area), and a single point gives just that point.
convexHull = function(points)
	pts = uniquePoints(points)
	if pts.len < 3 then return pts

	// Start at the leftmost point (smallest x, then smallest z).
	start = pts[0]
	for p in pts
		if p[0] < start[0] - epsilon or (abs(p[0] - start[0]) < epsilon and p[1] < start[1]) then start = p
	end for

	hull = []
	current = start
	while true
		hull.push current
		// Find the point `next` such that no point lies to the right of the
		// line current→next.  If several are in line, take the farthest.
		next = null
		for candidate in pts
			if samePoint(candidate, current) then continue
			if next == null then
				next = candidate
				continue
			end if
			turn = cross(current, next, candidate)
			if turn < -epsilon then
				next = candidate      // candidate is to the right: it's further "out"
			else if abs(turn) <= epsilon and dist2(current, candidate) > dist2(current, next) then
				next = candidate      // in line, but farther away
			end if
		end for
		current = next
		if samePoint(current, start) or hull.len > pts.len then break
	end while
	return hull
end function
