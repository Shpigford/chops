#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="FastTalk"
PROJECT_FILE="FastTalk.xcodeproj"
SCHEME="FastTalk"
CONFIGURATION="LocalRelease"
BUILD_ROOT="$ROOT_DIR/build/local-release"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
ARTIFACTS_DIR="$BUILD_ROOT/artifacts"
LOCAL_PRODUCT_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
STAGED_APP_PATH="$ARTIFACTS_DIR/$APP_NAME.app"
PROJECT_SPEC_FILE="$ROOT_DIR/project.yml"
PROJECT_PBXPROJ_PATH="$ROOT_DIR/$PROJECT_FILE/project.pbxproj"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/local-release.sh bundle
  ./scripts/local-release.sh copy <host> [remote_subdir]
  ./scripts/local-release.sh open <host> [remote_subdir]
  ./scripts/local-release.sh restart <host> [remote_subdir]
  ./scripts/local-release.sh copy-and-open <host> [remote_subdir]

Examples:
  ./scripts/local-release.sh bundle
  ./scripts/local-release.sh copy macbook Desktop
  ./scripts/local-release.sh open macbook Desktop
  ./scripts/local-release.sh restart macbook Desktop
  ./scripts/local-release.sh copy-and-open macbook Desktop
EOF
}

log_step() {
  printf '\n==> %s\n' "$1"
}

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

generate_or_validate_project() {
  if command -v xcodegen >/dev/null 2>&1; then
    log_step "Generating Xcode project"
    (
      cd "$ROOT_DIR"
      xcodegen generate
    )
    return
  fi

  [ -f "$PROJECT_PBXPROJ_PATH" ] || fail "xcodegen is not installed and $PROJECT_PBXPROJ_PATH is missing"

  if [ -f "$PROJECT_SPEC_FILE" ] && [ "$PROJECT_SPEC_FILE" -nt "$PROJECT_PBXPROJ_PATH" ]; then
    fail "xcodegen is not installed and $PROJECT_SPEC_FILE is newer than $PROJECT_PBXPROJ_PATH"
  fi

  log_step "Using committed Xcode project (xcodegen not installed)"
}

verify_local_artifact_exists() {
  [ -d "$STAGED_APP_PATH" ] || fail "staged app bundle not found at $STAGED_APP_PATH; run build first"
}

remote_app_path() {
  local remote_subdir="${1:-Desktop}"
  printf '$HOME/%s/%s.app' "$remote_subdir" "$APP_NAME"
}

remote_exec_path() {
  local remote_subdir="${1:-Desktop}"
  printf '$HOME/%s/%s.app/Contents/MacOS/%s' "$remote_subdir" "$APP_NAME" "$APP_NAME"
}

stop_remote_app() {
  local host="${1:-}"
  local remote_subdir="${2:-Desktop}"

  [ -n "$host" ] || fail "remote host is required to stop the app"

  require_command ssh

  local remote_path
  remote_path="$(remote_app_path "$remote_subdir")"
  local remote_exec
  remote_exec="$(remote_exec_path "$remote_subdir")"

  ssh "$host" /bin/bash -s -- "$remote_path" "$remote_exec" <<'EOF'
set -euo pipefail

remote_path="${1/#\$HOME/$HOME}"
remote_exec="${2/#\$HOME/$HOME}"

[ -d "$remote_path" ] || exit 0

if pgrep -f "$remote_exec" >/dev/null 2>&1; then
  echo "Stopping existing app process for $remote_exec"
  pkill -TERM -f "$remote_exec" || true
  for _ in 1 2 3 4 5; do
    if ! pgrep -f "$remote_exec" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if pgrep -f "$remote_exec" >/dev/null 2>&1; then
    echo "Escalating to SIGKILL for $remote_exec"
    pkill -KILL -f "$remote_exec" || true
    sleep 1
  fi
fi

if pgrep -f "$remote_exec" >/dev/null 2>&1; then
  echo "failed to stop existing app process for $remote_exec" >&2
  exit 1
fi
EOF
}

