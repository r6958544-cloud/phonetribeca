-- fix36. Causal image-space orientation lock with bounded pan following.
-- No Gyroflow code is copied. No raw camera pose is modified.
STTS = STTS or {}
local E = {}; STTS.PhoneEIS = E

local overscans={1.22,1.35}
local modes = {
 [1]={crop=1.20, hold=4, limit=7, delay=0, swing=true, name="EIS 1"},
 [2]={crop=1.40, hold=8, limit=11, delay=0, full=true, name="EIS 2"}
}
function E.Mode(wep)
 if IsValid(wep)and wep.GetNW2Int then
  local p=wep.STTS_EISPrediction
  if p and RealTime()-p.at<1 and wep:GetNW2Int("EIS",2)~=p.mode then return p.mode end
  return math.Clamp(wep:GetNW2Int("EIS",2),0,2)
 end
 return 2
end
function E.Predict(wep,mode)if IsValid(wep)then wep.STTS_EISPrediction={mode=mode,at=RealTime()}end end
function E.Label(m) return modes[m] and modes[m].name or "EIS OFF" end
function E.New(wep) return {mode=E.Mode(wep), history={}, cursor=0, ring={}} end
local function norm(q)
 local n=math.sqrt(q[1]^2+q[2]^2+q[3]^2+q[4]^2)
 if n<1e-12 then return {1,0,0,0} end
 return {q[1]/n,q[2]/n,q[3]/n,q[4]/n}
end
local function mul(a,b)
 return {a[1]*b[1]-a[2]*b[2]-a[3]*b[3]-a[4]*b[4],a[1]*b[2]+a[2]*b[1]+a[3]*b[4]-a[4]*b[3],a[1]*b[3]-a[2]*b[4]+a[3]*b[1]+a[4]*b[2],a[1]*b[4]+a[2]*b[3]-a[3]*b[2]+a[4]*b[1]}
end
local function inv(q) return {q[1],-q[2],-q[3],-q[4]} end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]+a[4]*b[4] end
local function mix(a,b,k)
 local d=dot(a,b);local sign=d<0 and -1 or 1;d=math.min(1,math.abs(d))
 if d>0.9995 then return norm({a[1]*(1-k)+b[1]*sign*k,a[2]*(1-k)+b[2]*sign*k,a[3]*(1-k)+b[3]*sign*k,a[4]*(1-k)+b[4]*sign*k}) end
 local t=math.acos(d);local x=math.sin((1-k)*t)/math.sin(t);local y=math.sin(k*t)/math.sin(t)*sign
 return {a[1]*x+b[1]*y,a[2]*x+b[2]*y,a[3]*x+b[3]*y,a[4]*x+b[4]*y}
end
function E.Quaternion(a)
 local p,y,r=math.rad(a.p)*0.5,math.rad(a.y)*0.5,math.rad(a.r)*0.5
 local cp,sp,cy,sy,cr,sr=math.cos(p),math.sin(p),math.cos(y),math.sin(y),math.cos(r),math.sin(r)
 return {cr*cp*cy+sr*sp*sy,sr*cp*cy-cr*sp*sy,cr*sp*cy+sr*cp*sy,cr*cp*sy-sr*sp*cy}
end
local function basis(q)
 local w,x,y,z=q[1],q[2],q[3],q[4]
 return Vector(1-2*(y*y+z*z),2*(x*y+w*z),2*(x*z-w*y)),
 Vector(-2*(x*y-w*z),-(1-2*(x*x+z*z)),-2*(y*z+w*x)),
 Vector(2*(x*z+w*y),2*(y*z-w*x),1-2*(x*x+y*y))
end
function E.Reset(s,key)
 s.history,s.ring,s.cursor,s.lastOutput,s.ready={}, {},0,nil,false
 s.key,s.lastMode,s.lastAt,s.anchor=key,s.mode,nil,nil
 s.motion=nil
