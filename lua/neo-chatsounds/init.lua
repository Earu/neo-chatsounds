local chatsounds = {}
_G.chatsounds = chatsounds

local NO_METALOG_HEADER_COLOR = Color(100, 100, 255)
local COLOR_WHITE = Color(255, 255, 255)
function chatsounds.Log(...)
	if not metalog then
		local str_args = {}
		for _, arg in pairs({...}) do
			table.insert(str_args, isstring(arg) and arg or tostring(arg))
		end

		MsgC(COLOR_WHITE, "[", NO_METALOG_HEADER_COLOR, "neo-chatsounds: " .. (CLIENT and "Client" or "Server"), COLOR_WHITE, "] " .. table.concat(str_args, "\t") .. "\n")
		return
	end

	metalog.info("neo-chatsounds", CLIENT and "Client" or "Server", ...)
end

function chatsounds.Error(err)
	if not metalog then
		ErrorNoHalt("[neo-chatsounds: " .. (CLIENT and "Client" or "Server") .. "] " .. err)
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