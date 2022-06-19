local MODIFIER = {}

MODIFIER.Name = "startpos"
MODIFIER.DefaultValue = 0

function MODIFIER:ParseArgs(args)
	local n = tonumber(args)
	if not n then return 0 end

	return math.max(0, n) / 100
end

function MODIFIER:OnStreamThink(stream)
	if not self.StreamStarted then
		self.StreamStarted = true
		local value = self.ExpressionFn and self.ExpressionFn() or self.Value
		stream:SetSamplePosition(stream:GetSampleCount() * value)
	end
end

return MODIFIER