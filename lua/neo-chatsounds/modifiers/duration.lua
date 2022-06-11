local MODIFIER = {}

MODIFIER.Name = "duration"
MODIFIER.LegacySyntax = "="
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(args)
	local duration = tonumber(args)
	if not duration then return 0 end

	return math.max(0, duration)
end

return MODIFIER