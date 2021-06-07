--[[
    _           ____  _                   
  | |__   __ _|  _ \(_) __ _ _ __   __ _ 
  | '_ \ / _` | | | | |/ _` | '_ \ / _` |
  | | | | (_| | |_| | | (_| | | | | (_| |
  |_| |_|\__, |____/|_|\__,_|_| |_|\__,_|
            |_|                          
--]]

if _G.Player.CharName ~= "Diana" then return false end

--[[
  ===================================================================================================
  ========================================== Configuration ==========================================
  ===================================================================================================
--]]
--#region Configuration
local CONFIG = {
  MODULE_NAME = "hqDiana",
  MODULE_VERSION = "1.0.2",
  MODULE_AUTHOR = "hq.af",
  UPDATE_URL = "https://raw.githubusercontent.com/hq-af/roburlol/main/hqDiana.lua",
  CHANGELOG = "added jungle/lane clear"
}

module(CONFIG.MODULE_NAME, package.seeall, log.setup)
clean.module(CONFIG.MODULE_NAME, package.seeall, log.setup)

--#endregion

--[[
  ====================================================================================================
  ============================================ API v1.0.0 ============================================
  ====================================================================================================
--]]
--#region API
local API = {
  Game = _G.CoreEx.Game,
  Input = _G.CoreEx.Input,
  Vector = _G.CoreEx.Geometry.Vector,
  Polygon = _G.CoreEx.Geometry.Polygon,
  Player = _G.Player,
  Circle = _G.CoreEx.Geometry.Circle,
  Cone = _G.CoreEx.Geometry.Cone,
  EventManager = _G.CoreEx.EventManager,
  Enums = _G.CoreEx.Enums,
  Libs = _G.Libs,
  GetCurrentMillis = _G.getCurrentMillis,
  Renderer = _G.CoreEx.Renderer,
  ObjectManager = _G.CoreEx.ObjectManager,
  Nav = _G.CoreEx.Nav,
  SpellLib = _G.Libs.Spell,
  Orbwalker = _G.Libs.Orbwalker,
  TargetSelector = _G.Libs.TargetSelector,
  CollisionLib = _G.Libs.CollisionLib,
  HealthPred = _G.Libs.HealthPred
}
--#endregion

--[[
  ====================================================================================================
  ====================================== Custom Geometry v1.0.0 ======================================
  ====================================================================================================
--]]
--#region Custom Geometry
local Geometry = {}

function Geometry.Angle(p1, p2)
  return math.atan2(p2.z - p1.z, p2.x - p1.x)
end

function Geometry.RotateAround(p, c, angle)  
  local cos = math.cos(angle)
  local sin = math.sin(angle)
  local x =  cos * (p.x - c.x) - sin * (p.z - c.z) + c.x
  local z = sin * (p.x - c.x) + cos * (p.z - c.z) + c.z

  return API.Vector(
   x,
   API.Nav.GetTerrainHeight(API.Vector(x, 0, z)),
   z
  )
end

function Geometry.Midpoint(p1, p2)
  local x = (p1.x + p2.x) / 2
  local z = (p1.z + p2.z) /2

  return API.Vector(
    x,
    API.Nav.GetTerrainHeight(API.Vector(x, 0, z)),
    z
  )
end


function Geometry.Distance(p1, p2)
  return math.sqrt(math.pow(p2.x - p1.x, 2) + math.pow(p2.z - p1.z, 2))
end

function Geometry.EllipticCurve(center, width, height, fromAngle, toAngle, quality, extraCurveW, extraCurveH)
  local addIn = (toAngle - fromAngle)/(quality-1);
  local step = fromAngle;
  local points = {}
  local w = width
  local h = height

  for i=0,quality do
    local x = math.cos(step)*w+center.x
    local z = math.sin(step)*h+center.z

    table.insert(points, API.Vector(
        x,
        API.Nav.GetTerrainHeight(API.Vector(x, 0, z)),
        z
    ))

    w = w + extraCurveW
    h = h + extraCurveH
    step = step + addIn;
  end
  
  return points
end

function Geometry.Crescent(startPos, endPos, maxWidth, componentQuality)

  local nb = componentQuality -- Diana:10
  local dist = Geometry.Distance(startPos, endPos)
  local mid = Geometry.Midpoint(startPos, endPos)
  local scale = dist/maxWidth -- Diana:795
  local offsetAngle = Geometry.Angle(startPos, endPos)

  local pointsInner = Geometry.EllipticCurve(mid, dist/2, 110*scale, math.pi, math.pi*2, nb, 3, 2)
  local inner = {}
  for _, point in pairs(pointsInner) do
    local r = Geometry.RotateAround(point, mid, offsetAngle);
    table.insert(inner, r);
  end

  local pointsOuter = Geometry.EllipticCurve(mid, dist/2, 380*scale, math.pi, math.pi*2, nb, 2, 2)
  local outer = {}
  for _, point in pairs(pointsOuter) do
    local r = Geometry.RotateAround(point, mid, offsetAngle)
    table.insert(outer, r)
  end

  local points = {}
  for i=1, nb do
    points[i] = outer[i]
    if i ~= nb then
      points[nb*2 - 1 - i] =  inner[i]
    end
  end

  return API.Polygon(points)
end
--#endregion

--[[
  ===================================================================================================
  ============================================== Diana ==============================================
  ===================================================================================================
--]]
--#region Variables
local Menu = nil --@ Menu
local Diana = {
  Crescent = nil, --@ nil|Polygon
  Explosion = nil, --@ nil|Circle
  Cone = nil, --@ nil|Cone
  RQueueMs = 0,
  TargetSelector = API.TargetSelector(),
  EnemySpells = {}, --@ { source: AIHero, name: string, charName: string , slot: ("Q"|"W"|"E"|"R"), isMimic: boolean }
  EnemySpellsHashTable = {}, --@eg ["CaitlynEntrapment"] = "CaitlynE"
  RInterruptSpellsDefault = {
    ["TristanaW"] = true,
    ["CaitlynE"] = true,
    ["VelkozR"] = true,
    ["KatarinaR"] = true,
    ["NunuR"] = true,
    ["QuinnE"] = true,
    ["MalzaharR"] = true,
    ["LucianE"] = true,
    ["CorkiW"] = true,
    ["AhriR"] = true
  },

  -- Texts
  ComboRText = "Combo R Active",
  AutoHarassText = "Auto Harass",

  -- Spells
  Q = API.SpellLib.Skillshot({
    Slot = API.Enums.SpellSlots.Q,
    Range = 830,
    Delay = 0.25,
    Radius = 160,
    Speed = 1800,
    Collisions = { WindWall=true },
    Type = "Circular",
  }),
  W = API.SpellLib.Active({
    Slot = API.Enums.SpellSlots.W,
    Radius = 280
  }),
  E = API.SpellLib.Targeted({
    Slot = API.Enums.SpellSlots.E,
    Range = 825
  }),
  R = API.SpellLib.Active({
    Slot = API.Enums.SpellSlots.R,
    Delay = 0.25,
    Type = "Circular",
    Radius = 475,
    RadiusSqr = 225625
  })
}
--#endregion

local Config = {}
setmetatable(Config, {
  __index = function(obj, key) 
    return Menu and Menu.Get(key, true)
  end
})

--#region Q Zone
function Diana.InitZones(endPos)
  Diana.Cone = API.Cone(API.Player.Position, Geometry.RotateAround(API.Player.Position, endPos, math.pi/2 - 0.3), math.pi/2 -0.3, 200)
  Diana.Crescent = Geometry.Crescent(API.Player.Position, endPos, 800, 10)
  Diana.Explosion = API.Circle(endPos, 160)
end

function Diana.ResetZones()
  Diana.Crescent = nil
  Diana.Cone = nil
  Diana.Explosion = nil
end

function Diana.HasZones()
  return Diana.Crescent ~= nil
end

function Diana.ZoneHitChance(position, radius)
  if not Diana.HasZones() then return 0 end

  local hitCircle = API.Circle(position, radius)
  
  if Diana.Cone:Contains(hitCircle) then return 6
  elseif Diana.Cone:Intersects(hitCircle) then return 5
  elseif Diana.Crescent:Contains(hitCircle) then return 4
  elseif Diana.Explosion:Contains(hitCircle) then return 3
  elseif Diana.Crescent:Intersects(hitCircle) then return 2
  elseif Diana.Explosion:Intersects(hitCircle) then return 1 end

  return 0
end

function Diana.SimulatedZoneHitChance(playerPos, point, targetPos)

  local cone = API.Cone(playerPos, Geometry.RotateAround(playerPos, point, math.pi/2 - 0.3), math.pi/2 -0.3, 200)
  local crescent = Geometry.Crescent(playerPos, point, 800, 10)

  local c0 = API.Circle(targetPos, 10)
  local c1 = API.Circle(targetPos, 150)
  local c2 = API.Circle(targetPos, 100)
  local c3 = API.Circle(targetPos, 50)

  if cone:Contains(c0) then
    return 4
  elseif crescent:Contains(c1) then
    return 3
  elseif crescent:Contains(c2) then
   return 2
  elseif crescent:Contains(c3) then
    return 1
  end

  return 0
end

function Diana.OnCreateObject(obj)
  local missile = obj.IsMissile and obj.AsMissile or nil
  if missile ~= nil and missile.Caster == API.Player and missile.Name == "DianaQInnerMissile" then
    Diana.InitZones(missile.EndPos)
  end
end

function Diana.OnDeleteObject(obj)
  if Diana.HasZones() then
    local missile = obj.IsMissile and obj.AsMissile or nil
    if missile ~= nil and missile.Caster == API.Player and missile.Name == "DianaQInnerMissile" then
      Diana.ResetZones()
    end
  end
end
--#endregion


--#region QCrescentPrediction
function Diana.QCrescentPrediction(target, hitMax)

  local dist = math.min(800, Geometry.Distance(API.Player.Position, target.Position))

  if dist > 700 then
    local circlePred = Diana.Q:GetPrediction(target)
    if circlePred ~= nil and circlePred.HitChance >= 0.95 then
      return circlePred.CastPosition
    end
    return nil
  end

  local off = 0

  if dist < 300 then
    off = 0.3
  elseif dist > 500 then
    off = -0.3
  end

  local minAngle = 0.3 -(0.1*dist/800) + off
  local maxAngle = 1 -(0.1*dist/800) + off
  local angle = minAngle
  local step = 0.06
  local predictions = {}

  local qDelay = API.Game.GetLatency() + 250 + 100 -- Q cast time included
  local targetPred = target:FastPrediction(qDelay) 
  local playerPred = API.Player:FastPrediction(100)
  local c0 = API.Circle(targetPred, 10)
  local c1 = API.Circle(targetPred, 150)
  local c2 = API.Circle(targetPred, 100)
  local c3 = API.Circle(targetPred, 50)
  
  local startTime = API.GetCurrentMillis()

  while angle < maxAngle do

    local collision = API.CollisionLib.SearchYasuoWall(playerPred, targetPred, 50, Diana.Q.Speed, 0, 1, "enemy")
    
    if not collision.Result then

      local point = playerPred:Extended(
        Geometry.RotateAround(targetPred, playerPred, angle),
        800
      )
      
      local hitChance = Diana.SimulatedZoneHitChance(playerPred, point, targetPred)
      if hitChance > 0 then
        local extraHit = 0
        if hitMax then
          for _, enemy in pairs(API.ObjectManager.GetNearby("enemy", "heroes")) do
            if enemy ~= target and enemy.IsValid and enemy.IsAlive and enemy.IsVisible and Diana.SimulatedZoneHitChance(playerPred, point, enemy:FastPrediction(qDelay)) > 0 then
              extraHit = extraHit+1
            end
          end
        end

        local castPos = playerPred:Extended(
          Geometry.RotateAround(targetPred, playerPred, angle),
          1200
        )

        table.insert(predictions, {
          position = castPos,
          hitChance = hitChance,
          extraHit = extraHit
        })
      end
    end

    angle = angle + step
  end

  if table.getn(predictions) > 0 then
    if table.getn(predictions) > 1 then
      table.sort(predictions, function(a, b)
        if a.extraHit == b.extraHit then
          return a.hitChance > b.hitChance
        end
        return a.extraHit > b.extraHit
      end)
    end
    
    return predictions[1].position
  end

  return nil
end
--#endregion

--#region Utility
function Diana.CanCast(spell, ignoreRMana)
  return
    spell:IsReady() and API.Player.Mana >= spell:GetManaCost() and
    (ignoreRMana or Diana.R == spell or not Diana.R:IsReady() or not Config.SaveManaR or API.Player.Mana >= Diana.R:GetManaCost() + spell:GetManaCost())
end

function Diana.ComboE(castTarget)
  -- Queue R if toggle
  if Config.ComboAlwaysRFollowingEToggle and Diana.CanCast(Diana.R) then
    Diana.RQueueMs = API.GetCurrentMillis()
  end

  Diana.E:Cast(castTarget)
end

function Diana.CastQIfHit(target, hitMax)
  local prediction = nil
  if Config.CrescentPrediction then -- custom prediction
    prediction = Diana.QCrescentPrediction(target, hitMax)
  else -- normal prediction
    local cprediction = Diana.Q:GetPrediction(target)
    if cprediction and cprediction.HitChance >= Config.NormalPredictionHitChance then
      prediction = cprediction.CastPosition
    end
  end
  -- prediction found
  if prediction then
    Diana.Q:Cast(prediction)
    return true
  end

  return false
end

function Diana.CastWIfHitAny()
  -- W logic
  local wtarget = Diana.TargetSelector:GetTarget(Diana.W.Radius)
  if wtarget then
    Diana.W:Cast()
    return true
  end

  return false
end

function Diana.HasQBuff(unit, delay)
  local buff = unit:GetBuff("dianamoonlight")
  if buff == nil or buff.EndTime*1000 - delay < API.Game.GetTime()*1000 then return false end
  
  return true
end

function Diana.GetBuffTargets(range, team, type, delay)
  local result = {}

  local distSqr = range*range
  for _, target in pairs(API.ObjectManager.GetNearby(team, type)) do
    if (team ~= "neutral" or target.IsMonster) and target.IsValid and target.IsAlive and target.IsTargetable and target.Position:DistanceSqr(API.Player) < distSqr then 
      for _, buff in pairs(target.Buffs) do
        if Diana.HasQBuff(target, delay) then
          table.insert(result, target)
        end
      end
    end
  end

  return result
end

function Diana.GetFarmMinions(range, checkBuff)
  local result = {}

  local distSqr = range*range
  for team, list in pairs({["enemy"] = API.ObjectManager.GetNearby("enemy", "minions"), ["neutral"] = API.ObjectManager.GetNearby("neutral", "minions")}) do
    for _, target in pairs(list) do
      if (team ~= "neutral" or target.IsMonster) and target.IsValid and target.IsAlive and target.IsTargetable and target.Position:DistanceSqr(API.Player) < distSqr then
        if not checkBuff or Diana.HasQBuff(target, API.Game.GetLatency() + 100) then
          table.insert(result, target)
        end
      end
    end
  end
  
  return result
end
--#endregion

--#region Combo
function Diana.Combo()

  -- R Queue
  if Diana.RQueueMs > 0 then
    local diff = API.GetCurrentMillis() - Diana.RQueueMs
    if diff > 100 and Diana.CanCast(Diana.R) then
      Diana.R:Cast()
      return
    elseif diff > 2000 then -- timeout
      Diana.RQueueMs = 0
    end
  end

  -- Q & E logic
  local tsQTarget = Diana.TargetSelector:GetTarget(Diana.Q.Range)
  if Config.UseQCombo and tsQTarget and Diana.CanCast(Diana.Q) then -- if Q is available and has target in Q range
    if Diana.CastQIfHit(tsQTarget, true) then return end
  elseif Config.UseECombo and tsQTarget and not Diana.Q:IsReady() and Diana.E:IsReady() then -- if Q is not available and has target (no target in Q range == no target in E range)
    local ERange = Diana.E.Range + 50 -- E range with offset
    tsETarget = Diana.TargetSelector:GetTarget(ERange)

    if tsETarget and Diana.CanCast(Diana.E, tsETarget.Position:DistanceSqr(API.Player) > Diana.R.Radius*Diana.R.Radius) then
      local delay = API.Game.GetLatency() + 100 -- delay to cast E
      local targetPosition = tsETarget:FastPrediction(delay) -- predicted target position after delay

      if Diana.HasQBuff(tsETarget, delay) then -- if target has Q buff
        Diana.ComboE(tsETarget)
        return
      elseif Diana.HasZones() and tsETarget.Health > Diana.Q:GetDamage(tsETarget) then -- Q is shooting and will not kill 
        if Config.PredictEHit then
          if Diana.ZoneHitChance(targetPosition, tsETarget.BoundingRadius) > 0  then
            Diana.ComboE(tsETarget)
            return
          end
        end
      else -- Q not shooting
        local poolChampions = Diana.GetBuffTargets(ERange, "enemy", "heroes", delay)
        local pool = poolChampions

        --#region Cast E on target (if buff) or gapclose within AA range (if buff)
        local AARange = API.Player.AttackRange
        if tsETarget.Position:DistanceSqr(API.Player) > (AARange+50)*(AARange+50) then -- only if need to gapclose !
          local AARangeSqr = AARange*AARange
          for i=1,3 do
            for _, unit in pairs(pool) do
              unitPosition = unit:FastPrediction(delay)
              if unitPosition:DistanceSqr(targetPosition) < AARangeSqr then
                Diana.ComboE(unit)
                return
              end
            end
            if i < 3 then
              pool = i == 1 and Diana.GetBuffTargets(ERange, "enemy", "minions", delay) or Diana.GetBuffTargets(ERange, "neutral", "minions", delay)
            end
          end -- for i,3
        end

        -- can't reach target, change target /!\ GetTargetFromList is broken
        --local newTarget = Diana.TargetSelector:GetTargetFromList(poolChampions)
        --if newTarget then
          --Diana.ComboE(newTarget)
          --return
        --end

        --#endregion
      end -- target has QBuff or IsShooting or IsNotShooting
    end -- tsETarget
  end

  -- W
  if Config.UseWCombo and Diana.CanCast(Diana.W) and Diana.CastWIfHitAny() then return end

end
--#endregion

--#region Harass
function Diana.Harass()
  -- Q
  if Config.UseQHarass and Diana.CanCast(Diana.Q) then
    local tsQTarget = Diana.TargetSelector:GetTarget(Diana.Q.Range)
    if tsQTarget and Diana.CastQIfHit(tsQTarget, true) then return end
  end

  -- W
  if Config.UseWHarass and Diana.CanCast(Diana.W) and Diana.CastWIfHitAny() then return end

end
--#endregion

--#region KS
function Diana.KS()

  if Config.UseQKS and Diana.CanCast(Diana.Q, true) then
    for _, enemy in pairs(Diana.TargetSelector:GetTargets(Diana.Q.Range)) do
      if Diana.Q:GetDamage(enemy) > Diana.Q:GetKillstealHealth(enemy) and Diana.CastQIfHit(enemy, false) then 
        return true
      end
    end
  end

  if Config.UseEKS and not Diana.HasZones() and Diana.CanCast(Diana.E, true) then -- check zone to avoid double KS
    for _, enemy in pairs(Diana.TargetSelector:GetTargets(Diana.E.Range)) do
      if Diana.E:GetDamage(enemy) > Diana.E:GetKillstealHealth(enemy) then 
        Diana.E:Cast(enemy)
        return true
      end
    end
  end

  if Config.UseRKS and not Diana.HasZones() and Diana.CanCast(Diana.R, true) then -- check zone to avoid double KS
    for _, enemy in pairs(Diana.TargetSelector:GetTargets(Diana.R.Radius)) do
      if Diana.R:GetDamage(enemy) > Diana.R:GetKillstealHealth(enemy) then 
        Diana.R:Cast()
        return true
      end
    end
  end

  return false
end
--#endregion

--#region AutoR
function Diana.AutoR(minR)

  local targets = Diana.TargetSelector:GetTargets(Diana.R.Radius)
  if table.getn(targets) >= minR then
    Diana.R:Cast()
    return true
  end

  return false
end
--#endregion

--#region RInterrupt
function Diana.OnProcessSpell(source, spell)
  if Config.RInterrupt and
    source.TeamId ~= API.Player.TeamId and source.IsHero and spell.SpellData and
    Diana.EnemySpellsHashTable[spell.SpellData.Name] and
    (Config[Diana.EnemySpellsHashTable[spell.SpellData.Name]] or Config[source.CharName .. "_" .. Diana.EnemySpellsHashTable[spell.SpellData.Name]]) and
    Diana.CanCast(Diana.R, true) and source.Position:DistanceSqr(API.Player) < Diana.R.RadiusSqr then
      Diana.R:Cast()
  end
end
--#endregion

--#region Farm
function Diana.Farm()
  if Config.UseQFarm and Diana.CanCast(Diana.Q) then
    local targets = Diana.GetFarmMinions(Diana.Q.Range, false)
    local position, count = Diana.Q:GetBestCircularCastPos(targets)

    if position and count and count > 0 then
      if count and count == 1 then
        local orbTarget = API.Orbwalker.GetTarget()
        if orbTarget and orbTarget.IsMonster and and orbTarget.DistanceSqr(API.Player) < Diana.Q.Range*Diana.Q.Range then
          position = orbTarget:FastPrediction(250 + API.Game.GetLatency())
        end
      end
      Diana.Q:Cast(position)
      return
    end
  end

  if Config.UseWFarm and Diana.CanCast(Diana.W) then
    local nbHit = table.getn(Diana.GetFarmMinions(Diana.W.Radius, false))
    if nbHit > 0 then
      Diana.W:Cast()
      return
    end
  end

  if Config.UseEFarm and Diana.CanCast(Diana.E) then
    local targets = Diana.GetFarmMinions(Diana.E.Range, true)
    if table.getn(targets) > 0 then
      local orbTarget = API.Orbwalker.GetTarget()
      table.sort(targets, function(a, b)
        if orbTarget and orbTarget.IsMonster and a == orbTarget then return true end
        if a.Health < b.Health and a.Health < Diana.E:GetDamage(a) then return true end
        return a.MaxHealth > b.MaxHealth
      end)
      Diana.E:Cast(targets[1])
      return
    end
  end
end
--#endregion

--#region InitEnemySpells
function Diana.InitEnemySpells()
  local slots = {["Q"] = API.Enums.SpellSlots.Q, ["W"] = API.Enums.SpellSlots.W, ["E"] = API.Enums.SpellSlots.E, ["R"] = API.Enums.SpellSlots.R}
  for _, enemy in pairs(API.ObjectManager.Get("enemy", "heroes")) do
    for slotName, slot in pairs(slots) do
      local sname = enemy:GetSpell(slot).Name
      table.insert(Diana.EnemySpells, {source = enemy, name = sname, charName = enemy.CharName, slot = slotName })
      Diana.EnemySpellsHashTable[sname] = enemy.CharName .. slotName
      if slotName == "R" and enemy.CharName == "Viego" then
        for _, ally in pairs(API.ObjectManager.Get("ally", "heroes")) do
          for slotName2, slot2 in pairs(slots) do
            if slotName2 ~= "R" then
              local sname = ally:GetSpell(slot2).Name
              table.insert(Diana.EnemySpells, {source = enemy, name = sname, charName = ally.CharName, slot = slotName2, isMimic = true })
              Diana.EnemySpellsHashTable[sname] = ally.CharName .. slotName2
            end
          end
        end
      elseif slotName == "R" and enemy.CharName == "Sylas" then
        for _, ally in pairs(API.ObjectManager.Get("ally", "heroes")) do
          local sname = ally:GetSpell(slot).Name
          table.insert(Diana.EnemySpells, {source = enemy, name = sname, charName = ally.CharName, slot = slotName, isMimic = true })
          Diana.EnemySpellsHashTable[sname] = ally.CharName .. slotName
        end
      end
    end
  end
end
--#endregion

--#region OnTick
function Diana.OnTick()
  local minR = Config.MinMultiUltCount
  if minR > 0 and Diana.CanCast(Diana.R, true) and Diana.AutoR(minR) then return end

  if Diana.KS() then return end
  local mode = API.Orbwalker.GetMode()

  if mode == "Combo" then
    Diana.Combo()
  elseif mode == "Waveclear" and API.Player.ManaPercent * 100 > Config.FarmMinManaPercent then
    Diana.Farm()
  -- should stay last (auto harass toggle) /!\
  elseif (mode == "Harass" or Config.AutoHarassToggle) and API.Player.ManaPercent * 100 > Config.HarassMinManaPercent then
    Diana.Harass()
  end 

end
--#endregion

--#region Menu
function Diana.SetupMenu()
  Menu = API.Libs.NewMenu

  Menu.RegisterMenu(CONFIG.MODULE_NAME, CONFIG.MODULE_NAME, function()

    Menu.NewTree("Prediction", "Prediction", function()
      Menu.Text("Crescent Prediction", true)
      Menu.Checkbox("CrescentPrediction", "Use Advanced Q Prediction", true)
      Menu.Checkbox("PredictEHit", "Use E Hit Prediction (Combo)", true)
      Menu.Separator()
      Menu.Text("Normal Prediction (^ If Advanced Q Is Disabled ^)", true)
      Menu.Slider("NormalPredictionHitChance", "Q Hit Chance", 0.8, 0.01, 1, 0.01)
    end)

    Menu.NewTree("Combo", "Combo", function()
      Menu.Checkbox("UseQCombo", "Use Q", true)
      Menu.Checkbox("UseWCombo", "Use W", true)
      Menu.Checkbox("UseECombo", "Use E (if reset)", true)
      Menu.Keybind("ComboAlwaysRFollowingEToggle", "Use R Toggle", 84 --[[ T ]], true)
    end)

    Menu.NewTree("Harass", "Harass", function()
      Menu.Slider("HarassMinManaPercent", "Min Mana %", 50, 0, 100, 1)
      Menu.Checkbox("UseQHarass", "Use Q", true)
      Menu.Checkbox("UseWHarass", "Use W", true)
      Menu.Keybind("AutoHarassToggle", "Auto Harass Toggle", 87 --[[ Z ]], true)
    end)

    Menu.NewTree("Farm", "Lane/Jungle Farm", function()
      Menu.Slider("FarmMinManaPercent", "Min Mana %", 50, 0, 100, 1)
      Menu.Checkbox("UseQFarm", "Use Q")
      Menu.Checkbox("UseWFarm", "Use W")
      Menu.Checkbox("UseEFarm", "Use E (if reset)")
    end)

    Menu.NewTree("KillSteal", "KillSteal", function()
      Menu.Checkbox("UseQKS", "Use Q", true)
      Menu.Checkbox("UseEKS", "Use E")
      Menu.Checkbox("UseRKS", "Use R")
    end)

    Menu.NewTree("AutoR", "Automatic R", function()
      Menu.Text("Auto Cast", true)
      Menu.Slider("MinMultiUltCount", ">= Hit (0 to disable)", 3, 0, 5, 1)
      Menu.Separator()
      Menu.Text("Interrupt Spells", true)
      Menu.Checkbox("RInterrupt", "Enable Interrupt Spells", true)

      for _, enemy in pairs(API.ObjectManager.Get("enemy", "heroes")) do
        if enemy.CharName ~= "PracticeTool_TargetDummy" then
          Menu.NewTree("RInterrupt" .. enemy.CharName, enemy.CharName, function()
            for _, data in ipairs(Diana.EnemySpells) do
              if data.source == enemy then
                if data.isMimic then
                  local id = enemy.CharName .. "_" .. data.charName .. data.slot
                  local name = data.charName .. data.slot .. " (Mimic)"
                  Menu.Checkbox(id, name, Diana.RInterruptSpellsDefault[data.charName .. data.slot])
                else
                  local id = data.charName .. data.slot
                  Menu.Checkbox(id, id .. " (" .. data.name .. ")", Diana.RInterruptSpellsDefault[data.charName .. data.slot])
                end
              end
            end
          end)
        end
      end
    end)

    Menu.NewTree("Misc", "Misc", function()
      Menu.Checkbox("SaveManaR", "Save Mana For R", true)
    end)

    Menu.NewTree("Drawings", "Drawings", function()
      Menu.Checkbox("DrawQ", "Draw Q Range", true)
      Menu.ColorPicker("DrawQColor", "Draw Q Color", 0x118AB2FF)
      Menu.Checkbox("DrawW", "Draw W Radius")
      Menu.ColorPicker("DrawWColor", "Draw W Color", 0x118AB2FF)
      Menu.Checkbox("DrawE", "Draw E Range")
      Menu.ColorPicker("DrawEColor", "Draw E Color", 0x118AB2FF)
      Menu.Checkbox("DrawR", "Draw R Radius")
      Menu.ColorPicker("DrawRColor", "Draw R Color", 0x118AB2FF)
      Menu.Separator()
      Menu.Checkbox("DrawComboR", "Draw R Combo Toggle Status", true)
      Menu.Checkbox("DrawAutoHarass", "Draw Auto Harass Toggle Status", true)
      Menu.Checkbox("DrawZones", "Debug Q Zone")

    end)

    Menu.Separator()
    Menu.Text(CONFIG.MODULE_NAME .. " v" .. CONFIG.MODULE_VERSION .. " by " .. CONFIG.MODULE_AUTHOR, true)
    Menu.Text("~ OwO ~", true)

  end)
end
--#endregion

--#region Draw
function Diana.OnDraw()

  if Config.DrawZones and Diana.Crescent ~= nil then
    Diana.Cone:Draw()
    Diana.Crescent:Draw()
    Diana.Explosion:Draw()
  end

  if Config.DrawQ and Diana.Q:IsReady() then
    API.Renderer.DrawCircle3D(API.Player.Position, Diana.Q.Range, 30, 3, Config.DrawQColor)
  end

  if Config.DrawW and Diana.W:IsReady() then
    API.Renderer.DrawCircle3D(API.Player.Position, Diana.W.Radius, 30, 3, Config.DrawWColor)
  end

  if Config.DrawE and Diana.E:IsReady() then
    API.Renderer.DrawCircle3D(API.Player.Position, Diana.E.Range, 30, 3, Config.DrawEColor)
  end

  if Config.DrawR and Diana.R:IsReady() then
    API.Renderer.DrawCircle3D(API.Player.Position, Diana.R.Radius, 30, 3, Config.DrawRColor)
  end

  local off = 0
  if Config.DrawComboR and Config.ComboAlwaysRFollowingEToggle then
    local pos = API.Player.Position
    pos.y = pos.y + 100
    pos.x = pos.x + 80
    off = 50
    API.Renderer.DrawText(pos:ToScreen(), API.Renderer.CalcTextSize(Diana.ComboRText), Diana.ComboRText, 0xFF0000FF)
  end

  if Config.DrawAutoHarass and Config.AutoHarassToggle then
    local pos = API.Player.Position
    pos.y = pos.y + 100 - off
    pos.x = pos.x + 80

    API.Renderer.DrawText(pos:ToScreen(), API.Renderer.CalcTextSize(Diana.AutoHarassText), Diana.AutoHarassText, 0xB4FF00FF)
  end

end
--#endregion

--#region Init
function Diana.Init()
  Diana.InitEnemySpells()
  Diana.SetupMenu()

  for eventName, eventId in pairs(API.Enums.Events) do
    if Diana[eventName] then
        API.EventManager.RegisterCallback(eventId, Diana[eventName])
    end
  end
end
--#endregion

--[[
  ====================================================================================================
  ============================================ Entrypoint ============================================
  ====================================================================================================
--]]
--#region Entrypoint
function OnLoad()
  INFO(CONFIG.MODULE_NAME .. " v" .. CONFIG.MODULE_VERSION .. " by " .. CONFIG.MODULE_AUTHOR .. " loaded")
  INFO("changelog: " .. CONFIG.CHANGELOG)
  Diana.Init()
  return true
end
--#endregion

