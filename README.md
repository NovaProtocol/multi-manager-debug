# Multi Manager Debug

An operator-only debug channel for a Factorio server. It adds one command, `/debug`, and a
remote interface for an external program. It does not open a network listener, does not ship a host
process, and does not need a companion service.

## Command

```text
/debug help
/debug ping
/debug tools
/debug probe <operation> [json]
/debug query <tool> [json]
/debug <operation> [json]        shorthand for /debug probe
```

The command is RCON-only. A player invoking it is refused; use the server console or an
external RCON client.

## Probe operations

World and entity inspection, player/force queries, controlled actions, blueprint and
construction-plan operations:

- `world`, `observe`, `inspect_entity`, `prototypes`, `recipes`, `research`, `trains`
- `agent_status`, `move_to`, `mine_entity`, `craft`, `action_status`, `cancel_action`
- `place_entity`, `entity_inventory`, `transfer_items`, `configure_entity`, `shoot_at`
- `blueprint_catalog`, `blueprint_import`, `blueprint_export`, `blueprint_capture`,
  `blueprint_inspect`, `find_sites`, `plan_create`, `plan_inspect`, `plan_preview`,
  `plan_apply`
- `ping`, `help`

## Query tools

Monitoring, player, world, behavior and file tools:

- Server/performance/memory/entity metrics, recent logs, player events, chat and command history
- Player, force, surface, research and production queries
- Logistics, item and inventory queries
- Behavior recorder status, tracking, history and CSV/JSON export
- `file_read`, `file_write`, `file_append`, `file_delete`, `file_list`
- Console command execution, console command list, game speed, tick pause, save, broadcast

`execute_shell` reports that host shell execution is unavailable: this mod has no host-side process and the Factorio Lua sandbox has no process API.

## Install and operate

Install the mod only on a server you control and only for debugging. It exposes powerful
game-state and file operations through RCON. Keep the RCON port on loopback and use a strong
password.

The mod writes its own small config and diagnostic files under
`script-output/multi-manager-debug/`.

## Release

```sh
python3 scripts/release.py                 # build only
python3 scripts/release.py --tag v0.1.3    # GitHub and mod portal
```

Publishing requires `GITHUB_TOKEN` and `MOD_PORTAL_KEY`. The GitHub release is the manager's
fallback; the portal release is for clients.
