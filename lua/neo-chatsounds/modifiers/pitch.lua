local MODIFIER = {}

MODIFIER.Name = "pitch"
MODIFIER.LegacySyntax = "%"
MODIFIER.DefaultValue = 1

function MODIFIER:ParseArgs(args)
	local pitch = tonumber(args)
	if not pitch then return self.DefaultValue end

	return math.min(math.max(-5, pitch), 5)
end

function MODIFIER:LegacyParseArgs(args)
	local pitch = tonumber(args) or 100
	return math.min(math.max(-5, pitch / 100), 5)
end

function MODIFIER:GetValue()
	if not self.Value then return self.DefaultValue end
	if isfunction(self.ExpressionFn) then
		local _, ret = pcall(self.ExpressionFn)
		if not isnumber(ret) then return self.DefaultValue end

		return math.min(math.max(-5, ret), 5)
	end

	return self.Value
end

function MODIFIER:OnStreamInit(stream)
	if not stream.Duration then
		stream.Duration = stream:GetLength()
	end

	stream.Duration = stream.Duration / math.abs(self:GetValue())
end

function MODIFIER:OnStreamThink(stream)
	stream:SetPlaybackRate(self:GetValue())
end

return MODIFIER