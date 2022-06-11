local MODIFIER = {}

MODIFIER.Name = "skip"
MODIFIER.LegacySyntax = "++"
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(args)
	local skip = tonumber(args)
	if not skip then return 0 end

	return math.max(0, skip)
end

return MODIFIER