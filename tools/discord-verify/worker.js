// Volleyball Rush Discord verification: a Cloudflare Worker that answers the /discordverify slash command
// (named that, not /verify, so it isn't mixed up with other bots' verify commands).
//
// The game gives each player a code (Config.Discord) and saves "code_<CODE>" -> { userId, name }
// in the DiscordVerify data store. Here, /discordverify CODE checks that entry through Roblox Open Cloud,
// writes "done_<CODE>" (the game's Verify button reads it and pays the reward) and
// "discord_<Discord user id>" (one Discord account verifies one Roblox account), and gives the
// Verified role if VERIFIED_ROLE_ID is set. Setup: README.md next to this file.
//
// Variables (Worker > Settings > Variables and Secrets):
//   DISCORD_PUBLIC_KEY, DISCORD_APP_ID, DISCORD_GUILD_ID, DISCORD_BOT_TOKEN (secret),
//   ROBLOX_API_KEY (secret), UNIVERSE_ID, SETUP_SECRET (secret), VERIFIED_ROLE_ID (optional),
//   DATASTORE (optional, default DiscordVerify)

const CODE_RE = /^[A-HJ-NP-Z2-9]{7}$/;

export default {
	async fetch(request, env, ctx) {
		const url = new URL(request.url);
		if (request.method === "GET" && url.pathname === "/register") {
			return register(url, env);
		}
		if (request.method !== "POST") {
			return new Response("Volleyball Rush verification bot is running.", { status: 200 });
		}
		const body = await request.text();
		const ok = await verifySignature(request, body, env.DISCORD_PUBLIC_KEY);
		if (!ok) {
			return new Response("bad signature", { status: 401 });
		}
		const interaction = JSON.parse(body);
		if (interaction.type === 1) {
			return json({ type: 1 }); // Discord's PING when the endpoint is saved
		}
		if (interaction.type === 2 && interaction.data && interaction.data.name === "discordverify") {
			// answer "thinking..." (only they see it) now, and the result once the lookups finish
			ctx.waitUntil(
				handleVerify(interaction, env).then(
					(text) => followUp(interaction, env, text),
					(err) => followUp(interaction, env, "Something went wrong, try again in a minute. (" + String(err && err.message || err).slice(0, 150) + ")")
				)
			);
			return json({ type: 5, data: { flags: 64 } });
		}
		return json({ type: 4, data: { content: "Unknown command.", flags: 64 } });
	},
};

async function handleVerify(interaction, env) {
	const user = interaction.member && interaction.member.user;
	if (!user) {
		return "Use /discordverify in the Volleyball Rush server, not in DMs.";
	}
	const opt = (interaction.data.options || []).find((o) => o.name === "code");
	const code = String(opt ? opt.value : "").trim().toUpperCase().replace(/^CODE\s*:?/, "").replace(/[^A-Z0-9]/g, "");
	if (!CODE_RE.test(code)) {
		return "That isn't a code. Open **Codes** in Volleyball Rush and copy yours (7 letters and numbers).";
	}
	const owner = await getEntry(env, "code_" + code);
	if (!owner || !owner.userId) {
		return "That code doesn't exist. Open **Codes** in Volleyball Rush and copy yours.";
	}
	const done = await getEntry(env, "done_" + code);
	if (done) {
		return String(done.discordId) === String(user.id)
			? "You're already verified as **" + owner.name + "**. In Volleyball Rush, open **Codes** and click **Verify**."
			: "That code was already used by another Discord account.";
	}
	const linked = await getEntry(env, "discord_" + user.id);
	if (linked && String(linked.userId) !== String(owner.userId)) {
		return "Your Discord account already verified **" + linked.name + "**. Each Discord account can verify one Roblox account.";
	}
	const at = Math.floor(Date.now() / 1000);
	await setEntry(env, "done_" + code, { userId: owner.userId, discordId: user.id, at });
	await setEntry(env, "discord_" + user.id, { userId: owner.userId, name: owner.name, at });
	let roleNote = "";
	if (env.VERIFIED_ROLE_ID) {
		const r = await fetch(
			"https://discord.com/api/v10/guilds/" + env.DISCORD_GUILD_ID + "/members/" + user.id + "/roles/" + env.VERIFIED_ROLE_ID,
			{ method: "PUT", headers: { Authorization: "Bot " + env.DISCORD_BOT_TOKEN, "X-Audit-Log-Reason": "Volleyball Rush verify" } }
		);
		if (!r.ok) {
			roleNote = "\n(I couldn't give you the Verified role. A mod can sort it out.)";
		}
	}
	return "Verified as **" + owner.name + "**! Go back to Volleyball Rush, open **Codes** and click **Verify** for your reward." + roleNote;
}

