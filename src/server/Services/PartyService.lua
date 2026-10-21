-- Parties (the owner, 2026-10-21: "add a proper party system so you can actually queue ranked, but
-- also regular queues"): players in this server team up (Config.Party.Max), and the leader's
-- Quick Match or ranked queue takes everyone in, on one side (LobbyService.quick).
--
-- The Party remote: client -> server (op, a); server -> client { party = { id, leader, members =
-- { { id, name } } } or false, invites = { { id = party id, from = name } }, notice }.
--   ("get")                 your party and your invites
--   ("invite", userId)      the leader invites someone here who isn't in a party
--   ("accept", partyId)     join it (leaving yours)
--   ("decline", partyId)
--   ("leave")               (a leader leaving hands it on; the last one out ends it)
--   ("kick", userId)        the leader
--   ("lead", userId)        the leader makes someone else the leader

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PartyService = {}
local reg
local P = Config.Party
local parties = {} -- id -> { id, leader = userId, members = { userId... } (leader first), invites = { [userId] = expires } }
local partyOf = {} -- userId -> party id
local nextId = 0

local function nameOf(userId)
	local plr = Players:GetPlayerByUserId(userId)
	return plr and plr.DisplayName or tostring(userId)
end

local function payload(plr, notice)
	local id = partyOf[plr.UserId]
	local party = id and parties[id]
	local out = { party = false, invites = {}, notice = notice }
	if party then
		local members = {}
		for _, u in ipairs(party.members) do
			table.insert(members, { id = u, name = nameOf(u) })
		end
		out.party = { id = party.id, leader = party.leader, members = members, max = P.Max }
	end
	local now = os.clock()
	for pid, p in pairs(parties) do
		local exp = p.invites[plr.UserId]
		if exp and exp > now and pid ~= id then
			table.insert(out.invites, { id = pid, from = nameOf(p.leader), expires = exp - now })
		end
	end
	return out
end

local function send(plr, notice)
	if plr and plr.Parent then
		Net.get("Party"):FireClient(plr, payload(plr, notice))
	end
end

local function sendAll(party, notice)
	for _, u in ipairs(party.members) do
		send(Players:GetPlayerByUserId(u), notice)
	end
end

local function removeFrom(party, userId)
	for i, u in ipairs(party.members) do
		if u == userId then
			table.remove(party.members, i)
			break
		end
	end
	partyOf[userId] = nil
	if #party.members == 0 then
		parties[party.id] = nil
		return
	end
	if party.leader == userId then
		party.leader = party.members[1]
	end
	if #party.members == 1 then
		-- a party of one is no party
		local last = party.members[1]
		partyOf[last] = nil
		parties[party.id] = nil
		send(Players:GetPlayerByUserId(last), "Your party ended.")
		return
	end
	sendAll(party)
end

-- The players a queue takes for `plr`: their party here (leader first) when they lead one, else
-- just them. A party member who isn't the leader can't queue: returns nil and why.
function PartyService.membersFor(plr)
	local id = partyOf[plr.UserId]
	local party = id and parties[id]
	if not party then
		return { plr }
	end
	if party.leader ~= plr.UserId then
		return nil, "Your party's leader queues for everyone."
	end
	local list = {}
	for _, u in ipairs(party.members) do
		local p = Players:GetPlayerByUserId(u)
		if p then
			table.insert(list, p)
		end
	end
	return list
end

function PartyService.partyOf(plr)
	local id = partyOf[plr.UserId]
	return id and parties[id] or nil
end

local ops = {}

function ops.get(plr)
	send(plr)
end

function ops.invite(plr, userId)
	local target = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if not target or target == plr then
		return send(plr, "Pick someone in this server.")
	end
	local id = partyOf[plr.UserId]
	local party = id and parties[id]
	if party and party.leader ~= plr.UserId then
		return send(plr, "Only your party's leader can invite.")
	end
	if partyOf[target.UserId] and partyOf[target.UserId] == id then
		return send(plr, target.DisplayName .. " is in your party already.")
	end
	if not party then
		nextId = nextId + 1
		party = { id = "P" .. nextId, leader = plr.UserId, members = { plr.UserId }, invites = {} }
		parties[party.id] = party
		partyOf[plr.UserId] = party.id
	end
	if #party.members >= P.Max then
		return send(plr, string.format("A party is %d at most.", P.Max))
	end
	party.invites[target.UserId] = os.clock() + P.InviteSeconds
	send(plr, "Invite sent to " .. target.DisplayName .. ".")
	send(target, plr.DisplayName .. " invited you to their party.")
end

function ops.accept(plr, partyId)
	local party = type(partyId) == "string" and parties[partyId]
	local exp = party and party.invites[plr.UserId]
	if not party or not exp or exp < os.clock() then
		return send(plr, "That invite has run out.")
	end
	if #party.members >= P.Max then
		return send(plr, "That party is full.")
	end
	local mine = partyOf[plr.UserId] and parties[partyOf[plr.UserId]]
	if mine then
		removeFrom(mine, plr.UserId)
	end
	party.invites[plr.UserId] = nil
	table.insert(party.members, plr.UserId)
	partyOf[plr.UserId] = party.id
	sendAll(party, plr.DisplayName .. " joined the party.")
end

function ops.decline(plr, partyId)
	local party = type(partyId) == "string" and parties[partyId]
	if party then
		party.invites[plr.UserId] = nil
		send(Players:GetPlayerByUserId(party.leader), plr.DisplayName .. " said no.")
	end
	send(plr)
end

function ops.leave(plr)
	local party = partyOf[plr.UserId] and parties[partyOf[plr.UserId]]
	if party then
		removeFrom(party, plr.UserId)
	end
	send(plr, party and "You left the party." or nil)
end

function ops.kick(plr, userId)
	local party = partyOf[plr.UserId] and parties[partyOf[plr.UserId]]
	local uid = tonumber(userId)
	if not party or party.leader ~= plr.UserId or not uid or uid == plr.UserId or partyOf[uid] ~= party.id then
		return
	end
	removeFrom(party, uid)
	send(Players:GetPlayerByUserId(uid), "You were removed from the party.")
	send(plr)
end

function ops.lead(plr, userId)
	local party = partyOf[plr.UserId] and parties[partyOf[plr.UserId]]
	local uid = tonumber(userId)
	if not party or party.leader ~= plr.UserId or not uid or partyOf[uid] ~= party.id then
		return
	end
	party.leader = uid
	-- the leader first in the list (they queue)
	for i, u in ipairs(party.members) do
		if u == uid then
			table.remove(party.members, i)
			table.insert(party.members, 1, uid)
			break
		end
	end
	sendAll(party, nameOf(uid) .. " leads the party now.")
end

function PartyService.init(r)
	reg = r
	Net.get("Party").OnServerEvent:Connect(function(plr, op, a)
		local fn = type(op) == "string" and ops[op]
		if fn then
			local ok, err = pcall(fn, plr, a)
			if not ok then
				warn("[SpikeRush] party " .. tostring(op) .. ": " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(plr)
		local party = partyOf[plr.UserId] and parties[partyOf[plr.UserId]]
		if party then
			removeFrom(party, plr.UserId)
		end
		for _, p in pairs(parties) do
			p.invites[plr.UserId] = nil
		end
	end)
	-- a joiner sees the parties' invites once they're in (none yet)
	Players.PlayerAdded:Connect(function(plr)
		task.delay(3, send, plr)
	end)
end

return PartyService
