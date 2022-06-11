local chatsounds = {}
_G.chatsounds = chatsounds

function chatsounds.Log(...)
	if not metalog then
		Msg("[neo-chatsounds] ")
		print(...)
		return
	end

	metalog.info("neo-chatsounds", nil, ...)
end

function chatsounds.Error(err)
	if not metalog then
		ErrorNoHalt("[neo-chatsounds] " .. err)
		return
	end

	metalog.error("neo-chatsounds", nil, err)
end

-- external deps
do
	AddCSLuaFile("neo-chatsounds/dependencies/find_head_pos.lua")
	AddCSLuaFile("neo-chatsounds/dependencies/webaudio.lua")
	AddCSLuaFile("neo-chatsounds/dependencies/tasks.lua")

	chatsounds.WebAudio = include("neo-chatsounds/dependencies/webaudio.lua")
	chatsounds.Tasks = include("neo-chatsounds/dependencies/tasks.lua")
end

function chatsounds.Module(name)
	local module = chatsounds[name] or {}
	chatsounds[name] = module
	return module
end

-- internal deps + modules
do
	AddCSLuaFile("neo-chatsounds/internal_modules/runners.lua")
	AddCSLuaFile("neo-chatsounds/internal_modules/expressions.lua")

	include("neo-chatsounds/internal_modules/runners.lua")
	include("neo-chatsounds/internal_modules/expressions.lua")
end

-- core
do
	local modifiers = chatsounds.Module("Modifiers")
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