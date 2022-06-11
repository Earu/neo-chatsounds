local MODIFIER = {}

MODIFIER.Name = "legacy_volume"
MODIFIER.LegacySyntax = "^^"
MODIFIER.OnlyLegacy = true
MODIFIER.DefaultValue = { 100, 100 }

function MODIFIER:ParseArgs(args)
	local str_args = args:Split(".")
	local volume_start = math.max(1, tonumber(str_args[1]) or 100)
	local volume_end = math.max(1, tonumber(str_args[2]) or 100)

	return { volume_start, volume_end }
end

return MODIFIER