-- fix45: scoped phone view isolation; a missed auxiliary snapshot NEVER gates recording.
STTS = STTS or {}
local V = {}
STTS.PhoneView43 = V
local contexts, buffers, slots50 = {}, {}, {}
local blocked = {
 RenderScreenspaceEffects = true, DrawOverlay = true,
 RenderScene = true, CalcView = true, CalcViewModelView = true,
 ["Post Processing"] = true, ["Post Pre Post Processing"] = true,
 ["Post Post Processing"] = true,
 ["Post Post Pre Post Processing"] = true, ["Post Pain Processing"] = true
}
local world = {PostDrawOpaqueRenderables = true, PostDrawTranslucentRenderables = true}
local function name(rt)
 if not rt or not rt.GetName then return end
 return rt:GetName()
end
local function targetMatches(c)
 local rt = render.GetRenderTarget()
 c.lastRT = name(rt) or "nil"
 -- GMod may return a different Lua ITexture handle for the same engine texture.
 return rt == c.target or (name(rt) ~= nil and name(rt) == c.targetName)
end
local function snapshot(stage, depth, skybox, skybox3D)
 local c = contexts[#contexts]
 if not c then return end
 c.events = c.events + 1
 if depth or skybox3D then return end
 -- bSkybox=true is NOT sufficient to identify a sky-only render (2D sky maps).
 if not targetMatches(c) then c.rejected = c.rejected + 1;return end
 -- Do not replace a final pre-FX image with an earlier world-stage image.
 if c.stage == "pre-fx" then return end
 local diag=STTS.PhoneDiag47
 if diag and diag.Call then diag.Call('phone.CopyWorldToClean',render.CopyRenderTargetToTexture,c.clean)else render.CopyRenderTargetToTexture(c.clean)end
 c.copied, c.stage = true, stage
end
-- Also cover a cached engine/ULib dispatcher which does not read our scoped hook.Call.
-- ULib -2 is a monitor which runs before ordinary callbacks, regardless of their returns.
if hook.Remove then
 hook.Remove("PostDrawOpaqueRenderables", "STTS.PhoneView43.Opaque")
 hook.Remove("PostDrawTranslucentRenderables", "STTS.PhoneView43.World")
end
local function worldFallback(d,s,s3)
 local c=contexts[#contexts]
 if c and (c.worldDepth or 0)==0 then snapshot("world",d,s,s3) end
end
hook.Add("PostDrawOpaqueRenderables", "STTS.PhoneView45.Opaque", worldFallback, -2)
hook.Add("PostDrawTranslucentRenderables", "STTS.PhoneView45.World", worldFallback, -2)
hook.Add("RenderScreenspaceEffects", "STTS.PhoneView45.PreFX", function() snapshot("pre-fx") end, -2)

function V.Render(view, target, w, h)
 -- fix65: second try of a black photo: the engine render alone (no hook isolation / clean copy)
 if V.Direct65 then
  local ok,err=pcall(render.RenderView,view)
  local last=V.last or {};V.last=last
  last.stage,last.events,last.rejected,last.target,last.active="direct",0,0,name(target) or "unnamed","direct"
  if not ok then error(err,0) end
  return false
 end
 local key = w .. "x" .. h .. "_" .. (#contexts + 1)
 local clean = buffers[key]
 if not clean then
  clean = GetRenderTargetEx("stts_phone_clean45_" .. key, w, h,
   RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGB888)
  buffers[key] = clean
 end
 -- Recycle per-depth context and dispatch closures instead of constructing
 -- four Lua objects for every phone render. No change to snapshot/fade rules.
 local depth=#contexts+1
 local c=slots50[depth]
 if not c then
  c={};slots50[depth]=c
  local function dispatch(fn,event,isCall,...)
   local active=contexts[#contexts]==c
   if active then
    if event=="RenderScreenspaceEffects"then snapshot("pre-fx");return end
    if blocked[event]then return end
    if world[event]then c.worldDepth=(c.worldDepth or 0)+1 end
   end
   local a,b,c1,d,e,f=fn(event,...)
   if active and contexts[#contexts]==c and world[event]then
    c.worldDepth=c.worldDepth-1
    if c.worldDepth==0 then
     if isCall then local gm,d1,sky,sky3=...;snapshot("world",d1,sky,sky3)
     else snapshot("world",...)end
    end
   end
   return a,b,c1,d,e,f
  end
  c.call=function(event,...)return dispatch(c.oldCall,event,true,...)end
  c.run=function(event,...)return dispatch(c.oldRun,event,false,...)end
 end
 c.target,c.targetName,c.clean=target,name(target),clean
 c.copied,c.events,c.rejected,c.worldDepth,c.stage,c.lastRT=false,0,0,0,nil,nil
 local oldCall,oldRun=hook.Call,hook.Run;c.oldCall,c.oldRun=oldCall,oldRun
 contexts[depth]=c
 hook.Call,hook.Run=c.call,c.run
 local diag=STTS.PhoneDiag47
 local ok, err
 if diag and diag.Call then ok,err=pcall(diag.Call,'phone.engine.RenderView',render.RenderView,view)else ok,err=pcall(render.RenderView,view)end
 hook.Call, hook.Run = oldCall, oldRun
 contexts[#contexts] = nil
 if not ok then error(err, 0) end
 if c.copied then
  if diag and diag.Call then diag.Call('phone.RestoreCleanTexture',render.CopyTexture,clean,target)else render.CopyTexture(clean,target)end
 end
 local last=V.last or {};V.last=last
 last.stage,last.events,last.rejected=c.stage or "direct",c.events,c.rejected
 last.target,last.active=c.targetName or "unnamed",c.lastRT or "no hooks"
 -- This return describes isolation only, NOT frame readiness. RenderView succeeded.
 return c.copied
end
