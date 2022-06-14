local MODIFIER = {}

MODIFIER.Name = "lowpass"
MODIFIER.DefaultValue = 0.5

function MODIFIER:ParseArgs(args)
	local cutoff = tonumber(args)
	if not cutoff then return 0.5 end

	return math.min(1, cutoff)
end

function MODIFIER:OnStreamInit(stream)
	stream:SetFilterType(1)
	stream:SetFilterFraction(num)
end

return MODIFIER