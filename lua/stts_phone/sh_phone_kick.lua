--[[---------------------------------------------------------------------------
	ZPhone: "Litvin" - keepy-uppy with the phone (Q menu -> Phone -> Litvin,
	console: stts_phone_kick)

	the player looks down and stands on the right leg, the left leg goes up a bit
	(bent, IK) and follows the mouse: left / right = sideways, up / down = height,
	W / S = closer / further. the left hand holds the phone glass up on the palm
	over the foot. RMB = the hand dips and flicks it off the palm, then goes back
	down to the side (the arm balances there while you juggle). the phone falls (a
	rigid body: the box of THIS phone model with its mass spread, spin, bounces,
	friction) onto the top of the foot / the shin / the floor. a quick move of the
	foot up throws it up again (the foot is a moving plate, the hit is an impulse at
	the contact point, the toe goes up on a flick so it pops toward the chest).
	slow motion while the phone is in the air (stronger right before the foot).
	fix56/57: RMB again (the phone in the air) = the left hand comes out (IK, the
	palm open) and the MOUSE moves it instead of the foot, the same way: left / right
	= sideways, up / down = height, W / S = closer / further (the foot stays where it
	is). the phone touches the hand = caught, the animation ends and you are back in
	the normal pose. RMB once more = the hand goes back down, the mouse has the foot. every kick
	that keeps it up counts (One. Two. ... like the Fury-13 kill counter of Z-City,
	white). on the floor = the phone stays there (it is dropped as a real physics
	object with its pose and speed). R = stop (in the air: the foot goes down).

	client: simulation, input, camera, legs (Z-City TPIK, hg.MainTPIKFunction) and
	        the left hand (SWEP:SetHandPos), slow motion
	server: validation, movement lock (NW2 "Kick" on the weapon), the drop, relays
	        the pose stream (20 / s) to the players around (same legs, hand, phone)
	included by weapons/weapon_stts_phone.lua (SWEP is the phone weapon table)
---------------------------------------------------------------------------]]
local SWEP = SWEP
STTS = STTS or {}
local KK = STTS.PhoneKick or {}
STTS.PhoneKick = KK

local sqrt, abs, min, max, sin, cos, exp, rad, deg, floor, ceil = math.sqrt, math.abs, math.min, math.max, math.sin, math.cos, math.exp, math.rad, math.deg, math.floor, math.ceil
local function Clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function Smooth(x) x = Clamp(x, 0, 1) return x * x * (3 - 2 * x) end
-- smootherstep: also no jerk at the ends (starts / stops softer than Smooth)
local function Smooth5(x) x = Clamp(x, 0, 1) return x * x * x * (x * (x * 6 - 15) + 10) end
KK.Clamp, KK.Smooth, KK.Smooth5 = Clamp, Smooth, Smooth5

local PH_LIFT, PH_READY, PH_TOSS, PH_AIR, PH_GROUND, PH_CAUGHT, PH_OUT = 1, 2, 3, 4, 5, 6, 7
KK.PH = {LIFT = 1, READY = 2, TOSS = 3, AIR = 4, GROUND = 5, CAUGHT = 6, OUT = 7}
-- contact surfaces
local K_PLATE, K_SHIN, K_THIGH, K_TORSO, K_RLEG, K_GND = 1, 2, 3, 4, 5, 6
local NKIND = 6

local C = {
	HZ = 300, MAXSUB = 16, G = 600,              -- simulation substeps / s, gravity (sv_gravity on start)
	LIFT = 0.55, OUT = 0.55, HOLD = 0.45, ATTACH = 0.08,
	FOOT_HZ = 5.2, FOOT_ZETA = 0.82, FOOT_VMAX = 300, FOOT_FWD = 22, FOOT_SENS = 0.04,
	FX0 = 6, FX1 = 23, FY0 = -7, FY1 = 8, FZ0 = 8, FZ1 = 31,   -- where the foot can go (x, y from the hip, z)
	DEF_X = 17, DEF_Y = 0.6, DEF_Z = 10,
	DROP_FWD = 2.5, DROP_DZ = 16,                  -- the hand drops it this far ahead of the plate centre (clear of the knee), under the eyes
	OUT_DEG = 8,                                  -- the left foot points a little outward
	PITCH0 = -1, PITCH_K = 0.07, PITCH_LO = -8, PITCH_HI = 20, PITCH_RATE = 18,
	PLATE_FWD = 0.9, PLATE_HL = 2.4, PLATE_HW = 2.1, PLATE_HT = 1.6, PLATE_UP = -0.2,
	SHIN_R = 2.0, THIGH_R = 2.6, TORSO_R = 6.2, RLEG_R = 2.8,
	E_PLATE = 0.32, E_SHIN = 0.25, E_BODY = 0.15, E_GND = 0.28,   -- restitution
	MU_PLATE = 0.65, MU_GND = 0.55, MU_CAP = 0.4,                 -- friction
	REST_V = 18, ITER = 4, ITER_HIT = 12,
	SOFT = 0.85, SOFT_V0 = 20, SOFT_V1 = 120,      -- a soft shoe: a hard hit acts closer to the centre (less spin)
	SPIN_DAMP = 0.005,                            -- ... and the shoe soaks up spin (per unit of impulse)
	KICK_FV = 35, KICK_PV = 70, KICK_CD = 0.25,
	CAM_P = 62, CAM_FOLLOW = 0.45, CAM_RATE = 7, CAM_YAW = 22,
	BAL_SIDE = 1.6, BAL_DOWN = 0.6,
	REL_T = 0.19,                                 -- the palm lets go (s after RMB)
	REST_AT = 0.04, REST_T = 0.46,                -- after the release the arm goes back down to the side (delay, time)
	SH_X = 1, SH_Y = 7.5, SH_DZ = 8, REACH_R = 23, -- the left shoulder (under the eyes), how far the hand gets from it
	REACH_X0 = 5, REACH_MIN = 0.16,               -- not into the chest, no catch right after the drop
	HAND_SENS = 1.5, HAND_FWD = 26,               -- the hand on the mouse: x the sensitivity of the foot, W S units / s
	TOUCH_R = 6,                                  -- the phone this close to the palm = it touches the hand
	HAND_W = 22, HAND_W_TOSS = 44, HAND_W_REACH = 30, -- the hand follows its target (critically damped spring, rad / s)
	SEND = 0.05, INTERP = 0.1,
}
KK.C = C
KK.DefMeas = {hx = 0, hy = 3.9, hz = 37.5, l1 = 17.6, l2 = 17.2, lf = 6, ax = 1, ay = 4.2, az = 3.6, fp = -25}

local OUTC, OUTS = cos(rad(C.OUT_DEG)), sin(rad(C.OUT_DEG))

--[[ two-bone leg: hip -> knee -> ankle. the knee bends toward the pole.
     numbers only (local or world), returns knee xyz + the reachable ankle xyz ]]
function KK.Knee(hx, hy, hz, ax, ay, az, l1, l2, px, py, pz)
	local dx, dy, dz = ax - hx, ay - hy, az - hz
	local d = sqrt(dx * dx + dy * dy + dz * dz)
	if d < 1e-4 then dx, dy, dz, d = 0, 0, -1, 1 end
	local ux, uy, uz = dx / d, dy / d, dz / d
	d = Clamp(d, abs(l1 - l2) + 0.5, (l1 + l2) * 0.995)
	local a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
	local hh = sqrt(max(l1 * l1 - a * a, 0))
	local pd = px * ux + py * uy + pz * uz
	local qx, qy, qz = px - ux * pd, py - uy * pd, pz - uz * pd
	local ql = sqrt(qx * qx + qy * qy + qz * qz)
	if ql < 1e-4 then
		qx, qy, qz = uy, -ux, 0
		ql = sqrt(qx * qx + qy * qy)
		if ql < 1e-4 then qx, qy, qz, ql = 1, 0, 0, 1 end
	end
	qx, qy, qz = qx / ql, qy / ql, qz / ql
	return hx + ux * a + qx * hh, hy + uy * a + qy * hh, hz + uz * a + qz * hh, hx + ux * d, hy + uy * d, hz + uz * d
end