build_local_release() {
  require_command xcodebuild
  require_command ditto
  require_command codesign
  require_command du

  generate_or_validate_project

  log_step "Preparing build directories"
  rm -rf "$BUILD_ROOT"
  mkdir -p "$ARTIFACTS_DIR"

  log_step "Building $APP_NAME ($CONFIGURATION)"
  (
    cd "$ROOT_DIR"
    xcodebuild \
      -project "$PROJECT_FILE" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      clean build
  )

  [ -d "$LOCAL_PRODUCT_PATH" ] || fail "expected app bundle missing at $LOCAL_PRODUCT_PATH"

  log_step "Staging app bundle"
  ditto "$LOCAL_PRODUCT_PATH" "$STAGED_APP_PATH"

  log_step "Verifying local app bundle"
  codesign --verify --deep --strict --verbose=2 "$STAGED_APP_PATH"
  du -sh "$STAGED_APP_PATH"

  printf '\nLocal artifact: %s\n' "$STAGED_APP_PATH"
}

copy_to_remote() {
  local host="${1:-}"
  local remote_subdir="${2:-Desktop}"

  [ -n "$host" ] || fail "remote host is required for copy"

  require_command ssh
  require_command rsync
  verify_local_artifact_exists

  local remote_path
  remote_path="$(remote_app_path "$remote_subdir")"

  log_step "Stopping existing remote app on $host before overwrite"
  stop_remote_app "$host" "$remote_subdir"

  log_step "Preparing remote destination on $host"
  ssh "$host" "mkdir -p \"\$HOME/$remote_subdir\" && rm -rf \"$remote_path\""

  log_step "Copying app bundle to $host"
  rsync -a --delete "$STAGED_APP_PATH/" "$host:\"$remote_path/\""

  log_step "Verifying remote app bundle on $host"
  ssh "$host" "codesign --verify --deep --strict --verbose=2 \"$remote_path\" >/dev/null && ls -ld \"$remote_path\" && du -sh \"$remote_path\""
}

open_remote_app() {
  local host="${1:-}"
  local remote_subdir="${2:-Desktop}"

  [ -n "$host" ] || fail "remote host is required for open"

  require_command ssh

  local remote_path
  remote_path="$(remote_app_path "$remote_subdir")"
  local remote_exec
  remote_exec="$(remote_exec_path "$remote_subdir")"

  log_step "Restarting app bundle on $host"
  stop_remote_app "$host" "$remote_subdir"
  ssh "$host" /bin/bash -s -- "$remote_path" "$remote_exec" <<'EOF'
set -euo pipefail

remote_path="${1/#\$HOME/$HOME}"
remote_exec="${2/#\$HOME/$HOME}"

[ -d "$remote_path" ] || {
  echo "missing remote app bundle at $remote_path" >&2
  exit 1
}

open -na "$remote_path"
sleep 2
pgrep -fal "$remote_exec"
EOF
}

main() {
  local command="${1:-}"

  case "$command" in
    bundle|build)
      build_local_release
      ;;
    copy)
      shift || true
      copy_to_remote "${1:-}" "${2:-Desktop}"
      ;;
    open|restart)
      shift || true
      open_remote_app "${1:-}" "${2:-Desktop}"
      ;;
    copy-and-open)
      shift || true
      copy_to_remote "${1:-}" "${2:-Desktop}"
      open_remote_app "${1:-}" "${2:-Desktop}"
      ;;
    bundle-and-copy|build-and-copy)
      shift || true
      build_local_release
      copy_to_remote "${1:-}" "${2:-Desktop}"
      ;;
    bundle-and-copy-and-open)
      shift || true
      build_local_release
      copy_to_remote "${1:-}" "${2:-Desktop}"
      open_remote_app "${1:-}" "${2:-Desktop}"
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      usage
      fail "unknown command: $command"
      ;;
  esac
}

main "$@"
