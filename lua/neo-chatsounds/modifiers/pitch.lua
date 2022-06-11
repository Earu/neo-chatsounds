local MODIFIER = {}

MODIFIER.Name = "pitch"
MODIFIER.LegacySyntax = "%"
MODIFIER.DefaultValue = 100

function MODIFIER:ParseArgs(args)
	local pitch = tonumber(args)
	if not pitch then return 100 end

	return math.min(math.max(1, pitch), 255)
end

return MODIFIER