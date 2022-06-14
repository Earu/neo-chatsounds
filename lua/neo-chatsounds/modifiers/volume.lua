local MODIFIER = {}

MODIFIER.Name = "volume"
MODIFIER.LegacySyntax = "^"
MODIFIER.DefaultValue = 1

function MODIFIER:ParseArgs(args)
	local volume = tonumber(args)
	if volume then return math.abs(volume) end

	return 1
end

function MODIFIER:LegacyParseArgs(args)
	local volume = tonumber(args)
	if volume then return math.abs(volume / 100) end

	return 1
end

function MODIFIER:OnStreamThink(stream)
	stream:SetVolume(self.Value)
end

return MODIFIER