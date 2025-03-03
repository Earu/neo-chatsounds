SF.RegisterLibrary("chatsounds")
local api = chatsounds.Module("API")
local checkluatype = SF.CheckLuaType

local player_fns = {
	PlayScope = true,
	PlaySounds = true,
	PlaySound = true
}
if SERVER then
	SF.Permissions.registerPrivilege("chatsounds.playOnPlayers", "Chatsounds Play methods", "Allow the user to emit chatsounds from you", { server = { default = 3 }})
end

if CLIENT then
	SF.Permissions.registerPrivilege("chatsounds.repos", "Chatsounds addRepo methods", "Allow the user to add new chatsounds repos", { client = { default = 3 } })
end

local function module(instance)
	local unwrap = instance.Types.Player.Unwrap
	local cs = instance.Libraries.chatsounds
	local checkPermission = instance.player ~= SF.Superuser and SF.Permissions.check or function() end

	for key, fn in pairs(api) do
		local new_fn = fn
		if SERVER and player_fns[key] then
			if key == "PlayScope" then
				new_fn = function(ply, scope, recipient_filter)
					ply = unwrap(ply)
					checkPermission(instance, ply, "chatsounds.playOnPlayers")

					if recipient_filter then
						checkluatype(recipient_filter, TYPE_TABLE)
						for i, pl in ipairs(recipient_filter) do
							recipient_filter[i] = unwrap(pl)
						end
					end

					return fn(ply, scope, recipient_filter)
				end
			else
				new_fn = function(ply, ...)
					ply = unwrap(ply)
					checkPermission(instance, ply, "chatsounds.playOnPlayers")

					return fn(ply, ...)
				end
			end
		end

		local new_key = key[1]:lower() .. key:sub(2)
		cs[new_key] = new_fn
	end

	if CLIENT then
		function cs.addRepo(...)
			checkPermission(instance, instance.player, "chatsounds.repos")

			return api.AddRepo(...)
		end

		function cs.addRepos(...)
			checkPermission(instance, instance.player, "chatsounds.repos")

			return api.AddRepos(...)
		end
	end
end

return module
