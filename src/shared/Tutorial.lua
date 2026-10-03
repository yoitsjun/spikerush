-- Practice drills, and the tutorial made of them. Nothing here is a rally: every rep the server
-- (PracticeService) puts the ball where the drill needs it (a bot setter's set to you, a bot's
-- spike at the net or at you, or the ball in your hands to serve), judges that one touch or
-- landing, and resets. The tutorial runs all four drills in order and pays Config.Tutorial's
-- reward once; the Practice tab runs one drill as often as you like.
-- Shared so the server, the menus, the HUD coach and the headless tests read the same drills.

local Config = require(script.Parent.Config)

local Tutorial = {}

-- goal: successful reps to finish; inARow: a miss starts the count again
Tutorial.Drills = {
	{
		id = "spike",
		title = "Spike",
		goal = 3,
		inARow = false,
		blurb = "A setter puts the ball up for you. Spike 3 into their court.",
		key = "Run up as the set comes ({Spike} or left click), then press it again in the air to hit it.",
		pad = "Run up as the set comes (A), then A again in the air to hit it.",
		touch = "Tap Jump as the set comes, then Spike in the air.",
	},
	{
		id = "block",
		title = "Block",
		goal = 3,
		inARow = false,
		blurb = "Their attacker hits from the net. Get your hands on 3 of them.",
		key = "Hold {Block} at the net and let go to jump as they swing.",
		pad = "Hold Y at the net and let go to jump as they swing.",
		touch = "At the net, hold Bump (it turns into Block) and let go to jump as they swing.",
	},
	{
		id = "serve",
		title = "Serve",
		goal = 3,
		inARow = true,
		blurb = "Land 3 serves in their court in a row.",
		key = "{EasyServe} for an easy underhand serve, tap {Serve} for an overhand, hold {Serve} to toss for a jump serve.",
		pad = "D-pad up for an easy serve, tap X for an overhand, hold X to toss for a jump serve.",
		touch = "Basic Serve, or Spike Serve (hold it to toss for a jump serve).",
	},
	{
		id = "dig",
		title = "Dig",
		goal = 3,
		inARow = true,
		blurb = "Their attacker spikes at you. Dig 3 in a row.",
		key = "Press {Receive} (or right click) a little before the ball reaches you.",
		pad = "Press B a little before the ball reaches you.",
		touch = "Tap Bump a little before the ball reaches you.",
	},
}
Tutorial.Steps = Tutorial.Drills -- the tutorial's steps are the drills, in this order

local BY_ID = {}
for _, d in ipairs(Tutorial.Drills) do
	BY_ID[d.id] = d
end

-- A drill's keyboard line with your keys in it: {Action} becomes keysText(action) (Settings >
-- Controls can move them).
function Tutorial.fill(text, keysText)
	return (string.gsub(text or "", "{(%a+)}", function(action)
		return keysText(action)
	end))
end

function Tutorial.drill(id)
	return BY_ID[id or ""]
end

function Tutorial.isStep(id)
	return BY_ID[id or ""] ~= nil
end

-- A rep's result on a drill's count: returns the new count and whether the drill is done.
-- A miss costs nothing on a drill you finish in total, and starts an in-a-row drill again.
function Tutorial.tally(drill, count, success)
	if success then
		count = count + 1
	elseif drill.inARow then
		count = 0
	end
	return count, count >= drill.goal
end

-- The first drill not done yet (nil when all are), and how many are done.
function Tutorial.progress(done)
	done = done or {}
	local n, nextStep = 0, nil
	for _, d in ipairs(Tutorial.Drills) do
		if done[d.id] then
			n = n + 1
		elseif not nextStep then
			nextStep = d
		end
	end
	return nextStep, n, #Tutorial.Drills
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
