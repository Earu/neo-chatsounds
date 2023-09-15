local chatsounds = _G.chatsounds or {}
_G.chatsounds = chatsounds

chatsounds.Debug = false

function chatsounds.Reload()
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

	function chatsounds.DebugLog(...)
		if not chatsounds.Debug then return end

		chatsounds.Log(...)
	end

	function chatsounds.Error(err)
		if not metalog then
			ErrorNoHalt("[neo-chatsounds: " .. (CLIENT and "Client" or "Server") .. "] " .. err .. "\n")
			return
		end

		metalog.error("neo-chatsounds", CLIENT and "Client" or "Server", err)
	end

	-- we create a different convar for the server because it breaks in p2p and singleplayer otherwise
	local CS_ENABLE = SERVER
		and CreateConVar("chatsounds_enable_sv", "1", FCVAR_ARCHIVE, "Enables/disables chatsounds", 0, 1)
		or CreateConVar("chatsounds_enable", "1", FCVAR_ARCHIVE, "Enables/disables chatsounds", 0, 1)

	chatsounds.Enabled = CS_ENABLE:GetBool()
	cvars.AddChangeCallback(CS_ENABLE:GetName(), function()
		chatsounds.Enabled = CS_ENABLE:GetBool()
	end)

	-- external deps
	do
		AddCSLuaFile("neo-chatsounds/dependencies/find_head_pos.lua")
		AddCSLuaFile("neo-chatsounds/dependencies/webaudio.lua")
		AddCSLuaFile("neo-chatsounds/dependencies/tasks.lua")
		AddCSLuaFile("neo-chatsounds/dependencies/json.lua")
		AddCSLuaFile("neo-chatsounds/dependencies/msgpack.lua")

		if CLIENT then
			chatsounds.WebAudio = include("neo-chatsounds/dependencies/webaudio.lua")
		end

		chatsounds.Tasks = include("neo-chatsounds/dependencies/tasks.lua")
		chatsounds.Json = include("neo-chatsounds/dependencies/json.lua")
		chatsounds.MsgPack = include("neo-chatsounds/dependencies/msgpack.lua")
	end


	function chatsounds.Module(name)
		if name == "Data" then
			-- HACK: Hiding Data module from lua_find_cl 
			local module = chatsounds[name]

			if not module then
				local module_table = {}
				chatsounds["Get" .. name] = function() return module_table end

				module = setmetatable({}, {
					__index = module_table,
					__newindex = module_table,
					module_table = module_table,
					__tostring = function() return "<Chatsounds Module: " .. name .. ">" end
				})
			end

			chatsounds[name] = module

			return module
		end

		local module = chatsounds[name] or {}
		chatsounds[name] = module

		return module
	end

	-- internal deps + modules
	do
		AddCSLuaFile("neo-chatsounds/internal_modules/runners.lua")
		AddCSLuaFile("neo-chatsounds/internal_modules/expressions.lua")
		AddCSLuaFile("neo-chatsounds/internal_modules/http.lua")

		include("neo-chatsounds/internal_modules/runners.lua")
		include("neo-chatsounds/internal_modules/expressions.lua")
		include("neo-chatsounds/internal_modules/http.lua")
	end

	-- core
	do
		local modifiers = chatsounds.Module("Modifiers")
		for _, f in pairs(file.Find("neo-chatsounds/modifiers/*.lua", "LUA")) do
			AddCSLuaFile("neo-chatsounds/modifiers/" .. f)
			modifiers[f:StripExtension()] = include("neo-chatsounds/modifiers/" .. f)
		end

		AddCSLuaFile("neo-chatsounds/data.lua")
		AddCSLuaFile("neo-chatsounds/completion.lua")
		AddCSLuaFile("neo-chatsounds/parser.lua")
		AddCSLuaFile("neo-chatsounds/player.lua")
		AddCSLuaFile("neo-chatsounds/blacklist.lua")
		AddCSLuaFile("neo-chatsounds/flexes.lua")

		include("neo-chatsounds/data.lua")
		include("neo-chatsounds/completion.lua")
		include("neo-chatsounds/parser.lua")
		include("neo-chatsounds/player.lua")
		include("neo-chatsounds/blacklist.lua")
		include("neo-chatsounds/flexes.lua")
	end
end

chatsounds.Reload()

concommand.Remove("chatsounds_reload")
concommand.Add("chatsounds_reload", function()
	chatsounds.Reload()
	chatsounds.Data.CompileLists()
end, "Reloads chatsounds")
