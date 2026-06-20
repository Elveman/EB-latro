# Buttlatro (Steamodded Port)

A [Balatro](https://www.playbalatro.com/) mod that adds
[Buttplug.io](https://buttplug.io/) support for vibration-based
[compatible devices](https://iostindex.com/?filter0ButtplugSupport=4).
While your hand is being scored, the connected device vibrates with
increasing intensity as each card, joker, and bonus effect triggers.

This is a port of the original
[Buttlatro](https://github.com/Fraggenard/Buttlatro) mod (written for
[Balamod](https://github.com/balamod/balamod)) to the
[Steamodded](https://github.com/Steamodded/smods) /
[Lovely](https://github.com/ethangreen-dev/lovely-injector) modding stack.

## Supported Platforms

- ✅ Windows (via bundled `pollnet.dll`)
- ✅ Linux / Steam Deck / Proton (via bundled `libpollnet.so`)

## Installation

### 1. Install the required mod loaders

Balatro on PC ships as a LÖVE2D game. You need two things to run this mod:

- [**Lovely Injector**](https://github.com/ethangreen-dev/lovely-injector/releases)
  (v0.9.0 or newer). Follow the install instructions in their README — on
  Windows this is a simple DLL drop into the game directory.
- [**Steamodded (SMODS)**](https://github.com/Steamodded/smods/releases)
  (1.0.0-beta or newer). Extract into your Balatro `Mods/` folder.

The recommended mod directory locations are:

| Platform | Path |
|---|---|
| Windows | `C:\Users\<username>\AppData\Roaming\Balatro\Mods\` |
| Linux (native LÖVE) | `~/.local/share/love/Mods/` |
| Linux / Deck (Proton) | `~/.local/share/Steam/steamapps/compatdata/2379780/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro/Mods/` |

### 2. Install this mod

Download the `.zip` of this repository (Code → Download ZIP) and extract
it so that you end up with:

```
Mods/
├── lovely/
├── smods/
└── Buttlatro-smods/
    ├── buttlatro-smods.json
    ├── main.lua
    ├── config.lua
    ├── lib/
    ├── lovely/
    └── native/
```

Do **not** extract the zip's contents directly into `Mods/` — the inner
folder name `Buttlatro-smods` must be preserved.

### 3. Set up Intiface Central

This mod talks to your device through Intiface. Download
[Intiface Central](https://intiface.com/central/) (or
[Intiface Engine CLI](https://github.com/intiface/intiface-engine) if you
prefer the command line) and:

1. Start Intiface Central.
2. Enable the server and note the listening port (default: `12345`).
3. Pair / connect your device in the Intiface UI.

### 4. Launch Balatro

Start the game normally. On the main menu, open **Mods** and confirm
**Buttlatro-smods** is listed and enabled. If Intiface was running on the
default port, the mod will report "Connected to Intiface server" on its
Config tab on the first launch.

## Usage

### In-game

Nothing to configure — vibration tracks your scored hand automatically.
Intensity starts at whatever the **Start Intensity** slider is set to, and
grows by the **Trigger Increment** value for every scoring event.

### Config tab (Mods → Buttlatro-smods → Config)

| Slider | Default | Range | Effect |
|---|---|---|---|
| Start Intensity (%) | 5 | 0 – 10 | Vibration level at the very beginning of scoring |
| Trigger Increment (%) | 6 | 0 – 10 | Amount added per card / joker / bonus trigger |

Two test buttons (`Start Test Vibration` / `Stop Test Vibration`) are also
provided so you can confirm your device responds before playing for real.

Changes are saved automatically when you leave the Mods menu — stored in
`Settings/Buttlatro-smods.jkr` next to your other save data.

## Troubleshooting

**"Intiface server not running at ws://127.0.0.1:12345"**
Intiface Central isn't running, isn't listening, or is on a non-default
port. Start it and keep the server toggle on.

**Device doesn't respond during scoring**
Confirm the test button actually vibrates the device. If it does but
scoring doesn't, other audio mods may be interfering with the `play_sound`
wrapper. Open an issue with details.

**Crash on load**
Make sure Steamodded and Lovely are both installed and up to date. This
mod relies on `SMODS.current_mod.config`, `create_slider`, and Lovely's
`patches.module` / `patches.pattern` features — older loaders will error.

## Credits

- [**Fraggenard**](https://github.com/Fraggenard/Buttlatro) — authored the
  original Buttlatro for Balamod. Everything fun about the idea originates
  from that work; this port just translates it to a different loader.
- [**abbiwyn**](https://github.com/nonpolynomial-libraries) — Lua client
  for the Buttplug.io protocol, used under the MIT License.
- **probable-basilisk** — [pollnet](https://github.com/probable-basilisk/pollnet)
  (WebSocket / TCP library) and its LuaJIT FFI bindings, used under the MIT
  License. The bundled `pollnet.dll` (Windows) and `libpollnet.so` (Linux)
  are Rust binaries from the same project.
- **rxi** — [json.lua](https://github.com/rxi/json), used under the MIT
  License.
- The [**Buttplug.io**](https://buttplug.io/) project (metafetish) for
  designing and documenting the open intimate-device protocol this mod
  speaks.
- The [**Lovely**](https://github.com/ethangreen-dev/lovely-injector) and
  [**Steamodded**](https://github.com/Steamodded/smods) teams for the
  modern Balatro modding stack that made this port possible.

## License

MIT — see [LICENSE](./LICENSE).

The LICENSE file covers the original codebase by Fraggenard and this port
by Elveman. The vendored third-party libraries under `lib/` and `native/`
retain their own MIT licenses as documented in their headers.

## AI Assistance Disclaimer

Portions of this port were developed with the assistance of AI coding
tools. All changes were reviewed, tested, and finalized by the author.
