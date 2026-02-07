#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-.github/config/repo-settings.json}"

# ─── Phase 1: Validate ───────────────────────────────────────────────────────

echo "=== Phase 1: Validate ==="

if ! command -v jq &>/dev/null; then
  echo "[ERROR] jq is not installed" >&2
  exit 1
fi

if ! command -v gh &>/dev/null; then
  echo "[ERROR] gh CLI is not installed" >&2
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "[ERROR] gh is not authenticated" >&2
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "[ERROR] Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  echo "[ERROR] Config file is not valid JSON: $CONFIG_FILE" >&2
  exit 1
fi

OWNER=$(jq -r '.owner' "$CONFIG_FILE")
REPO=$(jq -r '.repo' "$CONFIG_FILE")
echo "[OK] Config validated for ${OWNER}/${REPO}"

# ─── Phase 2: Apply repo settings ────────────────────────────────────────────

echo ""
echo "=== Phase 2: Apply repo settings ==="

DESIRED_REPO=$(jq -c '.repository' "$CONFIG_FILE")
CURRENT_REPO=$(gh api "repos/${OWNER}/${REPO}" 2>/dev/null)

REPO_DRIFT=false
REPO_PATCH="{}"

for key in $(echo "$DESIRED_REPO" | jq -r 'keys[]'); do
  desired_val=$(echo "$DESIRED_REPO" | jq -c ".[\"$key\"]")
  current_val=$(echo "$CURRENT_REPO" | jq -c ".[\"$key\"]")

  if [ "$desired_val" != "$current_val" ]; then
    echo "[WARN] Drift in repo.$key: current=$current_val desired=$desired_val"
    REPO_PATCH=$(echo "$REPO_PATCH" | jq --argjson v "$desired_val" ". + {\"$key\": \$v}")
    REPO_DRIFT=true
  fi
done

if [ "$REPO_DRIFT" = true ]; then
  echo "[INFO] Patching repository settings..."
  echo "$REPO_PATCH" | gh api "repos/${OWNER}/${REPO}" --method PATCH --input - >/dev/null
  echo "[OK] Repository settings updated"
else
  echo "[OK] Repository settings match — no changes needed"
fi

# ─── Phase 3: Apply Actions permissions ───────────────────────────────────────

echo ""
echo "=== Phase 3: Apply Actions permissions ==="

DESIRED_ACTIONS=$(jq -c '.actions_permissions // empty' "$CONFIG_FILE")

if [ -n "$DESIRED_ACTIONS" ]; then
  CURRENT_ACTIONS=$(gh api "repos/${OWNER}/${REPO}/actions/permissions/workflow" 2>/dev/null)
  ACTIONS_DRIFT=false

  for key in $(echo "$DESIRED_ACTIONS" | jq -r 'keys[]'); do
    desired_val=$(echo "$DESIRED_ACTIONS" | jq -c ".[\"$key\"]")
    current_val=$(echo "$CURRENT_ACTIONS" | jq -c ".[\"$key\"]")
    if [ "$desired_val" != "$current_val" ]; then
      echo "[WARN] Drift in actions.$key: current=$current_val desired=$desired_val"
      ACTIONS_DRIFT=true
    fi
  done

  if [ "$ACTIONS_DRIFT" = true ]; then
    echo "[INFO] Updating Actions workflow permissions..."
    echo "$DESIRED_ACTIONS" | gh api "repos/${OWNER}/${REPO}/actions/permissions/workflow" \
      --method PUT --input - >/dev/null
    echo "[OK] Actions permissions updated"
  else
    echo "[OK] Actions permissions match — no changes needed"
  fi
else
  echo "[SKIP] No actions_permissions in config"
fi

# ─── Phase 4: Apply branch protection ────────────────────────────────────────

echo ""
echo "=== Phase 4: Apply branch protection ==="

BRANCH_COUNT=$(jq '.branch_protection | length' "$CONFIG_FILE")

