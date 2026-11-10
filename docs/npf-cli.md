# npf-cli.sh

[Back to script index](../README.md) · [Script source](../npf-cli.sh)

Single-file, menu-driven Bash client for the No Part Finance integration API.
Browse account balances, categories, transaction history, pending proposals, and
submission status. Submit ordinary transactions or transfers/payments interactively
or from TXT/JSON answer files. Account and category inputs use exact names, with
IDs resolved internally. Submissions require Owner or Member approval in the
application before they affect balances.

Requires Bash 4+, `curl`, `jq`, and standard Unix utilities. No separate example
files or `.env` file are needed.

## Install and configure

```bash
curl -fL -o npf-cli.sh https://raw.githubusercontent.com/ajpri/linux-scripts/main/npf-cli.sh
chmod +x npf-cli.sh
./npf-cli.sh
```

The first interactive run prompts for the HTTPS API URL and integration key, then
opens the menu. The key prompt hides input. Configuration is saved privately in
`~/.config/npf-cli/config` (or `$XDG_CONFIG_HOME/npf-cli/config`). There is no
default API URL: enter the HTTPS base URL for your own No Part Finance deployment,
for example `https://finance.example.com`. The example is a placeholder. Existing
saved URLs and integration keys continue to work; blank answers keep existing
values. A missing URL triggers setup in an interactive session or an actionable
configuration error in a noninteractive run, before any API request is sent.

```bash
./npf-cli.sh config                          # Configure URL and key
./npf-cli.sh config url https://finance.example.com
./npf-cli.sh config key                      # Hidden key prompt
./npf-cli.sh config show                     # Shows URL; never prints the key
./npf-cli.sh help
```

`--env FILE` before the command selects an optional alternative configuration file
for automation. Existing literal `EXPTRACK_BASE_URL`, `EXPTRACK_API_KEY`,
`EXPTRACK_TIMEOUT`, and `EXPTRACK_PAGE_SIZE` settings remain supported. Values are
never executed as shell code. Keep credentials out of Git and avoid `bash -x`,
which can expose them.

## Browse and submit

```bash
./npf-cli.sh accounts
./npf-cli.sh categories
./npf-cli.sh transactions --account 'Checking' --period thisMonth
./npf-cli.sh transactions --category 'Recurring Needs' --start 2026-10-01 --end 2026-10-31
./npf-cli.sh pending
./npf-cli.sh status
./npf-cli.sh new
./npf-cli.sh transfer
```

Account balances show credit debt as a positive amount labeled `owed`, and
positive overpayment balances as `credit`. History uses the API's display amounts,
retaining negative refunds and income reversals. Names are case-sensitive;
unknown, ambiguous, or ineligible submission names are rejected. History and
status results are paginated; terminal users choose whether to fetch another
page, while redirected input fetches all pages.

## Answer files and built-in examples

```bash
./npf-cli.sh example > groceries.txt
./npf-cli.sh example transfer > transfer.txt
./npf-cli.sh example json > groceries.json
# Edit dates, names, descriptions, and amounts before previewing/submitting.
./npf-cli.sh preview groceries.txt
./npf-cli.sh submit groceries.txt
```

The default example is one ordinary transaction in literal `key=value` text:

```text
type=transaction
date=2026-11-04
account=Checking
category=Groceries
description=Weekly groceries
amount=50.00
```

Use one proposal per text file. Blank lines and full-line `#` comments are allowed;
values need no quotes or escaping. JSON accepts an object or an array of proposals;
amounts must be strings. Transfers use `type=transfer`, `fromAccount`, and
`toAccount`, with no category. Dates must be explicit `YYYY-MM-DD` calendar dates.
Entered USD amounts accept up to two decimal places: ordinary expenses and income
are positive, refunds and income reversals are negative, and transfers are
strictly positive.

`submissionId` is optional. The script generates missing IDs and saves them in a
private `<answer-file>.exptrack-state.json` companion before submitting. Keep that
file with the unchanged answer file for retries, especially after a timeout.
`preview` reads the catalogs and saves retry state without sending a proposal.
Changed content with generated retry state is rejected; use a new answer file
for a new transaction. Do not discard retry state to retry an uncertain request,
as doing so could create a duplicate proposal.

Interactive answers and their retry state are stored under
`~/.local/state/npf-cli/answers` (or `$XDG_STATE_HOME/npf-cli/answers`). JSON batches
are validated before sending, then submitted individually; batches are not atomic.
An error stops further submissions, and earlier items may already have succeeded.
