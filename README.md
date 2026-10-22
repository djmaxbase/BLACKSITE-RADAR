# BLACKSITE RADAR — Complete Edition

CC:Tweaked + Create: Radars tactical radar dashboard and wireless pocket companion.

## Files
- `radar.lua`: Main large-monitor radar (6.0).
- `mobile_server.lua`: Read-only wireless Rednet bridge on base computer.
- `mobile.lua`: Wireless Advanced Pocket Computer client.
- `blacksite_start.lua`: Starts radar and mobile bridge together.

## Base computer setup

Required: wired access to Create: Radars monitor peripheral, a large advanced monitor, and a **wireless modem**.

Download the latest files on the base computer:

```sh
wget https://raw.githubusercontent.com/djmaxbase/BLACKSITE-RADAR/main/radar.lua radar.lua
wget https://raw.githubusercontent.com/djmaxbase/BLACKSITE-RADAR/main/mobile_server.lua mobile_server.lua
wget https://raw.githubusercontent.com/djmaxbase/BLACKSITE-RADAR/main/blacksite_start.lua blacksite_start.lua
blacksite_start.lua
```

## Pocket computer setup

Required: Advanced Pocket Computer with wireless modem.

```sh
wget https://raw.githubusercontent.com/djmaxbase/BLACKSITE-RADAR/main/mobile.lua mobile.lua
mobile.lua
```

The pocket client discovers the base via Rednet, refreshes automatically, and offers radar, security and player intelligence views. Use number keys 1–3 to switch pages.

## Troubleshooting
- `Not Found`: Check exact file names and branch `main`.
- `No wireless modem`: Run `lua` then `for _,s in ipairs(peripheral.getNames()) do if peripheral.hasType(s,"modem") then print(s,peripheral.wrap(s).isWireless()) end end`.
- No contacts: Check that `create_radar:monitor_0` is connected and returns player tracks with `getTracks()`.
- No mobile link: Both computers must be on, in radio range, and have working wireless modems.
- A username is shown only if available from radar data or stored local name mappings.

## Notes
Security and intelligence data come from local radar configuration. Do not assume that a remote player can be detected outside the radar's actual tracking range. This package has not been tested on every modpack/server.