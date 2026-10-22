-- The AFK Lounge (Config.Lounge, the Lounge module; the owner: "add an afk chamber"): a player who
-- steps in from Home's AFK button earns Gold every Interval they stay, up to today's cap, with a
-- small chance of V Points each payout. Their time towards the next payout lives on the profile
-- (ProfileService.lounge), so it carries on after leaving or rejoining.
--   * "Lounge" remote: client -> server "enter", "leave", "get"; server -> client the lounge's
--     state ({ inside, nextIn, interval, rate, vip, premium, earned, earnedVP, today, cap, ... }),
--     or { refused = text } / { refreshing = true }.
--   * A player in a match can't come in; one in a lobby leaves it on the way in, and one pulled
--     into a lobby or a match while inside (a party) is let out.
--   * Your own server (the owner, 2026-10-22: "make this teleport you to your own game"): stepping
--     in from a public server reserves a private server of this place for you alone and teleports
--     you there with { lounge = true, loungeServer = true }; that server is a lounge server
--     (isLoungeServer), where Return to game teleports you back to a public server. Where
--     teleports can't happen (Studio, or one failing) the lounge runs where you are, as before.
--   * Roblox drops a player after 20 minutes without input. Inputs come in as the Activity pings
--     (InputController); past RefreshAfter without one, the profile is saved and the player is
--     teleported to a fresh server of this place with { lounge = true }, where they're put
--     straight back in (and the loading screen skips its click). Teleports don't work in Studio.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Lounge = require(Shared.Lounge)
local Economy = require(Shared.Economy)

local LoungeService = {}
local L = Config.Lounge
local reg
local inside = {} -- player -> { earned, vp, synced }: this visit's Gold and V Points, the last send
local lastInput = {} -- player -> os.clock() of their last input
local refreshing = {} -- player -> "lounge" or "game" while their teleport there is on its way
local isLoungeServer = false -- this server is someone's own lounge (they came in with loungeServer)
local rng = Random.new()

local function perks(plr)
	local vip = reg.ProfileService.hasPass(plr, "VIP")
	local premium = plr.MembershipType == Enum.MembershipType.Premium
	return vip, premium
end

local function onCourt(plr)
	local TS = reg.TeamService
	return TS.inMatch and TS.entityForPlayer(plr) ~= nil
end

local function inLobby(plr)
	local LS = reg.LobbyService
	return LS ~= nil and LS.lobbyOf(plr) ~= nil
end

