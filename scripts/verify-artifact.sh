#!/usr/bin/env bash
#
# Verify a distribution artifact before it reaches anyone.
#
#   scripts/verify-artifact.sh path/to/Errol.app [--golden FILE]
#   scripts/verify-artifact.sh path/to/Errol.dmg
#
# --golden defaults to the repo's Config/designated-requirement.txt, found from
# this script's own directory, so the check does not depend on the working
# directory. An app is always held to it: a missing golden file is a failure,
# never a skipped check.
#
# Read-only: every check here inspects, none of them re-sign or modify the
# artifact. Safe to run against an installed copy.
#
# The identity checks exist because Errol is useless without its Accessibility
# grant, and macOS keys that grant to the app's designated requirement. If the
# requirement drifts, every existing user silently loses the permission on their
# next update. This script is the gate that stops that shipping.

set -euo pipefail

EXPECTED_BUNDLE_ID="com.t7m8.Errol"
EXPECTED_TEAM_ID="${ERROL_TEAM_ID:-JN3SN725AZ}"
GOLDEN_REQ=""
ARTIFACT=""
FAILURES=0
REVIEW_EVENTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --golden) GOLDEN_REQ="$2"; shift 2 ;;
    --team)   EXPECTED_TEAM_ID="$2"; shift 2 ;;
    *)        ARTIFACT="$1"; shift ;;
  esac
done

[[ -n "$ARTIFACT" ]] || { echo "usage: $0 <Errol.app|Errol.dmg> [--golden FILE] [--team ID]" >&2; exit 2; }
[[ -e "$ARTIFACT" ]] || { echo "no such artifact: $ARTIFACT" >&2; exit 2; }
[[ -n "$GOLDEN_REQ" ]] || GOLDEN_REQ="$(cd "$(dirname "$0")/.." && pwd)/Config/designated-requirement.txt"

