local MODIFIER = {}

MODIFIER.Name = "echo"
MODIFIER.DefaultValue = { 0.25, 0.5 }

function MODIFIER:ParseArgs(args)
	local str_args = args:Split(",")
	local echo_delay = math.max(0, tonumber(str_args[1]) or 0.25)
	local echo_feedback = math.max(0, tonumber(str_args[2]) or 0.5)

	return { echo_delay, echo_feedback }
end

function MODIFIER:OnStreamInit(stream)
	stream:SetEcho(true)
	stream:SetEchoDelay(self.Value[1])
	stream:SetEchoFeedback(self.Value[2])
end

return MODIFIER