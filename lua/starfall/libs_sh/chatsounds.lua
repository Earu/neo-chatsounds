SF.RegisterLibrary("chatsounds")
local api = chatsounds.Module("API")

local player_fns = { "PlayScope", "PlaySounds", "PlaySound" }

local function module(instance)
	local unwrap = instance.Types.Player.Unwrap
	local cs = instance.Libraries.chatsounds

	for key, fn in pairs(api) do
		local new_fn = fn
		if SERVER and player_fns[key] then
			new_fn = function(ply, ...)
				ply = unwrap(ply)
				return fn(ply, ...)
			end
		end

		local new_key = key[1]:lower() .. key:sub(2)
		cs[new_key] = new_fn
	end
end

return module