end
function E.Sample(s,a,now,key)
 if not s.history then E.Reset(s,key) end
 if s.key~=key or s.lastMode~=s.mode or (s.lastAt and (now-s.lastAt>0.4 or now<s.lastAt)) then E.Reset(s,key) end
 -- RenderCam and the gyro sampler can run in the same game frame.
 if s.lastAt and now-s.lastAt<0.001 and #s.history>0 then return end
 local dt=s.lastAt and math.Clamp(now-s.lastAt,0,0.1) or 0
 s.lastAt=now
 local raw=E.Quaternion(a);local m=modes[s.mode]
 local desired=s.anchor or raw
 if m then
  local delta=mul(inv(raw),desired)
  local twist=norm({delta[1],delta[2],0,0})
  if m.roll then delta=twist elseif m.swing then delta=mul(delta,inv(twist)) end
  desired=norm(mul(raw,delta))
  local angle=math.deg(2*math.acos(math.min(1,math.abs(dot(raw,desired)))))
  -- A virtual tripod: small shake never moves the anchor. Following starts
  -- only outside the hold zone. Do not recenter after a shake has stopped.
  if angle>m.hold then
   local near=mix(raw,desired,m.hold/math.max(angle,1e-9))
   desired=mix(desired,near,1-math.exp(-dt*12))
   local remaining=math.deg(2*math.acos(math.min(1,math.abs(dot(raw,desired)))))
   if remaining>m.limit then desired=mix(raw,desired,m.limit/remaining) end
  end
 else desired=raw end
 s.anchor=desired
 -- No delayed frame queue: retain only four samples and recycle metadata.
 local item=#s.history>=4 and table.remove(s.history,1) or {}
 item.t,item.q,item.d=now,raw,desired;s.history[#s.history+1]=item
end
function E.Smooth(s,t,raw)
 if not modes[s.mode] then return raw end
 local h=s.history
 if #h==0 then return raw end
 if t<=h[1].t then return h[1].d end
 for i=#h,2,-1 do
  if t>=h[i-1].t then local a,b=h[i-1],h[i];return mix(a.d,b.d,math.Clamp((t-a.t)/math.max(1e-8,b.t-a.t),0,1)) end
 end
 return h[#h].d
end

-- Translation compensation is image-space only, for the unstable ragdoll case.
-- A single estimated scene plane cannot remove near/far parallax simultaneously.
function E.Position(s,pos,now,unstable,depth)
 if not unstable or s.mode<1 then s.motion=nil return end
 local m=s.motion
 if not m then m={x=pos.x,y=pos.y,z=pos.z,t=now,depth=math.Clamp(depth or 128,24,1500)};s.motion=m end
 local dt=math.Clamp(now-m.t,0,0.1);m.t=now
 m.depth=m.depth+(math.Clamp(depth or m.depth,24,1500)-m.depth)*(1-math.exp(-dt*5))
 local dx,dy,dz=m.x-pos.x,m.y-pos.y,m.z-pos.z
 local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
 local hold=math.min(s.mode==2 and 4 or 2,m.depth*0.025)
 local limit=math.min(s.mode==2 and 7 or 4,m.depth*0.055)
 if dist>hold then
  local k=1-(1-hold/math.max(dist,1e-9))*(1-math.exp(-dt*10))
  k=math.min(k,limit/math.max(dist,1e-9));dx,dy,dz=dx*k,dy*k,dz*k
  m.x,m.y,m.z=pos.x+dx,pos.y+dy,pos.z+dz
 end
 m.shift=m.shift or Vector();m.shift.x,m.shift.y,m.shift.z=dx/m.depth,dy/m.depth,dz/m.depth
end

function E.Mapping(raw,desired,rawFov,outFov,w,h,shift)
 local sf,sr,su=basis(raw);local th=math.tan(math.rad(rawFov)*0.5);local tv=th*h/w
 local oth=math.tan(math.rad(outFov)*0.5);local otv=oth*h/w
 local dx,dy,dz=shift and shift.x or 0,shift and shift.y or 0,shift and shift.z or 0
 local function project(f,r,u,x,y,k)
  local rx,uy=(2*x-1)*oth,(1-2*y)*otv
  local vx,vy,vz=f.x+r.x*rx+u.x*uy,f.y+r.y*rx+u.y*uy,f.z+r.z*rx+u.z*uy
  vx,vy,vz=vx+dx*k,vy+dy*k,vz+dz*k
  local z=vx*sf.x+vy*sf.y+vz*sf.z
  if z<=1e-5 then return -1,-1 end
  return 0.5+(vx*sr.x+vy*sr.y+vz*sr.z)/(2*z*th),0.5-(vx*su.x+vy*su.y+vz*su.z)/(2*z*tv)
 end
 local function fits(k)
  local f,r,u=basis(mix(raw,desired,k))
  for x=0,1 do for y=0,1 do local a,b=project(f,r,u,x,y,k);if a<0.001 or a>0.999 or b<0.001 or b>0.999 then return false end end end
  return true
 end
 local k=1
 if not fits(1) then local lo,hi=0,1;for _=1,10 do local mid=(lo+hi)*0.5;if fits(mid) then lo=mid else hi=mid end end;k=lo end
 local f,r,u=basis(mix(raw,desired,k))
 return function(x,y) return project(f,r,u,x,y,k) end,k
end
local pool={}
local function target(w,h,slot,channel)
 local key=(channel or "record").."_"..w.."x"..h.."_"..slot
 if not pool[key] then
  local rt=GetRenderTargetEx("stts_eis31_"..key,w,h,RT_SIZE_LITERAL,MATERIAL_RT_DEPTH_SEPARATE,0,0,IMAGE_FORMAT_RGB888)
  pool[key]={rt=rt,w=w,h=h,mat=CreateMaterial("stts_eis31m_"..key,"UnlitGeneric",{["$basetexture"]=rt:GetName(),["$vertexcolor"]=1,["$vertexalpha"]=1,["$ignorez"]=1})}
 end
 return pool[key]
end
-- Resource-only preparation while the idle camera is open. No change of
-- quaternion history, image mapping, output quality or capture timestamps.
function E.Warm49(w,h,mode,channel)
 local o=overscans[mode]or 1
 return target(math.ceil(w*o/2)*2,math.ceil(h*o/2)*2,1,channel or"record")
end
-- Keep a fixed ANGULAR stabilization reserve at telephoto, not a fixed
-- percentage of a shrinking FOV. The cone/plane bound covers any rotation
-- within the mode's hard limit, including diagonal shake and portrait corners.
function E.SourceFov(mode,fov,w,h,translation)
 local m=modes[mode];local overscan=overscans[mode] or 1
 local original=math.tan(math.rad(fov)*0.5)*overscan
 if not m or m.roll then return math.deg(2*math.atan(original)) end
 local out=math.tan(math.rad(fov)*0.5)/m.crop;local aspect=h/w
 local norm=math.sqrt(1+out*out*(1+aspect*aspect))
 local margin=math.sin(math.rad(m.limit+(translation and 4 or 0)))
 local function fits(t)
  return (t-out)/(norm*math.sqrt(1+t*t))>=margin+0.002 and
   (t-out)*aspect/(norm*math.sqrt(1+t*t*aspect*aspect))>=margin+0.002
 end
 local lo,hi=original,math.tan(math.rad(80))
 if fits(original) then return math.deg(2*math.atan(original)) end
 for _=1,18 do local mid=(lo+hi)*0.5;if fits(mid) then hi=mid else lo=mid end end
 return math.deg(2*math.atan(hi))
end
-- Strong mode uses a wider virtual lens BEFORE image-space crop. At 1x
-- the final horizontal FOV is base minus 5 degrees, not base divided by 1.4.
-- At telephoto cap that loss at 10% so zoom does not get cropped twice.
function E.LensFov(mode,base)
 if mode~=2 then return base end
 local out=math.max(1,base-math.min(5,base*0.1))
 return math.deg(2*math.atan(math.tan(math.rad(out)*0.5)*modes[mode].crop))
end
function E.OutputFov(mode,base)
 local m=modes[mode];if not m then return base end
 return math.deg(2*math.atan(math.tan(math.rad(E.LensFov(mode,base))*0.5)/m.crop))
end
function E.Begin(s,w,h,fov)
 fov=E.LensFov(s.mode,fov)
 -- Fixed shared pools by dimensions: RTs never grow with clip count.
 s.cursor=1
 local overscan=overscans[s.mode] or 1
 local rw,rh=math.ceil(w*overscan/2)*2,math.ceil(h*overscan/2)*2
 local p=target(rw,rh,s.cursor,s.channel)
 local moving=s.motion~=nil
 if s.sourceBase~=fov or s.sourceMode~=s.mode or s.sourceMoving~=moving or s.sourceW~=w or s.sourceH~=h then
  s.sourceFov=E.SourceFov(s.mode,fov,w,h,moving)
  s.sourceBase,s.sourceMode,s.sourceMoving,s.sourceW,s.sourceH=fov,s.mode,moving,w,h
 end
 p.fov=s.sourceFov
 return p
end
local function vertex(v) mesh.Position(v.pos);mesh.TexCoord(0,v.u,v.v);mesh.Color(255,255,255,255);mesh.AdvanceVertex() end
local function draw(source,raw,outFov,s,w,h)
 local desired=E.Smooth(s,source.t,raw)
 local map,k=E.Mapping(raw,desired,source.fov,outFov,w,h,s.motion and s.motion.shift);s.available=k
 if not s.grid then
  s.grid,s.polys={},{}
  for j=0,16 do for i=0,10 do s.grid[j*11+i+1]={x=0,y=0,pos=Vector()} end end
  for j=0,15 do for i=0,9 do local n=j*11+i+1;s.polys[#s.polys+1]={s.grid[n],s.grid[n+1],s.grid[n+12],s.grid[n+11]} end end
 end
 for j=0,16 do for i=0,10 do local v=s.grid[j*11+i+1];v.x,v.y=i*w/10,j*h/16;v.pos.x,v.pos.y=v.x,v.y;v.u,v.v=map(i/10,j/16) end end
 render.Clear(0,0,0,255)
 cam.Start2D()
 render.PushFilterMin(TEXFILTER.LINEAR);render.PushFilterMag(TEXFILTER.LINEAR)
 surface.SetMaterial(source.mat);surface.SetDrawColor(255,255,255,255)
 if mesh and mesh.Begin then
  -- One streamed triangle batch instead of 160 separate draw submissions.
  render.SetMaterial(source.mat);mesh.Begin(MATERIAL_TRIANGLES,320)
  for _,p in ipairs(s.polys) do vertex(p[1]);vertex(p[2]);vertex(p[3]);vertex(p[1]);vertex(p[3]);vertex(p[4]) end
  mesh.End()
 else for _,p in ipairs(s.polys) do surface.DrawPoly(p) end end
 render.PopFilterMag();render.PopFilterMin()
 cam.End2D()
 s.outputAt,s.ready=source.t,true
end
function E.Draw(source,w,h,a,fov,s)
 fov=E.LensFov(s.mode,fov)
 local now=RealTime();local m=modes[s.mode]
 source.t,source.q=now,E.Quaternion(a)
 -- Ring entries own their metadata. Source target objects are shared/reused.
 local item=s.ring[s.cursor] or {};s.ring[s.cursor]=item
 item.rt,item.mat,item.fov,item.baseFov,item.t,item.q=source.rt,source.mat,source.fov,fov,now,source.q
 local chosen
 for _,p in pairs(s.ring) do if p.t<=now-m.delay and (not chosen or p.t>chosen.t) then chosen=p end end
 s.ready=chosen~=nil
 if not chosen then chosen=s.ring[s.cursor] end
 local outFov=math.deg(2*math.atan(math.tan(math.rad(chosen.baseFov)*0.5)/m.crop))
 draw(chosen,chosen.q,outFov,s,w,h)
 s.ready=now-chosen.t>=m.delay-0.001
 s.lastOutput=chosen.t;s.baseFov=fov
end
function E.Drain(s,w,h)
 local chosen
 for _,p in pairs(s.ring or {}) do if p.t>(s.lastOutput or -1)+1e-6 and (not chosen or p.t<chosen.t) then chosen=p end end
 if not chosen then return false end
 local m=modes[s.mode];if not m then return false end
 local out=math.deg(2*math.atan(math.tan(math.rad(chosen.baseFov)*0.5)/m.crop))
 draw(chosen,chosen.q,out,s,w,h);s.lastOutput=chosen.t
 return true
end
concommand.Add("zhphone_eis_info",function() print("[ZPHONE] image-space tripod EIS, mode="..E.Mode().."; causal, no delayed frame queue") end)
