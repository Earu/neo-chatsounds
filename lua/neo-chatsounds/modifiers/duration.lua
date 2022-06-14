local MODIFIER = {}

MODIFIER.Name = "duration"
MODIFIER.LegacySyntax = "="
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(args)
	local duration = tonumber(args)
	if not duration then return -1 end

	return math.max(0, duration)
end

function MODIFIER:OnStreamInit(stream)
	if self.Value ~= -1 then
		stream.Duration = self.Value
	end

	if self.IsLegacy then
		stream.Overlap = true
	end
end

return MODIFIER