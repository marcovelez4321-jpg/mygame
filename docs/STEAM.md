# Steam co-op (invites)

Co-op through Steam, added 2026-10-17. The host makes a friends-only Steam lobby and invites friends from Steam. The game connects over Steam's own relays, so there are no ports to forward and no IP addresses. Hosting and joining by IP or LAN still work as before.

The code is in place: `scripts/net/steam_coop.gd` (`SteamCoop`, a child of the `Network` autoload), the **Host on Steam** and **Invite friends** buttons in the pause menu's Co-op panel, and pings measured by the game itself (Steam's connection has no ENet stats). It only needs the GodotSteam extension installed. Without it, the Co-op panel says "Steam invites are off: GodotSteam isn't installed" and everything else works as before.

## 1. Install GodotSteam (one time)

1. Get the **GodotSteam GDExtension** for Godot 4.x: version **4.23.1** or newer, built on Steamworks SDK 1.65. Download it from the Godot Asset Store (https://store.godotengine.org/asset/godotsteam/godotsteam-gdextension/), or from inside the editor's AssetLib tab (search "GodotSteam GDExtension").
   - It's the standard GodotSteam, not the Server one. Since GodotSteam 4.17 it includes `SteamMultiplayerPeer`, which the game uses.
2. Unzip it so you have `addons/godotsteam/` in the project (with its `.gdextension` file and the `win64` folder holding `steam_api64.dll`).
3. Restart the Godot editor.

### The Steam edition of Godot (important)

Godot from Steam ships its own, older `steam_api64.dll` in its install folder. Windows loads that one first, so GodotSteam fails in the editor with "Error 127: The specified procedure could not be found". Fixed 2026-10-18: GodotSteam's newer `steam_api64.dll` (10.83, Steamworks SDK 1.65) was copied over Godot's (10.24) in `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\`. The original is kept beside it as `steam_api64.dll.godot-original.bak`. Newer Steam DLLs work with older programs, so Godot itself is fine.

- **If Steam updates Godot and puts the old DLL back:** close Godot and copy `addons/godotsteam/win64/steam_api64.dll` over Godot's again.
- **To undo:** delete Godot's `steam_api64.dll` and rename the `.bak` back.
- **Exported games aren't affected:** they load GodotSteam's own DLL.

## 2. App ID

- Until the game has its own Steam App ID, it uses **480** (Spacewar, Valve's free test app). It's set in `SteamCoop.APP_ID` and in `steam_appid.txt` at the project root (which Steam reads when you run from the editor).
- With a real App ID from Steamworks ($100 per game), change both. When shipping on Steam, Valve says not to include `steam_appid.txt`.

## 3. Test it

Steam won't let one account be in a game twice, so you need **two Steam accounts on two PCs** (a friend, or a second PC with a second account). The accounts must be Steam friends.

1. Both PCs: Steam open and logged in, run the game.
2. Host: pause menu, Co-op, **Host on Steam**. The status shows "Hosting on Steam -- press Invite friends".
3. Host: **Invite friends**. Steam's overlay opens its invite list; pick the friend.
4. Friend: accept the invite (the Steam overlay or chat). Or right-click the host in the Steam friends list and choose **Join Game**. Their game joins the lobby, connects to the host, loads the host's world and spawns in, the same as joining by IP.
5. A friend whose game isn't running can still accept. Steam launches it with `+connect_lobby <id>` and it joins once it's loaded.

The Steam overlay needs to work for the invite list: run the game with Steam open, and if the overlay doesn't show, enable it in Steam's settings (In-Game).

## 4. Exporting

The export needs GodotSteam's files next to the `.exe`: `steam_api64.dll`, and the GodotSteam GDExtension DLL, which Godot's export copies itself. For testing builds outside Steam, also put `steam_appid.txt` (480) next to the `.exe`.

## How it fits together

- **Host on Steam:** `Steam.createLobby` (friends-only, 4 places), then on `lobby_created` a `SteamMultiplayerPeer.create_host(0)`, and the lobby's rich presence `connect` is set to `+connect_lobby <id>`.
- **Invite friends:** `Steam.activateGameOverlayInviteDialog(lobby)`.
- **Joining:** `join_requested` (invite accepted / Join Game), `join_game_requested` (rich presence), or `+connect_lobby` on the command line all lead to `Steam.joinLobby`. Then `lobby_joined` leads to `SteamMultiplayerPeer.create_client(lobby owner's Steam ID, 0)`.
- **From there:** `Network.use_steam_peer` hands the connection to the usual co-op flow (the host's scene, bodies, play). Leaving, the host going away, or a failed connection all leave the lobby.

## Not done yet

- Installed and checked on the dev PC (2026-10-18): GodotSteam 4.23.1 loads, SteamMultiplayerPeer is there, and Steam starts with app 480. Not yet tested between two accounts.
- If the host leaves, everyone's sent home (no host migration), the same as IP co-op.
- No lobby browser: friends join by invite or Join Game only, which is what friends-only lobbies are for.