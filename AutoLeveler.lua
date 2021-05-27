-- https://raw.githubusercontent.com/hq-af/roburlol/main/AutoLeveler.lua

module("AutoLeveler", package.seeall, log.setup)
clean.module("AutoLeveler", clean.seeall, log.setup)

local Events, EventManager = _G.CoreEx.Enums.Events, _G.CoreEx.EventManager
local Menu = _G.Libs.NewMenu
local Player = _G.Player
local SpellSlots = _G.CoreEx.Enums.SpellSlots
local Input = _G.CoreEx.Input
local Game = _G.CoreEx.Game

local AutoLeveler = {}
AutoLeveler.SleepUntil = 0

function AutoLeveler.SetupMenu()
    Menu.RegisterMenu("AutoLeveler", "AutoLeveler", function()
        Menu.Checkbox("LevelEnable" .. Player.CharName, "Enable for " .. Player.CharName, false)
        Menu.Separator()
        Menu.Text("Spell Order")
        Menu.Slider("LevelOrderR" .. Player.CharName, "R", 1, 1, 4)
        Menu.Slider("LevelOrderQ" .. Player.CharName, "Q", 2, 1, 4)
        Menu.Slider("LevelOrderW" .. Player.CharName, "W", 3, 1, 4)
        Menu.Slider("LevelOrderE" .. Player.CharName, "E", 4, 1, 4)
        Menu.Checkbox("LevelAll" .. Player.CharName, "Learn all spells first", true)
        Menu.Separator()
        Menu.Slider("LevelAt" .. Player.CharName, "Start at level >=", 4, 1, 18)
		Menu.Slider("LevelDelay", "Delay (ms)", 100, 0, 5000)
    end)
end

function AutoLeveler.OnTick()
    if Player.SpellPoints < 1
       or not Menu.Get("LevelEnable" .. Player.CharName) 
       or Player.Level < Menu.Get("LevelAt" .. Player.CharName)
    then return end
	
    if AutoLeveler.SleepUntil == 0 then
		AutoLeveler.SleepUntil = Game.GetTime()*1000 + Menu.Get("LevelDelay")
        return
    elseif Game.GetTime()*1000 < AutoLeveler.SleepUntil then return end
	
    AutoLeveler.SleepUntil = 0

    local order = { 
        { Menu.Get("LevelOrderR" .. Player.CharName), SpellSlots.R,  Player:CanLevelSpell(SpellSlots.R), Player:GetSpell(SpellSlots.R).Level },
        { Menu.Get("LevelOrderQ" .. Player.CharName), SpellSlots.Q,  Player:CanLevelSpell(SpellSlots.Q), Player:GetSpell(SpellSlots.Q).Level },
        { Menu.Get("LevelOrderW" .. Player.CharName), SpellSlots.W,  Player:CanLevelSpell(SpellSlots.W), Player:GetSpell(SpellSlots.W).Level },
        { Menu.Get("LevelOrderE" .. Player.CharName), SpellSlots.E,  Player:CanLevelSpell(SpellSlots.E), Player:GetSpell(SpellSlots.E).Level }
    }

    table.sort(order, function(a, b)
        return a[1] < b[1] -- order order
    end)

    if Menu.Get("LevelAll" .. Player.CharName) then
        for _, entry in pairs(order) do
            if entry[3] and entry[4] == 0 then -- canLevel level
                Input.LevelSpell(entry[2]) -- slot
                return
            end
        end
    end

    for _, entry in pairs(order) do
        if entry[3] then -- canLevel
            Input.LevelSpell(entry[2]) -- slot
            return
        end
    end
end

AutoLeveler.SetupMenu()
EventManager.RegisterCallback(Events.OnTick, AutoLeveler.OnTick)

return true