--[[---------------------------------------------------------------------------
	the phone as a rigid body (the local frame of the player: x forward, y left,
	z up, origin = the feet when it started). plain numbers, no garbage per step.
	p = centre of mass, e1 e2 e3 = the axes of the phone (top, left edge, display)
---------------------------------------------------------------------------]]
function KK.Body(mn, mx)
	local b = {}
	b.hx, b.hy, b.hz = (mx.x - mn.x) * 0.5, (mx.y - mn.y) * 0.5, (mx.z - mn.z) * 0.5
	b.cx, b.cy, b.cz = (mx.x + mn.x) * 0.5, (mx.y + mn.y) * 0.5, (mx.z + mn.z) * 0.5
	local a2, b2, c2 = (2 * b.hx) ^ 2, (2 * b.hy) ^ 2, (2 * b.hz) ^ 2
	-- solid box, mass 1: inverse inertia around its own axes
	b.ix, b.iy, b.iz = 12 / max(b2 + c2, 0.01), 12 / max(a2 + c2, 0.01), 12 / max(a2 + b2, 0.01)
	local pts = {}
	local function add(x, y, z) pts[#pts + 1] = x pts[#pts + 1] = y pts[#pts + 1] = z end
	for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do add(sx * b.hx, sy * b.hy, sz * b.hz) end end end
	for _, fx in ipairs({-0.5, 0, 0.5}) do for sy = -1, 1, 2 do for sz = -1, 1, 2 do add(fx * b.hx, sy * b.hy, sz * b.hz) end end end
	for sx = -1, 1, 2 do for sz = -1, 1, 2 do add(sx * b.hx, 0, sz * b.hz) end end
	add(0, 0, b.hz) add(0, 0, -b.hz)
	b.pts = pts
	b.r = sqrt(b.hx * b.hx + b.hy * b.hy + b.hz * b.hz)
	b.px, b.py, b.pz, b.vx, b.vy, b.vz, b.wx, b.wy, b.wz = 0, 0, 0, 0, 0, 0, 0, 0, 0
	b.e1x, b.e1y, b.e1z, b.e2x, b.e2y, b.e2z, b.e3x, b.e3y, b.e3z = 1, 0, 0, 0, 1, 0, 0, 0, 1
	return b
end

-- the phone model origin + its axes (local frame) -> the body
function KK.BodySet(b, ox, oy, oz, fx, fy, fz, lx, ly, lz, ux, uy, uz)
	b.e1x, b.e1y, b.e1z, b.e2x, b.e2y, b.e2z, b.e3x, b.e3y, b.e3z = fx, fy, fz, lx, ly, lz, ux, uy, uz
	b.px = ox + fx * b.cx + lx * b.cy + ux * b.cz
	b.py = oy + fy * b.cx + ly * b.cy + uy * b.cz
	b.pz = oz + fz * b.cx + lz * b.cy + uz * b.cz
end

-- the model origin of the body (local frame)
function KK.BodyOrigin(b)
	return b.px - (b.e1x * b.cx + b.e2x * b.cy + b.e3x * b.cz),
		b.py - (b.e1y * b.cx + b.e2y * b.cy + b.e3y * b.cz),
		b.pz - (b.e1z * b.cx + b.e2z * b.cy + b.e3z * b.cz)
end

-- world inverse inertia * t
local function IW(b, tx, ty, tz)
	local l1 = (tx * b.e1x + ty * b.e1y + tz * b.e1z) * b.ix
	local l2 = (tx * b.e2x + ty * b.e2y + tz * b.e2z) * b.iy
	local l3 = (tx * b.e3x + ty * b.e3y + tz * b.e3z) * b.iz
	return b.e1x * l1 + b.e2x * l2 + b.e3x * l3, b.e1y * l1 + b.e2y * l2 + b.e3y * l3, b.e1z * l1 + b.e2z * l2 + b.e3z * l3
end

-- 1 / effective mass of a contact at r along n
local function EffMass(b, rx, ry, rz, nx, ny, nz)
	local ix, iy, iz = IW(b, ry * nz - rz * ny, rz * nx - rx * nz, rx * ny - ry * nx)
	return 1 + nx * (iy * rz - iz * ry) + ny * (iz * rx - ix * rz) + nz * (ix * ry - iy * rx)
end

-- impulse j at r (from the centre of mass)
local function Push(b, jx, jy, jz, rx, ry, rz)
	b.vx, b.vy, b.vz = b.vx + jx, b.vy + jy, b.vz + jz
	local ix, iy, iz = IW(b, ry * jz - rz * jy, rz * jx - rx * jz, rx * jy - ry * jx)
	b.wx, b.wy, b.wz = b.wx + ix, b.wy + iy, b.wz + iz
end
KK.Push = Push

local function RotN(vx, vy, vz, kx, ky, kz, c, s)
	local d = (kx * vx + ky * vy + kz * vz) * (1 - c)
	return vx * c + (ky * vz - kz * vy) * s + kx * d, vy * c + (kz * vx - kx * vz) * s + ky * d, vz * c + (kx * vy - ky * vx) * s + kz * d
end

-- the simulation context: surfaces around the phone (local frame)
function KK.NewSim(m, eyeZ)
	local S = {g = C.G, cn = 0, pool = {}, plate = {}, caps = {}, capOn = {}, hi = {}, hv = {}, deep = {}}
	for k = 1, NKIND do S.hi[k], S.hv[k], S.deep[k] = 0, 0, {d = 0, nx = 0, ny = 0, nz = 0} end
	local function cap(kind, r, e)
		return {kind = kind, r = r, e = e, mu = C.MU_CAP, ax = 0, ay = 0, az = 0, bx = 0, by = 0, bz = -1,
			vax = 0, vay = 0, vaz = 0, vbx = 0, vby = 0, vbz = 0}
	end
	S.caps[1] = cap(K_SHIN, C.SHIN_R, C.E_SHIN)
	S.caps[2] = cap(K_THIGH, C.THIGH_R, C.E_SHIN)
	S.caps[3] = cap(K_TORSO, C.TORSO_R, C.E_BODY)
	S.caps[4] = cap(K_RLEG, C.RLEG_R, C.E_BODY)
	KK.SimBody(S, m, eyeZ)
	S.gnd = {px = 0, py = 0, pz = -200, nx = 0, ny = 0, nz = 1}
	return S
end

-- the parts of the body that do not move: chest, the right (standing) leg
function KK.SimBody(S, m, eyeZ)
	local t, r = S.caps[3], S.caps[4]
	t.ax, t.ay, t.az, t.bx, t.by, t.bz = -1, 0, eyeZ - 26, -1, 0, eyeZ - 9
	r.ax, r.ay, r.az, r.bx, r.by, r.bz = 0.5, -abs(m.hy), 4, 0.5, -abs(m.hy), m.hz - 4
end

--[[ the foot: a critically damped spring after its target (sim time), the toe goes up
     on a quick move up. F = {tx ty tz, x y z, vx vy vz, pitch, prate, ptgt} ]]
function KK.FootStep(F, m, h)
	local w = 2 * math.pi * C.FOOT_HZ
	local kd, ww = 2 * C.FOOT_ZETA * w, w * w
	local vx = F.vx + (ww * (F.tx - F.x) - kd * F.vx) * h
	local vy = F.vy + (ww * (F.ty - F.y) - kd * F.vy) * h
	local vz = F.vz + (ww * (F.tz - F.z) - kd * F.vz) * h
	local vl = sqrt(vx * vx + vy * vy + vz * vz)
	if vl > C.FOOT_VMAX then local k = C.FOOT_VMAX / vl vx, vy, vz = vx * k, vy * k, vz * k end
	local x, y, z = F.x + vx * h, F.y + vy * h, F.z + vz * h
	-- not further than the leg reaches
	local dx, dy, dz = x - m.hx, y - m.hy, z - m.hz
	local d = sqrt(dx * dx + dy * dy + dz * dz)
	local R = (m.l1 + m.l2) * 0.97
	if d > R then
		local k = R / d
		x, y, z = m.hx + dx * k, m.hy + dy * k, m.hz + dz * k
		local ux, uy, uz = dx / d, dy / d, dz / d
		local vo = vx * ux + vy * uy + vz * uz
		if vo > 0 then vx, vy, vz = vx - ux * vo, vy - uy * vo, vz - uz * vo end
	end
	F.x, F.y, F.z, F.vx, F.vy, F.vz = x, y, z, vx, vy, vz
	local pt = F.ptgt or (C.PITCH0 + Clamp(vz * C.PITCH_K, C.PITCH_LO, C.PITCH_HI))
	local np = F.pitch + (pt - F.pitch) * (1 - exp(-h * C.PITCH_RATE))
	F.prate = (np - F.pitch) / h
	F.pitch = np
end

-- the top of the shoe as a box (moves with the foot), + the shin and the thigh
function KK.SimLeg(S, F, m)
	local P = S.plate
	local p = rad(F.pitch)
	local cp, sp = cos(p), sin(p)
	local ux, uy, uz = OUTC * cp, OUTS * cp, sp -- toward the toes
	local sx, sy, sz = -OUTS, OUTC, 0          -- left of the foot
	local nx, ny, nz = uy * sz - uz * sy, uz * sx - ux * sz, ux * sy - uy * sx -- up from the top of the foot
	local f = m.lf * 0.5 + C.PLATE_FWD
	P.ax, P.ay, P.az = F.x, F.y, F.z
	P.cx, P.cy, P.cz = F.x + ux * f + nx * C.PLATE_UP, F.y + uy * f + ny * C.PLATE_UP, F.z + uz * f + nz * C.PLATE_UP
	P.ux, P.uy, P.uz, P.sx, P.sy, P.sz, P.nx, P.ny, P.nz = ux, uy, uz, sx, sy, sz, nx, ny, nz
	P.hl, P.hw, P.ht = m.lf * 0.5 + C.PLATE_HL, C.PLATE_HW, C.PLATE_HT
	P.br = sqrt(P.hl * P.hl + P.hw * P.hw + P.ht * P.ht)
	P.vx, P.vy, P.vz = F.vx, F.vy, F.vz
	local pr = rad(F.prate)
	P.wx, P.wy, P.wz = -sx * pr, -sy * pr, -sz * pr
	local kx, ky, kz = KK.Knee(m.hx, m.hy, m.hz, F.x, F.y, F.z, m.l1, m.l2, 1, 0.12, 0)
	local s, t = S.caps[1], S.caps[2]
	s.ax, s.ay, s.az, s.bx, s.by, s.bz = kx, ky, kz, F.x, F.y, F.z
	s.vax, s.vay, s.vaz, s.vbx, s.vby, s.vbz = F.vx * 0.5, F.vy * 0.5, F.vz * 0.5, F.vx, F.vy, F.vz
	t.ax, t.ay, t.az, t.bx, t.by, t.bz = m.hx, m.hy, m.hz, kx, ky, kz
	t.vax, t.vay, t.vaz, t.vbx, t.vby, t.vbz = 0, 0, 0, F.vx * 0.5, F.vy * 0.5, F.vz * 0.5
end

local function AddC(S, kind, nx, ny, nz, d, rx, ry, rz, vx, vy, vz, e, mu)
	local n = S.cn + 1
	S.cn = n
	local c = S.pool[n]
	if not c then c = {} S.pool[n] = c end
	c.kind, c.nx, c.ny, c.nz, c.d, c.rx, c.ry, c.rz, c.vx, c.vy, c.vz, c.e, c.mu = kind, nx, ny, nz, d, rx, ry, rz, vx, vy, vz, e, mu
end

-- every sample point of the phone against the plate, the capsules, the floor
function KK.Detect(b, S)
	S.cn = 0
	local px, py, pz = b.px, b.py, b.pz
	local P = S.plate
	local usePlate = P and P.cx and ((px - P.cx) ^ 2 + (py - P.cy) ^ 2 + (pz - P.cz) ^ 2) < (b.r + P.br + 0.5) ^ 2
	local caps, on = S.caps, S.capOn
	local any = usePlate
	for i = 1, #caps do
		local c = caps[i]
		local abx, aby, abz = c.bx - c.ax, c.by - c.ay, c.bz - c.az
		local l2 = abx * abx + aby * aby + abz * abz
		c.abx, c.aby, c.abz, c.l2 = abx, aby, abz, max(l2, 1e-6)
		local t = Clamp(((px - c.ax) * abx + (py - c.ay) * aby + (pz - c.az) * abz) / c.l2, 0, 1)
		local qx, qy, qz = c.ax + abx * t - px, c.ay + aby * t - py, c.az + abz * t - pz
		on[i] = (qx * qx + qy * qy + qz * qz) < (b.r + c.r + 0.3) ^ 2
		any = any or on[i]
	end
	local g = S.gnd
	local useG = g and ((px - g.px) * g.nx + (py - g.py) * g.ny + (pz - g.pz) * g.nz) < b.r + 0.5
	if not (any or useG) then return end
	local pts = b.pts
	for i = 1, #pts, 3 do
		local lx, ly, lz = pts[i], pts[i + 1], pts[i + 2]
		local rx = b.e1x * lx + b.e2x * ly + b.e3x * lz
		local ry = b.e1y * lx + b.e2y * ly + b.e3y * lz
		local rz = b.e1z * lx + b.e2z * ly + b.e3z * lz
		local wx, wy, wz = px + rx, py + ry, pz + rz
		if usePlate then
			local dx, dy, dz = wx - P.cx, wy - P.cy, wz - P.cz
			local ax = dx * P.ux + dy * P.uy + dz * P.uz
			local ay = dx * P.sx + dy * P.sy + dz * P.sz
			local az = dx * P.nx + dy * P.ny + dz * P.nz
			if abs(ax) < P.hl and abs(ay) < P.hw and abs(az) < P.ht then
				-- surface speed: foot speed + its turn (toe up / down) around the ankle
				local qx, qy, qz = wx - P.ax, wy - P.ay, wz - P.az
				local svx, svy, svz = P.vx + P.wy * qz - P.wz * qy, P.vy + P.wz * qx - P.wx * qz, P.vz + P.wx * qy - P.wy * qx
				-- the face it came in through: back along the relative speed, the first face it leaves by
				-- (a fast hit goes deep in one step, the nearest face would often be the wrong one)
				local rvx, rvy, rvz = b.vx + b.wy * rz - b.wz * ry - svx, b.vy + b.wz * rx - b.wx * rz - svy, b.vz + b.wx * ry - b.wy * rx - svz
				local vu = rvx * P.ux + rvy * P.uy + rvz * P.uz
				local vs = rvx * P.sx + rvy * P.sy + rvz * P.sz
				local vn = rvx * P.nx + rvy * P.ny + rvz * P.nz
				-- (only a face it could have come through in the last steps; never the sole: the phone
				-- under a foot that comes down just lets it through)
				local top, bot, fb, sd = P.ht - az, P.ht + az, P.hl - abs(ax), P.hw - abs(ay)
				local su, ss = ax > 0 and 1 or -1, ay > 0 and 1 or -1
				local nx, ny, nz, d = P.nx, P.ny, P.nz, top
				local found, hs = false, (S.h or 0.004) * 2.5
				if vu * vu + vs * vs + vn * vn > 25 then
					local best = 1e9
					if vn < -1e-3 and top < -vn * hs + 0.3 then best, found = top / -vn, true end
					local w = -vu * su
					if w > 1e-3 and fb < w * hs + 0.3 and fb / w < best then best, found, nx, ny, nz, d = fb / w, true, P.ux * su, P.uy * su, P.uz * su, fb end
					w = -vs * ss
					if w > 1e-3 and sd < w * hs + 0.3 and sd / w < best then found, nx, ny, nz, d = true, P.sx * ss, P.sy * ss, P.sz * ss, sd end
				end
				if not found then -- resting / unclear: the nearest face, the top wins unless it is clearly another one
					local best
					best, nx, ny, nz, d = top, P.nx, P.ny, P.nz, top
					if fb * 2 < best then best, nx, ny, nz, d = fb * 2, P.ux * su, P.uy * su, P.uz * su, fb end
					if sd * 2 < best then best, nx, ny, nz, d = sd * 2, P.sx * ss, P.sy * ss, P.sz * ss, sd end
					if bot * 2 < best then d = nil end
				end
				if d then AddC(S, K_PLATE, nx, ny, nz, d, rx, ry, rz, svx, svy, svz, C.E_PLATE, C.MU_PLATE) end
			end
		end
		for ci = 1, #caps do
			if on[ci] then
				local c = caps[ci]
				local t = Clamp(((wx - c.ax) * c.abx + (wy - c.ay) * c.aby + (wz - c.az) * c.abz) / c.l2, 0, 1)
				local qx, qy, qz = wx - (c.ax + c.abx * t), wy - (c.ay + c.aby * t), wz - (c.az + c.abz * t)
				local dd = qx * qx + qy * qy + qz * qz
				if dd < c.r * c.r and dd > 1e-8 then
					local d = sqrt(dd)
					AddC(S, c.kind, qx / d, qy / d, qz / d, c.r - d, rx, ry, rz,
						c.vax + (c.vbx - c.vax) * t, c.vay + (c.vby - c.vay) * t, c.vaz + (c.vbz - c.vaz) * t, c.e, c.mu)
				end
			end
		end
		if useG then
			local d = (wx - g.px) * g.nx + (wy - g.py) * g.ny + (wz - g.pz) * g.nz
			if d < 0 then AddC(S, K_GND, g.nx, g.ny, g.nz, -d, rx, ry, rz, 0, 0, 0, C.E_GND, C.MU_GND) end
		end
	end
end

-- one substep: gravity, contacts (sequential impulses, friction), integration, push out
function KK.SimStep(b, S, h)
	S.h = h
	b.vz = b.vz - S.g * h
	KK.Detect(b, S)
	local n, pool = S.cn, S.pool
	local hv = S.hv
	for i = 1, n do
		local c = pool[i]
		local rx, ry, rz = c.rx, c.ry, c.rz
		local vn = (b.vx + b.wy * rz - b.wz * ry - c.vx) * c.nx + (b.vy + b.wz * rx - b.wx * rz - c.vy) * c.ny + (b.vz + b.wx * ry - b.wy * rx - c.vz) * c.nz
		if c.kind == K_PLATE and -vn > C.SOFT_V0 then
			-- a soft shoe gives under a hard hit: it acts as if closer to the centre of mass
			local k = 1 - C.SOFT * Smooth((-vn - C.SOFT_V0) / (C.SOFT_V1 - C.SOFT_V0))
			rx, ry, rz = rx * k, ry * k, rz * k
			c.rx, c.ry, c.rz = rx, ry, rz
			vn = (b.vx + b.wy * rz - b.wz * ry - c.vx) * c.nx + (b.vy + b.wz * rx - b.wx * rz - c.vy) * c.ny + (b.vz + b.wx * ry - b.wy * rx - c.vz) * c.nz
		end
		c.tv = (vn < -C.REST_V) and (-c.e * vn) or 0
		c.acc = 0
		c.km = EffMass(b, rx, ry, rz, c.nx, c.ny, c.nz)
		if -vn > hv[c.kind] then hv[c.kind] = -vn end
	end
	-- a hard hit needs more passes, every other pass goes backwards (no order bias = no fake spin)
	local iters = C.ITER
	for i = 1, n do if pool[i].tv > 0 then iters = C.ITER_HIT break end end
	for it = 1, iters do
		local i0, i1, di = 1, n, 1
		if it % 2 == 0 then i0, i1, di = n, 1, -1 end
		for i = i0, i1, di do
			local c = pool[i]
			local rx, ry, rz = c.rx, c.ry, c.rz
			local vx, vy, vz = b.vx + b.wy * rz - b.wz * ry - c.vx, b.vy + b.wz * rx - b.wx * rz - c.vy, b.vz + b.wx * ry - b.wy * rx - c.vz
			local vn = vx * c.nx + vy * c.ny + vz * c.nz
			local j = (c.tv - vn) / c.km
			local na = c.acc + j
			if na < 0 then na = 0 end
			j = na - c.acc
			c.acc = na
			if j ~= 0 then
				Push(b, c.nx * j, c.ny * j, c.nz * j, rx, ry, rz)
				if j > 0 and c.kind == K_PLATE then -- the soft shoe soaks up spin (before the friction sees it)
					local k = exp(-C.SPIN_DAMP * j)
					b.wx, b.wy, b.wz = b.wx * k, b.wy * k, b.wz * k
				end
				vx, vy, vz = b.vx + b.wy * rz - b.wz * ry - c.vx, b.vy + b.wz * rx - b.wx * rz - c.vy, b.vz + b.wx * ry - b.wy * rx - c.vz
				vn = vx * c.nx + vy * c.ny + vz * c.nz
			end
			if c.acc > 0 then
				local tx, ty, tz = vx - c.nx * vn, vy - c.ny * vn, vz - c.nz * vn
				local tl = sqrt(tx * tx + ty * ty + tz * tz)
				if tl > 1e-4 then
					tx, ty, tz = tx / tl, ty / tl, tz / tl
					local jt = min(tl / EffMass(b, rx, ry, rz, tx, ty, tz), c.mu * c.acc)
					Push(b, -tx * jt, -ty * jt, -tz * jt, rx, ry, rz)
				end
			end
		end
	end
	local hi, deep = S.hi, S.deep
	for k = 1, NKIND do deep[k].d = 0 end
	local onG, onP = false, false
	for i = 1, n do
		local c = pool[i]
		hi[c.kind] = hi[c.kind] + c.acc
		local dk = deep[c.kind]
		if c.d > dk.d then dk.d, dk.nx, dk.ny, dk.nz = c.d, c.nx, c.ny, c.nz end
		if c.kind == K_GND then onG = true elseif c.kind == K_PLATE then onP = true end
	end
	-- integrate
	b.px, b.py, b.pz = b.px + b.vx * h, b.py + b.vy * h, b.pz + b.vz * h
	local wl = sqrt(b.wx * b.wx + b.wy * b.wy + b.wz * b.wz)
	if wl > 1e-7 then
		local a = wl * h
		local kx, ky, kz = b.wx / wl, b.wy / wl, b.wz / wl
		local ca, sa = cos(a), sin(a)
		local e1x, e1y, e1z = RotN(b.e1x, b.e1y, b.e1z, kx, ky, kz, ca, sa)
		local e2x, e2y, e2z = RotN(b.e2x, b.e2y, b.e2z, kx, ky, kz, ca, sa)
		local l = sqrt(e1x * e1x + e1y * e1y + e1z * e1z)
		e1x, e1y, e1z = e1x / l, e1y / l, e1z / l
		local dd = e1x * e2x + e1y * e2y + e1z * e2z
		e2x, e2y, e2z = e2x - e1x * dd, e2y - e1y * dd, e2z - e1z * dd
		l = sqrt(e2x * e2x + e2y * e2y + e2z * e2z)
		e2x, e2y, e2z = e2x / l, e2y / l, e2z / l
		b.e1x, b.e1y, b.e1z, b.e2x, b.e2y, b.e2z = e1x, e1y, e1z, e2x, e2y, e2z
		b.e3x, b.e3y, b.e3z = e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x
	end
	-- out of what it went into (the deepest point of every surface)
	for k = 1, NKIND do
		local dk = deep[k]
		if dk.d > 0.01 then
			local s = (dk.d - 0.01) * 0.5
			b.px, b.py, b.pz = b.px + dk.nx * s, b.py + dk.ny * s, b.pz + dk.nz * s
		end
	end
	-- air / rolling losses
	local wd = 1 / (1 + h * (onG and 3 or (onP and 1.5 or 0.35)))
	b.wx, b.wy, b.wz = b.wx * wd, b.wy * wd, b.wz * wd
	local vd = 1 / (1 + h * 0.02)
	b.vx, b.vy, b.vz = b.vx * vd, b.vy * vd, b.vz * vd
	return n > 0
end

--[[---------------------------------------------------------------------------
	shared: who may, the movement lock, the stream sample
---------------------------------------------------------------------------]]

function KK.Kicking(wep)
	if not IsValid(wep) then return false end
	if CLIENT and KK.K and KK.K.wep == wep then return true end
	return wep:GetNW2Bool("Kick", false)
end

function KK.LegsOK(ply)
	local org = ply.organism
	if not org then return true end
	if org.llegamputated or org.rlegamputated then return false end
	if (tonumber(org.lleg) or 0) >= 0.999 or (tonumber(org.rleg) or 0) >= 0.999 then return false end
	return true
end

-- the phone lies in the free left hand + standing still on both legs
function KK.CanKick(wep, ply)
	ply = ply or (IsValid(wep) and wep:GetOwner())
	if not (IsValid(wep) and IsValid(ply) and ply:IsPlayer()) then return false end
	if KK.Kicking(wep) or (CLIENT and KK.K) then return false end
	if not (KK.BaseCanToss and KK.BaseCanToss(wep, ply)) then return false end
	if not ply:OnGround() or ply:Crouching() or ply:WaterLevel() >= 2 or ply:GetMoveType() ~= MOVETYPE_WALK then return false end
	if ply:GetVelocity():Length2D() > 70 then return false end
	return KK.LegsOK(ply)
end

local BLOCK = bit.bor(IN_JUMP, IN_DUCK, IN_SPEED, IN_WALK, IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_USE, IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT)
KK.BLOCK = BLOCK
hook.Add("StartCommand", "STTS_PhoneKick", function(ply, cmd)
	local wep = ply:GetActiveWeapon()
	if not (IsValid(wep) and wep:GetClass() == "weapon_stts_phone") then return end
	local on = wep:GetNW2Bool("Kick", false)
	if CLIENT and not on then
		local K = KK.K
		on = K ~= nil and K.wep == wep
	end
	if not on then return end
	cmd:ClearMovement()
	cmd:RemoveKey(BLOCK)
end)

-- quantized net values
local function WQ(v, scale, bits)
	local lim = 2 ^ (bits - 1) - 1
	net.WriteInt(Clamp(floor((tonumber(v) or 0) * scale + 0.5), -lim, lim), bits)
end
local function RQ(scale, bits) return net.ReadInt(bits) / scale end
local function WA(a, bits)
	local n = 2 ^ bits
	net.WriteUInt(floor(((tonumber(a) or 0) % 360) / 360 * n + 0.5) % n, bits)
end
local function RA(bits)
	local a = net.ReadUInt(bits) / 2 ^ bits * 360
	return a > 180 and a - 360 or a
end
local function W8(v) net.WriteUInt(Clamp(floor((tonumber(v) or 0) * 255 + 0.5), 0, 255), 8) end

--[[ the stream sample (local frame of the player: feet + yaw):
     ph, lw (leg weight), yaw, foot xyz + pitch, hand weight / open / back at the side
     + the phone pose the hand holds, the free phone pose, event counters (foot / floor / catch) ]]
function KK.WriteSample(s)
	net.WriteUInt(Clamp(s.ph or 0, 0, 7), 3)
	W8(s.lw) WA(s.yaw, 16)
	WQ(s.fx, 32, 15) WQ(s.fy, 32, 15) WQ(s.fz, 32, 15) WQ(s.fpt, 4, 11)
	W8(s.hw) W8(s.ho) W8(s.hb)
	if (s.hw or 0) > 0.002 then
		WQ(s.hx, 32, 15) WQ(s.hy, 32, 15) WQ(s.hz, 32, 15)
		WA(s.hp, 12) WA(s.hya, 12) WA(s.hr, 12)
	end
	net.WriteBool(s.free and true or false)
	if s.free then
		WQ(s.px, 16, 16) WQ(s.py, 16, 16) WQ(s.pz, 16, 16)
		WA(s.pp, 12) WA(s.pya, 12) WA(s.pr, 12)
	end
	net.WriteUInt((s.ck or 0) % 16, 4) net.WriteUInt((s.cg or 0) % 16, 4) net.WriteUInt((s.cc or 0) % 4, 2)
end

function KK.ReadSample()
	local s = {}
	s.ph = net.ReadUInt(3)
	s.lw = net.ReadUInt(8) / 255
	s.yaw = RA(16)
	s.fx, s.fy, s.fz, s.fpt = RQ(32, 15), RQ(32, 15), RQ(32, 15), RQ(4, 11)
	s.hw = net.ReadUInt(8) / 255
	s.ho = net.ReadUInt(8) / 255
	s.hb = net.ReadUInt(8) / 255
	if s.hw > 0.002 then
		s.hx, s.hy, s.hz = RQ(32, 15), RQ(32, 15), RQ(32, 15)
		s.hp, s.hya, s.hr = RA(12), RA(12), RA(12)
	end
	s.free = net.ReadBool()
	if s.free then
		s.px, s.py, s.pz = RQ(16, 16), RQ(16, 16), RQ(16, 16)
		s.pp, s.pya, s.pr = RA(12), RA(12), RA(12)
	end
	s.ck, s.cg, s.cc = net.ReadUInt(4), net.ReadUInt(4), net.ReadUInt(2)
	return s
end

--[[---------------------------------------------------------------------------
	SWEP wraps (the weapon file defines the originals before including this;
	a new SWEP table on every load, so the originals are always the fresh ones)
---------------------------------------------------------------------------]]
local WRAP = not SWEP.STTS_KickWrapped
SWEP.STTS_KickWrapped = true
if WRAP then
	KK.BaseCanToss, KK.BaseDeploy, KK.BaseHolster = SWEP.CanToss, SWEP.Deploy, SWEP.Holster
	KK.BaseThink, KK.BasePrimary = SWEP.Think, SWEP.ClientPrimary
end
function SWEP:CanToss(ply)
	if KK.Kicking(self) then return false end
	return KK.BaseCanToss(self, ply)
end

function SWEP:CanKick(ply) return KK.CanKick(self, ply) end

-- the arm bones stay neutral while the IK holds the hand (see SWEP:Step)
function SWEP:KickArm()
	if CLIENT and KK.HandOf then
		local H = KK.HandOf(self, self:GetOwner())
		if H and H.w > 0.001 then return true end
	end
	return self:GetNW2Bool("Kick", false)
end

local function KickOff(self)
	if SERVER and self:GetNW2Bool("Kick", false) then self:SetNW2Bool("Kick", false) end
	if CLIENT and KK.K and KK.K.wep == self and KK.Clear then KK.Clear() end
end
function SWEP:Deploy(...)
	KickOff(self)
	return KK.BaseDeploy(self, ...)
end
function SWEP:Holster(...)
	KickOff(self)
	return KK.BaseHolster(self, ...)
end
function SWEP:ClientPrimary(...)
	if KK.Kicking(self) then return end
	return KK.BasePrimary(self, ...)
end
function SWEP:Think(...)
	local r = KK.BaseThink(self, ...)
	if SERVER and self:GetNW2Bool("Kick", false) then
		local ply = self:GetOwner()
		-- the client stopped streaming / gone / switched: let go of the lock
		if not (IsValid(ply) and ply:IsPlayer() and ply:Alive() and ply:GetActiveWeapon() == self) or CurTime() - (self.STTS_KickS or 0) > 2.5 then
			self:SetNW2Bool("Kick", false)
		end
	end
	return r
end

--[[---------------------------------------------------------------------------
	server
---------------------------------------------------------------------------]]
if SERVER then
	util.AddNetworkString("stts_phone_kick")
	util.AddNetworkString("stts_phone_kick_s")

	-- like hg.drop (sv_drop.lua) without the shove animation, with the exact pose + speed
	function KK.Drop(ply, wep, pos, ang, vel, avel)
		local eye = ply:EyePos()
		if pos:DistToSqr(ply:GetPos()) > 260 * 260 then pos = eye + ply:GetAimVector() * 12 end
		local tr = util.TraceLine({start = eye, endpos = pos, filter = {ply, wep}, mask = MASK_SOLID})
		if tr.Hit then pos = tr.HitPos + tr.HitNormal * 2 end
		if vel:Length() > 700 then vel = vel:GetNormalized() * 700 end
		avel = Vector(Clamp(avel.x, -3000, 3000), Clamp(avel.y, -3000, 3000), Clamp(avel.z, -3000, 3000))
		wep:SetNW2Bool("Kick", false)
		wep.STTS_KickDrop = {pos, ang, vel, avel}
		local hands = ply:GetWeapon("weapon_hands_sh")
		if IsValid(hands) then
			ply:SelectWeapon("weapon_hands_sh")
			ply:SetActiveWeapon(hands)
		end
		ply:DropWeapon(wep, nil, vel)
		if not IsValid(wep) then return end
		wep.init = true
		wep.IsSpawned = true
		wep:SetOwner()
		wep:SetPos(pos)
		wep:SetAngles(ang)
	end

	net.Receive("stts_phone_kick", function(_, ply)
		local op = net.ReadUInt(3)
		local wep = net.ReadEntity()
		if not (IsValid(ply) and IsValid(wep) and wep:GetClass() == "weapon_stts_phone" and wep:GetOwner() == ply) then return end
		if op == 1 then
			if (ply.STTS_KickNext or 0) > CurTime() then return end
			ply.STTS_KickNext = CurTime() + 0.4
			if ply:GetActiveWeapon() == wep and KK.CanKick(wep, ply) then
				wep:SetNW2Bool("Kick", true)
				wep.STTS_KickS = CurTime()
			else
				net.Start("stts_phone_kick")
				net.WriteUInt(4, 3)
				net.WriteEntity(wep)
				net.Send(ply)
			end
		elseif op == 2 then
			local pos, ang, vel, avel = net.ReadVector(), net.ReadAngle(), net.ReadVector(), net.ReadVector()
			if not (wep:GetNW2Bool("Kick", false) or CurTime() - (wep.STTS_KickS or 0) < 3) then return end
			if ply:GetActiveWeapon() ~= wep or not ply:Alive() then return end
			KK.Drop(ply, wep, pos, ang, vel, avel)
		elseif op == 3 then
			wep:SetNW2Bool("Kick", false)
		end
	end)

	-- the pose stream: checked, relayed to the players around
	net.Receive("stts_phone_kick_s", function(_, ply)
		local wep = IsValid(ply) and ply:GetActiveWeapon()
		if not (IsValid(wep) and wep:GetClass() == "weapon_stts_phone" and wep:GetNW2Bool("Kick", false)) then return end
		local now = CurTime()
		if (ply.STTS_KickRate or 0) > now then return end
		ply.STTS_KickRate = now + 0.025
		wep.STTS_KickS = now
		local s = KK.ReadSample()
		local rf = RecipientFilter()
		rf:AddPVS(ply:GetPos())
		rf:RemovePlayer(ply)
		if rf:GetCount() == 0 then return end
		net.Start("stts_phone_kick_s", true)
		net.WriteEntity(ply)
		KK.WriteSample(s)
		net.Send(rf)
	end)
end

if not CLIENT then return end

--[[---------------------------------------------------------------------------
	client
---------------------------------------------------------------------------]]
local cvSlow = CreateClientConVar("stts_phone_kick_slowmo", "0.6", true, false, "keepy-uppy (Litvin): time scale of the phone in the air (1 = no slow motion)", 0.1, 1)
local cvSlowMin = CreateClientConVar("stts_phone_kick_slowmo_min", "0.35", true, false, "keepy-uppy (Litvin): time scale right before the phone meets the foot", 0.1, 1)
local cvSens = CreateClientConVar("stts_phone_kick_sens", "1", true, false, "keepy-uppy (Litvin): mouse sensitivity of the foot", 0.1, 5)
local cvBal = CreateClientConVar("stts_phone_kick_balance", "1", true, false, "keepy-uppy (Litvin): the body shifts its weight onto the right leg (0 = off)", 0, 2)
-- the phone on the palm, relative to the body (pitch yaw roll, + pitch = the top down, + yaw = the top to the left).
-- glass up (display to the sky, a bit toward the eyes), the top turned out a little so the wrist stays straight
local cvHold = CreateClientConVar("stts_phone_kick_hold", "-16 26 -6", true, false, "keepy-uppy (Litvin): the phone on the palm before the drop, glass up: pitch yaw roll")
local cvCatch = CreateClientConVar("stts_phone_kick_catch", "-24 28 -6", true, false, "keepy-uppy (Litvin): the open palm that catches the phone: pitch yaw roll")

local Zv = Vector(0, 0, 1)
KK.LS = KK.LS or {}     -- legs to pose, per player: {w, x y z (ankle, local), pitch, yaw, o, drv}
KK.Meas = KK.Meas or {} -- measured legs (before the IK), per player
KK.R = KK.R or {}       -- other players: their stream

function KK.Err(err)
	if (KK.errT or 0) > RealTime() then return end
	KK.errT = RealTime() + 5
	ErrorNoHalt("[ZPhone keepy-uppy] " .. tostring(err) .. "\n")
end

function KK.Frame(yaw)
	local r = rad(yaw or 0)
	local c, s = cos(r), sin(r)
	return Vector(c, s, 0), Vector(-s, c, 0)
end
local function L2W(o, F, L, x, y, z) return o + F * x + L * y + Zv * z end
local function W2L(o, F, L, p) local d = p - o return d:Dot(F), d:Dot(L), d.z end
KK.L2W, KK.W2L = L2W, W2L

-- angle blend through the axes (no Euler wrap problems)
local function NLerpAng(t, a, b)
	if t <= 0 then return a elseif t >= 1 then return b end
	local f = LerpVector(t, a:Forward(), b:Forward())
	local u = LerpVector(t, a:Up(), b:Up())
	if f:LengthSqr() < 1e-6 then return t < 0.5 and a or b end
	f:Normalize()
	u = u - f * u:Dot(f)
	if u:LengthSqr() < 1e-6 then return t < 0.5 and a or b end
	u:Normalize()
	return f:AngleEx(u)
end
KK.NLerpAng = NLerpAng

function KK.Snd(kind, pos, vol)
	local s
	if kind == 2 then s = "physics/plastic/plastic_box_impact_hard" .. math.random(1, 4) .. ".wav"
	elseif kind == 3 then s = "physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav"
	else s = "physics/plastic/plastic_box_impact_soft" .. math.random(1, 4) .. ".wav" end
	sound.Play(s, pos or LocalPlayer():GetPos(), 62, math.random(96, 108), vol or 0.6)
end

function KK.Deny() surface.PlaySound("common/wpn_denyselect.wav") end

--[[---------------------------------------------------------------------------
	legs (render): weight onto the right leg, the left one to the foot pose.
	the bone matrices after ent:SetupBones() (Z-City DrawPlayerRagdoll), before the
	arm IK. every bone keeps its own twist: its old frame (direction + knee axis) is
	turned onto the new one; children follow (ApplyBone)
---------------------------------------------------------------------------]]
local boneCache, kidCache = {}, {}
local BONES = {pelvis = "ValveBiped.Bip01_Pelvis", lt = "ValveBiped.Bip01_L_Thigh", lc = "ValveBiped.Bip01_L_Calf", lf = "ValveBiped.Bip01_L_Foot",
	lto = "ValveBiped.Bip01_L_Toe0", rt = "ValveBiped.Bip01_R_Thigh", rc = "ValveBiped.Bip01_R_Calf", rf = "ValveBiped.Bip01_R_Foot"}
function KK.Bones(ent)
	local mdl = ent:GetModel() or ""
	local B = boneCache[mdl]
	if B == nil then
		B = {}
		for k, name in pairs(BONES) do B[k] = ent:LookupBone(name) end
		if not (B.lt and B.lc and B.lf) then B = false end
		boneCache[mdl] = B
	end
	return B or nil
end

-- every bone under this one (cached per model)
function KK.Kids(ent, bone)
	local mdl = ent:GetModel() or ""
	local c = kidCache[mdl]
	if not c then c = {} kidCache[mdl] = c end
	local l = c[bone]
	if l then return l end
	l = {}
	local stack = {bone}
	while #stack > 0 do
		local b = table.remove(stack)
		for _, k in ipairs(ent:GetChildBones(b) or {}) do
			l[#l + 1] = k
			stack[#stack + 1] = k
		end
	end
	c[bone] = l
	return l
end

-- set a bone matrix, the bones under it move with it
function KK.ApplyBone(ent, bone, nm)
	local old = ent:GetBoneMatrix(bone)
	if not old then return end
	local inv = old:GetInverse()
	if inv then
		local delta = nm * inv
		local kids = KK.Kids(ent, bone)
		for i = 1, #kids do
			local km = ent:GetBoneMatrix(kids[i])
			if km then ent:SetBoneMatrix(kids[i], delta * km) end
		end
	end
	ent:SetBoneMatrix(bone, nm)
end

local function Basis(u, n)
	local p = n - u * n:Dot(u)
	if p:LengthSqr() < 1e-8 then p = abs(u.z) < 0.9 and Zv:Cross(u) or Vector(1, 0, 0):Cross(u) end
	p:Normalize()
	return p, u:Cross(p)
end

-- matrix m turned so that the frame (uo, no) becomes (un, nn), moved to pos (scale stays)
function KK.RotMat(m, uo, no, un, nn, pos)
	local ao2, ao3 = Basis(uo, no)
	local an2, an3 = Basis(un, nn)
	local f, rt, up = m:GetForward(), m:GetRight(), m:GetUp()
	local r = Matrix()
	r:Set(m)
	r:SetForward(un * f:Dot(uo) + an2 * f:Dot(ao2) + an3 * f:Dot(ao3))
	r:SetRight(un * rt:Dot(uo) + an2 * rt:Dot(ao2) + an3 * rt:Dot(ao3))
	r:SetUp(un * up:Dot(uo) + an2 * up:Dot(ao2) + an3 * up:Dot(ao3))
	r:SetTranslation(pos)
	return r
end

-- the knee axis (sideways, toward the left of the body)
local function Hinge(d1, d2, L)
	local n = d1:Cross(d2)
	local l = n:Length()
	if l > 0.08 and n:Dot(L) > 0.2 * l then return n / l end
	local p = L - d1 * L:Dot(d1)
	if p:LengthSqr() < 1e-6 then return L end
	p:Normalize()
	return p
end

function KK.KneeV(H, A, l1, l2, pole)
	local kx, ky, kz, ax, ay, az = KK.Knee(H.x, H.y, H.z, A.x, A.y, A.z, l1, l2, pole.x, pole.y, pole.z)
	return Vector(kx, ky, kz), Vector(ax, ay, az)
end

local function LegBones(ent, bt, bc, mT, mC, T0, C0, A0, H, knee, A, L)
	local d1o, d2o = (C0 - T0):GetNormalized(), (A0 - C0):GetNormalized()
	local no = Hinge(d1o, d2o, L)
	local d1n, d2n = (knee - H):GetNormalized(), (A - knee):GetNormalized()
	local nn = Hinge(d1n, d2n, L)
	KK.ApplyBone(ent, bt, KK.RotMat(mT, d1o, no, d1n, nn, H))
	KK.ApplyBone(ent, bc, KK.RotMat(mC, d2o, no, d2n, nn, knee))
	return no, nn
end

-- the legs in the local frame (hip, lengths, standing ankle, foot pitch)
function KK.Measure(ply, o, F, L, T0, C0, A0, To0)
	local l1, l2 = T0:Distance(C0), C0:Distance(A0)
	if l1 < 6 or l1 > 40 or l2 < 6 or l2 > 40 then return end
	local m = KK.Meas[ply] or {}
	KK.Meas[ply] = m
	m.hx, m.hy, m.hz = W2L(o, F, L, T0)
	m.l1, m.l2, m.lf = l1, l2, Clamp(A0:Distance(To0), 3, 10)
	m.ax, m.ay, m.az = W2L(o, F, L, A0)
	local fd = (To0 - A0):GetNormalized()
	m.fp = deg(math.asin(Clamp(fd.z, -1, 1)))
	return m
end

function KK.MeasureNow(ply, o, yaw)
	local B = KK.Bones(ply)
	if not B then return end
	ply:InvalidateBoneCache()
	ply:SetupBones()
	local mT, mC, mF = ply:GetBoneMatrix(B.lt), ply:GetBoneMatrix(B.lc), ply:GetBoneMatrix(B.lf)
	if not (mT and mC and mF) then return end
	local F, L = KK.Frame(yaw)
	local A0 = mF:GetTranslation()
	local mTo = B.lto and ply:GetBoneMatrix(B.lto)
	return KK.Measure(ply, o, F, L, mT:GetTranslation(), mC:GetTranslation(), A0, mTo and mTo:GetTranslation() or (A0 + F * 5.5 - Zv * 2.5))
end

function KK.DoLegs(ent, ply)
	local ls = KK.LS[ply]
	if not ls then return end
	local B = KK.Bones(ent)
	if not B then return end
	local mT, mC, mF = ent:GetBoneMatrix(B.lt), ent:GetBoneMatrix(B.lc), ent:GetBoneMatrix(B.lf)
	if not (mT and mC and mF) then return end
	local o = ls.o or ply:GetPos()
	local F, L = KK.Frame(ls.yaw or ply:EyeAngles().y)
	local T0, C0, A0 = mT:GetTranslation(), mC:GetTranslation(), mF:GetTranslation()
	local mTo = B.lto and ent:GetBoneMatrix(B.lto)
	local To0 = mTo and mTo:GetTranslation() or (A0 + F * 5.5 - Zv * 2.5)
	KK.Measure(ply, o, F, L, T0, C0, A0, To0)
	local w = Smooth(ls.w or 0)
	if w <= 0.001 or not ls.x then return end
	-- the weight goes onto the right leg: the pelvis moves over it, the right foot stays planted
	local shift
	local bal = cvBal:GetFloat() * w
	if bal > 0.001 and B.pelvis and B.rt and B.rc and B.rf then
		local mP, mRT, mRC, mRF = ent:GetBoneMatrix(B.pelvis), ent:GetBoneMatrix(B.rt), ent:GetBoneMatrix(B.rc), ent:GetBoneMatrix(B.rf)
		if mP and mRT and mRC and mRF then
			shift = (L * -C.BAL_SIDE - Zv * C.BAL_DOWN) * bal
			local RT0, RC0, RA0 = mRT:GetTranslation(), mRC:GetTranslation(), mRF:GetTranslation()
			local nP = Matrix()
			nP:Set(mP)
			nP:SetTranslation(mP:GetTranslation() + shift)
			KK.ApplyBone(ent, B.pelvis, nP)
			local H = RT0 + shift
			local knee, A = KK.KneeV(H, RA0, RT0:Distance(RC0), RC0:Distance(RA0), F - L * 0.12)
			LegBones(ent, B.rt, B.rc, mRT, mRC, RT0, RC0, RA0, H, knee, A, L)
			local nF = Matrix()
			nF:Set(mRF)
			nF:SetTranslation(A)
			KK.ApplyBone(ent, B.rf, nF)
		end
	end
	-- the left leg: hip -> knee (bends forward, a bit out) -> the ankle at the foot pose
	local H = shift and (T0 + shift) or T0
	local A = LerpVector(w, A0, o + F * ls.x + L * ls.y + Zv * ls.z)
	local fd0 = (To0 - A0):GetNormalized()
	local p = rad(ls.pitch or 0)
	local fdt = (F * OUTC + L * OUTS) * cos(p) + Zv * sin(p)
	local fd = LerpVector(w, fd0, fdt)
	if fd:LengthSqr() < 1e-6 then fd = fdt end
	fd:Normalize()
	local knee, A2 = KK.KneeV(H, A, T0:Distance(C0), C0:Distance(A0), F + L * 0.12)
	local no, nn = LegBones(ent, B.lt, B.lc, mT, mC, T0, C0, A0, H, knee, A2, L)
	KK.ApplyBone(ent, B.lf, KK.RotMat(mF, fd0, no, fd, nn, A2))
end

--[[ fix60: hg.MainTPIKFunction is wrapped twice: here (the legs) and by the phone in a
     vehicle (sh_phone_car.lua). each one only checked "is the function MY wrapper", so
     they wrapped each other again and again (a new layer every few seconds) and every
     layer did the legs once more: the weight shift onto the right leg added up and the
     body slid off to the right. now every wrapper notes what it wraps (STTS.WrapInner),
     a wrapper found anywhere in the chain is not wrapped again, and a second layer of
     this one (somebody else wrapped around it) only passes the call through ]]
STTS.WrapInner = STTS.WrapInner or setmetatable({}, {__mode = "k"})
STTS.WrapHas = STTS.WrapHas or function(fn, mine)
	if not mine then return false end
	local inner = STTS.WrapInner
	for _ = 1, 64 do
		if fn == nil then return false end
		if fn == mine then return true end
		fn = inner[fn]
	end
	return false
end

-- Z-City: the legs right after the body bones, before the hand IK / arm TPIK of the weapon
function KK.WrapTPIK()
	if not (hg and isfunction(hg.MainTPIKFunction)) then return end
	if KK.wTPIK and STTS.WrapHas(hg.MainTPIKFunction, KK.wTPIK) then return end
	local orig = hg.MainTPIKFunction
	local function wrap(ent, ply, wpn, ...)
		local f = FrameNumber()
		if KK.busyE == ent and KK.busyF == f then return orig(ent, ply, wpn, ...) end -- (an inner layer)
		KK.busyE, KK.busyF = ent, f
		KK.inTPIK = nil
		if IsValid(ply) and KK.LS[ply] and ent == ply then
			local ok, err = pcall(KK.DoLegs, ent, ply)
			if not ok then KK.Err(err) end
			KK.inTPIK = ply
		end
		-- the animation's own left arm, before the hand IK / TPIK bends it (see KK.ArmBlend)
		local snap
		if ent == ply then
			local ok, r = pcall(KK.ArmSnap, ent, ply, wpn)
			if ok then snap = r else KK.Err(r) end
		end
		orig(ent, ply, wpn, ...)
		if snap then
			local ok, err = pcall(KK.ArmBlend, ent, snap)
			if not ok then KK.Err(err) end
		end
		KK.inTPIK = nil
		KK.busyE = nil
	end
	STTS.WrapInner[wrap] = orig
	KK.wTPIK = wrap
	hg.MainTPIKFunction = wrap
end

--[[---------------------------------------------------------------------------
	the left hand (from SWEP:SetHandPos): the phone pose it should hold (local frame
	of the player), blended with the idle pose by H.w, fingers opened by H.open.
	H.rest = how far the arm went back down to the side: the IK stays on meanwhile
	(so the hand can come up again for the catch right away, no Z-City IK fade in /
	out), but after it the arm bones are blended back to the animation's own arm
	(KK.ArmBlend), so it hangs relaxed like the right one, not bent out by the IK
---------------------------------------------------------------------------]]

-- the resting arm. the Z-City arm IK puts the elbow far out to the side (its pole), so
-- an IK hand at the hip gives a bent, twisted arm. instead the IK result is blended,
-- bone by bone in local space (upper arm, forearm, hand, fingers), back to the arm
-- of the animation (the same pose the right arm has) by H.rest
KK.ArmR = KK.ArmR or setmetatable({}, {__mode = "k"})
function KK.ArmSnap(ent, ply, wpn)
	local H = IsValid(wpn) and KK.HandOf(wpn, ply)
	local r
	if H and (H.w or 0) > 0.001 then
		r = Clamp(H.rest or 0, 0, 1)
		r = r * r * (3 - 2 * r) -- late at first: the hand is free for the catch before the arm is
		KK.ArmR[ply] = {r, RealTime()}
	else
		-- the hand let go (stop / the phone on the floor): the Z-City IK still fades out
		-- for a moment (ply.lerp_lh), the arm stays as it was meanwhile
		local a = KK.ArmR[ply]
		if not a or (ply.lerp_lh or 0) <= 0 or RealTime() - a[2] > 0.8 then KK.ArmR[ply] = nil return end
		r = a[1]
	end
	if r <= 0.002 then return end
	local ua = ent:LookupBone("ValveBiped.Bip01_L_UpperArm")
	local pa = ua and ent:GetBoneParent(ua)
	if not pa or pa < 0 then return end
	local pm, um = ent:GetBoneMatrix(pa), ent:GetBoneMatrix(ua)
	if not (pm and um) then return end
	local kids = KK.Kids(ent, ua)
	local m = {[pa] = pm, [ua] = um}
	for i = 1, #kids do m[kids[i]] = ent:GetBoneMatrix(kids[i]) end
	return {r = r, pa = pa, ua = ua, kids = kids, m = m}
end

local function BlendBone(ent, b, p, ik, A, out, r)
	local cb, pi, pa = ik[b], ik[p], A.m[p]
	local ab = A.m[b]
	if not (cb and ab and pi and pa and out[p]) then return end
	local iA = pa:GetInverse()
	if not iA then return end
	local lA = iA * ab
	local l = lA
	if r < 0.999 then
		local iI = pi:GetInverse()
		if not iI then return end
		local lI = iI * cb
		l = Matrix()
		l:SetAngles(NLerpAng(r, lI:GetAngles(), lA:GetAngles()))
		l:SetTranslation(LerpVector(r, lI:GetTranslation(), lA:GetTranslation()))
	end
	local w = out[p] * l
	ent:SetBoneMatrix(b, w)
	out[b] = w
end

function KK.ArmBlend(ent, A)
	local ua, pa, kids, r = A.ua, A.pa, A.kids, A.r
	local ik = {[pa] = ent:GetBoneMatrix(pa), [ua] = ent:GetBoneMatrix(ua)}
	for i = 1, #kids do ik[kids[i]] = ent:GetBoneMatrix(kids[i]) end
	local out = {[pa] = ik[pa]}
	BlendBone(ent, ua, pa, ik, A, out, r)
	for i = 1, #kids do
		local b = kids[i]
		BlendBone(ent, b, ent:GetBoneParent(b), ik, A, out, r)
	end
end

function KK.HandOf(self, ply)
	local K = KK.K
	if K and K.wep == self then return K.H end
	local R = IsValid(ply) and KK.R[ply]
	if R and R.H and R.H.lp and ply:GetActiveWeapon() == self then return R.H end
end

function KK.HandPos(self)
	local ply = self:GetOwner()
	if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return false end
	local H, ls = KK.HandOf(self, ply), KK.LS[ply]
	if not H and not ls then return false end
	if not (hg and hg.DragLeftHand_Ex and hg.GetCurrentCharacter) then return false end
	local ent = hg.GetCurrentCharacter(ply)
	if not IsValid(ent) or ent ~= ply then return false end
	if ls and KK.inTPIK ~= ply then KK.DoLegs(ent, ply) end -- no TPIK wrap (PoseNow / other caller)
	if not H or (H.w or 0) <= 0.001 or not H.lp then return false end
	if hg.CanUseLeftHand and not hg.CanUseLeftHand(ply) then return false end
	self.lhandik = false self.rhandik = false
	local hand = ent:LookupBone("ValveBiped.Bip01_L_Hand")
	local hm = hand and ent:GetBoneMatrix(hand)
	if not hm then return false end
	local vec, off = self:HandOffset()
	local animPos, animAng = LocalToWorld(vec, off, hm:GetTranslation(), hm:GetAngles())
	local tPos, tAng = LocalToWorld(H.lp, H.la, H.o or ply:GetPos(), Angle(0, H.yaw or 0, 0))
	local rest = Clamp(H.rest or 0, 0, 1)
	if rest > 0.001 then
		-- down to the side / up from it on an arc: out around the raised knee, not through it
		-- (the arm itself is blended back to the animation's arm after the IK: KK.ArmBlend)
		local Fw, Lw = KK.Frame(H.yaw or 0)
		local arc = sin(math.pi * rest)
		tPos = LerpVector(rest, tPos, animPos) + Lw * (2.6 * arc) + Zv * (1.2 * arc)
		tAng = NLerpAng(rest, tAng, animAng)
	end
	local e = Smooth(H.w)
	local pPos, pAng = LerpVector(e, animPos, tPos), NLerpAng(e, animAng, tAng)
	-- phone pose -> wrist pose (inverse of the palm offset), like TossHand
	local _, inverse = WorldToLocal(vector_origin, angle_zero, vector_origin, off)
	local _, handAng = LocalToWorld(vector_origin, inverse, vector_origin, pAng)
	local disp = LocalToWorld(vec, angle_zero, vector_origin, handAng)
	hg.DragLeftHand_Ex(ent, self, pPos - disp, handAng)
	if self.STTS_LFing and self.STTS_ApplyLeftFingers then self.STTS_ApplyLeftFingers(self, ent, hand)
	elseif hg.set_hold then hg.set_hold(ent, "normal") end
	local open = (H.open or 0) * e
	if open > 0.001 and self.STTS_OpenFingers then self.STTS_OpenFingers(ent, hand, open) end
	-- caught: the phone flies the last bit into the palm
	local K = KK.K
	if K and K.wep == self and K.ph == PH_CAUGHT and (K.attach or 1) < 1 and K.cfP then
		local k = Smooth(K.attach)
		K.blendP, K.blendA, K.blendF = LerpVector(k, K.cfP, pPos), NLerpAng(k, K.cfA, pAng), FrameNumber()
	end
	return true
end

-- the phone out of the hand this frame (world pose) or nil = in the palm
function KK.Free(self)
	local K = KK.K
	if K and K.wep == self then
		if K.held then
			if K.ph == PH_CAUGHT and (K.attach or 1) < 1 and K.blendF == FrameNumber() then return K.blendP, K.blendA end
			return
		end
		return K.freeP, K.freeA
	end
	local ply = self:GetOwner()
	local R = IsValid(ply) and KK.R[ply]
	if R and R.freeP then return R.freeP, R.freeA end
end

if WRAP then KK.BaseSetHandPos, KK.BaseTossFree = SWEP.SetHandPos, SWEP.TossFree end
function SWEP:SetHandPos(...)
	local ok, r = pcall(KK.HandPos, self)
	if ok and r then return end
	if not ok then KK.Err(r) end
	return KK.BaseSetHandPos(self, ...)
end
function SWEP:TossFree(...)
	local p, a = KK.Free(self)
	if p then return p, a end
	return KK.BaseTossFree(self, ...)
end

--[[---------------------------------------------------------------------------
	your own keepy-uppy (KK.K)
---------------------------------------------------------------------------]]
-- defaults of stts_phone_kick_hold / stts_phone_kick_catch (the phone on the palm, glass up)
local HOLD_ANG, CATCH_ANG = Angle(-16, 26, -6), Angle(-24, 28, -6)
local angCache = {}
local function CvAng(cv, def)
	local str = cv:GetString()
	local c = angCache[cv]
	if c and c.s == str then return c.a end
	local n = {}
	for v in string.gmatch(str, "[%-%d%.]+") do n[#n + 1] = tonumber(v) end
	local a = (n[1] and n[2] and n[3]) and Angle(Clamp(n[1], -89, 89), n[2], n[3]) or def
	angCache[cv] = {s = str, a = a}
	return a
end

--[[ the drop, hand keys from RMB (real time): t (s), forward, left, up, wrist pitch (+ = the top down).
     a short dip (the wrist gives), a flick up that tosses the phone off the palm at REL_T, the
     hand stops short and gets out from under it (back, out, down) while the phone is still
     going up. then the arm goes down to the side (H.rest).
     Hermite with Catmull-Rom tangents: the hand never stops dead between the keys ]]
local TOSS_KEYS = {
	{0, 0, 0, 0, 0},
	{0.11, 0.2, 0, -1.4, 5},
	{0.19, 0.1, 0.1, 0.5, -5},
	{0.24, 0, 0.3, 1, -8},
	{0.32, -2.2, 2.6, -0.8, -4},
	{0.44, -3.8, 4.2, -2.6, 0},
}
for i, k in ipairs(TOSS_KEYS) do
	local a, b = TOSS_KEYS[i - 1], TOSS_KEYS[i + 1]
	local m = {0, 0, 0, 0}
	if a and b then for j = 1, 4 do m[j] = (b[j + 1] - a[j + 1]) / (b[1] - a[1]) end end
	k.m = m
end
local function TossKey(t)
	local keys = TOSS_KEYS
	local n = #keys
	if t <= 0 then return 0, 0, 0, 0 end
	if t >= keys[n][1] then local e = keys[n] return e[2], e[3], e[4], e[5] end
	for i = 1, n - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			local d = b[1] - a[1]
			local s = (t - a[1]) / d
			local s2 = s * s
			local s3 = s2 * s
			local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, (s3 - 2 * s2 + s) * d, 3 * s2 - 2 * s3, (s3 - s2) * d
			local am, bm = a.m, b.m
			return h00 * a[2] + h10 * am[1] + h01 * b[2] + h11 * bm[1],
				h00 * a[3] + h10 * am[2] + h01 * b[3] + h11 * bm[2],
				h00 * a[4] + h10 * am[3] + h01 * b[4] + h11 * bm[3],
				h00 * a[5] + h10 * am[4] + h01 * b[5] + h11 * bm[4]
		end
	end
	local e = keys[n]
	return e[2], e[3], e[4], e[5]
end
KK.TossKey = TossKey

-- critically damped spring toward tgt (the exact step, stable for any frame time); numbers or vectors
local function Spring(x, v, tgt, w, h)
	local y = x - tgt
	local q = (v + y * w) * h
	local e = exp(-w * h)
	return tgt + (y + q) * e, (v - q * w) * e
end
KK.Spring = Spring

local function Send(op, wep, fn)
	net.Start("stts_phone_kick")
	net.WriteUInt(op, 3)
	net.WriteEntity(wep)
	if fn then fn() end
	net.SendToServer()
end

function KK.Start(wep)
	local ply = LocalPlayer()
	if not (IsValid(wep) and IsValid(ply) and KK.CanKick(wep, ply)) then return false end
	local ea = ply:EyeAngles()
	local yaw, o = ea.y, ply:GetPos()
	local m = (KK.LS[ply] and KK.Meas[ply]) or KK.MeasureNow(ply, o, yaw) or KK.Meas[ply] or KK.DefMeas
	local mm = {}
	for k, v in pairs(m) do mm[k] = v end
	-- the sim works with the hip where the balance shift puts it (the foot ranges with the real one)
	local bal = cvBal:GetFloat()
	mm.hy0 = mm.hy
	mm.hy, mm.hz = mm.hy - C.BAL_SIDE * bal, mm.hz - C.BAL_DOWN * bal
	local eyeZ = Clamp(ply:EyePos().z - o.z, 40, 80)
	local M = wep:Geo()
	local K = {wep = wep, ply = ply, ph = PH_LIFT, t = 0, st = 0, o = o, yaw = yaw, p0 = ea.p, camP = ea.p, camY = yaw,
		eyeZ = eyeZ, m = mm, lw = 0, hw = 0, ts = 1, mx = 0, my = 0, fwd = 0, juggles = 0,
		ck = 0, cg = 0, cc = 0, sendT = 0, rmbWas = true, held = true, mins = M.Mins, maxs = M.Maxs}
	K.FW, K.FL = KK.Frame(yaw)
	K.FA = Angle(0, yaw, 0)
	K.F = {tx = C.DEF_X, ty = mm.hy0 + C.DEF_Y, tz = C.DEF_Z, x = mm.ax, y = mm.ay, z = mm.az, vx = 0, vy = 0, vz = 0, pitch = mm.fp, prate = 0}
	K.S = KK.NewSim(mm, eyeZ)
	local r = K.S.caps[4]
	r.ay, r.by = -abs(mm.hy0), -abs(mm.hy0)
	K.S.g = Clamp(tonumber(GetConVarNumber("sv_gravity")) or 600, 100, 3000)
	KK.SimLeg(K.S, K.F, mm)
	K.rx, K.ry = Clamp(K.S.plate.cx + C.DROP_FWD, 14, 25), Clamp(K.S.plate.cy, mm.hy0 - 2, mm.hy0 + 6)
	K.H = {w = 0, open = 0, rest = 0, lp = Vector(K.rx, K.ry, eyeZ - C.DROP_DZ), la = CvAng(cvHold, HOLD_ANG), yaw = yaw, o = o}
	KK.K = K
	KK.LS[ply] = KK.LS[ply] or {w = 0}
	Send(1, wep)
	return true
end

function KK.Request(wep)
	if KK.K then return end
	if not KK.Start(wep) then KK.Deny() end
end

function KK.Clear()
	local K = KK.K
	KK.K = nil
	if K and not K.endSent and IsValid(K.wep) then Send(3, K.wep) end
end

function KK.SendEnd(K)
	if K.endSent then return end
	K.endSent = true
	if IsValid(K.wep) then Send(3, K.wep) end
end

function KK.Out(K)
	if K.ph == PH_OUT then return end
	K.ph, K.to, K.lw0, K.hw0 = PH_OUT, 0, K.lw, K.hw
end

-- the phone is not in the hand any more: the server drops it exactly like this
function KK.SendDrop(K)
	if K.dropped then return end
	local b = K.body
	local pos, ang = KK.BodyLocalPose(b)
	local wp, wa = LocalToWorld(pos, ang, K.o, K.FA)
	local v = K.FW * b.vx + K.FL * b.vy + Zv * b.vz
	local d = deg(1)
	local av = Vector((b.wx * b.e1x + b.wy * b.e1y + b.wz * b.e1z) * d, (b.wx * b.e2x + b.wy * b.e2y + b.wz * b.e2z) * d, (b.wx * b.e3x + b.wy * b.e3y + b.wz * b.e3z) * d)
	Send(2, K.wep, function()
		net.WriteVector(wp) net.WriteAngle(wa) net.WriteVector(v) net.WriteVector(av)
	end)
	K.dropped, K.endSent = true, true
	KK.Out(K)
end

function KK.Abort(K)
	if K.body and not K.held then KK.SendDrop(K) return end
	KK.SendEnd(K)
	KK.Out(K)
end

function KK.Broken(K)
	local ply = K.ply
	local org = ply.organism
	if org and (org.otrub or org.canmove == false) then return true end
	if hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) ~= ply then return true end
	if not KK.LegsOK(ply) or ply:GetPos():DistToSqr(K.o) > 24 * 24 then return true end
	if K.held and K.ph ~= PH_OUT and hg and hg.CanUseLeftHand and not hg.CanUseLeftHand(ply) then return true end
	return false
end

function KK.BodyLocalPose(b)
	local ox, oy, oz = KK.BodyOrigin(b)
	return Vector(ox, oy, oz), Vector(b.e1x, b.e1y, b.e1z):AngleEx(Vector(b.e3x, b.e3y, b.e3z))
end

local function BodyWorld(K)
	local b = K.body
	return L2W(K.o, K.FW, K.FL, b.px, b.py, b.pz)
end

-- the hand lets go: the phone starts as a body where the palm held it
function KK.Release(K)
	local b = KK.Body(K.mins, K.maxs)
	local lp, la = K.H.lp, K.H.la
	local f, r, u = la:Forward(), la:Right(), la:Up()
	KK.BodySet(b, lp.x, lp.y, lp.z, f.x, f.y, f.z, -r.x, -r.y, -r.z, u.x, u.y, u.z)
	-- tossed off the palm: the speed of the hand (its spring) + the flick of the fingers / wrist,
	-- a little up (~1.5 units) so the hand has the time to get out from under it, a little random
	local v = K.hs and K.hs.v
	b.vx = Clamp(v and v.x or 0, -6, 6) + math.Rand(-0.8, 0.8)
	b.vy = Clamp(v and v.y or 0, -6, 6) + math.Rand(-0.8, 0.8)
	b.vz = Clamp(v and v.z or 0, 0, 24) + 26 + math.Rand(0, 6)
	-- a little spin (an open hand lets it go almost flat)
	b.wx, b.wy, b.wz = math.Rand(-0.2, 0.2), math.Rand(-0.45, 0.45), math.Rand(-0.6, 0.6)
	K.body, K.held, K.ph = b, false, PH_AIR
	K.fromFoot, K.reach, K.hp = false, false, nil
end

function KK.NearFoot(K)
	local b, P = K.body, K.S.plate
	if not b or b.vz >= 0 or not P.cx then return false end
	local dh = b.pz - (P.cz + P.nz * P.ht)
	return dh > -1 and dh < 14 and ((b.px - P.cx) ^ 2 + (b.py - P.cy) ^ 2) < 81
end

-- the floor under the phone (one trace per frame), as a plane in the local frame
function KK.Ground(K)
	local c = BodyWorld(K)
	local tr = util.TraceLine({start = c + Zv * 6, endpos = c - Zv * 600, filter = {K.ply, K.wep}, mask = MASK_SOLID})
	local g = K.S.gnd
	if tr.Hit and not tr.StartSolid then
		g.px, g.py, g.pz = W2L(K.o, K.FW, K.FL, tr.HitPos)
		local n = tr.HitNormal
		g.nx, g.ny, g.nz = n:Dot(K.FW), n:Dot(K.FL), n.z
	elseif not tr.Hit then
		g.px, g.py, g.pz, g.nx, g.ny, g.nz = 0, 0, -600, 0, 0, 1
	end
end

-- walls (and anything it would fly through this frame)
function KK.Walls(K, prevW)
	local b = K.body
	local now = BodyWorld(K)
	if now:DistToSqr(prevW) < 1e-4 then return end
	local tr = util.TraceLine({start = prevW, endpos = now, filter = {K.ply, K.wep}, mask = MASK_SOLID})
	if not tr.Hit or tr.StartSolid then return end
	local n = tr.HitNormal
	local nx, ny, nz = n:Dot(K.FW), n:Dot(K.FL), n.z
	b.px, b.py, b.pz = W2L(K.o, K.FW, K.FL, tr.HitPos + n * 1.2)
	local vn = b.vx * nx + b.vy * ny + b.vz * nz
	if vn >= 0 then return end
	local k = 1.3 * vn
	b.vx, b.vy, b.vz = b.vx - nx * k, b.vy - ny * k, b.vz - nz * k
	b.wx, b.wy, b.wz = b.wx * 0.7, b.wy * 0.7, b.wz * 0.7
	if -vn > 25 then
		K.cg = K.cg + 1
		KK.Snd(-vn > 120 and 2 or 1, tr.HitPos, Clamp(-vn / 200, 0.3, 0.9))
	end
	if nz > 0.7 and K.ph == PH_AIR then K.ph, K.tg, K.restT = PH_GROUND, 0, 0 end
end

-- what the phone touched this frame: kicks (+ counter), sounds, the floor
function KK.Events(K, maxFV)
	local S, b = K.S, K.body
	local pos = K.freeP or BodyWorld(K)
	if S.hi[K_PLATE] > 0 then
		local vin = S.hv[K_PLATE]
		if maxFV > C.KICK_FV and b.vz > C.KICK_PV and K.st - (K.lastKick or -9) > C.KICK_CD and K.ph == PH_AIR then
			K.lastKick, K.juggles, K.fromFoot, K.ck = K.st, K.juggles + 1, true, K.ck + 1
			KK.Snd(vin > 60 and 2 or 1, pos, 0.75)
			KK.Counter(K.juggles)
		elseif vin > 25 then
			K.ck = K.ck + 1
			KK.Snd(1, pos, Clamp(vin / 150, 0.25, 0.7))
		end
	end
	for k = K_SHIN, K_RLEG do
		if S.hi[k] > 0 then
			if S.hv[k] > 30 then K.ck = K.ck + 1 KK.Snd(3, pos, 0.35) end
		end
	end
	if S.hi[K_GND] > 0 then
		local vin = S.hv[K_GND]
		if K.ph == PH_AIR then K.ph, K.tg, K.restT = PH_GROUND, 0, 0 end
		if vin > 15 then
			K.cg = K.cg + 1
			KK.Snd(vin > 120 and 2 or 1, pos, Clamp(vin / 200, 0.3, 0.9))
		end
	end
end

--[[ RMB again while it flies: the left hand comes out and the mouse moves it (K.hp, the
     local frame). it stays where an arm gets: REACH_R from the shoulder, not into the
     chest, from about the knee to the eyes ]]
function KK.HandClamp(K, p)
	local sx, sy, sz, R = C.SH_X, C.SH_Y, K.eyeZ - C.SH_DZ, C.REACH_R
	p.x, p.y, p.z = Clamp(p.x, C.REACH_X0, 27), Clamp(p.y, -8, 20), Clamp(p.z, K.eyeZ - 40, K.eyeZ + 2)
	local dx, dy, dz = p.x - sx, p.y - sy, p.z - sz
	local d = sqrt(dx * dx + dy * dy + dz * dz)
	if d > R then
		local k = R / d
		p.x, p.y, p.z = sx + dx * k, sy + dy * k, sz + dz * k
	end
	return p
end

-- out: in front of the chest over the foot, where it held the phone (then the mouse has it)
function KK.HandOut(K)
	K.reach, K.hp = true, KK.HandClamp(K, Vector(K.rx - 1, K.ry + 1, K.eyeZ - C.DROP_DZ + 1))
end

-- the phone touches the hand that is out for it = caught (the closest it came this frame: it can be fast)
function KK.TryCatch(K)
	if not K.reach or (K.H.rest or 1) > 0.3 or (K.tr or 0) < C.REL_T + C.REACH_MIN then return end
	local b, hp = K.body, K.H.lp
	local ax, ay, az = K.bx0 or b.px, K.by0 or b.py, K.bz0 or b.pz
	local ux, uy, uz = b.px - ax, b.py - ay, b.pz - az
	local l2 = ux * ux + uy * uy + uz * uz
	local s = l2 > 1e-6 and Clamp(((hp.x - ax) * ux + (hp.y - ay) * uy + (hp.z - az) * uz) / l2, 0, 1) or 1
	local cx, cy, cz = ax + ux * s - hp.x, ay + uy * s - hp.y, az + uz * s - hp.z
	if cx * cx + cy * cy + cz * cz < C.TOUCH_R * C.TOUCH_R then KK.Catch(K) end
end

function KK.Catch(K)
	K.held, K.ph, K.tc, K.attach = true, PH_CAUGHT, 0, 0
	K.cfP, K.cfA = K.freeP or BodyWorld(K), K.freeA or K.FA
	K.catchP = Vector(K.H.lp) -- where the palm is right now (no jump)
	local b = K.body
	local sp = sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
	K.catchAmp = Clamp(sp * 0.011, 0.5, 2.2) -- a faster phone pushes the palm further
	-- ... the way it was going (caught on the way up = the hand goes up with it a bit)
	local d = Vector(0.3, 0, 1) -- (down / back if it was slow)
	if sp > 1 then d = LerpVector(Clamp(sp / 80, 0, 0.85), d, Vector(-b.vx, -b.vy, -b.vz) / sp) end
	d:Normalize()
	K.catchD = d
	K.cc, K.reach, K.hp, K.juggles = K.cc + 1, false, nil, 0
	KK.Snd(3, K.cfP, 0.55)
end

function KK.Bounds(K)
	local b = K.body
	if b.px * b.px + b.py * b.py + (b.pz - 40) ^ 2 > 230 * 230 or b.pz < -400 then KK.SendDrop(K) end
end

function KK.Phase(K, dtR, dt)
	local ph = K.ph
	if K.tr then K.tr = K.tr + dtR end -- the hand runs in real time (from RMB)
	if ph == PH_LIFT then
		K.lw = Smooth(K.t / (C.LIFT * 0.9)) -- the leg a moment before the hand
		K.hw = Smooth5(K.t / C.LIFT)
		if K.t >= C.LIFT then K.ph, K.t, K.lw, K.hw = PH_READY, 0, 1, 1 end
	elseif ph == PH_READY then
		K.lw, K.hw = 1, 1
	elseif ph == PH_TOSS then
		K.tt = K.tt + dt
		if (K.tr or 0) >= C.REL_T and K.held then KK.Release(K) end
	elseif ph == PH_AIR then
		K.tt = (K.tt or 0) + dt
		if K.reach then KK.TryCatch(K) end
		if K.ph == PH_AIR then KK.Bounds(K) end
	elseif ph == PH_GROUND then
		K.tt = (K.tt or 0) + dt
		K.tg = K.tg + dt
		if K.reach then KK.TryCatch(K) end
		if K.ph ~= PH_GROUND then return end
		local b = K.body
		if b.vx * b.vx + b.vy * b.vy + b.vz * b.vz < 9 and b.wx * b.wx + b.wy * b.wy + b.wz * b.wz < 2.25 then K.restT = K.restT + dt else K.restT = 0 end
		if K.restT > 0.3 or K.tg > 1.6 then KK.SendDrop(K) else KK.Bounds(K) end
	elseif ph == PH_CAUGHT then
		K.tc = K.tc + dtR
		K.attach = min((K.attach or 0) + dtR / C.ATTACH, 1)
		if K.tc >= C.HOLD then KK.SendEnd(K) KK.Out(K) end
	elseif ph == PH_OUT then
		K.to = K.to + dtR
		local k = 1 - Smooth5(K.to / C.OUT)
		K.lw, K.hw = (K.lw0 or 0) * k, (K.hw0 or 0) * k
		if K.to >= C.OUT and (not K.dropped or K.to > 1.5) then KK.Clear() end
	end
end

--[[ the phone pose the left hand holds now (local frame), its weight, how open it is and how
     far the arm went back down to the side. the raw target of every phase goes through a
     critically damped spring (K.hs): a phase switch never snaps, a quick move speeds up and
     stops like an arm does, the flick gives the phone its speed (KK.Release) ]]
function KK.HandTarget(K, dtR)
	local H, m, P, ph = K.H, K.m, K.S.plate, K.ph
	local holdA, catchA = CvAng(cvHold, HOLD_ANG), CvAng(cvCatch, CATCH_ANG)
	if ph == PH_LIFT or ph == PH_READY then -- over the top of the foot, follows it (smoothed)
		local k = 1 - exp(-dtR * 5)
		K.rx = K.rx + (Clamp(P.cx + C.DROP_FWD, 14, 25) - K.rx) * k
		K.ry = K.ry + (Clamp(P.cy, m.hy0 - 2, m.hy0 + 6) - K.ry) * k
	end
	local base = Vector(K.rx, K.ry, K.eyeZ - C.DROP_DZ)
	local pos, ang, open, rest, w = base, holdA, 0.06, 0, C.HAND_W
	local tgt = K.tgt
	if ph == PH_LIFT then
		-- up from the idle hold on a small arc, turning glass up on the way
		local s = Smooth5(K.t / C.LIFT)
		pos = base + Vector(-1.5 * (1 - s), 0.6 * (1 - s), 2 * sin(math.pi * s) - 1.2 * (1 - s))
	elseif ph == PH_READY then
		-- held out still, only breathing
		local t = K.t
		pos = base + Vector(0, 0.15 * sin(t * 1.7), 0.3 * sin(t * 1.25 + 0.6))
		ang = Angle(holdA.p + 1.2 * sin(t * 1.1), holdA.y, holdA.r + 0.8 * sin(t * 0.9 + 1))
	elseif (ph == PH_TOSS or ph == PH_AIR or ph == PH_GROUND) and K.tr then
		local tr = K.tr
		local dx, dy, dz, dp = TossKey(tr)
		pos = base + Vector(dx, dy, dz)
		ang = Angle(holdA.p + dp, holdA.y, holdA.r)
		w = C.HAND_W_TOSS
		open = 0.06 + Smooth((tr - C.REL_T + 0.03) / 0.07) * 0.64 -- the fingers open as it leaves
		-- then the arm goes back down to the side and balances there, the hand relaxed
		rest = Smooth5((tr - C.REL_T - C.REST_AT) / C.REST_T)
		open = open + (0.25 - open) * rest
		if rest > 0.25 then w = C.HAND_W end
		if K.reach and K.hp then
			-- out (RMB): up from the side, then where the mouse puts it, the palm open
			pos, ang, open, rest, w = K.hp, catchA, 0.85, 0, C.HAND_W_REACH
		end
	elseif ph == PH_CAUGHT or (ph == PH_OUT and K.catchP) then
		local tc = ph == PH_CAUGHT and K.tc or (C.HOLD + K.to)
		local amp = K.catchAmp or 1.2
		-- the palm gives under it and springs back, the wrist with it
		local dip = exp(-7 * tc) * sin(16 * tc) * amp
		-- then the hand brings it in a little, as you look at what you caught
		local back = Smooth5((tc - 0.14) / 0.45)
		local cd = K.catchD or Vector(0.3, 0, 1)
		pos = K.catchP + Vector(-cd.x * dip - 3 * back, -cd.y * dip + 0.6 * back, -cd.z * dip + 1.5 * back)
		ang = NLerpAng(back, Angle(catchA.p + 5 * dip, catchA.y, catchA.r), holdA)
		open = 0.85 * (1 - Smooth(tc / 0.12)) -- the fingers close on it
		w = C.HAND_W_TOSS
	elseif ph == PH_OUT and tgt then
		-- stopped (R) / aborted: stays where it was, the weight takes it back to the idle hold
		pos, ang, rest = tgt.p, tgt.a, tgt.r
		open = tgt.o * (1 - Smooth(K.to / 0.25))
	end
	if not tgt then tgt = {} K.tgt = tgt end
	tgt.p, tgt.a, tgt.o, tgt.r = pos, ang, open, rest
	-- the spring
	local hs = K.hs
	if not hs then
		hs = {p = Vector(pos), v = Vector(0, 0, 0), a = ang, r = rest, rv = 0, o = open}
		K.hs = hs
	end
	local h = min(dtR, 0.05)
	hs.p, hs.v = Spring(hs.p, hs.v, pos, w, h)
	hs.r, hs.rv = Spring(hs.r, hs.rv, rest, max(w * 0.8, 20), h)
	hs.a = NLerpAng(1 - exp(-h * w * 0.75), hs.a, ang)
	hs.o = hs.o + (open - hs.o) * (1 - exp(-h * 24))
	H.lp, H.la, H.open, H.rest = hs.p, hs.a, Clamp(hs.o, 0, 1), Clamp(hs.r, 0, 1)
	H.w, H.yaw, H.o = K.hw, K.yaw, K.o
end

function KK.Camera(K, dtR)
	local tp, ty, ph = C.CAM_P, K.yaw, K.ph
	if ph == PH_OUT then
		tp = K.p0
	elseif K.body and not K.held and K.freeP then -- follows the phone a bit (the hand is out: between them)
		local at = K.freeP
		if K.reach and K.H.lp then at = (at + L2W(K.o, K.FW, K.FL, K.H.lp.x, K.H.lp.y, K.H.lp.z)) * 0.5 end
		local a = (at - K.ply:EyePos()):Angle()
		tp = C.CAM_P + (Clamp(math.NormalizeAngle(a.p), 18, 75) - C.CAM_P) * C.CAM_FOLLOW
		ty = K.yaw + Clamp(math.AngleDifference(a.y, K.yaw) * C.CAM_FOLLOW, -C.CAM_YAW, C.CAM_YAW)
	elseif ph == PH_CAUGHT then
		tp = C.CAM_P - 8
	end
	local k = 1 - exp(-dtR * C.CAM_RATE)
	K.camP = K.camP + (tp - K.camP) * k
	K.camY = K.camY + math.AngleDifference(ty, K.camY) * k
end

-- the stream for the players around (20 / s + on every phase change)
function KK.Send(K)
	local now = RealTime()
	if now < K.sendT and K.ph == K.sentPh then return end
	K.sendT, K.sentPh = now + C.SEND, K.ph
	local s = K.sample or {}
	K.sample = s
	local F, H = K.F, K.H
	s.ph, s.lw, s.yaw, s.fx, s.fy, s.fz, s.fpt = K.ph, K.lw, K.yaw, F.x, F.y, F.z, F.pitch
	s.hw, s.ho, s.hb = H.w or 0, H.open or 0, H.rest or 0
	s.hx, s.hy, s.hz, s.hp, s.hya, s.hr = H.lp.x, H.lp.y, H.lp.z, H.la.p, H.la.y, H.la.r
	s.free = K.lpP ~= nil
	if s.free then s.px, s.py, s.pz, s.pp, s.pya, s.pr = K.lpP.x, K.lpP.y, K.lpP.z, K.lpA.p, K.lpA.y, K.lpA.r end
	s.ck, s.cg, s.cc = K.ck, K.cg, K.cc
	net.Start("stts_phone_kick_s", true)
	KK.WriteSample(s)
	net.SendToServer()
end

function KK.LocalThink()
	local K = KK.K
	if not K then return end
	local ply, wep = K.ply, K.wep
	if not (IsValid(ply) and IsValid(wep)) or ply ~= LocalPlayer() or not ply:Alive() or ply:GetActiveWeapon() ~= wep or wep:GetOwner() ~= ply then
		KK.Clear() -- dropped (the server took it), switched away, dead: the legs fade by themselves
		return
	end
	local dtR = Clamp(RealFrameTime(), 0, 0.05)
	if dtR <= 0 then return end
	if K.ph ~= PH_OUT and KK.Broken(K) then KK.Abort(K) end
	local m, F, S = K.m, K.F, K.S
	K.t = K.t + dtR
	-- buttons
	local free = not (gui.IsGameUIVisible() or vgui.CursorVisible())
	local rmb = free and input.IsMouseDown(MOUSE_RIGHT)
	local rmbPress = rmb and not K.rmbWas
	K.rmbWas = rmb
	local rPress = K.rPress
	K.rPress = nil
	if rPress then
		if K.ph == PH_LIFT or K.ph == PH_READY then KK.SendEnd(K) KK.Out(K)
		elseif K.ph == PH_TOSS or K.ph == PH_AIR then K.lower = true end
	end
	if rmbPress then
		if K.ph == PH_READY then
			K.ph, K.tt, K.tr = PH_TOSS, 0, 0
		elseif (K.ph == PH_AIR or K.ph == PH_GROUND) and not K.held then
			if K.reach then K.reach, K.hp = false, nil else KK.HandOut(K) end -- the left hand out / back down
		end
	end
	-- the foot target: mouse = sideways / height, W S = forward / back
	local sv = GetConVar("sensitivity")
	local sens = C.FOOT_SENS * cvSens:GetFloat() * ((sv and sv:GetFloat() or 3) / 3)
	if K.reach and K.hp and not K.held then
		-- the left hand is out (RMB): the mouse moves it the same way, the foot stays
		local hp, hs = K.hp, sens * C.HAND_SENS
		hp.y, hp.z = hp.y - K.mx * hs, hp.z - K.my * hs
		hp.x = hp.x + K.fwd * C.HAND_FWD * dtR
		KK.HandClamp(K, hp)
		if K.ph ~= PH_AIR or K.lower then F.tx, F.ty, F.tz, F.ptgt = m.ax, m.ay, m.az + 0.3, m.fp end
	elseif (K.ph == PH_READY or K.ph == PH_TOSS or K.ph == PH_AIR) and not K.lower then
		F.ty = Clamp(F.ty - K.mx * sens, m.hy0 + C.FY0, m.hy0 + C.FY1)
		F.tz = Clamp(F.tz - K.my * sens, C.FZ0, C.FZ1)
		F.tx = Clamp(F.tx + K.fwd * C.FOOT_FWD * dtR, C.FX0, C.FX1)
		F.ptgt = nil
	elseif K.ph ~= PH_LIFT then -- down again: on the floor / caught / out / R in the air
		F.tx, F.ty, F.tz, F.ptgt = m.ax, m.ay, m.az + 0.3, m.fp
	end
	K.mx, K.my = 0, 0
	-- slow motion while it flies
	local b = K.body
	local flying = b ~= nil and not K.held
	local tsT = 1
	if flying and (K.ph == PH_AIR or K.ph == PH_GROUND) then
		tsT = cvSlow:GetFloat()
		if KK.NearFoot(K) then tsT = min(tsT, cvSlowMin:GetFloat()) end
	end
	K.ts = K.ts + (tsT - K.ts) * (1 - exp(-dtR * 6))
	local dt = dtR * K.ts
	-- substeps: the foot spring, the phone
	local n = Clamp(ceil(dt * C.HZ), 1, C.MAXSUB)
	local h = dt / n
	for k = 1, NKIND do S.hi[k], S.hv[k] = 0, 0 end
	local maxFV, prevW = -1e9, nil
	if flying then KK.Ground(K) prevW = BodyWorld(K) K.bx0, K.by0, K.bz0 = b.px, b.py, b.pz end
	for _ = 1, n do
		KK.FootStep(F, m, h)
		if F.vz > maxFV then maxFV = F.vz end
		KK.SimLeg(S, F, m)
		if flying then KK.SimStep(b, S, h) end
		K.st = K.st + h
	end
	if flying then
		KK.Walls(K, prevW)
		KK.Events(K, maxFV)
	end
	KK.Phase(K, dtR, dt)
	if KK.K ~= K then return end
	KK.HandTarget(K, dtR)
	-- the free phone (world, for the draw / the cameras of the phone)
	if K.body and not K.held then
		K.lpP, K.lpA = KK.BodyLocalPose(K.body)
		K.freeP, K.freeA = LocalToWorld(K.lpP, K.lpA, K.o, K.FA)
	else
		K.lpP, K.lpA, K.freeP, K.freeA = nil, nil, nil, nil
	end
	KK.Camera(K, dtR)
	local ls = KK.LS[ply] or {w = 0}
	KK.LS[ply] = ls
	ls.w, ls.x, ls.y, ls.z, ls.pitch, ls.yaw, ls.o, ls.drv = K.lw, F.x, F.y, F.z, F.pitch, K.yaw, K.o, FrameNumber()
	KK.Send(K)
end

--[[---------------------------------------------------------------------------
	the other players: their stream, drawn 0.1 s late (interpolated)
---------------------------------------------------------------------------]]
net.Receive("stts_phone_kick_s", function()
	local ply = net.ReadEntity()
	local s = KK.ReadSample()
	if not (IsValid(ply) and ply:IsPlayer()) or ply == LocalPlayer() then return end
	local R = KK.R[ply]
	if not R then R = {buf = {}, fade = 0} KK.R[ply] = R end
	s.t = RealTime()
	local buf = R.buf
	buf[#buf + 1] = s
	while #buf > 12 do table.remove(buf, 1) end
end)

net.Receive("stts_phone_kick", function()
	local op = net.ReadUInt(3)
	local wep = net.ReadEntity()
	local K = KK.K
	if op == 4 and K and K.wep == wep then -- refused by the server
		K.endSent = true
		KK.Clear()
		KK.Deny()
	end
end)

local function RemoteSounds(ply, R, s)
	if R.ck == nil then R.ck, R.cg, R.cc = s.ck, s.cg, s.cc return end
	local pos = R.freeP or (ply:GetPos() + Zv * 20)
	if s.ck ~= R.ck then KK.Snd(1, pos, 0.55) end
	if s.cg ~= R.cg then KK.Snd(2, pos, 0.6) end
	if s.cc ~= R.cc then KK.Snd(3, pos, 0.5) end
	R.ck, R.cg, R.cc = s.ck, s.cg, s.cc
end

function KK.RemoteThink(dtR)
	local now = RealTime()
	local rt = now - C.INTERP
	for ply, R in pairs(KK.R) do
		local buf = R.buf
		local last = buf[#buf]
		if not IsValid(ply) or not last or now - last.t > 3 then
			KK.R[ply] = nil
		else
			local a, b = buf[1], buf[1]
			for i = #buf, 1, -1 do
				if buf[i].t <= rt then a, b = buf[i], buf[i + 1] or buf[i] break end
			end
			local f = (b ~= a) and Clamp((rt - a.t) / max(b.t - a.t, 1e-3), 0, 1) or 0
			RemoteSounds(ply, R, a)
			local stale = now - last.t > 0.3 or last.ph == PH_OUT and now - last.t > 0.1
			R.fade = Clamp((R.fade or 0) + (stale and -dtR / C.OUT or dtR / 0.15), 0, 1)
			local yaw = a.yaw + math.AngleDifference(b.yaw, a.yaw) * f
			local ls = KK.LS[ply] or {w = 0}
			KK.LS[ply] = ls
			ls.w = Lerp(f, a.lw, b.lw) * R.fade
			ls.x, ls.y, ls.z = Lerp(f, a.fx, b.fx), Lerp(f, a.fy, b.fy), Lerp(f, a.fz, b.fz)
			ls.pitch, ls.yaw, ls.o, ls.drv = Lerp(f, a.fpt, b.fpt), yaw, nil, FrameNumber()
			local H = R.H or {}
			R.H = H
			local ah = a.hx and a or b
			local bh = b.hx and b or a
			if ah.hx then
				H.lp = LerpVector(f, Vector(ah.hx, ah.hy, ah.hz), Vector(bh.hx, bh.hy, bh.hz))
				H.la = NLerpAng(f, Angle(ah.hp, ah.hya, ah.hr), Angle(bh.hp, bh.hya, bh.hr))
			end
			H.w = H.lp and Lerp(f, a.hw, b.hw) * R.fade or 0
			H.open = Lerp(f, a.ho, b.ho)
			H.rest = Lerp(f, a.hb or 0, b.hb or 0)
			H.yaw, H.o = yaw, ply:GetPos()
			local fa = Angle(0, yaw, 0)
			if a.free and R.fade > 0.3 then
				local lp, la = Vector(a.px, a.py, a.pz), Angle(a.pp, a.pya, a.pr)
				if b.free and b ~= a then
					lp = LerpVector(f, lp, Vector(b.px, b.py, b.pz))
					la = NLerpAng(f, la, Angle(b.pp, b.pya, b.pr))
				end
				R.freeP, R.freeA = LocalToWorld(lp, la, ply:GetPos(), fa)
			else
				R.freeP, R.freeA = nil, nil
			end
		end
	end
end

function KK.LegsThink(dtR)
	local f = FrameNumber()
	for ply, ls in pairs(KK.LS) do
		if not IsValid(ply) then
			KK.LS[ply] = nil
		elseif ls.drv ~= f then
			ls.w = (ls.w or 0) - dtR / C.OUT
			if ls.w <= 0 then KK.LS[ply] = nil end
		end
	end
end

hook.Add("Think", "STTS_PhoneKick", function()
	KK.WrapTPIK()
	local dtR = Clamp(RealFrameTime(), 0, 0.05)
	if KK.K then
		local ok, err = pcall(KK.LocalThink)
		if not ok then
			KK.Err(err)
			KK.Clear()
		end
	end
	if next(KK.R) then
		local ok, err = pcall(KK.RemoteThink, dtR)
		if not ok then KK.Err(err) end
	end
	if next(KK.LS) then KK.LegsThink(dtR) end
end)

--[[---------------------------------------------------------------------------
	input: the mouse moves the foot (the view is held), W S move it, R stops,
	nothing else (jump, crouch, use, weapon switch, the Q menu) meanwhile
---------------------------------------------------------------------------]]
hook.Add("CreateMove", "STTS_PhoneKick", function(cmd)
	local K = KK.K
	if not K then return end
	local fm = cmd:GetForwardMove()
	K.fwd = fm > 0 and 1 or (fm < 0 and -1 or 0)
	cmd:ClearMovement()
	cmd:RemoveKey(BLOCK)
end)

local BLOCK_BINDS = {"+attack", "+jump", "+duck", "+use", "invnext", "invprev", "slot", "lastinv", "+speed", "+walk", "+menu", "+zoom"}
hook.Add("PlayerBindPress", "STTS_PhoneKick", function(_, bind, pressed)
	local K = KK.K
	if not K then return end
	bind = string.lower(bind or "")
	if string.find(bind, "+reload", 1, true) then
		if pressed then K.rPress = true end
		return true
	end
	for i = 1, #BLOCK_BINDS do
		if string.find(bind, BLOCK_BINDS[i], 1, true) then return true end
	end
end)

-- Z-City: InputMouseApply "fakeCameraAngles" -> HG.InputMouseApply
hook.Add("HG.InputMouseApply", "STTS_PhoneKick", function(tbl)
	local K = KK.K
	if not K then return end
	K.mx, K.my = K.mx + (tonumber(tbl.x) or 0), K.my + (tonumber(tbl.y) or 0)
	tbl.x, tbl.y = 0, 0
	tbl.angle = Angle(K.camP, K.camY, 0)
	tbl.override_angle = true
end)
-- fix71: the same from any InputMouseApply hook (cl_compat.lua puts it in front of foreign ones)
function STTS.KickMouse71(cmd, x, y)
	local K = KK.K
	if not K then return false end
	K.mx, K.my = K.mx + (tonumber(x) or 0), K.my + (tonumber(y) or 0)
	cmd:SetViewAngles(Angle(K.camP, K.camY, 0))
	return true
end
hook.Add("InputMouseApply", "STTS_PhoneKick", function(cmd, x, y)
	if not KK.K then return end
	local t = hook.GetTable().InputMouseApply
	if t and t.fakeCameraAngles then return end -- Z-City does it through HG.InputMouseApply
	if STTS.KickMouse71(cmd, x, y) then return true end
end)

--[[---------------------------------------------------------------------------
	fix56: the juggle counter (every kick that keeps it up without the hand). done
	like the Fury-13 kill counter of Z-City (homigrad/sh_notification.lua, the
	berserk notification): the same font ("Who asks Satan", ScreenScale 25), typed
	letter by letter with the peep (a pause on a full stop), at the bottom middle,
	scaled with the beat, shaken, 40 copies smeared around it on a circle, glowing,
	fading out over ~4 s. white instead of pink. a new kick replaces it at once.
	the beat: Fury pulses with its music, here every kick is the first beat
---------------------------------------------------------------------------]]
hook.Remove("HUDPaint", "STTS_PhoneKick")
hook.Remove("RenderScreenspaceEffects", "STTS_PhoneKick")
local cvCounter = CreateClientConVar("stts_phone_kick_counter", "1", true, false, "keepy-uppy (Litvin): the kick counter (One. Two. ...) at the bottom of the screen", 0, 1)
local NUMS = {"One.", "Two.", "Three.", "Four.", "Five.", "Six.", "Seven.", "Eight.", "Nine.", "Ten.",
	"Eleven.", "Twelve.", "Thirteen.", "Fourteen.", "Fifteen.", "Sixteen.", "Seventeen.", "Eighteen.", "Nineteen.", "Twenty."}
sound.Add({name = "stts_phone_peep", channel = CHAN_AUTO, volume = 0.5, level = 30, pitch = {150, 150}, sound = "snd_jack_peep.wav"})
local CF = {}
function KK.CounterFonts()
	local size = math.max(math.floor(ScreenScale(25) + 0.5), 8)
	if CF.size == size then return end
	CF.size = size
	local d = {font = "Who asks Satan", size = size, extended = true, weight = 400, antialias = true}
	surface.CreateFont("STTS_KickCount", d)
	d.blursize = 4
	surface.CreateFont("STTS_KickCountG1", d)
	d.blursize = 20
	surface.CreateFont("STTS_KickCountG2", d)
end

function KK.Counter(n)
	if not cvCounter:GetBool() or n < 1 then return end
	KK.J = {msg = NUMS[n] or (n .. "."), t = RealTime(), kick = RealTime(), click = 0, n = n}
end

local TXT, CM, pushed = Color(255, 255, 255), Matrix(), false
local V_SCALE, V_POS, V_OFF = Vector(1, 1, 0), Vector(0, 0, 0), Vector(0, 0, 0)
function KK.DrawCounter(J)
	local now = RealTime()
	local msg = J.msg
	local len = #msg
	local per = 0.06 -- s per letter
	local read = len * per
	local wait = Clamp(read / 3, 1, 4) + 3
	if now > J.t + read + wait then KK.J = nil return end
	local part = Clamp(1 - (J.t + read - now) / read, 0, 1)
	local fade = Clamp((wait + min(J.t + read - now, 0)) / wait, 0, 1)
	local click = math.ceil(part * len)
	if click < len and string.sub(msg, click, click) == "." then J.t = J.t + RealFrameTime() / 1.5 end
	if click ~= J.click then
		J.click = click
		local vs = render.GetViewSetup and render.GetViewSetup()
		sound.Play("stts_phone_peep", (vs and vs.origin or EyePos()) - vector_up * 10)
	end
	local txt = string.sub(msg, 1, click)
	if txt == "" then return end
	KK.CounterFonts()
	surface.SetFont("STTS_KickCount")
	local tw = surface.GetTextSize(txt)
	local a = 255 * fade
	-- the beat: InExpo of a saw that starts at every kick (~128 / min), stronger with more kicks
	local beat = 1 - ((now - J.kick) * (128 / 60)) % 1
	local x = Clamp(beat * 0.25 + 0.75, 0, 1)
	local int = 2 ^ (10 * x - 10) * Clamp(0.45 + J.n * 0.05, 0, 1) * 2
	local scale = 1 + int / 4
	local shake = min(0.5 + J.n * 0.25, 3) * 2 * fade
	V_POS.x, V_POS.y = ScrW() / 2 + math.Rand(-shake, shake), ScrH() - ScrH() / 6 + math.Rand(-shake, shake)
	V_SCALE.x, V_SCALE.y = scale, scale
	V_OFF.x = -tw / 2
	CM:Identity()
	CM:Translate(V_POS)
	CM:Scale(V_SCALE)
	CM:Translate(V_OFF)
	render.PushFilterMag(TEXFILTER.ANISOTROPIC)
	cam.PushModelMatrix(CM, true)
	DisableClipping(true)
	pushed = true
	local st, rt = SysTime(), RealTime() * 7
	local sx, sy = -sin(rt) * 0.5 * int, -cos(rt) * 0.5 * int
	for i = 1, 40 do
		local al = a - i * 5
		if al <= 0 then break end
		local v = 255 - i * 1.6 - 14 * (0.5 + 0.5 * sin(st + i / 50)) * min(int, 1) -- white, the smear a touch greyer
		TXT.r, TXT.g, TXT.b, TXT.a = v, v, v, al
		draw.SimpleText(txt, "STTS_KickCount", sx * i, sy * i, TXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	TXT.r, TXT.g, TXT.b = 255, 255, 255
	TXT.a = min(a, 50)
	draw.SimpleText(txt, "STTS_KickCountG1", 0, 0, TXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	TXT.a = min(a, 10)
	draw.SimpleText(txt, "STTS_KickCountG2", 0, 0, TXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	TXT.a = a
	draw.SimpleText(txt, "STTS_KickCount", 0, 0, TXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	pushed = false
	DisableClipping(false)
	cam.PopModelMatrix()
	render.PopFilterMag()
end

hook.Add("DrawOverlay", "STTS_PhoneKickCounter", function()
	local J = KK.J
	if not J then return end
	local ply = LocalPlayer()
	if not (IsValid(ply) and ply:Alive()) then KK.J = nil return end
	local ok, err = pcall(KK.DrawCounter, J)
	if not ok then
		KK.J = nil
		KK.Err(err)
		if pushed then -- it broke in the middle
			pushed = false
			DisableClipping(false)
			cam.PopModelMatrix()
			render.PopFilterMag()
		end
	end
end)

--[[---------------------------------------------------------------------------
	the Q menu
---------------------------------------------------------------------------]]

-- Q menu -> "Phone" -> "Anims": "Toss phone" (moved here from the main menu) + "Litvin"
-- fix74: the phone in the left hand next to a weapon (STTS.PhoneRH, weapon file): the
-- phone comes back into the hands first (the weapon goes away), then the anim
function KK.PhoneMenu(wep)
	local function Do(fn)
		local RH = STTS.PhoneRH
		local lp = LocalPlayer()
		if IsValid(wep) and IsValid(lp) and lp:GetActiveWeapon() ~= wep and RH and RH.AfterPhone and RH.Phone and RH.Phone(lp) == wep then
			RH.AfterPhone(wep, fn)
			return
		end
		fn(wep)
	end
	local toss = {function(mouseClick)
		local kind = mouseClick == 2 and 2 or 1
		Do(function(w)
			if IsValid(w) and w.RequestToss and w:CanToss() then w:RequestToss(kind) else KK.Deny() end
		end)
		if mouseClick == 2 then return 1 end -- RMB closes the menu as well
	end, "Toss phone\nRMB - double flip"}
	local kick = {function(mouseClick)
		Do(function(w) KK.Request(w) end)
		if mouseClick == 2 then return 1 end
	end, "Litvin"}
	return {toss, kick}
end

--[[ fix74: Q menu -> "Phone" = two categories:
       Anims      Toss phone / Litvin (above)
       RightHand  every weapon you have that can be in the right hand while the left
                  one holds the phone (pistols, one-handed melee weapons). picked =
                  it is in the right hand (LMB = shoot / hit), the phone stays in the
                  left one. the one in the hand now is "> name <", "Phone only" =
                  the weapon goes away. any weapon picked the normal way (1, 2, 3 ...)
                  = the end, the phone goes into the pocket ]]
function KK.PhoneRoot(wep)
	local anims = {function()
		hg.CreateRadialMenu(KK.PhoneMenu(wep))
		return -1 -- the menu stays open with the submenu
	end, "Anims"}
	local right = {function(mouseClick)
		local RH = STTS.PhoneRH
		local opts = RH and RH.MenuOptions and RH.MenuOptions(wep)
		if not opts then
			KK.Deny()
			if mouseClick == 2 then return 1 end
			return
		end
		hg.CreateRadialMenu(opts)
		return -1
	end, "RightHand"}
	return {anims, right}
end

hook.Remove("radialOptions", "STTS_PhoneToss")
hook.Add("radialOptions", "STTS_PhoneTab", function()
	if not (hg and hg.radialOptions and hg.CreateRadialMenu) then return end
	local ply = LocalPlayer()
	if not (IsValid(ply) and ply:Alive()) or (ply.organism and ply.organism.otrub) then return end
	local wep = ply:GetActiveWeapon()
	local phone
	if IsValid(wep) and wep:GetClass() == "weapon_stts_phone" then
		if KK.Kicking(wep) then return end
		phone = wep
	else
		-- fix74: the phone in the left hand next to a weapon in the right one
		local RH = STTS.PhoneRH
		phone = RH and RH.Phone and RH.Phone(ply)
		if not phone then return end
	end
	hg.radialOptions[#hg.radialOptions + 1] = {function()
		hg.CreateRadialMenu(KK.PhoneRoot(phone))
		return -1 -- the menu stays open with the submenu
	end, "Phone"}
end)

concommand.Add("stts_phone_kick", function(ply)
	local wep = IsValid(ply) and ply:GetActiveWeapon()
	if IsValid(wep) and wep:GetClass() == "weapon_stts_phone" then KK.Request(wep) end
end, nil, "keepy-uppy with the phone in the left hand (the same as Q menu -> Phone -> Litvin)")
