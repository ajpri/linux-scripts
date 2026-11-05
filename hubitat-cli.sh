#!/usr/bin/env bash
# Hubitat Maker API client. Requires Bash 4+, curl, jq, and Unix utilities.
set -uo pipefail
umask 077

ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hubitat-cli/config"
WORK_DIR=''
JSON_OUTPUT=0
DRY_RUN=0
cleanup() { [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'Error: %s\n' "$*" >&2; return 1; }

usage() {
    cat <<'HELP'
Usage: hubitat-cli.sh [--env FILE] [--json] [--dry-run] COMMAND [ARGS]
  menu                              Interactive menu (default)
  config                            Configure Maker API base URL and token
  config show                       Show settings with token hidden
  config url [BASE_URL]              Change base URL
  config token                      Change token using a hidden prompt
  devices [--all]                    List authorized devices (or full details)
  device DEVICE                     Read device details/current state
  events DEVICE                     Read recent device events
  commands DEVICE                   List device commands
  attribute DEVICE ATTRIBUTE         Read one attribute
  send DEVICE COMMAND [ARG ...]      Send a device command
  label DEVICE NEW_LABEL             Change device display label
  modes                             List modes, including current mode
  mode MODE                         Set mode by exact name or id:NUMBER
  hsm [ACTION]                      Read HSM status or send an action
  variables                         List authorized hub variables
  variable NAME [VALUE]              Read or set a hub variable
  rooms                             List rooms
  room ID                           Read room details
  post-url URL|clear                 Set/clear the event callback URL
  example                           Print a JSON answer-file example
  preview FILE                      Validate/resolve all answer-file actions
  submit FILE                       Validate, then send answer-file actions
  help                              Show this help

DEVICE is an exact, case-sensitive label (name if unlabeled), id:NUMBER,
or a numeric ID. Duplicate labels require an ID. Quote names with spaces.
Multiple command arguments become one comma-separated parameter segment.
For JSON parameters, pass the entire JSON object as one quoted argument.

HSM actions: armAway armHome armNight disarm disarmAll armAll CancelAlerts
--json gives machine-readable JSON; --dry-run prints write paths without
sending them, but still reads the hub to resolve names/validate commands.
Options must precede COMMAND. CLI writes run immediately without prompts.

First interactive run without arguments guides you through setup, then opens
the menu. Later runs reuse your saved settings. Run config to change them.

Private configuration: ~/.config/hubitat-cli/config (XDG_CONFIG_HOME honored).
Use --env FILE for a literal KEY=value file, never executed as shell code.
Required keys: HUBITAT_BASE_URL, HUBITAT_ACCESS_TOKEN. Optional:
HUBITAT_TIMEOUT=30. File values override inherited environment variables.
Local base: http://192.168.1.50/apps/api/123
Cloud base: https://cloud.hubitat.com/api/HUB_ID/apps/123
Copy the base from your Maker API app; omit /devices and ?access_token=...
No retries are made: a timed-out command may already have taken effect.
HELP
}

read_config() {
    local line key value number=0
    [[ -r "$ENV_FILE" ]] || { fail "Cannot read configuration: $ENV_FILE"; return 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        number=$((number + 1)); line=${line%$'\r'}
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" =~ ^([A-Z_][A-Z_0-9]*)=(.*)$ ]] || { fail "Expected KEY=value on config line $number"; return 1; }
        key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}
        if [[ ${#value} -ge 2 ]]; then
            case "$value" in \"*\"|\'*\') value=${value:1:${#value}-2} ;; esac
        fi
        case "$key" in
            HUBITAT_BASE_URL|HUBITAT_ACCESS_TOKEN|HUBITAT_TIMEOUT) printf -v "$key" '%s' "$value" ;;
            *) fail "Unknown config key on line $number"; return 1 ;;
        esac
    done < "$ENV_FILE"
}

defaults() {
    HUBITAT_BASE_URL=${HUBITAT_BASE_URL:-}
    HUBITAT_BASE_URL=${HUBITAT_BASE_URL%/}
    HUBITAT_ACCESS_TOKEN=${HUBITAT_ACCESS_TOKEN:-}
    HUBITAT_TIMEOUT=${HUBITAT_TIMEOUT:-30}
}

validate_config() {
    # Reject credentials, queries, fragments, and characters unsafe in a URL.
    local pattern='^https?://[^/?#[:space:]@"\\]+/(apps/api/[0-9]+|api/[A-Za-z0-9-]+/apps/[0-9]+)$'
    [[ "$HUBITAT_BASE_URL" =~ $pattern ]] || { fail 'Use a complete Maker API base URL ending in /apps/api/APP_ID (local) or /api/HUB_ID/apps/APP_ID (cloud), without a query'; return 1; }
    [[ -n "$HUBITAT_ACCESS_TOKEN" && "$HUBITAT_ACCESS_TOKEN" != *[[:cntrl:]]* ]] || { fail 'A nonempty access token without control characters is required'; return 1; }
    [[ "$HUBITAT_TIMEOUT" =~ ^[1-9][0-9]{0,3}$ ]] || { fail 'HUBITAT_TIMEOUT must be 1–9999 seconds'; return 1; }
}

configure() {
    local action=${1:-setup} value temporary directory
    (( $# == 0 )) || shift
    case "$action" in
        setup|show|token) (( $# == 0 )) || { fail "Unexpected arguments for config $action"; return 1; } ;;
        url) (( $# <= 1 )) || { fail 'Usage: config url [BASE_URL]'; return 1; } ;;
        *) fail 'Use config, config show, config url, or config token'; return 1 ;;
    esac
    if [[ "$action" == show ]]; then
        printf 'Configuration: %s\nBase URL: %s\nToken: %s\nTimeout: %s seconds\n' \
            "$ENV_FILE" "$HUBITAT_BASE_URL" "$(if [[ -n "$HUBITAT_ACCESS_TOKEN" ]]; then printf configured; else printf missing; fi)" "$HUBITAT_TIMEOUT"
        return
    fi
    if [[ "$action" == setup || "$action" == url ]]; then
        if (( $# )); then value=$1
        else read -r -p "Maker API base URL [$HUBITAT_BASE_URL]: " value || return 1; fi
        HUBITAT_BASE_URL=${value:-$HUBITAT_BASE_URL}
    fi
    if [[ "$action" == setup || "$action" == token ]]; then
        read -r -s -p 'Access token (hidden; blank keeps existing): ' value || { printf '\n' >&2; return 1; }
        printf '\n' >&2
        HUBITAT_ACCESS_TOKEN=${value:-$HUBITAT_ACCESS_TOKEN}
    fi
    defaults
    validate_config || return 1
    directory=$(dirname -- "$ENV_FILE") || return 1
    mkdir -p -- "$directory" || return 1
    temporary=$(mktemp "$directory/.hubitat-config.XXXXXXXX") || return 1
    if ! printf 'HUBITAT_BASE_URL=%s\nHUBITAT_ACCESS_TOKEN=%s\nHUBITAT_TIMEOUT=%s\n' \
        "$HUBITAT_BASE_URL" "$HUBITAT_ACCESS_TOKEN" "$HUBITAT_TIMEOUT" > "$temporary"; then
        rm -f -- "$temporary"; return 1
    fi
    if ! mv -f -- "$temporary" "$ENV_FILE"; then rm -f -- "$temporary"; return 1; fi
    printf 'Configuration saved: %s\n' "$ENV_FILE"
}

segment() {
    [[ -n "$1" ]] || { fail 'URL path values cannot be empty'; return 1; }
    case "$1" in .) printf '%%2E' ;; ..) printf '%%2E%%2E' ;; *) printf '%s' "$1" | jq -sRr @uri ;; esac
}

api() {
    local kind=$1 path=$2 code
    shift 2
    if [[ "$kind" == write && "$DRY_RUN" == 1 ]]; then
        jq -n --arg path "$path" --args '{dryRun:true,method:"GET",path:$path,query:$ARGS.positional}' -- "$@"
        return
    fi
    # Maker API uses GET even for writes. Token data is read from a private file,
    # keeping it out of curl's argument list. Do not follow redirects or retry.
    if ! code=$(curl --disable --silent --globoff --path-as-is --proto '=http,https' \
        --connect-timeout 10 --max-time "$HUBITAT_TIMEOUT" \
        --get --data-urlencode "access_token@$WORK_DIR/token" \
        --header 'Accept: application/json' "$@" \
        --output "$WORK_DIR/response" --write-out '%{http_code}' \
        --url "$HUBITAT_BASE_URL$path" 2> "$WORK_DIR/curl-error"); then
        fail 'Connection failed or timed out; check the URL, network and TLS certificate. No retry was made.'
        [[ "$kind" != write ]] || printf 'The command may have reached the hub. Read its state before repeating it.\n' >&2
        return 1
    fi
    if [[ ! "$code" =~ ^2[0-9][0-9]$ ]]; then
        fail "Maker API returned HTTP $code. Check token, local/cloud access, device authorization, and feature permissions."
        return 1
    fi
    if [[ ! -s "$WORK_DIR/response" ]]; then
        [[ "$kind" == write ]] || { fail 'Expected JSON but received an empty response'; return 1; }
        printf '{"accepted":true}\n'; return
    fi
    if ! jq -e -s 'length == 1' "$WORK_DIR/response" >/dev/null 2>&1; then
        # Do not treat an unexpected response as proof the command succeeded.
        fail 'Maker API returned a non-JSON response; check hub state before repeating a write'
        return 1
    fi
    if jq -e 'type == "object" and ((.error != null and .error != false and .error != "") or (.errors != null and .errors != [] and .errors != false))' "$WORK_DIR/response" >/dev/null 2>&1; then
        fail 'Maker API reported an error in its JSON response. Check device commands and feature permissions.'; return 1
    fi
    cat -- "$WORK_DIR/response"
}

resolve_device() {
    local selector=$1 id
    if [[ "$selector" =~ ^(id:)?([0-9]+)$ ]]; then printf '%s\n' "${BASH_REMATCH[2]}"; return; fi
    api read /devices > "$WORK_DIR/devices" || return 1
    id=$(jq -er --arg name "$selector" '
        [.[] | select((if (.label // "") != "" then .label else .name end) == $name)] |
        if length == 1 then .[0].id | tostring
        elif length == 0 then error("No authorized device has this label/name")
        else error("Duplicate labels; use id:NUMBER from devices") end' "$WORK_DIR/devices") || return 1
    [[ "$id" =~ ^[0-9]+$ ]] || { fail 'Device catalog returned a nonnumeric ID'; return 1; }
    printf '%s\n' "$id"
}

resolve_mode() {
    local selector=$1
    api read /modes > "$WORK_DIR/modes" || return 1
    jq -er --arg selector "$selector" '
        [.[] | select(if ($selector | test("^(id:)?[0-9]+$"))
            then (.id | tostring) == ($selector | sub("^id:"; "")) else .name == $selector end)] |
        if length == 1 then .[0].id | tostring else error("Mode must match exactly one authorized mode") end
        | if test("^[0-9]+$") then . else error("Invalid mode ID") end' "$WORK_DIR/modes"
}

# Resolve and validate a mutation into PLAN_PATH and optional curl query args.
# The same path is used by direct commands, previews, and answer files.
plan_write() {
    local action=$1 id command value joined item
    shift
    PLAN_PATH=''; PLAN_QUERY=()
    case "$action" in
        send)
            (( $# >= 2 )) || { fail 'Usage: send DEVICE COMMAND [ARG ...]'; return 1; }
            id=$(resolve_device "$1") || return 1
            command=$2; shift 2
            [[ "$command" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { fail 'Invalid command name'; return 1; }
            api read "/devices/$id/commands" > "$WORK_DIR/commands" || return 1
            jq -e --arg command "$command" 'any(.[]; (if type == "string" then . else .command end) == $command)' \
                "$WORK_DIR/commands" >/dev/null || { fail 'Command is not in this device’s supported command list'; return 1; }
            PLAN_PATH="/devices/$id/$command"
            if (( $# )); then
                joined=$1; shift
                for item in "$@"; do joined+=",$item"; done
                value=$(segment "$joined") || return 1
                PLAN_PATH+="/$value"
            fi ;;
        label)
            (( $# == 2 )) && [[ -n "$2" ]] || { fail 'Usage: label DEVICE NEW_LABEL'; return 1; }
            id=$(resolve_device "$1") || return 1
            PLAN_PATH="/devices/$id/setLabel"; PLAN_QUERY=(--data-urlencode "label=$2") ;;
        mode)
            (( $# == 1 )) || { fail 'Usage: mode MODE'; return 1; }
            id=$(resolve_mode "$1") || return 1
            PLAN_PATH="/modes/$id" ;;
        hsm)
            (( $# == 1 )) || { fail 'Usage: hsm [ACTION]'; return 1; }
            case "$1" in armAway|armHome|armNight|disarm|disarmAll|armAll|CancelAlerts) ;;
                *) fail 'Unknown HSM action; see help (actions are case-sensitive)'; return 1 ;; esac
            PLAN_PATH="/hsm/$1" ;;
        variable)
            (( $# == 2 )) || { fail 'Usage: variable NAME [VALUE]'; return 1; }
            id=$(segment "$1") && value=$(segment "$2") || return 1
            PLAN_PATH="/hubvariables/$id/$value" ;;
        post-url)
            (( $# == 1 )) || { fail 'Usage: post-url URL|clear'; return 1; }
            PLAN_PATH=/postURL
            if [[ "$1" != clear ]]; then
                [[ "$1" =~ ^https?://[^[:space:]]+$ ]] || { fail 'Callback URL must start with http:// or https://'; return 1; }
                value=$(segment "$1") || return 1
                PLAN_PATH+="/$value"
            fi ;;
        *) fail 'Unsupported write action'; return 1 ;;
    esac
}

write_command() {
    plan_write "$@" || return 1
    api write "$PLAN_PATH" "${PLAN_QUERY[@]}" | jq .
}

example() {
    cat <<'JSON'
[
  {"action":"send","device":"Living Room Light","command":"on","args":[]},
  {"action":"send","device":"Living Room Light","command":"setLevel","args":[50,2]},
  {"action":"mode","name":"Evening"},
  {"action":"variable","name":"Greeting","value":"Welcome home"}
]
JSON
}

decode_argument() {
    # A sentinel keeps command substitution from removing trailing newlines.
    local decoded
    decoded=$(jq -r '. + "\u0001"' <<< "$2") || return 1
    printf -v "$1" '%s' "${decoded%$'\001'}"
}

answer_file() {
    local operation=$1 file=$2 entry action row path index=0
    local -a args query
    [[ -r "$file" ]] || { fail 'Cannot read answer file'; return 1; }
    # Snapshot the file, validate the complete schema, then plan every action
    # before sending any writes. Unknown fields are errors to catch typos.
    jq -ce -s '
        def no_nul: (explode | index(0)) == null;
        def text: type == "string" and length > 0 and no_nul;
        def scalar: (type == "string" and no_nul) or type == "number" or type == "boolean";
        def fields($keys): (keys_unsorted - $keys | length) == 0;
        def valid:
          type == "object" and
          (if .action == "send" then
             fields(["action","device","command","args"]) and (.device | text) and (.command | text)
             and (if has("args") then (.args | type == "array" and all(.[]; scalar)) else true end)
           elif .action == "mode" then fields(["action","name"]) and (.name | text)
           elif .action == "hsm" then fields(["action","value"]) and (.value | text)
           elif .action == "label" then fields(["action","device","value"]) and (.device | text) and (.value | text)
           elif .action == "variable" then fields(["action","name","value"]) and (.name | text) and (.value | scalar)
           elif .action == "post-url" then fields(["action","value"]) and (.value | text)
           else false end);
        if length != 1 then error("Expected one JSON document") else .[0] end |
        if type == "object" then [.] else . end |
        if type == "array" and length > 0 and all(.[]; valid) then .[]
        else error("Invalid answer file: see README schema") end
    ' "$file" > "$WORK_DIR/actions" || return 1
    : > "$WORK_DIR/plan"
    while IFS= read -r entry; do
        action=$(jq -r .action <<< "$entry") || return 1
        args=()
        case "$action" in
            send) mapfile -t args < <(jq -c '.device, .command, ((.args // [])[] | tostring)' <<< "$entry") ;;
            mode) mapfile -t args < <(jq -c '.name' <<< "$entry") ;;
            label) mapfile -t args < <(jq -c '.device, .value' <<< "$entry") ;;
            variable) mapfile -t args < <(jq -c '.name, (.value | tostring)' <<< "$entry") ;;
            hsm|post-url) mapfile -t args < <(jq -c '.value' <<< "$entry") ;;
        esac
        # JSON framing preserves newlines inside a scalar argument.
        for index in "${!args[@]}"; do decode_argument 'args[index]' "${args[$index]}" || return 1; done
        plan_write "$action" "${args[@]}" || return 1
        jq -nc --arg action "$action" --arg path "$PLAN_PATH" --args \
            '{action:$action,path:$path,query:$ARGS.positional}' -- "${PLAN_QUERY[@]}" >> "$WORK_DIR/plan" || return 1
    done < "$WORK_DIR/actions"
    if [[ "$operation" == preview || "$DRY_RUN" == 1 ]]; then jq -s . "$WORK_DIR/plan"; return; fi
    index=0
    while IFS= read -r row; do
        index=$((index + 1))
        path=$(jq -r .path <<< "$row") || return 1
        mapfile -t query < <(jq -c '.query[]' <<< "$row")
        for entry in "${!query[@]}"; do decode_argument 'query[entry]' "${query[$entry]}" || return 1; done
        printf 'Sending action %s\n' "$index" >&2
        if ! api write "$path" "${query[@]}" | jq -c .; then
            fail "Stopped at action $index; earlier actions may have run. Inspect hub state before resubmitting."
            return 1
        fi
    done < "$WORK_DIR/plan"
}

dispatch() {
    local command=$1 id path
    shift
    case "$command" in
        devices)
            (( $# <= 1 )) && [[ "${1:-}" == '' || "${1:-}" == --all ]] || { fail 'Usage: devices [--all]'; return 1; }
            path=/devices; [[ "${1:-}" != --all ]] || path=/devices/all
            if [[ "$JSON_OUTPUT" == 1 || "$path" == /devices/all ]]; then api read "$path" | jq .
            else api read "$path" | jq -r '["ID","LABEL","NAME"], (.[] | [.id,.label,.name]) | @tsv'; fi ;;
        device|events|commands|attribute)
            if [[ "$command" == attribute ]]; then
                (( $# == 2 )) || { fail 'Usage: attribute DEVICE ATTRIBUTE'; return 1; }
            else (( $# == 1 )) || { fail "Usage: $command DEVICE"; return 1; }; fi
            id=$(resolve_device "$1") || return 1
            path="/devices/$id"
            case "$command" in
                events|commands) path+="/$command" ;;
                attribute) id=$(segment "$2") || return 1; path+="/attribute/$id" ;;
            esac
            api read "$path" | jq . ;;
        send|label|mode|post-url) write_command "$command" "$@" ;;
        hsm)
            if (( $# )); then write_command hsm "$@"; else api read /hsm | jq .; fi ;;
        variable)
            if (( $# == 2 )); then write_command variable "$@"
            elif (( $# == 1 )); then id=$(segment "$1") || return 1; api read "/hubvariables/$id" | jq .
            else fail 'Usage: variable NAME [VALUE]'; fi ;;
        modes|variables|rooms)
            (( $# == 0 )) || { fail "Unexpected arguments for $command"; return 1; }
            path="/$command"; [[ "$command" != variables ]] || path=/hubvariables
            api read "$path" | jq . ;;
        room)
            (( $# == 1 )) && [[ "$1" =~ ^[0-9]+$ ]] || { fail 'Usage: room NUMERIC_ID'; return 1; }
            api read "/room/select/$1" | jq . ;;
        preview|submit)
            (( $# == 1 )) || { fail "Usage: $command FILE"; return 1; }
            answer_file "$command" "$1" ;;
        *) fail "Unknown command: $command (see help)" ;;
    esac
}

menu() {
    local choice device command value name file count i old_url old_token old_timeout
    local -a args
    while true; do
        printf '\nHubitat Maker API\n1) List devices\n2) Device details\n3) Device events\n4) Supported commands\n5) Send command\n6) Read attribute\n7) List modes\n8) Set mode\n9) HSM status\n10) HSM action\n11) List variables\n12) Read variable\n13) Set variable\n14) List rooms\n15) Set/clear event callback\n16) Preview answer file\n17) Submit answer file\n18) Configuration\n19) Change device label\n0) Quit\n'
        read -r -p 'Choice: ' choice || return 0
        args=()
        case "$choice" in
            0|q|quit) return 0 ;;
            1) args=(devices) ;;
            2|3|4|5|6|19)
                read -r -p 'Device label or id:NUMBER: ' device || return 0
                case "$choice" in
                    2) args=(device "$device") ;;
                    3) args=(events "$device") ;;
                    4) args=(commands "$device") ;;
                    5)
                        dispatch commands "$device" || continue
                        read -r -p 'Command: ' command || return 0
                        read -r -p 'Number of arguments [0]: ' count || return 0
                        count=${count:-0}
                        [[ "$count" =~ ^[0-9]{1,2}$ ]] || { fail 'Enter 0–99'; continue; }
                        args=(send "$device" "$command")
                        for ((i=0; i<10#$count; i++)); do
                            read -r -p "Argument $((i + 1)): " value || return 0
                            args+=("$value")
                        done ;;
                    6) read -r -p 'Attribute name: ' name || return 0; args=(attribute "$device" "$name") ;;
                    19) read -r -p 'New label: ' value || return 0; args=(label "$device" "$value") ;;
                esac ;;
            7) args=(modes) ;;
            8) dispatch modes || continue; read -r -p 'Mode name or id:NUMBER: ' name || return 0; args=(mode "$name") ;;
            9) args=(hsm) ;;
            10) read -r -p 'HSM action (armAway/armHome/armNight/disarm/disarmAll/armAll/CancelAlerts): ' value || return 0; args=(hsm "$value") ;;
            11) args=(variables) ;;
            12|13)
                read -r -p 'Variable name: ' name || return 0
                args=(variable "$name")
                if [[ "$choice" == 13 ]]; then read -r -p 'Value: ' value || return 0; args+=("$value"); fi ;;
            14) args=(rooms) ;;
            15) read -r -p 'Event callback URL (or clear): ' value || return 0; args=(post-url "$value") ;;
            16|17)
                read -r -p 'JSON answer file: ' file || return 0
                args=(preview "$file")
                if [[ "$choice" == 17 ]]; then
                    dispatch preview "$file" || continue
                    read -r -p 'Send all actions now? [y/N]: ' value || return 0
                    [[ "$value" == y || "$value" == Y ]] || continue
                    args=(submit "$file")
                fi ;;
            18)
                configure show
                old_url=$HUBITAT_BASE_URL; old_token=$HUBITAT_ACCESS_TOKEN; old_timeout=$HUBITAT_TIMEOUT
                if configure setup; then
                    printf '%s' "$HUBITAT_ACCESS_TOKEN" > "$WORK_DIR/token" || return 1
                else
                    HUBITAT_BASE_URL=$old_url; HUBITAT_ACCESS_TOKEN=$old_token; HUBITAT_TIMEOUT=$old_timeout
                fi
                continue ;;
            *) printf 'Choose a menu number.\n'; continue ;;
        esac
        # Handle each failure explicitly so a failed request leaves the menu usable.
        dispatch "${args[@]}" || printf 'Action failed; returning to menu.\n' >&2
    done
}

main() {
    (( BASH_VERSINFO[0] >= 4 )) || { fail 'Bash 4+ is required'; return 1; }
    while (( $# )); do
        case "$1" in
            --env) (( $# >= 2 )) || { fail '--env requires a filename'; return 1; }; ENV_FILE=$2; shift 2 ;;
            --json) JSON_OUTPUT=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            -h|--help) usage; return ;;
            --) shift; break ;;
            -*) fail 'Unknown option; see help'; return 1 ;;
            *) break ;;
        esac
    done
    local command=${1:-menu} tool
    (( $# == 0 )) || shift
    case "$command" in
        help|example)
            (( $# == 0 )) || { fail "Unexpected arguments for $command"; return 1; }
            if [[ "$command" == help ]]; then usage; else example; fi
            return ;;
    esac
    if [[ -e "$ENV_FILE" ]]; then read_config || return 1; fi
    defaults
    if [[ "$command" == config ]]; then configure "$@"; return; fi
    if [[ -z "$HUBITAT_BASE_URL" || -z "$HUBITAT_ACCESS_TOKEN" ]]; then
        [[ -t 0 && "$command" == menu ]] || { fail "Run hubitat-cli.sh --env '$ENV_FILE' config first, or set HUBITAT_BASE_URL and HUBITAT_ACCESS_TOKEN"; return 1; }
        cat <<'SETUP'
Welcome to Hubitat CLI. Let's set up your Maker API connection.
1. On your hub, open Apps, add the built-in Maker API app, and authorize devices.
2. Enable local and/or cloud access, select Update, and find its endpoint URLs.
3. Enter the base URL below, without /devices or the ?access_token=... query.
   Local example: http://192.168.1.50/apps/api/123
   Cloud example: https://cloud.hubitat.com/api/YOUR-HUB-ID/apps/123
4. Enter the access token separately at the hidden prompt, then select Done
   in the Maker API app if you have not already done so.
SETUP
        printf 'Settings will be saved privately to: %s\n\n' "$ENV_FILE"
        configure setup || return 1
    fi
    validate_config || return 1
    for tool in curl jq; do command -v "$tool" >/dev/null || { fail "Missing $tool; install curl and jq using your package manager"; return 1; }; done
    WORK_DIR=$(mktemp -d) || return 1
    printf '%s' "$HUBITAT_ACCESS_TOKEN" > "$WORK_DIR/token" || return 1
    if [[ "$command" == menu ]]; then
        (( $# == 0 )) || { fail 'menu takes no arguments'; return 1; }
        menu
    else dispatch "$command" "$@"; fi
}

main "$@"
