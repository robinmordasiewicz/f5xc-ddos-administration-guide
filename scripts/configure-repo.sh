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

# ─── Phase 4: Apply Pages settings ───────────────────────────────────────────

echo ""
echo "=== Phase 4: Apply Pages settings ==="

DESIRED_PAGES=$(jq -c '.pages // empty' "$CONFIG_FILE")

if [ -n "$DESIRED_PAGES" ]; then
  DESIRED_BUILD_TYPE=$(echo "$DESIRED_PAGES" | jq -r '.build_type')
  DESIRED_SOURCE_BRANCH=$(echo "$DESIRED_PAGES" | jq -r '.source.branch')
  DESIRED_SOURCE_PATH=$(echo "$DESIRED_PAGES" | jq -r '.source.path')

  PAGES_HTTP_CODE=$(gh api "repos/${OWNER}/${REPO}/pages" \
    --include 2>/dev/null | head -1 | awk '{print $2}') || true

  if [ "$PAGES_HTTP_CODE" = "404" ]; then
    echo "[WARN] No Pages site found — will create"
    echo "[INFO] Creating Pages site with build_type=$DESIRED_BUILD_TYPE..."
    jq -n \
      --arg build_type "$DESIRED_BUILD_TYPE" \
      --arg branch "$DESIRED_SOURCE_BRANCH" \
      --arg path "$DESIRED_SOURCE_PATH" \
      '{build_type: $build_type, source: {branch: $branch, path: $path}}' \
    | gh api "repos/${OWNER}/${REPO}/pages" --method POST --input - >/dev/null
    echo "[OK] Pages site created"
  else
    CURRENT_PAGES=$(gh api "repos/${OWNER}/${REPO}/pages" 2>/dev/null)
    CURRENT_BUILD_TYPE=$(echo "$CURRENT_PAGES" | jq -r '.build_type')
    CURRENT_SOURCE_BRANCH=$(echo "$CURRENT_PAGES" | jq -r '.source.branch')
    CURRENT_SOURCE_PATH=$(echo "$CURRENT_PAGES" | jq -r '.source.path')

    PAGES_DRIFT=false

    if [ "$DESIRED_BUILD_TYPE" != "$CURRENT_BUILD_TYPE" ]; then
      echo "[WARN] Drift in pages.build_type: current=$CURRENT_BUILD_TYPE desired=$DESIRED_BUILD_TYPE"
      PAGES_DRIFT=true
    fi
    if [ "$DESIRED_SOURCE_BRANCH" != "$CURRENT_SOURCE_BRANCH" ]; then
      echo "[WARN] Drift in pages.source.branch: current=$CURRENT_SOURCE_BRANCH desired=$DESIRED_SOURCE_BRANCH"
      PAGES_DRIFT=true
    fi
    if [ "$DESIRED_SOURCE_PATH" != "$CURRENT_SOURCE_PATH" ]; then
      echo "[WARN] Drift in pages.source.path: current=$CURRENT_SOURCE_PATH desired=$DESIRED_SOURCE_PATH"
      PAGES_DRIFT=true
    fi

    if [ "$PAGES_DRIFT" = true ]; then
      echo "[INFO] Updating Pages settings..."
      jq -n \
        --arg build_type "$DESIRED_BUILD_TYPE" \
        --arg branch "$DESIRED_SOURCE_BRANCH" \
        --arg path "$DESIRED_SOURCE_PATH" \
        '{build_type: $build_type, source: {branch: $branch, path: $path}}' \
      | gh api "repos/${OWNER}/${REPO}/pages" --method PUT --input - >/dev/null
      echo "[OK] Pages settings updated"
    else
      echo "[OK] Pages settings match — no changes needed"
    fi
  fi
else
  echo "[SKIP] No pages in config"
fi

# ─── Phase 5: Apply topics ────────────────────────────────────────────────────

echo ""
echo "=== Phase 5: Apply topics ==="

DESIRED_TOPICS=$(jq -c '.topics.names // empty' "$CONFIG_FILE")