local function send(plr, extra)
	local rec = reg.ProfileService.lounge(plr)
	if not rec then
		return
	end
	local st = inside[plr]
	local vip, premium = perks(plr)
	local out = {
		inside = st ~= nil,
		nextIn = Lounge.nextIn(rec), -- (nil once today's are all paid)
		interval = L.Interval,
		rate = Lounge.rate(vip, premium),
		base = L.BaseGold,
		vip = vip,
		premium = premium,
		earned = st and st.earned or 0,
		earnedVP = st and st.vp or 0,
		today = rec.gold,
		cap = Lounge.cap(vip, premium),
		paidToday = rec.payouts,
		refreshing = refreshing[plr] ~= nil,
		moving = refreshing[plr], -- ("lounge": to their own server; "game": back to a public one)
		own = isLoungeServer,
	}
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	if st then
		st.synced = os.clock()
	end
	Net.get("Lounge"):FireClient(plr, out)
end

local move -- (a teleport to their own server or back: below)

local function enter(plr)
	if inside[plr] or not reg.ProfileService.lounge(plr) then
		send(plr)
		return
	end
	if onCourt(plr) then
		Net.get("Lounge"):FireClient(plr, { refused = "Finish your match first." })
		return
	end
	if inLobby(plr) then
		reg.LobbyService.leave(plr)
	end
	inside[plr] = { earned = 0, vp = 0, synced = 0 }
	lastInput[plr] = lastInput[plr] or os.clock()
	send(plr)
	if not isLoungeServer then
		move(plr, "lounge") -- (their own server; the time inside counts on the way)
	end
end

local function leave(plr)
	if not inside[plr] then
		return
	end
	inside[plr] = nil
	reg.ProfileService.markDirty(plr)
	send(plr)
end

-- A teleport: `to` "lounge" is a new private server of this place for them alone (stepping in, and
-- the refresh before Roblox's idle kick), "game" a public one (Return to game). The profile is
-- saved first. Teleports don't work in Studio: there (or when one fails) they stay where they are.
function move(plr, to)
	if refreshing[plr] then
		return
	end
	refreshing[plr] = to
	lastInput[plr] = os.clock() -- (a failed refresh tries again after another RefreshAfter)
	send(plr)
	task.spawn(function()
		reg.ProfileService.save(plr)
		local ok, err = pcall(function()
			if RunService:IsStudio() then
				error("teleports don't work in Studio")
			end
			local opts = Instance.new("TeleportOptions")
			if to == "lounge" then
				opts.ReservedServerAccessCode = TeleportService:ReserveServer(game.PlaceId)
				opts:SetTeleportData({ lounge = true, loungeServer = true })
			end
			TeleportService:TeleportAsync(game.PlaceId, { plr }, opts)
		end)
		if not ok then
			warn("[SpikeRush] lounge teleport (" .. to .. ") for " .. plr.Name .. ": " .. tostring(err))
			refreshing[plr] = nil
			if plr.Parent then
				if to == "game" then
					leave(plr) -- (back on the menus here)
				else
					send(plr)
				end
			end
		end
	end)
end

local function refresh(plr)
	move(plr, "lounge")
end

local function tick(dt)
	for plr, st in pairs(inside) do
		if not plr.Parent then
			inside[plr] = nil
		elseif onCourt(plr) or inLobby(plr) then
			leave(plr) -- (pulled into a lobby or a match: a party's)
		else
			local rec = reg.ProfileService.lounge(plr)
			if rec then
				local vip, premium = perks(plr)
				local gold, vp, n = Lounge.advance(rec, dt, Lounge.rate(vip, premium), function()
					return rng:NextNumber()
				end)
				reg.ProfileService.markDirty(plr)
				if n > 0 then
					st.earned = st.earned + gold
					st.vp = st.vp + vp
					local g = Economy.cleanGrant({ Gold = gold, VP = vp })
					reg.ProfileService.grant(plr, g, (vp > 0 and "AFK Lounge, a lucky find: " or "AFK Lounge: ") .. Economy.describe(g))
					send(plr, { paid = gold, paidVP = vp })
				elseif os.clock() - st.synced >= L.SyncEvery then
					send(plr)
				end
				if os.clock() - (lastInput[plr] or 0) >= L.RefreshAfter then
					refresh(plr)
				end
			end
		end
	end
end

-- Put a player who came in through a refresh back in, once their profile has loaded.
local function arrived(plr)
	local ok, data = pcall(function()
		return plr:GetJoinData().TeleportData
	end)
	if not (ok and type(data) == "table" and data.lounge == true) then
		return
	end
	if data.loungeServer == true then
		isLoungeServer = true
	end
	task.spawn(function()
		for _ = 1, 60 do
			if not plr.Parent then
				return
			end
			if reg.ProfileService.lounge(plr) then
				enter(plr)
				return
			end
			task.wait(0.5)
		end
	end)
end

function LoungeService.isInside(plr)
	return inside[plr] ~= nil
end

function LoungeService.init(r)
	reg = r
	Net.get("Lounge").OnServerEvent:Connect(function(plr, op)
		if op == "enter" then
			enter(plr)
		elseif op == "leave" then
			if isLoungeServer then
				move(plr, "game") -- (your own server: back to a public one)
			else
				leave(plr)
			end
		elseif op == "get" then
			send(plr)
		end
	end)
	Net.get("Activity").OnServerEvent:Connect(function(plr)
		lastInput[plr] = os.clock()
	end)
	TeleportService.TeleportInitFailed:Connect(function(plr, result, message)
		if refreshing[plr] then
			warn("[SpikeRush] lounge refresh for " .. plr.Name .. " failed: " .. tostring(result) .. " " .. tostring(message))
			refreshing[plr] = nil
			send(plr)
		end
	end)
	Players.PlayerAdded:Connect(function(plr)
		lastInput[plr] = os.clock()
		arrived(plr)
	end)
	for _, plr in ipairs(Players:GetPlayers()) do
		lastInput[plr] = lastInput[plr] or os.clock()
		arrived(plr)
	end
	Players.PlayerRemoving:Connect(function(plr)
		if inside[plr] then
			reg.ProfileService.markDirty(plr)
		end
		inside[plr] = nil
		lastInput[plr] = nil
		refreshing[plr] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			local ok, err = pcall(tick, math.min(now - last, 5))
			last = now
			if not ok then
				warn("[SpikeRush] lounge: " .. tostring(err))
			end
		end
	end)
end

return LoungeService
