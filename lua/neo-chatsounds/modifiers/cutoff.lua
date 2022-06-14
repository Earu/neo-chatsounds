local MODIFIER = {}

MODIFIER.Name = "cutoff"
MODIFIER.LegacySyntax = "--"
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(args)
	local cutoff = tonumber(args)
	if not cutoff then return 100 end

	return math.max(0, cutoff)
end

function MODIFIER:OnStreamInit(stream)
	stream.Duration = stream.Duration * (self.Value / 100)
end

return MODIFIER