// ------------------------------------------------------------------------------------------
// Roblox Open Cloud data stores (v2), the game's DiscordVerify store, scope "global"
// ------------------------------------------------------------------------------------------

function entriesUrl(env) {
	const ds = encodeURIComponent(env.DATASTORE || "DiscordVerify");
	return "https://apis.roblox.com/cloud/v2/universes/" + env.UNIVERSE_ID + "/data-stores/" + ds + "/scopes/global/entries";
}

async function getEntry(env, key) {
	const r = await fetch(entriesUrl(env) + "/" + encodeURIComponent(key), { headers: { "x-api-key": env.ROBLOX_API_KEY } });
	if (r.status === 404) {
		return null;
	}
	if (!r.ok) {
		throw new Error("Roblox read " + r.status + ": " + (await r.text()).slice(0, 120));
	}
	const data = await r.json();
	let v = data.value;
	if (typeof v === "string") {
		try {
			v = JSON.parse(v);
		} catch (e) {}
	}
	return v;
}

async function setEntry(env, key, value) {
	const headers = { "x-api-key": env.ROBLOX_API_KEY, "content-type": "application/json" };
	const body = JSON.stringify({ value });
	let r = await fetch(entriesUrl(env) + "?id=" + encodeURIComponent(key), { method: "POST", headers, body });
	if (r.status === 409) {
		r = await fetch(entriesUrl(env) + "/" + encodeURIComponent(key), { method: "PATCH", headers, body });
	}
	if (!r.ok) {
		throw new Error("Roblox write " + r.status + ": " + (await r.text()).slice(0, 120));
	}
}

// ------------------------------------------------------------------------------------------
// Discord
// ------------------------------------------------------------------------------------------

async function followUp(interaction, env, content) {
	await fetch("https://discord.com/api/v10/webhooks/" + env.DISCORD_APP_ID + "/" + interaction.token + "/messages/@original", {
		method: "PATCH",
		headers: { "content-type": "application/json" },
		body: JSON.stringify({ content }),
	});
}

// Visit /register?secret=SETUP_SECRET once (and after changing the command) to add /discordverify to the server (it replaces the old /verify).
async function register(url, env) {
	if (!env.SETUP_SECRET || url.searchParams.get("secret") !== env.SETUP_SECRET) {
		return new Response("Wrong or missing secret.", { status: 403 });
	}
	const r = await fetch("https://discord.com/api/v10/applications/" + env.DISCORD_APP_ID + "/guilds/" + env.DISCORD_GUILD_ID + "/commands", {
		method: "PUT",
		headers: { Authorization: "Bot " + env.DISCORD_BOT_TOKEN, "content-type": "application/json" },
		body: JSON.stringify([
			{
				name: "discordverify",
				description: "Link your Roblox account and get your Volleyball Rush reward",
				options: [{ type: 3, name: "code", description: "Your code from the Codes window in Volleyball Rush", required: true }],
			},
		]),
	});
	const text = await r.text();
	return new Response(r.ok ? "/discordverify is registered. You can close this tab." : "Discord said " + r.status + ": " + text, { status: r.ok ? 200 : 500 });
}

async function verifySignature(request, body, publicKey) {
	const sig = request.headers.get("x-signature-ed25519");
	const ts = request.headers.get("x-signature-timestamp");
	if (!sig || !ts || !publicKey) {
		return false;
	}
	const data = new TextEncoder().encode(ts + body);
	let key;
	try {
		key = await crypto.subtle.importKey("raw", hex(publicKey), { name: "Ed25519" }, false, ["verify"]);
		return await crypto.subtle.verify({ name: "Ed25519" }, key, hex(sig), data);
	} catch (e) {
		key = await crypto.subtle.importKey("raw", hex(publicKey), { name: "NODE-ED25519", namedCurve: "NODE-ED25519" }, false, ["verify"]);
		return await crypto.subtle.verify("NODE-ED25519", key, hex(sig), data);
	}
}

function hex(s) {
	const out = new Uint8Array(s.length / 2);
	for (let i = 0; i < out.length; i++) {
		out[i] = parseInt(s.substr(i * 2, 2), 16);
	}
	return out;
}

function json(obj) {
	return new Response(JSON.stringify(obj), { headers: { "content-type": "application/json" } });
}