for i in $(seq 0 $((BRANCH_COUNT - 1))); do
  BRANCH=$(jq -r ".branch_protection[$i].branch" "$CONFIG_FILE")
  echo "--- Branch: $BRANCH ---"

  # Build the desired API payload
  DESIRED_PAYLOAD=$(jq -c ".branch_protection[$i] | del(.branch)" "$CONFIG_FILE")

  # Fetch current protection (404 means none exists)
  HTTP_CODE=$(gh api "repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" \
    --include 2>/dev/null | head -1 | awk '{print $2}') || true
  CURRENT_PROTECTION=$(gh api "repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" 2>/dev/null) || true

  PROTECTION_DRIFT=false

  if [ "$HTTP_CODE" = "404" ] || [ -z "$CURRENT_PROTECTION" ]; then
    echo "[WARN] No branch protection found — will create"
    PROTECTION_DRIFT=true
  else
    # Compare enforce_admins
    desired_enforce=$(echo "$DESIRED_PAYLOAD" | jq '.enforce_admins')
    current_enforce=$(echo "$CURRENT_PROTECTION" | jq '.enforce_admins.enabled')
    if [ "$desired_enforce" != "$current_enforce" ]; then
      echo "[WARN] Drift in enforce_admins: current=$current_enforce desired=$desired_enforce"
      PROTECTION_DRIFT=true
    fi

    # Compare required_status_checks
    desired_checks=$(echo "$DESIRED_PAYLOAD" | jq -c '.required_status_checks')
    if [ "$desired_checks" = "null" ]; then
      current_checks=$(echo "$CURRENT_PROTECTION" | jq -c '.required_status_checks')
      if [ "$current_checks" != "null" ]; then
        echo "[WARN] Drift in required_status_checks: current=$current_checks desired=null"
        PROTECTION_DRIFT=true
      fi
    fi

    # Compare required_pull_request_reviews
    desired_reviews=$(echo "$DESIRED_PAYLOAD" | jq -c '.required_pull_request_reviews')
    if [ "$desired_reviews" != "null" ]; then
      current_approvals=$(echo "$CURRENT_PROTECTION" | jq '.required_pull_request_reviews.required_approving_review_count // empty')
      desired_approvals=$(echo "$desired_reviews" | jq '.required_approving_review_count')
      if [ "$current_approvals" != "$desired_approvals" ]; then
        echo "[WARN] Drift in required_approving_review_count: current=$current_approvals desired=$desired_approvals"
        PROTECTION_DRIFT=true
      fi

      current_dismiss=$(echo "$CURRENT_PROTECTION" | jq '.required_pull_request_reviews.dismiss_stale_reviews // false')
      desired_dismiss=$(echo "$desired_reviews" | jq '.dismiss_stale_reviews')
      if [ "$current_dismiss" != "$desired_dismiss" ]; then
        echo "[WARN] Drift in dismiss_stale_reviews: current=$current_dismiss desired=$desired_dismiss"
        PROTECTION_DRIFT=true
      fi

      current_codeowner=$(echo "$CURRENT_PROTECTION" | jq '.required_pull_request_reviews.require_code_owner_reviews // false')
      desired_codeowner=$(echo "$desired_reviews" | jq '.require_code_owner_reviews')
      if [ "$current_codeowner" != "$desired_codeowner" ]; then
        echo "[WARN] Drift in require_code_owner_reviews: current=$current_codeowner desired=$desired_codeowner"
        PROTECTION_DRIFT=true
      fi

      current_lastpush=$(echo "$CURRENT_PROTECTION" | jq '.required_pull_request_reviews.require_last_push_approval // false')
      desired_lastpush=$(echo "$desired_reviews" | jq '.require_last_push_approval')
      if [ "$current_lastpush" != "$desired_lastpush" ]; then
        echo "[WARN] Drift in require_last_push_approval: current=$current_lastpush desired=$desired_lastpush"
        PROTECTION_DRIFT=true
      fi
    fi

    # Compare restrictions
    desired_restrictions=$(echo "$DESIRED_PAYLOAD" | jq -c '.restrictions')
    if [ "$desired_restrictions" = "null" ]; then
      current_restrictions=$(echo "$CURRENT_PROTECTION" | jq -c '.restrictions')
      if [ "$current_restrictions" != "null" ]; then
        echo "[WARN] Drift in restrictions: current has restrictions, desired=null"
        PROTECTION_DRIFT=true
      fi
    fi

    # Compare boolean flags
    for flag in required_linear_history allow_force_pushes allow_deletions block_creations required_conversation_resolution lock_branch allow_fork_syncing; do
      desired_flag=$(echo "$DESIRED_PAYLOAD" | jq ".$flag")
      current_flag=$(echo "$CURRENT_PROTECTION" | jq ".$flag.enabled // false")
      if [ "$desired_flag" != "$current_flag" ]; then
        echo "[WARN] Drift in $flag: current=$current_flag desired=$desired_flag"
        PROTECTION_DRIFT=true
      fi
    done
  fi

  if [ "$PROTECTION_DRIFT" = true ]; then
    echo "[INFO] Applying branch protection for $BRANCH..."

    # Build the PUT payload in the format the API expects
    PUT_PAYLOAD=$(jq -n \
      --argjson desired "$DESIRED_PAYLOAD" \
      '{
        enforce_admins: $desired.enforce_admins,
        required_status_checks: $desired.required_status_checks,
        required_pull_request_reviews: (
          if $desired.required_pull_request_reviews == null then null
          else {
            required_approving_review_count: $desired.required_pull_request_reviews.required_approving_review_count,
            dismiss_stale_reviews: $desired.required_pull_request_reviews.dismiss_stale_reviews,
            require_code_owner_reviews: $desired.required_pull_request_reviews.require_code_owner_reviews,
            require_last_push_approval: $desired.required_pull_request_reviews.require_last_push_approval
          }
          end
        ),
        restrictions: $desired.restrictions,
        required_linear_history: $desired.required_linear_history,
        allow_force_pushes: $desired.allow_force_pushes,
        allow_deletions: $desired.allow_deletions,
        block_creations: $desired.block_creations,
        required_conversation_resolution: $desired.required_conversation_resolution,
        lock_branch: $desired.lock_branch,
        allow_fork_syncing: $desired.allow_fork_syncing
      }')

    echo "$PUT_PAYLOAD" | gh api "repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" \
      --method PUT --input - >/dev/null
    echo "[OK] Branch protection updated for $BRANCH"
  else
    echo "[OK] Branch protection matches — no changes needed"
  fi
