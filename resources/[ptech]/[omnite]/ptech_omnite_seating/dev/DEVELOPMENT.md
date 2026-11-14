# Development notes

> This document describes the original 0.0.1 tooling. For the current 0.2.0-dev dependencies, DB placement, ownership, patient beds, and installation, see README.md. The framework-independent installation described in older versions is no longer applicable.

## Resource layout

```text
ptech_omnite_seating/
├── config.lua                             # Target, seating, styles, chair models, and fixed seats
├── install/
│   └── items.lua                          # ox_inventory item entry
├── main/
│   ├── client/                            # Seating and placement clients
│   ├── nui/                               # Clipboard copy panel
│   └── server/                            # Seat ownership and DB placement
├── dev/
│   ├── tests/                             # Lua syntax and server behavior checks
│   ├── README.md                          # Current installation and usage
│   └── DEVELOPMENT.md                     # Original tooling notes
├── fxmanifest.lua
└── package.json                           # Test command and development dependencies
```

## Current behavior and assumptions

- `ox_target` provides the sit interaction for registered chair models and fixed MLO seats.
- A seat is reserved on the server before the sitting scenario starts. Each seat has one owner at a time.
- The server checks that a player is near the requested seat. It releases the reservation when the player stands up or disconnects.
- The stand key defaults to `X`. The style key defaults to `G` and cycles through the configured styles while seated.
- Sitting blocks movement and attacks while leaving camera, voice, phone, and inventory controls available.
- Style scenarios can have independent position and heading offsets. Chair models and fixed seats can restrict which style IDs they support.
- Fixed seat IDs must be unique. A model seat is keyed by its model hash and world coordinates.

## Values needed from the target server

1. **MLO seats:** add coordinate entries to `Config.FixedSeats` for chairs that are not exposed as separate objects.
2. **Custom chair props:** add model names and tune their offsets in `Config.ChairModels`.
3. **Seat alignment:** check the sitting position, facing direction, and exit movement for each target model, MLO, and style.
4. **Style fit:** remove styles that do not fit a particular chair by setting its `styles` list.
5. **Resource order:** start `ox_target` before `ptech_omnite_seating`.

These values can remain provisional while the resource structure and interaction flow are organized.

## Coordinate recorder

The ID is a unique label for the fixed seat, such as `pillbox_waiting_01`. It is used in configuration and lock state; it is not an object/model ID. Both commands accept an optional ID. If omitted, the resource generates an ID such as `seat_123456`; rename it to a location-based name when convenient.

The quick recorder captures the current player position and heading as one `Config.FixedSeats` entry. The result opens a copy panel. Click **コピー** to put the line on the clipboard, then paste it into `Config.FixedSeats`. If clipboard access is blocked, the line remains selectable in the panel.

1. Set `Config.SeatRecorder.enabled = true` in the resource-root `config.lua` and restart the resource.
2. Add these ACE permissions for administrators in `server.cfg`:

   ```cfg
   add_ace group.admin command.omnite_seatrecord allow
   add_ace group.admin command.omnite_seatsetup allow
   add_ace group.admin command.omnite_seatdebug allow
   add_ace group.admin command.omnite_seatghost allow
   ```

3. Stand at the desired position and face the direction players should face. Run `/omnite_seatrecord [id]`; omit the ID to generate one automatically.
4. Copy the generated line from the panel into `Config.FixedSeats`.

## Interactive seat setup

Run `/omnite_seatsetup [id]` while standing at the approximate seat location and facing the desired direction. The current style starts playing as a preview. The ID can be omitted and renamed in the generated line later.

| Input | Adjustment |
| --- | --- |
| Arrow keys | Move forward/back/left/right |
| `E` / `Q` | Raise/lower the seat point |
| `C` / `Z` | Turn the facing direction |
| `G` | Preview the next sitting style |
| `Shift` + adjustment key | Use the coarser step size |
| `Enter` | Open the generated fixed-seat line for clipboard copy |
| `Esc` | Cancel setup |

Movement uses `Config.SeatRecorder.fineStep`; holding Shift uses `coarseStep`. Rotation uses `headingStep`. When setup completes, copy the generated line into `Config.FixedSeats`. Seat setup is disabled by default and ACE-restricted when enabled.

## Seat debug mode

Run `/omnite_seatdebug` to toggle the ACE-restricted marker view. It displays configured chair-model objects and fixed MLO seats within `Config.SeatDebug.markerDistance`. Labels show a model name or fixed-seat ID and whether the seat lock is occupied.

Run `/omnite_seatghost` to toggle the separate ACE-restricted object pass-through mode. It temporarily disables collision with nearby object entities, including unregistered chair props, so an administrator can move through them while recording or adjusting a seat. Nearby decorative props are also pass-through while this mode is on. Run the command again to turn it off. The mode is disabled by default and cannot be toggled while sitting or adjusting a seat.

## Deferred implementation

- Verify the registered GTA chair models and their default offsets in the live server.
- Confirm the three default sitting scenarios, style offsets, and key bindings in-game.
- Add confirmed MLO seat coordinates and adjust model-specific offsets after in-game checks.
- Run multi-player checks for seat contention, disconnect cleanup, and standing up.
