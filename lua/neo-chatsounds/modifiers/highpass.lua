local MODIFIER = {}

MODIFIER.Name = "highpass"
MODIFIER.DefaultValue = 0.5

function MODIFIER:ParseArgs(args)
	local cutoff = tonumber(args)
	if not cutoff then return 0.5 end

	return math.min(1, cutoff)
end

return MODIFIER