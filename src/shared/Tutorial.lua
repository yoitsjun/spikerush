-- The tutorial: a 1v1 practice match against a weak bot with a checklist of the basics. Each
-- step is ticked by the server when you really do it (a serve, a receive, a set, a spike, a block
-- jump, a jump serve, a won rally); the last tick pays Config.Tutorial's reward once.
-- Shared so the server, the HUD coach and the headless tests read the same steps.

local Config = require(script.Parent.Config)

local Tutorial = {}

Tutorial.Steps = {
	{ id = "serve", title = "Serve", key = "Press F for an easy underhand serve (or tap X for an overhand).", pad = "Press D-pad up for an easy underhand serve.", touch = "Tap Easy serve." },
	{ id = "receive", title = "Receive", key = "When the ball comes to you, press S (or right click) a little before it arrives.", pad = "When the ball comes to you, press B a little before it arrives.", touch = "When the ball comes to you, tap Receive a little before it arrives." },
	{ id = "set", title = "Set", key = "After your receive, press E to set the ball up for yourself.", pad = "After your receive, press LB to set the ball up for yourself.", touch = "After your receive, tap Set to put the ball up for yourself." },
	{ id = "spike", title = "Spike", key = "As the set comes down, press Z to jump, then Z again in the air to hit it.", pad = "As the set comes down, press A to jump, then A again in the air to hit it.", touch = "As the set comes down, tap Spike to jump, then Spike again in the air." },
	{ id = "block", title = "Block", key = "Stand at the net, hold W and let go to jump with your hands up.", pad = "Stand at the net, hold Y and let go to jump with your hands up.", touch = "Stand at the net, hold Block and let go to jump." },
	{ id = "jumpserve", title = "Jump serve", key = "On your serve hold X to toss, then Z to jump and Z again to hit.", pad = "On your serve hold X to toss, then A to jump and A again to hit.", touch = "On your serve hold Serve to toss, then Spike to jump and Spike again." },
	{ id = "point", title = "Win a rally", key = "Put the ball down on their side.", pad = "Put the ball down on their side.", touch = "Put the ball down on their side." },
}

local VALID = {}
for _, s in ipairs(Tutorial.Steps) do
	VALID[s.id] = true
end

function Tutorial.isStep(id)
	return VALID[id] == true
end

-- The steps a touch of this hit type completes.
local BY_HIT = {
	Underhand = { "serve" },
	Overhand = { "serve" },
	JumpServe = { "serve", "jumpserve" },
	Bump = { "receive" },
	Set = { "set" },
	Spike = { "spike" },
	Block = { "block" },
}

function Tutorial.stepsFor(hitType)
	return BY_HIT[hitType or ""] or {}
end

-- The first step not done yet (nil when all are), and how many are done.
function Tutorial.progress(done)
	done = done or {}
	local n, nextStep = 0, nil
	for _, s in ipairs(Tutorial.Steps) do
		if done[s.id] then
			n = n + 1
		elseif not nextStep then
			nextStep = s
		end
	end
	return nextStep, n, #Tutorial.Steps
end

function Tutorial.complete(done)
	local nextStep = Tutorial.progress(done)
	return nextStep == nil
end

function Tutorial.reward()
	local T = Config.Tutorial
	return T.RewardVP, T.RewardGold, T.RewardSpins
end

return Tutorial
