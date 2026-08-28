#!/usr/bin/env bash
#
# One command from a fresh clone to a working Campus IT org.
#
#   ./scripts/setup-scratch-org.sh
#
# Creates a scratch org, deploys the source, assigns the permission set, seeds sample data,
# runs the Apex tests with coverage, and opens the Campus IT app.
#
# Options:
#   -a, --alias <name>    scratch org alias            (default: campus-it-dev)
#   -d, --days <n>        scratch org duration in days (default: 7)
#       --no-open         do not open the org in a browser
#       --no-tests        skip the test run
#       --keep            reuse an existing org with this alias instead of recreating it
#
# Requires an authenticated Dev Hub:  sf org login web --set-default-dev-hub

set -euo pipefail

ALIAS="campus-it-dev"
DAYS="7"
OPEN_ORG=true
RUN_TESTS=true
RECREATE=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--alias)  ALIAS="$2"; shift 2 ;;
    -d|--days)   DAYS="$2"; shift 2 ;;
    --no-open)   OPEN_ORG=false; shift ;;
    --no-tests)  RUN_TESTS=false; shift ;;
    --keep)      RECREATE=false; shift ;;
    -h|--help)   sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

if ! command -v sf >/dev/null 2>&1; then
  echo "The Salesforce CLI is not installed. See https://developer.salesforce.com/tools/salesforcecli" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

if ! sf org display --target-dev-hub >/dev/null 2>&1; then
  echo "No default Dev Hub. Run: sf org login web --set-default-dev-hub" >&2
  exit 1
fi

if [[ "$RECREATE" == true ]] && sf org display --target-org "$ALIAS" >/dev/null 2>&1; then
  step "Deleting the existing scratch org aliased $ALIAS"
  sf org delete scratch --target-org "$ALIAS" --no-prompt
fi

if ! sf org display --target-org "$ALIAS" >/dev/null 2>&1; then
  step "Creating scratch org $ALIAS for $DAYS days"
  sf org create scratch \
    --definition-file config/project-scratch-org-def.json \
    --alias "$ALIAS" \
    --duration-days "$DAYS" \
    --set-default \
    --wait 20
fi

step "Deploying force-app"
sf project deploy start --source-dir force-app --target-org "$ALIAS" --wait 20

step "Assigning the Campus IT Triage Agent permission set"
sf org assign permset --name Campus_IT_Triage_Agent --target-org "$ALIAS"

step "Seeding sample data"
sf apex run --file scripts/apex/seedSampleData.apex --target-org "$ALIAS"

if [[ "$RUN_TESTS" == true ]]; then
  step "Running Apex tests with code coverage"
  sf apex run test \
    --target-org "$ALIAS" \
    --test-level RunLocalTests \
    --code-coverage \
    --result-format human \
    --wait 20
fi

step "Ready"
echo "Org alias: $ALIAS"
echo "Open the Campus IT app from the App Launcher, or run: sf org open --target-org $ALIAS"

if [[ "$OPEN_ORG" == true ]]; then
  sf org open --target-org "$ALIAS"
fi