if [ -n "$DESIRED_TOPICS" ]; then
  CURRENT_TOPICS=$(gh api "repos/${OWNER}/${REPO}/topics" --jq '.names' 2>/dev/null)

  DESIRED_SORTED=$(echo "$DESIRED_TOPICS" | jq -c 'sort')
  CURRENT_SORTED=$(echo "$CURRENT_TOPICS" | jq -c 'sort')

  if [ "$DESIRED_SORTED" != "$CURRENT_SORTED" ]; then
    echo "[WARN] Drift in topics: current=$CURRENT_SORTED desired=$DESIRED_SORTED"
    echo "[INFO] Updating repository topics..."
    jq -n --argjson names "$DESIRED_TOPICS" '{names: $names}' \
      | gh api "repos/${OWNER}/${REPO}/topics" --method PUT --input - >/dev/null
    echo "[OK] Topics updated"
  else
    echo "[OK] Topics match — no changes needed"
  fi
else
  echo "[SKIP] No topics in config"
fi

# ─── Phase 6: Apply branch protection ────────────────────────────────────────

echo ""
echo "=== Phase 6: Apply branch protection ==="

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
    current_checks=$(echo "$CURRENT_PROTECTION" | jq -c '.required_status_checks')
    if [ "$desired_checks" != "null" ]; then
      current_contexts=$(echo "$current_checks" | jq -c '.contexts // []' 2>/dev/null || echo '[]')
      desired_contexts=$(echo "$desired_checks" | jq -c '.contexts // []')
      current_strict=$(echo "$current_checks" | jq '.strict // false' 2>/dev/null || echo 'false')
      desired_strict=$(echo "$desired_checks" | jq '.strict // false')
      if [ "$current_checks" = "null" ] || [ "$current_contexts" != "$desired_contexts" ] || [ "$current_strict" != "$desired_strict" ]; then
        echo "[WARN] Drift in required_status_checks: current=$current_checks desired=$desired_checks"
        PROTECTION_DRIFT=true
      fi
    else
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

# ─── Phase 7: Verify ─────────────────────────────────────────────────────────

echo ""
echo "=== Phase 7: Verify ==="

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

# Verify Pages settings
if [ -n "$DESIRED_PAGES" ]; then
  VERIFY_PAGES=$(gh api "repos/${OWNER}/${REPO}/pages" 2>/dev/null) || true
  if [ -z "$VERIFY_PAGES" ]; then
    echo "[FAIL] Pages site not found after apply"
    VERIFY_FAILED=true
  else
    actual_build_type=$(echo "$VERIFY_PAGES" | jq -r '.build_type')
    actual_source_branch=$(echo "$VERIFY_PAGES" | jq -r '.source.branch')
    actual_source_path=$(echo "$VERIFY_PAGES" | jq -r '.source.path')

    if [ "$DESIRED_BUILD_TYPE" != "$actual_build_type" ]; then
      echo "[FAIL] pages.build_type: expected=$DESIRED_BUILD_TYPE actual=$actual_build_type"
      VERIFY_FAILED=true
    fi
    if [ "$DESIRED_SOURCE_BRANCH" != "$actual_source_branch" ]; then
      echo "[FAIL] pages.source.branch: expected=$DESIRED_SOURCE_BRANCH actual=$actual_source_branch"
      VERIFY_FAILED=true
    fi
    if [ "$DESIRED_SOURCE_PATH" != "$actual_source_path" ]; then
      echo "[FAIL] pages.source.path: expected=$DESIRED_SOURCE_PATH actual=$actual_source_path"
      VERIFY_FAILED=true
    fi
  fi
fi

# Verify topics
if [ -n "$DESIRED_TOPICS" ]; then
  VERIFY_TOPICS=$(gh api "repos/${OWNER}/${REPO}/topics" --jq '.names' 2>/dev/null)
  VERIFY_TOPICS_SORTED=$(echo "$VERIFY_TOPICS" | jq -c 'sort')
  DESIRED_TOPICS_SORTED=$(echo "$DESIRED_TOPICS" | jq -c 'sort')
  if [ "$DESIRED_TOPICS_SORTED" != "$VERIFY_TOPICS_SORTED" ]; then
    echo "[FAIL] topics: expected=$DESIRED_TOPICS_SORTED actual=$VERIFY_TOPICS_SORTED"
    VERIFY_FAILED=true
  fi
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
