# Discord verification bot

Players open **Codes** in Spike Rush and copy their own 7-character code. In the Discord they type `/verify CODE`. This bot checks the code and marks it done. Back in the game they click **Verify** and get `Config.Discord.Reward`, which includes the Community Squad card.

How it works:

1. The game saves `code_<CODE> = { userId, name }` in the `DiscordVerify` data store.
2. This Worker reads that entry through Roblox Open Cloud. It writes `done_<CODE>` and `discord_<Discord user id>`, so each Discord account can verify only one Roblox account.
3. The game's Verify button reads `done_<CODE>`.

The bot is `worker.js`, a single file with no installs. It runs free on Cloudflare Workers, all the time, without your PC.

## Setup (about 15 minutes, once)

### 1. Roblox: an Open Cloud API key
1. Go to Creator Hub > **Open Cloud** > **API Keys** > **Create API Key**. Name it "Discord verify".
2. Under **Access Permissions**, add **Data Stores** (or "universe-datastores"), pick **Volleyball Spike: Rush**, and tick:
   - read entry
   - create entry
   - update entry
3. Under **Security**, set the allowed IP addresses to `0.0.0.0/0`. Cloudflare's addresses change, so it can't be narrower.
4. Click **Save & Generate Key** and copy the key. You only see it once.

### 2. Discord: the bot
1. Go to https://discord.com/developers/applications > **New Application**. Name it "Spike Rush".
2. On **General Information**, copy the **Application ID** and the **Public Key**.
3. On **Bot**, click **Reset Token** and copy the token.
4. On **OAuth2** > **URL Generator**:
   - Under scopes, tick **bot** and **applications.commands**.
   - Under bot permissions, tick **Manage Roles**.
   - Open the URL it makes and add the bot to your server.
5. Get the server ID: in Discord, open Settings > Advanced > Developer Mode. Then right-click your server > **Copy Server ID**.
6. (Optional) Add a role called "Verified" for verified players.
   - In Server Settings > Roles, drag the bot's role **above** "Verified".
   - Right-click "Verified" > **Copy Role ID**.

### 3. Cloudflare: the Worker
1. Sign up at https://dash.cloudflare.com (free).
2. Go to **Workers & Pages** > **Create** > **Create Worker**. Name it `spike-rush-verify` > **Deploy**.
3. Click **Edit code**. Delete what's there, paste all of `worker.js`, then **Deploy**.
4. Go to the Worker's **Settings** > **Variables and Secrets** and add each of these. Use **Secret** for the ones marked secret.

   | Name | Value |
   |---|---|
   | `DISCORD_PUBLIC_KEY` | the Public Key (step 2.2) |
   | `DISCORD_APP_ID` | the Application ID (step 2.2) |
   | `DISCORD_GUILD_ID` | the server ID (step 2.5) |
   | `DISCORD_BOT_TOKEN` (secret) | the bot token (step 2.3) |
   | `ROBLOX_API_KEY` (secret) | the Open Cloud key (step 1.4) |
   | `UNIVERSE_ID` | `10768040963` |
   | `SETUP_SECRET` (secret) | any made-up password |
   | `VERIFIED_ROLE_ID` | the role ID (step 2.6), or leave it out |

5. Copy the Worker's URL, something like `https://spike-rush-verify.<you>.workers.dev`.

### 4. Connect them
1. In the Discord Developer Portal > **General Information**, paste the Worker URL into **Interactions Endpoint URL** and save. Discord checks it right away; if it won't save, the Public Key variable is wrong.
2. Open `https://spike-rush-verify.<you>.workers.dev/register?secret=<your SETUP_SECRET>` in a browser. It should say "/verify is registered".
3. In Discord, `/verify` now shows up in your server.

### 5. The game page's Community link
Roblox shows Discord by name, with the invite, only to players it allows. Everyone else sees the BedWars wording: "Open the Spike Rush game page and join from the Community link". So put the invite on the game page too:

1. Go to Creator Hub > your experience > **Configure** > **Social Links** (or **Links**).
2. Add a **Discord** link with your invite (`https://discord.gg/T6N3uw5ghA`), titled **Community Server**.

Roblox shows that link only to players allowed to see it.

## Try it
1. In Spike Rush, open **Codes** and copy your code.
2. In Discord, type `/verify` and paste the code. The bot answers "Verified as ..." (only you see it).
3. In the game, click **Verify**. You get the reward and the Community Squad card.

If the bot answers "Something went wrong (Roblox read 401/403 ...)", the API key's permissions or experience are wrong (step 1).