pass() { printf '  \033[32mok\033[0m    %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
note() { printf '  \033[33mREVIEW\033[0m %s\n' "$1"; REVIEW_EVENTS=$((REVIEW_EVENTS + 1)); }

echo "Verifying $ARTIFACT"
echo

# --- 1. Signature integrity ------------------------------------------------
echo "Signature"
if codesign --verify --deep --strict --verbose=2 "$ARTIFACT" 2>&1 | grep -q "satisfies its Designated Requirement"; then
  pass "signature valid, satisfies its own designated requirement"
else
  codesign --verify --deep --strict --verbose=2 "$ARTIFACT" 2>&1 | sed 's/^/        /' || true
  fail "codesign --verify --deep --strict"
fi

# Everything below reads the app bundle; for a DMG we only assess the container.
if [[ "$ARTIFACT" == *.app ]]; then
  SIGN_INFO="$(codesign -dv --verbose=4 "$ARTIFACT" 2>&1)"

  # --- 2. Bundle identifier, asserted independently ------------------------
  ACTUAL_ID="$(printf '%s\n' "$SIGN_INFO" | awk -F= '/^Identifier=/{print $2}')"
  if [[ "$ACTUAL_ID" == "$EXPECTED_BUNDLE_ID" ]]; then
    pass "bundle identifier is $ACTUAL_ID"
  else
    fail "bundle identifier is '$ACTUAL_ID', expected '$EXPECTED_BUNDLE_ID'"
  fi

  # --- 3. Team identifier, asserted independently --------------------------
  ACTUAL_TEAM="$(printf '%s\n' "$SIGN_INFO" | awk -F= '/^TeamIdentifier=/{print $2}')"
  if [[ "$ACTUAL_TEAM" == "$EXPECTED_TEAM_ID" ]]; then
    pass "team identifier is $ACTUAL_TEAM"
  else
    fail "team identifier is '$ACTUAL_TEAM', expected '$EXPECTED_TEAM_ID'"
  fi

  # --- 4. Hardened runtime, required for notarization ----------------------
  if printf '%s\n' "$SIGN_INFO" | grep -q "flags=.*runtime"; then
    pass "hardened runtime enabled"
  else
    fail "hardened runtime flag absent (notarization will reject this)"
  fi

  # --- 5. get-task-allow must be absent from a distribution build ----------
  ENTITLEMENTS="$(codesign -d --entitlements - --xml "$ARTIFACT" 2>/dev/null || true)"
  if printf '%s\n' "$ENTITLEMENTS" | grep -q "get-task-allow"; then
    fail "com.apple.security.get-task-allow present -- this is a development build"
  else
    pass "get-task-allow absent"
  fi

  # --- 6. Designated requirement -------------------------------------------
  ACTUAL_DR="$(codesign -d -r- "$ARTIFACT" 2>&1 | sed -n 's/^designated => //p' | tr -s '[:space:]' ' ' | sed 's/ *$//')"
  echo
  echo "Designated requirement"
  echo "        $ACTUAL_DR"

  if [[ -f "$GOLDEN_REQ" ]]; then
    GOLDEN_TEXT="$(tr -s '[:space:]' ' ' < "$GOLDEN_REQ" | sed 's/^ *//; s/ *$//')"

    # 6a. Semantic gate: does this artifact actually satisfy the committed
    #     requirement? This is the check that matters -- it is what the
    #     privacy system effectively asks on every launch.
    if codesign --verify -R="$GOLDEN_TEXT" "$ARTIFACT" >/dev/null 2>&1; then
      pass "artifact satisfies the committed designated requirement"
    else
      fail "artifact does NOT satisfy the committed requirement -- installed users will lose Accessibility"
    fi

    # 6b. Textual drift: a difference here does not necessarily break anything
    #     (codesign's output formatting can shift between Xcode releases), but
    #     it means the identity expression changed and a human must look.
    if [[ "$ACTUAL_DR" == "$GOLDEN_TEXT" ]]; then
      pass "requirement text matches the golden expression exactly"
    else
      note "requirement text differs from the golden expression -- release-blocking review"
      printf '        golden: %s\n' "$GOLDEN_TEXT"
      printf '        actual: %s\n' "$ACTUAL_DR"
    fi
  else
    fail "golden requirement $GOLDEN_REQ not found -- cannot check the designated requirement"
  fi
fi

# --- 7. Gatekeeper assessment ---------------------------------------------
echo
echo "Gatekeeper and notarization"
case "$ARTIFACT" in
  *.app) SPCTL_TYPE=(-t exec) ;;
  *.dmg) SPCTL_TYPE=(-t open --context context:primary-signature) ;;
  *)     SPCTL_TYPE=(-t exec) ;;
esac
if spctl -a -vvv "${SPCTL_TYPE[@]}" "$ARTIFACT" 2>&1 | grep -qE "accepted"; then
  SOURCE="$(spctl -a -vvv "${SPCTL_TYPE[@]}" "$ARTIFACT" 2>&1 | awk -F= '/source=/{print $2}')"
  pass "Gatekeeper accepts it (source: ${SOURCE:-unknown})"
else
  spctl -a -vvv "${SPCTL_TYPE[@]}" "$ARTIFACT" 2>&1 | sed 's/^/        /' || true
  fail "Gatekeeper rejected the artifact"
fi

# --- 8. Stapled notarization ticket ---------------------------------------
if xcrun stapler validate "$ARTIFACT" >/dev/null 2>&1; then
  pass "notarization ticket is stapled"
else
  fail "no stapled ticket (first launch will need a network round trip, or be blocked)"
fi

echo
if [[ $FAILURES -gt 0 ]]; then
  printf '\033[31m%d check(s) failed.\033[0m Do not publish this artifact.\n' "$FAILURES"
  exit 1
fi
if [[ $REVIEW_EVENTS -gt 0 ]]; then
  printf '\033[33mAll checks passed, %d item(s) need human review before publishing.\033[0m\n' "$REVIEW_EVENTS"
  exit 0
fi
printf '\033[32mAll checks passed.\033[0m\n'
