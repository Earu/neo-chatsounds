local MODIFIER = {}

MODIFIER.Name = "cutoff"
MODIFIER.LegacySyntax = "--"
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(args)
	local cutoff = tonumber(args)
	if not cutoff then return 0 end

	return math.max(0, cutoff)
end

return MODIFIER