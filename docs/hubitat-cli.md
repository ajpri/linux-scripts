# hubitat-cli.sh

[Back to script index](../README.md) · [Script source](../hubitat-cli.sh)

Single-file Bash client for Hubitat Maker API with an interactive menu and CLI
commands. Read device state and events, send device commands, manage hub modes
and HSM, read/set hub variables, list rooms, and configure event callbacks.
Supports local/cloud access, device labels or IDs, JSON answer files, and previews.

## Install and requirements

```bash
curl -fL -o hubitat-cli.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/hubitat-cli.sh
chmod +x hubitat-cli.sh
./hubitat-cli.sh
```

Run the script without arguments to start guided setup and open the menu.
The script is self-contained; no example env or Python files are required.

Requires Bash 4+, curl, jq, and standard Unix utilities.

```bash
# Debian / Ubuntu
sudo apt install curl jq

# Fedora
sudo dnf install curl jq
```

## Hub setup and configuration

1. On your hub, open **Apps → Add App / Add Built-In App → Maker API**.
2. Authorize the devices and hub variables you want to access. Enable local
   and/or cloud access as needed. Enable **Allow control of modes** and
   **Allow control of HSM** if you want those features; HSM must be installed.
3. Select **Update**, then find the generated endpoint URLs. Copy the base URL
   and access token from the appropriate local or cloud URL. Select **Done**.
4. Run the script without arguments. On the first interactive run, it displays
   setup instructions, prompts for the base URL and token, saves your settings,
   and opens the menu. The token is hidden while you type:

```bash
./hubitat-cli.sh                  # First run: guided setup, then the menu
./hubitat-cli.sh config           # Run setup again whenever needed
```

For a generated URL such as
`http://192.168.1.50/apps/api/123/devices?access_token=YOUR_TOKEN`, enter
`http://192.168.1.50/apps/api/123` as the base URL and `YOUR_TOKEN` separately.
The app ID is the Maker API instance ID, not a device ID.

Cloud bases look like
`https://cloud.hubitat.com/api/YOUR-HUB-ID/apps/123`. Copy the actual URL
from your Maker API app, since the hub ID and app ID are specific to your hub.

Configuration is stored with mode `600` at
`~/.config/hubitat-cli/config`, or `$XDG_CONFIG_HOME/hubitat-cli/config`.
Use an alternative env file if preferred:

```bash
./hubitat-cli.sh --env /path/to/hubitat.env config
./hubitat-cli.sh --env /path/to/hubitat.env devices
./hubitat-cli.sh --env /path/to/hubitat.env menu
```

An adjacent `.env` is used only when explicitly selected with `--env`. The
supported keys are `HUBITAT_BASE_URL`, `HUBITAT_ACCESS_TOKEN`, and
`HUBITAT_TIMEOUT` (default `30` seconds). Inherited environment variables work
too; file values take precedence. Configuration is literal `KEY=value` data.
Matching outer quotes are stripped; shell substitutions, escapes, `export`,
and inline comments are not interpreted. Comments must be on their own lines.

```bash
./hubitat-cli.sh config show          # Token is hidden
./hubitat-cli.sh config token         # Hidden prompt to replace token
./hubitat-cli.sh config url http://192.168.1.51/apps/api/123
```

## Menu and command-line examples

Global options (`--env FILE`, `--json`, `--dry-run`) go **before** the command.
Device labels and mode/variable names are exact and case-sensitive. An unlabeled
device uses its name. A numeric selector or `id:123` selects a device ID; use
`id:NUMBER` to disambiguate duplicate labels. `devices` lists the available IDs.

```bash
./hubitat-cli.sh devices
./hubitat-cli.sh --json devices
./hubitat-cli.sh devices --all
./hubitat-cli.sh device 'Living Room Light'
./hubitat-cli.sh events 'Living Room Light'
./hubitat-cli.sh commands 'Living Room Light'
./hubitat-cli.sh attribute 'Living Room Light' switch

./hubitat-cli.sh send 'Living Room Light' on
./hubitat-cli.sh send 'Living Room Light' setLevel 50 2
./hubitat-cli.sh send id:42 setColor '{"hue":10,"saturation":100,"level":50}'
./hubitat-cli.sh label id:42 'Bedroom Dimmer'

./hubitat-cli.sh modes
./hubitat-cli.sh mode 'Evening'
./hubitat-cli.sh mode id:2
./hubitat-cli.sh hsm
./hubitat-cli.sh hsm armAway

./hubitat-cli.sh variables
./hubitat-cli.sh variable 'Greeting'
./hubitat-cli.sh variable 'Greeting' 'Welcome home'
./hubitat-cli.sh rooms
./hubitat-cli.sh room 7

./hubitat-cli.sh post-url 'http://192.168.1.10:8080/events'
./hubitat-cli.sh post-url clear
./hubitat-cli.sh --dry-run send 'Living Room Light' setLevel 50
./hubitat-cli.sh help
```

