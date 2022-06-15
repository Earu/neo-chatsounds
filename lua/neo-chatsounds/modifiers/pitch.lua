local MODIFIER = {}

MODIFIER.Name = "pitch"
MODIFIER.LegacySyntax = "%"
MODIFIER.DefaultValue = 100

function MODIFIER:ParseArgs(args)
	local pitch = tonumber(args)
	if not pitch then return 1 end

	return math.min(math.max(-5, pitch), 5)
end

function MODIFIER:LegacyParseArgs(args)
	local pitch = tonumber(args) or 100
	return math.min(math.max(-5, pitch / 100), 5)
end

function MODIFIER:OnStreamInit(stream)
	if not stream.Duration then
		stream.Duration = stream:GetLength()
	end

	stream.Duration = stream.Duration / math.abs(self.Value)
end

function MODIFIER:OnStreamThink(stream)
	stream:SetPlaybackRate(self.Value)
end

return MODIFIER