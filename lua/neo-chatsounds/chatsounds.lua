local chatsounds = {}
_G.chatsounds = chatsounds

chatsounds.modifiers = {}
for _, f in pairs(file.Find("neo-chatsounds/modifiers/*.lua", "LUA")) do
	AddCSLuaFile("neo-chatsounds/modifiers/" .. f)
	chatsounds.modifiers[f:StripExtension()] = include("neo-chatsounds/modifiers/" .. name)
end

AddCSLuaFile("neo-chatsounds/tasks.lua")
AddCSLuaFile("neo-chatsounds/expressions.lua")
AddCSLuaFile("neo-chatsounds/parser.lua")

include("neo-chatsounds/tasks.lua")
include("neo-chatsounds/expressions.lua")
include("neo-chatsounds/parser.lua")