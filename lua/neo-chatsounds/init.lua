local chatsounds = {}
_G.chatsounds = chatsounds

-- external deps
do
	AddCSLuaFile("neo-chatsounds/dependencies/webaudio.lua")
	AddCSLuaFile("neo-chatsounds/dependencies/tasks.lua")

	chatsounds.webaudio = include("neo-chatsounds/dependencies/webaudio.lua")
	chatsounds.tasks = include("neo-chatsounds/dependencies/tasks.lua")
end

function DEFINE_CHATSOUND_MODULE(name)
	local module = chatsounds[name] or {}
	chatsounds[name] = module
	return module
end

-- internal deps + modules
do
	AddCSLuaFile("neo-chatsounds/internal_modules/task_runners.lua")
	AddCSLuaFile("neo-chatsounds/internal_modules/expressions.lua")

	include("neo-chatsounds/internal_modules/task_runners.lua")
	include("neo-chatsounds/internal_modules/expressions.lua")
end

-- core
do
	local modifiers = DEFINE_CHATSOUND_MODULE("modifiers")
	for _, f in pairs(file.Find("neo-chatsounds/modifiers/*.lua", "LUA")) do
		AddCSLuaFile("neo-chatsounds/modifiers/" .. f)
		modifiers[f:StripExtension()] = include("neo-chatsounds/modifiers/" .. f)
	end

	AddCSLuaFile("neo-chatsounds/data.lua")
	AddCSLuaFile("neo-chatsounds/parser.lua")
	AddCSLuaFile("neo-chatsounds/player.lua")

	include("neo-chatsounds/data.lua")
	include("neo-chatsounds/parser.lua")
	include("neo-chatsounds/player.lua")
end