Multiple command arguments are joined with commas into one parameter segment,
as required by Maker API. `setLevel 50 2` sends `setLevel/50,2`, with URL encoding
applied automatically. JSON is one argument. Commands and their arguments depend
on the device driver; inspect `commands` and the device detail page on your hub.
The script checks command availability; the hub validates argument counts/types.

HSM actions are `armAway`, `armHome`, `armNight`, `disarm`, `disarmAll`, `armAll`,
and `CancelAlerts`. These are commands; returned status names such as `armedAway`
are different. Match the capitalization shown above.

`post-url` configures where the **hub sends** event POSTs. It replaces this Maker
API instance's existing callback. The script does not start a webhook receiver.
The receiver must be reachable from the hub. Enable location event forwarding
in Maker API if you need mode, HSM, or variable event notifications. `clear`
removes the callback; there is no callback-read command because calling the
bare `/postURL` endpoint clears it.

## Answer files

```bash
./hubitat-cli.sh example > evening.local.json
# Edit the device/mode/variable names for your hub.
./hubitat-cli.sh preview evening.local.json
./hubitat-cli.sh submit evening.local.json
```

A file contains one JSON action object or a nonempty array of actions. Supported
schemas are below; replace the example values. Only include the actions you need.

```json
[
  {"action":"send","device":"Living Room Light","command":"on","args":[]},
  {"action":"send","device":"Living Room Light","command":"setLevel","args":[50,2]},
  {"action":"send","device":"id:42","command":"setColor","args":["{\"hex\":\"FF0400\"}"]},
  {"action":"mode","name":"Evening"},
  {"action":"hsm","value":"armHome"},
  {"action":"variable","name":"Greeting","value":"Welcome home"},
  {"action":"label","device":"id:42","value":"Bedroom Dimmer"},
  {"action":"post-url","value":"http://192.168.1.10:8080/events"}
]
```

`send.args` is optional and contains strings, numbers, or booleans. Pass JSON
parameters as JSON **strings**, as in the `setColor` example. Variable values
can be strings, numbers, or booleans. Unknown fields are rejected to catch typos.

Preview validates the entire file, resolves names and command availability, and
prints planned paths and query arguments. It performs reads but sends no writes.
`--dry-run submit FILE` has the same effect. Previews omit the access token but
contain action parameters, so treat previews containing lock codes as private.

Submit plans every action before starting writes, then executes in order. It
returns one JSON response per line (NDJSON), with progress on stderr. A failure
stops the batch. Actions already sent remain applied; batches are not atomic and
have no retry protection. Check hub state before resubmitting. All names resolve
against the hub state before the batch starts, including when a batch renames a
device. The menu previews batches and asks before sending them.

## Behavior and limitations

- Direct CLI writes and individual menu actions execute immediately. Commands
  can control locks, alarms, and other physical devices. Maker API permissions
  determine the available devices and features.
- Maker API uses GET requests for both reads and writes. The client never
  follows redirects or automatically retries requests. A timeout does not mean
  a command failed to execute. Read the device state before repeating a write.
- Successful command responses report what the API returned. Device state may
  update asynchronously; query it again to confirm the physical result. An empty
  successful write response is shown as `{"accepted":true}`.
- Most commands print JSON. `devices` prints a tab-separated table unless
  `--json` is supplied; `devices --all` always prints full JSON. Failures exit
  nonzero with diagnostics on stderr. Menu failures return to the menu.
- `--dry-run` still needs a working hub for label resolution, mode selection,
  and device command validation. It is not an offline simulator.
- HTTPS certificate verification stays enabled. Local HTTP is supported as
  provided by Hubitat. Access tokens are sent as API query parameters, read from
  a private temporary file to keep them out of curl's process arguments. Keep
  config files private and do not run with `bash -x`, which exposes secrets.
- Maker API may reject commands even when the device lists them. Parameters
  containing commas are subject to Maker API's own parameter splitting. Empty
  path values (including empty hub-variable values) are not supported. Room
  listing/detail is supported; room editing and driver changes are outside this
  client's command set.

## Documentation and verification

Implemented against Hubitat's official documentation, reviewed November 5, 2026:

- [Maker API endpoints and setup](https://docs2.hubitat.com/en/apps/maker-api)
- [HSM interface and command values](https://docs2.hubitat.com/en/developer/interfaces/hubitat-safety-monitor-interface)
- [App Object: local/cloud API URL formats](https://docs2.hubitat.com/en/developer/app/app-object)

The attribute reference's heading specifies
`/devices/ID/attribute/ATTRIBUTE`, while its example omits `/attribute`. This
client follows the documented heading. Confirm that endpoint with your hub's
generated URLs if your firmware behaves differently.

No live Hubitat endpoint was available during development. Bash syntax checks,
10 local mock-server tests, and an interactive first-run setup check passed.
These verified client behavior, not firmware/driver compatibility. Only the
self-contained shell script is distributed here.