done

# ─── Phase 5: Verify ─────────────────────────────────────────────────────────

echo ""
echo "=== Phase 5: Verify ==="

VERIFY_FAILED=false

# Verify repo settings
VERIFY_REPO=$(gh api "repos/${OWNER}/${REPO}" 2>/dev/null)
for key in $(echo "$DESIRED_REPO" | jq -r 'keys[]'); do
  desired_val=$(echo "$DESIRED_REPO" | jq -c ".[\"$key\"]")
  actual_val=$(echo "$VERIFY_REPO" | jq -c ".[\"$key\"]")
  if [ "$desired_val" != "$actual_val" ]; then
    echo "[FAIL] repo.$key: expected=$desired_val actual=$actual_val"
    VERIFY_FAILED=true
  fi
done

# Verify Actions permissions
if [ -n "$DESIRED_ACTIONS" ]; then
  VERIFY_ACTIONS=$(gh api "repos/${OWNER}/${REPO}/actions/permissions/workflow" 2>/dev/null)
  for key in $(echo "$DESIRED_ACTIONS" | jq -r 'keys[]'); do
    desired_val=$(echo "$DESIRED_ACTIONS" | jq -c ".[\"$key\"]")
    actual_val=$(echo "$VERIFY_ACTIONS" | jq -c ".[\"$key\"]")
    if [ "$desired_val" != "$actual_val" ]; then
      echo "[FAIL] actions.$key: expected=$desired_val actual=$actual_val"
      VERIFY_FAILED=true
    fi
  done
fi

# Verify branch protection
for i in $(seq 0 $((BRANCH_COUNT - 1))); do
  BRANCH=$(jq -r ".branch_protection[$i].branch" "$CONFIG_FILE")
  DESIRED_PAYLOAD=$(jq -c ".branch_protection[$i] | del(.branch)" "$CONFIG_FILE")
  VERIFY_PROTECTION=$(gh api "repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" 2>/dev/null) || true

  if [ -z "$VERIFY_PROTECTION" ]; then
    echo "[FAIL] Branch protection for $BRANCH not found after apply"
    VERIFY_FAILED=true
    continue
  fi

  # Verify enforce_admins
  desired_enforce=$(echo "$DESIRED_PAYLOAD" | jq '.enforce_admins')
  actual_enforce=$(echo "$VERIFY_PROTECTION" | jq '.enforce_admins.enabled')
  if [ "$desired_enforce" != "$actual_enforce" ]; then
    echo "[FAIL] $BRANCH enforce_admins: expected=$desired_enforce actual=$actual_enforce"
    VERIFY_FAILED=true
  fi

  # Verify required_approving_review_count
  desired_reviews=$(echo "$DESIRED_PAYLOAD" | jq -c '.required_pull_request_reviews')
  if [ "$desired_reviews" != "null" ]; then
    desired_approvals=$(echo "$desired_reviews" | jq '.required_approving_review_count')
    actual_approvals=$(echo "$VERIFY_PROTECTION" | jq '.required_pull_request_reviews.required_approving_review_count // empty')
    if [ "$desired_approvals" != "$actual_approvals" ]; then
      echo "[FAIL] $BRANCH required_approving_review_count: expected=$desired_approvals actual=$actual_approvals"
      VERIFY_FAILED=true
    fi
  fi

  # Verify boolean flags
  for flag in required_linear_history allow_force_pushes allow_deletions block_creations required_conversation_resolution lock_branch allow_fork_syncing; do
    desired_flag=$(echo "$DESIRED_PAYLOAD" | jq ".$flag")
    actual_flag=$(echo "$VERIFY_PROTECTION" | jq ".$flag.enabled // false")
    if [ "$desired_flag" != "$actual_flag" ]; then
      echo "[FAIL] $BRANCH $flag: expected=$desired_flag actual=$actual_flag"
      VERIFY_FAILED=true
    fi
  done
done

if [ "$VERIFY_FAILED" = true ]; then
  echo ""
  echo "[ERROR] Verification failed — settings do not match desired state"
  exit 1
fi

echo "[OK] All settings verified successfully"
