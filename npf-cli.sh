#!/usr/bin/env bash
# Bash 4+, curl, jq. All writes create proposals requiring human approval.
set -euo pipefail
umask 077
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/npf-cli/config"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/npf-cli"
ENV_FILE="$CONFIG_FILE"
WORK_DIR=''
cleanup() { [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'Error: %s\n' "$*" >&2; return 1; }
usage() {
    cat <<'HELP'
Usage: npf-cli.sh [--env FILE] COMMAND [ARGS]
  config                       Set up or change URL and key interactively
  config url [HTTPS_URL]        Change API URL (prompt if omitted)
  config key                   Change integration key (hidden prompt)
  config show                  Show configuration location and URL; hide key
  example [transaction|transfer|json]  Print an answer-file example
  menu                         Interactive menu (default)
  accounts                     List account names, balances and eligibility
  categories                   List category names, roles and eligibility
  transactions [OPTIONS]       Browse ledger transactions with pagination
    --account NAME --category NAME --description TEXT
    --period all|thisMonth|lastMonth|yearToDate|last30Days|month:YYYY-MM
    --start YYYY-MM-DD --end YYYY-MM-DD (custom date range)
    --type all|transactions|transfers
  pending                      Show current pending proposals using names
  status [SUBMISSION_ID]       Browse this integration's submission statuses
  new                          Compose, save and submit an ordinary transaction
  transfer                     Compose, save and submit a transfer/payment
  submit FILE                  Submit text or JSON answer file
  preview FILE                 Resolve and validate answer file without submitting
  help                         Show this help

First run prompts for URL and key. Configuration is private at:
  ~/.config/npf-cli/config (or $XDG_CONFIG_HOME/npf-cli/config)
Use --env FILE for an optional alternative configuration file.
Interactive answers are saved under ~/.local/state/npf-cli/answers
(or $XDG_STATE_HOME/npf-cli/answers).

Account/category inputs are exact, case-sensitive names, never record IDs.
Amounts are entered USD: spending and income positive; refunds/reversals negative.
Transfers require a positive amount. Dates are explicit YYYY-MM-DD values.
Submissions are proposals requiring approval in the application.

Answer files accept literal key=value text or JSON (arrays for JSON batches).
submissionId is optional. Keep the generated *.exptrack-state.json companion
with the answer file for safe retries. A changed answer needs a new file.
Preview reads catalogs and saves retry state but sends no proposals.
Example: ./npf-cli.sh example > groceries.txt
         ./npf-cli.sh preview groceries.txt
         ./npf-cli.sh submit groceries.txt

Requires Bash 4+, curl, jq and standard Unix utilities. Configuration is literal
KEY=value data; never shell code. Do not run with bash -x: it exposes secrets.
Existing EXPTRACK_* configuration keys remain supported.
HELP
}
read_config() {
    [[ -r "$ENV_FILE" ]] || { fail "Cannot read configuration: $ENV_FILE"; return 1; }
    local line key value number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        number=$((number + 1)); line=${line%$'\r'}
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        if [[ "$line" =~ ^([A-Z_][A-Z_0-9]*)=(.*)$ ]]; then
            key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}
            # Strip matching outer quotes, without interpreting their contents.
            if [[ ${#value} -ge 2 ]]; then
                case "$value" in \"*\"|\'*\') value=${value:1:${#value}-2} ;; esac
            fi
            case "$key" in
                EXPTRACK_BASE_URL|EXPTRACK_API_KEY|EXPTRACK_TIMEOUT|EXPTRACK_PAGE_SIZE) printf -v "$key" '%s' "$value" ;;
                *) fail "Unknown env key $key on line $number"; return 1 ;;
            esac
        else
            fail "Expected KEY=value on env line $number"; return 1
        fi
    done < "$ENV_FILE"
}
config_defaults() {
    EXPTRACK_BASE_URL=${EXPTRACK_BASE_URL:-https://exptrack.pritchett.info}
    EXPTRACK_BASE_URL=${EXPTRACK_BASE_URL%/}
    EXPTRACK_TIMEOUT=${EXPTRACK_TIMEOUT:-30}
    EXPTRACK_PAGE_SIZE=${EXPTRACK_PAGE_SIZE:-100}
    EXPTRACK_API_KEY=${EXPTRACK_API_KEY:-}
}
validate_config() {
    [[ "$EXPTRACK_API_KEY" != *$'\n'* && "$EXPTRACK_API_KEY" != *$'\r'* ]] || { fail 'Key contains a newline'; return 1; }
    [[ "$EXPTRACK_BASE_URL" =~ ^https://[^/?#[:space:]]+(/[^?#[:space:]]*)?$ ]] || { fail 'Base URL must use HTTPS without a query or fragment'; return 1; }
    [[ "$EXPTRACK_TIMEOUT" =~ ^[1-9][0-9]{0,3}$ ]] || { fail 'Timeout must be 1–9999 seconds'; return 1; }
    [[ "$EXPTRACK_PAGE_SIZE" =~ ^[1-9][0-9]{0,2}$ ]] && (( EXPTRACK_PAGE_SIZE <= 500 )) || { fail 'Page size must be 1–500'; return 1; }
}
save_config() {
    local directory temporary
    config_defaults
    validate_config || return 1
    directory=$(dirname -- "$ENV_FILE")
    mkdir -p -- "$directory" || return 1
    temporary=$(mktemp "$directory/.npf-config.XXXXXXXX") || return 1
    if ! printf 'EXPTRACK_BASE_URL=%s\nEXPTRACK_API_KEY=%s\nEXPTRACK_TIMEOUT=%s\nEXPTRACK_PAGE_SIZE=%s\n' \
        "$EXPTRACK_BASE_URL" "$EXPTRACK_API_KEY" "$EXPTRACK_TIMEOUT" "$EXPTRACK_PAGE_SIZE" > "$temporary"; then
        rm -f -- "$temporary"; return 1
    fi
    # This file contains the secret; umask 077 keeps new files private.
    if ! mv -f -- "$temporary" "$ENV_FILE"; then rm -f -- "$temporary"; return 1; fi
    printf 'Configuration saved: %s\n' "$ENV_FILE"
}
configure() {
    local action=${1:-setup} value
    (( $# == 0 )) || shift
    case "$action" in
        setup|key|show) (( $# == 0 )) || { fail "Unexpected arguments for config $action"; return 1; } ;;
        url) (( $# <= 1 )) || { fail 'Usage: config url [HTTPS_URL]'; return 1; } ;;
        *) fail 'Use config, config url, config key, or config show'; return 1 ;;
    esac
    if [[ -e "$ENV_FILE" ]]; then read_config || return 1; fi
    config_defaults
    if [[ "$action" == show ]]; then
        printf 'Configuration: %s\nURL: %s\nKey: %s\n' "$ENV_FILE" "$EXPTRACK_BASE_URL" \
            "$(if [[ -n "$EXPTRACK_API_KEY" ]]; then printf configured; else printf 'not configured'; fi)"
        return
    fi
    if [[ "$action" == setup || "$action" == url ]]; then
        if (( $# )); then value=$1
        else read -r -p "API URL [$EXPTRACK_BASE_URL]: " value || return 1; fi
        EXPTRACK_BASE_URL=${value:-$EXPTRACK_BASE_URL}
    fi
    if [[ "$action" == setup || "$action" == key ]]; then
        read -r -s -p 'Integration key (hidden; blank keeps existing): ' value || { printf '\n' >&2; return 1; }
        printf '\n' >&2
        EXPTRACK_API_KEY=${value:-$EXPTRACK_API_KEY}
        [[ -n "$EXPTRACK_API_KEY" ]] || { fail 'An integration key is required'; return 1; }
    fi
    save_config
}
example() {
    case "${1:-transaction}" in
        transaction) cat <<'ANSWER'
type=transaction
date=2026-11-04
account=Checking
category=Groceries
description=Weekly groceries
amount=50.00
ANSWER
        ;;
        transfer) cat <<'ANSWER'
type=transfer
date=2026-11-04
fromAccount=Checking
toAccount=Savings
description=Savings transfer
amount=100.00
ANSWER
        ;;
        json) cat <<'ANSWER'
{
  "type": "transaction",
  "date": "2026-11-04",
  "account": "Checking",
  "category": "Groceries",
  "description": "Weekly groceries",
  "amount": "50.00"
}
ANSWER
        ;;
        *) fail 'Use example transaction, example transfer, or example json'; return 1 ;;
    esac
}
load_env() {
    if [[ -e "$ENV_FILE" ]]; then read_config || return 1; fi
    config_defaults
    if [[ ! -e "$ENV_FILE" || -z "$EXPTRACK_API_KEY" ]]; then
        [[ -t 0 ]] || { fail "Run ./npf-cli.sh config to configure $ENV_FILE"; return 1; }
        configure setup || return 1
    fi
    validate_config || return 1
    WORK_DIR=$(mktemp -d)
    # Header file keeps the key out of curl's command-line arguments.
    printf 'Authorization: Bearer %s\n' "$EXPTRACK_API_KEY" > "$WORK_DIR/auth"
    unset EXPTRACK_API_KEY
}
api() {
    local method=$1 path=$2 code
    shift 2
    if ! code=$(curl --disable --silent --show-error --proto '=https' \
        --connect-timeout 10 --max-time "$EXPTRACK_TIMEOUT" \
        --header "@$WORK_DIR/auth" --header 'Accept: application/json' \
        --request "$method" --output "$WORK_DIR/response" --write-out '%{http_code}' \
        "$@" "$EXPTRACK_BASE_URL$path"); then
        if [[ "$method" == GET ]]; then
            fail 'Read request failed. Check connectivity and try again.'
        else
            fail 'Request failed. Keep the saved answer file and retry it unchanged; the server may have received it.'
        fi
        return 1
    fi
    if [[ ! "$code" =~ ^2[0-9][0-9]$ ]]; then
        printf 'API error (HTTP %s):\n' "$code" >&2
        jq . "$WORK_DIR/response" >&2 2>/dev/null || cat "$WORK_DIR/response" >&2
        return 1
    fi
    jq -e 'type == "object" or type == "array"' "$WORK_DIR/response" >/dev/null || { fail 'API returned invalid JSON'; return 1; }
    cat "$WORK_DIR/response"
}
catalogs() {
    api GET /api/integration/read/accounts > "$WORK_DIR/accounts" || return 1
    api GET /api/integration/read/categories > "$WORK_DIR/categories" || return 1
}
accounts() {
    api GET /api/integration/read/accounts | jq -r '
      def usd:
        . as $c | (if $c < 0 then -$c else $c end) as $n |
        (if $c < 0 then "-" else "" end) + (($n / 100 | floor) | tostring) +
        "." + ("0" + (($n % 100) | tostring))[-2:];
      ["NAME","CLASS","BALANCE USD","BALANCE MEANING","ACTIVE","TRANSACTIONS","TRANSFERS"],
      (.[] | [.name,.accountClass,
        (if has("balanceCents") then
          (if .accountClass == "credit" and .balanceCents < 0 then -.balanceCents else .balanceCents end | usd)
         else "n/a" end),
        (if (has("balanceCents") | not) then "n/a"
         elif .accountClass == "credit" then
           (if .balanceCents < 0 then "owed" elif .balanceCents > 0 then "credit" else "settled" end)
         elif .balanceCents < 0 then "overdrawn" else "available" end),
        .active,.ordinaryEligible,.transferEligible]) | @tsv'
}
categories() {
    api GET /api/integration/read/categories | jq -r '
      ["NAME","ROLE","ELIGIBLE"], (.[] | [.name,.reportingRole,.ordinaryEligible]) | @tsv'
}
resolve_name() {
    local file=$1 name=$2 flag=${3:-}
    jq -er --arg name "$name" --arg flag "$flag" '
      [.[] | select(.name == $name)] |
      if length != 1 then error("Name must match exactly one record: " + $name)
      elif $flag != "" and (.[0][$flag] != true or .[0].active != 1) then error("Ineligible name: " + $name)
      else .[0].id end' "$file"
}
pending() {
    catalogs || return 1
    api GET /api/integration/pending | jq --slurpfile a "$WORK_DIR/accounts" --slurpfile c "$WORK_DIR/categories" '
      def name($list; $id): ([$list[] | select(.id == $id) | .name][0] // "<unavailable>");
      .rows |= map(if .kind == "transfer" then
        . + {fromAccount:name($a[0];.fromAccountId),toAccount:name($a[0];.toAccountId)} | del(.fromAccountId,.toAccountId)
      else . + {account:name($a[0];.accountId),category:name($c[0];.categoryId)} | del(.accountId,.categoryId) end)'
}
pages() {
    local path=$1 collection=$2 response offset=0 next choice
    shift 2
    while :; do
        response=$(api GET "$path" --get --data-urlencode "limit=$EXPTRACK_PAGE_SIZE" --data-urlencode "offset=$offset" "$@") || return 1
        if [[ "$collection" == transactions ]]; then
            jq -r '["DATE","ACCOUNT","DESCRIPTION","CATEGORY","DISPLAY USD"],
              (.transactions[] | [.date,(.accountName // "<unavailable>"),.description,(.categoryName // (if .combinedTransfer then "Transfer/payment" else "" end)),(.displayAmountCents/100|tostring)]) | @tsv' <<< "$response"
        else
            jq '.submissions' <<< "$response"
        fi
        printf 'Showing offset %s; total matches: %s\n' "$offset" "$(jq -r .total <<< "$response")"
        next=$(jq -r '.nextOffset // empty' <<< "$response")
        [[ -n "$next" ]] || break
        # Pipelines get every page; terminal users choose when to continue.
        if [[ -t 0 ]]; then
            read -r -p 'Next page? [y/N] ' choice || break
            [[ "$choice" == [yY] ]] || break
        fi
        [[ "$next" =~ ^[0-9]+$ ]] && (( next > offset )) || { fail 'Invalid pagination offset'; return 1; }
        offset=$next
    done
}
transactions() {
    local key value id start='' end=''
    local -a query=()
    catalogs || return 1
    while (( $# )); do
        (( $# >= 2 )) || { fail "Missing value for $1"; return 1; }
        key=$1; value=$2; shift 2
        case "$key" in
            --account) id=$(resolve_name "$WORK_DIR/accounts" "$value") || return 1; query+=(--data-urlencode "accountId=$id") ;;
            --category) id=$(resolve_name "$WORK_DIR/categories" "$value") || return 1; query+=(--data-urlencode "categoryId=$id") ;;
            --period|--type|--description) query+=(--data-urlencode "${key#--}=$value") ;;
            --start) start=$value ;;
            --end) end=$value ;;
            *) fail "Unknown transaction option: $key"; return 1 ;;
        esac
    done
    if [[ -n "$start$end" ]]; then
        [[ -n "$start" && -n "$end" ]] || { fail 'Provide both --start and --end'; return 1; }
        query+=(--data-urlencode period=custom --data-urlencode "startDate=$start" --data-urlencode "endDate=$end")
    fi
    pages /api/integration/read/transactions transactions "${query[@]}"
}
prepare_answers() {
    local file=$1 state="$1.exptrack-state.json" generated=0 seed temporary
    [[ -r "$file" ]] || { fail "Cannot read $file"; return 1; }
    # Parse data only: never source answer files as shell code.
    jq -Rse '
      if test("^\\s*[\\[{]") then fromjson
      else reduce (split("\n")[] | sub("\r$"; "")) as $line ({};
        if ($line | test("^\\s*(#|$)")) then .
        elif ($line | test("^[A-Za-z][A-Za-z0-9]*=")) then
          ($line | index("=")) as $i | ($line[0:$i]) as $key |
          if has($key) then error("Duplicate answer key: " + $key)
          else .[$key] = $line[($i+1):] end
        else error("Expected key=value in answer file") end)
      end |
      (if type == "array" then . else [.] end) |
      if length == 0 or any(.[]; type != "object") then error("Expected answer objects")
      else map(.type = (.type // "transaction")) end
    ' "$file" > "$WORK_DIR/input" || return 1
    if jq -e 'any(.[]; has("submissionId") | not)' "$WORK_DIR/input" >/dev/null; then
        generated=1
        if [[ -e "$state" ]]; then
            jq -e --slurpfile input "$WORK_DIR/input" '
              if .input == $input[0] and (.answers | type == "array") and
                 (.answers | map(del(.submissionId))) == ($input[0] | map(del(.submissionId)))
              then .answers else error("Answer differs from saved retry state; use a new file for a new submission") end
            ' "$state" > "$WORK_DIR/normalized" || return 1
        else
            seed=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
            jq --arg seed "$seed" 'to_entries | map(.value +
              (if (.value | has("submissionId")) then {} else
               {submissionId:("bash-" + $seed + "-" + (.key|tostring))} end))' \
              "$WORK_DIR/input" > "$WORK_DIR/normalized" || return 1
        fi
    else
        cp -- "$WORK_DIR/input" "$WORK_DIR/normalized" || return 1
    fi
    # Reject unknown keys, including IDs, before resolving names. Validate the
    # entire batch before any POST. API remains authoritative for business rules.
    jq -e '
      def text: type == "string" and length > 0;
      (if type == "array" then . else [.] end) |
      if length == 0 then error("Empty answer file") else . end |
      map(. as $r |
        if type != "object" then error("Each answer must be an object")
        elif (.type // "transaction") as $t | ($t != "transaction" and $t != "transfer") then error("Invalid type")
        else . end |
        (.type // "transaction") as $t |
        (if $t == "transfer" then ["submissionId","type","date","fromAccount","toAccount","description","amount"]
         else ["submissionId","type","date","account","category","description","amount"] end) as $allowed |
        if ((keys - $allowed)|length) > 0 then error("Unknown fields (use names, not IDs)") else . end |
        if ([.submissionId,.date,.description,.amount] | all(.[]; text)) and
           (.submissionId|length <= 128) and
           (.date|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and
           (.amount|test("^[+-]?[0-9]+([.][0-9]{1,2})?$")) and
           (if $t == "transfer" then ([.fromAccount,.toAccount]|all(.[];text)) and .fromAccount != .toAccount and (.amount|tonumber) > 0
            else ([.account,.category]|all(.[];text)) end)
        then . else error("Invalid required fields, date, names or USD amount string") end) |
      if ([.[].submissionId]|unique|length) != length then error("Duplicate submissionId in batch") else . end
    ' "$WORK_DIR/normalized" > "$WORK_DIR/answers" || return 1
    catalogs || return 1
    jq -e --slurpfile a "$WORK_DIR/accounts" --slurpfile c "$WORK_DIR/categories" '
      def resolve($list; $name; $flag):
        [$list[] | select(.name == $name)] |
        if length != 1 then error("Name must match exactly one record: " + $name)
        elif .[0][$flag] != true or .[0].active != 1 then error("Ineligible name: " + $name)
        else .[0].id end;
      map(if (.type // "transaction") == "transfer" then
        . + {fromAccountId:resolve($a[0];.fromAccount;"transferEligible"),toAccountId:resolve($a[0];.toAccount;"transferEligible")} | del(.fromAccount,.toAccount)
      else . + {accountId:resolve($a[0];.account;"ordinaryEligible"),categoryId:resolve($c[0];.category;"ordinaryEligible")} | del(.type,.account,.category) end)
    ' "$WORK_DIR/answers" > "$WORK_DIR/payloads" || return 1
    if (( generated )) && [[ -e "$state" ]]; then
        jq -e --slurpfile input "$WORK_DIR/input" --slurpfile answers "$WORK_DIR/answers" \
            '.input == $input[0] and .answers == $answers[0]' "$state" >/dev/null || {
            fail 'Retry state changed during preparation. Retry; nothing was submitted.'; return 1;
        }
    elif (( generated )); then
        temporary=$(mktemp "${state}.tmp.XXXXXXXX") || return 1
        if ! jq -n --slurpfile input "$WORK_DIR/input" --slurpfile answers "$WORK_DIR/answers" \
            '{input:$input[0],answers:$answers[0]}' > "$temporary"; then
            rm -f -- "$temporary"; return 1
        fi
        # Publish a complete state file atomically without overwriting a retry ID.
        if ! ln -- "$temporary" "$state"; then
            rm -f -- "$temporary"
            fail 'Could not save retry state (or another process created it). Retry; nothing was submitted.'
            return 1
        fi
        rm -f -- "$temporary"
    fi
}
submit_file() {
    local file=$1 mode=${2:-submit} payload sid
    prepare_answers "$file" || return 1
    if [[ "$mode" == preview ]]; then
        jq . "$WORK_DIR/answers"
        printf 'Names resolved successfully. No submissions sent.\n'
        return
    fi
    while IFS= read -r payload; do
        sid=$(jq -r .submissionId <<< "$payload")
        printf 'Submitting %s\n' "$sid"
        printf '%s\n' "$payload" > "$WORK_DIR/payload"
        if ! api POST /api/integration/submissions --header 'Content-Type: application/json' --data-binary "@$WORK_DIR/payload" | jq .; then
            printf 'Stopped at %s. Earlier items may have succeeded. Retry the same file unchanged.\n' "$sid" >&2
            return 1
        fi
    done < <(jq -c '.[]' "$WORK_DIR/payloads")
}
prompt() {
    local label=$1 var=$2 value
    read -r -p "$label: " value || return 1
    [[ -n "$value" ]] || { fail "$label is required"; return 1; }
    printf -v "$var" '%s' "$value"
}
compose() {
    local kind=$1 date description amount account category from to sid file choice
    accounts || return 1
    [[ "$kind" == transfer ]] || categories || return 1
    printf 'Amounts are entered USD: positive expense = spending; negative expense = refund.\n'
    prompt 'Date (YYYY-MM-DD)' date || return 1
    if [[ "$kind" == transfer ]]; then
        prompt 'From account name' from || return 1
        prompt 'To account name' to || return 1
    else
        prompt 'Account name' account || return 1
        prompt 'Category name' category || return 1
    fi
    prompt 'Description' description || return 1
    prompt 'Amount (e.g. 50.00)' amount || return 1
    sid="bash-$(date -u +%Y%m%dT%H%M%SZ)-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
    mkdir -p "$STATE_DIR/answers"
    file="$STATE_DIR/answers/$sid.txt"
    {
        printf 'type=%s\ndate=%s\n' "$kind" "$date"
        if [[ "$kind" == transfer ]]; then
            printf 'fromAccount=%s\ntoAccount=%s\n' "$from" "$to"
        else
            printf 'account=%s\ncategory=%s\n' "$account" "$category"
        fi
        printf 'description=%s\namount=%s\n' "$description" "$amount"
    } > "$file" || return 1
    printf 'Answer saved: %s\n' "$file"
    submit_file "$file" preview || return 1
    read -r -p 'Submit this proposal for review? [y/N] ' choice || return 1
    [[ "$choice" == [yY] ]] || return 0
    submit_file "$file"
}
menu() {
    local choice account period file sid
    while :; do
        printf '\nnpf-cli\n1) Accounts\n2) Categories\n3) View transactions\n4) View pending\n5) Submission status\n6) New transaction\n7) New transfer/payment\n8) Submit answer file\n9) Preview answer file\n0) Quit\n'
        read -r -p '> ' choice || return 0
        case "$choice" in
            1) accounts || : ;;
            2) categories || : ;;
            3) read -r -p 'Account name (blank = all): ' account || return 0
               read -r -p 'Period (blank = all, e.g. thisMonth or month:2026-11): ' period || return 0
               if [[ -n "$account" ]]; then transactions --account "$account" --period "${period:-all}" || :
               else transactions --period "${period:-all}" || :; fi ;;
            4) pending || : ;;
            5) read -r -p 'Submission ID (blank = all): ' sid || return 0
               status "$sid" || : ;;
            6) compose transaction || : ;;
            7) compose transfer || : ;;
            8|9) read -r -p 'Answer file path: ' file || return 0
                 if [[ "$choice" == 9 ]]; then submit_file "$file" preview || :
                 else submit_file "$file" || :; fi ;;
            0) return ;;
            *) printf 'Choose 0–9.\n' ;;
        esac
    done
}
status() {
    local -a query=()
    [[ -z ${1:-} ]] || query+=(--data-urlencode "submissionId=$1")
    pages /api/integration/submissions submissions "${query[@]}"
}
if [[ ${1:-} == --env ]]; then
    (( $# >= 2 )) || { fail '--env requires a file'; exit 1; }
    ENV_FILE=$2; shift 2
fi
command=${1:-menu}
(( $# == 0 )) || shift
case "$command" in
    help|--help|-h) usage; exit 0 ;;
    example) (( $# <= 1 )) || { usage >&2; exit 1; }; example "${1:-transaction}"; exit 0 ;;
    config) configure "$@"; exit 0 ;;
esac
for dependency in curl jq; do
    command -v "$dependency" >/dev/null || { fail "Install $dependency first"; exit 1; }
done
# Functions called by the menu explicitly propagate failures, since Bash disables
# errexit inside functions used as conditional commands.
case "$command" in
    menu|accounts|categories|pending|new|transfer) (( $# == 0 )) || { usage >&2; exit 1; } ;;
    submit|preview) (( $# == 1 )) || { usage >&2; exit 1; } ;;
    status) (( $# <= 1 )) || { usage >&2; exit 1; } ;;
    transactions) ;;
    *) usage >&2; exit 1 ;;
esac
load_env
case "$command" in
    menu) menu ;; accounts) accounts ;; categories) categories ;; pending) pending ;;
    transactions) transactions "$@" ;; status) status "${1:-}" ;;
    new) compose transaction ;; transfer) compose transfer ;;
    submit|preview) submit_file "$1" "$command" ;;
esac
