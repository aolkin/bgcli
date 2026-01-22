#!/usr/bin/env bash
set -euo pipefail

# Variables and constants
REPO="aolkin/bgcli"
ARTIFACT_NAME="bgcli-macos"
ZIP_NAME="bgcli-macos.zip"
APP_NAME="bgcli.app"
DEFAULT_INSTALL_DIR="$HOME/Applications"
TEMP_DIR=""

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Options
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
VERBOSE=false

# Cleanup function
cleanup() {
  if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}

trap cleanup EXIT

# Print functions
print_error() {
  echo -e "${RED}Error: $1${NC}" >&2
}

print_success() {
  echo -e "${GREEN}$1${NC}"
}

print_info() {
  echo -e "${BLUE}$1${NC}"
}

print_warning() {
  echo -e "${YELLOW}$1${NC}"
}

print_verbose() {
  if [[ "$VERBOSE" == true ]]; then
    echo -e "${BLUE}[VERBOSE] $1${NC}"
  fi
}

print_help() {
  cat << EOF
bgcli Installation Script

Usage: $0 [VERSION|PR_NUMBER] [OPTIONS]

Arguments:
  (none)          Install latest stable release
  PR_NUMBER       Install latest artifact from PR (e.g., 42)
  VERSION         Install specific version tag (e.g., v1.0.0)

Options:
  --system            Install to /Applications (requires sudo)
  --output-dir PATH   Install to custom directory
  --verbose           Show detailed progress
  --help              Display this help message

Examples:
  $0                      # Install latest release
  $0 42                   # Install from PR #42
  $0 v1.0.0               # Install version v1.0.0
  $0 --system             # Install to /Applications
  $0 --output-dir ~/tools # Install to custom directory

Exit Codes:
  0 - Success
  1 - General error
  2 - Missing dependencies
  3 - Authentication error
  4 - Download failed
  5 - Extraction failed
  6 - Installation failed
  7 - User cancelled

For more information, visit: https://github.com/$REPO
EOF
}

# Check dependencies
check_dependencies() {
  print_verbose "Checking for required dependencies..."

  if ! command -v gh &> /dev/null; then
    print_error "GitHub CLI (gh) is not installed."
    echo ""
    echo "Please install it from: https://cli.github.com/"
    echo ""
    echo "macOS installation:"
    echo "  brew install gh"
    exit 2
  fi

  print_verbose "Checking gh authentication status..."
  if ! gh auth status &> /dev/null; then
    print_error "GitHub CLI is not authenticated."
    echo ""
    echo "Please authenticate with:"
    echo "  gh auth login"
    exit 3
  fi

  if ! command -v unzip &> /dev/null; then
    print_error "unzip is not installed (this should not happen on macOS)."
    exit 2
  fi

  print_verbose "All dependencies satisfied."
}

# Parse arguments
parse_arguments() {
  local download_mode="latest"
  local download_arg=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --help)
        print_help
        exit 0
        ;;
      --system)
        INSTALL_DIR="/Applications"
        shift
        ;;
      --output-dir)
        if [[ -z "${2:-}" ]]; then
          print_error "--output-dir requires a path argument"
          exit 1
        fi
        INSTALL_DIR="$2"
        shift 2
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      -*)
        print_error "Unknown option: $1"
        echo "Run '$0 --help' for usage information."
        exit 1
        ;;
      *)
        if [[ -n "$download_arg" ]]; then
          print_error "Multiple version/PR arguments provided: $download_arg and $1"
          exit 1
        fi
        download_arg="$1"
        # Determine download mode
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          download_mode="pr"
        elif [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
          download_mode="version"
        else
          print_error "Invalid argument: $1"
          echo "Expected a PR number (e.g., 42) or version tag (e.g., v1.0.0)"
          exit 1
        fi
        shift
        ;;
    esac
  done

  echo "$download_mode:$download_arg"
}

# Download from release
download_release() {
  local version="${1:-}"

  print_verbose "Creating temporary directory..."
  TEMP_DIR=$(mktemp -d)

  if [[ -z "$version" ]]; then
    print_info "Downloading latest release..."
    if ! gh release download --repo "$REPO" --pattern "$ZIP_NAME" --dir "$TEMP_DIR" 2>&1; then
      print_error "Failed to download latest release."
      echo "Please verify that releases exist at: https://github.com/$REPO/releases"
      exit 4
    fi
  else
    print_info "Downloading release $version..."
    if ! gh release download "$version" --repo "$REPO" --pattern "$ZIP_NAME" --dir "$TEMP_DIR" 2>&1; then
      print_error "Failed to download release $version."
      echo "Please verify that the release exists at: https://github.com/$REPO/releases/tag/$version"
      exit 4
    fi
  fi

  print_verbose "Download completed to $TEMP_DIR"
}

# Download from PR artifact
download_pr_artifact() {
  local pr_number="$1"

  print_verbose "Creating temporary directory..."
  TEMP_DIR=$(mktemp -d)

  print_info "Finding latest workflow run for PR #$pr_number..."

  # Find the most recent workflow run for the PR
  local run_id
  run_id=$(gh run list --repo "$REPO" \
    --limit 100 \
    --json databaseId,status,event,headBranch,conclusion \
    --jq "[.[] | select(.event==\"pull_request\" and (.headBranch | contains(\"/$pr_number/\")) and .conclusion==\"success\")] | .[0].databaseId" 2>&1)

  if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    print_error "No successful workflow runs found for PR #$pr_number."
    echo "Please verify that:"
    echo "  1. PR #$pr_number exists"
    echo "  2. The build workflow has completed successfully"
    echo ""
    echo "View PR at: https://github.com/$REPO/pull/$pr_number"
    exit 4
  fi

  print_verbose "Found workflow run: $run_id"
  print_info "Downloading artifact from workflow run $run_id..."

  if ! gh run download "$run_id" --repo "$REPO" --name "$ARTIFACT_NAME" --dir "$TEMP_DIR" 2>&1; then
    print_error "Failed to download artifact from PR #$pr_number."
    echo "Please verify that the artifact '$ARTIFACT_NAME' exists for this run."
    exit 4
  fi

  print_verbose "Download completed to $TEMP_DIR"
}

# Extract and prepare
extract_and_prepare() {
  print_info "Extracting application..."

  local zip_path="$TEMP_DIR/$ZIP_NAME"

  # Verify download succeeded
  if [[ ! -f "$zip_path" ]]; then
    print_error "Downloaded file not found: $zip_path"
    exit 5
  fi

  if [[ ! -s "$zip_path" ]]; then
    print_error "Downloaded file is empty: $zip_path"
    exit 5
  fi

  print_verbose "Unzipping $zip_path..."

  # Extract zip
  if ! unzip -q "$zip_path" -d "$TEMP_DIR" 2>&1; then
    print_error "Failed to extract zip file. The file may be corrupted."
    exit 5
  fi

  # Verify bgcli.app exists
  if [[ ! -d "$TEMP_DIR/$APP_NAME" ]]; then
    print_error "Expected app bundle not found: $APP_NAME"
    echo "Contents of download:"
    ls -la "$TEMP_DIR"
    exit 5
  fi

  print_verbose "Removing quarantine attribute..."
  # Remove quarantine attribute
  xattr -cr "$TEMP_DIR/$APP_NAME" 2>/dev/null || true

  print_verbose "Extraction completed successfully."
}

# Handle existing installation
handle_existing_install() {
  local target_path="$INSTALL_DIR/$APP_NAME"

  if [[ -d "$target_path" ]]; then
    print_warning "Existing installation found at: $target_path"
    print_info "Removing old version..."

    if [[ "$INSTALL_DIR" == "/Applications" ]]; then
      if ! sudo rm -rf "$target_path"; then
        print_error "Failed to remove existing installation (requires sudo)."
        exit 6
      fi
    else
      if ! rm -rf "$target_path"; then
        print_error "Failed to remove existing installation."
        exit 6
      fi
    fi

    print_verbose "Old version removed."
  fi
}

# Install app
install_app() {
  print_info "Installing to $INSTALL_DIR..."

  # Create install directory if it doesn't exist
  if [[ ! -d "$INSTALL_DIR" ]]; then
    print_verbose "Creating directory: $INSTALL_DIR"

    if [[ "$INSTALL_DIR" == "/Applications" ]]; then
      if ! sudo mkdir -p "$INSTALL_DIR"; then
        print_error "Failed to create installation directory (requires sudo)."
        exit 6
      fi
    else
      if ! mkdir -p "$INSTALL_DIR"; then
        print_error "Failed to create installation directory."
        exit 6
      fi
    fi
  fi

  # Move app to install directory
  local source_path="$TEMP_DIR/$APP_NAME"
  local target_path="$INSTALL_DIR/$APP_NAME"

  print_verbose "Moving $source_path to $target_path..."

  if [[ "$INSTALL_DIR" == "/Applications" ]]; then
    if ! sudo mv "$source_path" "$target_path"; then
      print_error "Failed to install application (requires sudo)."
      exit 6
    fi
  else
    if ! mv "$source_path" "$target_path"; then
      print_error "Failed to install application."
      exit 6
    fi
  fi

  # Verify installation
  if [[ ! -d "$target_path" ]]; then
    print_error "Installation verification failed. App not found at: $target_path"
    exit 6
  fi

  print_verbose "Installation completed successfully."
}

# Main execution
main() {
  # Handle help flag early (before banner)
  for arg in "$@"; do
    if [[ "$arg" == "--help" ]]; then
      print_help
      exit 0
    fi
  done

  echo ""
  print_info "╔══════════════════════════════════════╗"
  print_info "║   bgcli Installation Script          ║"
  print_info "╚══════════════════════════════════════╝"
  echo ""

  # Parse arguments
  local mode_arg
  mode_arg=$(parse_arguments "$@")
  local download_mode="${mode_arg%%:*}"
  local download_arg="${mode_arg#*:}"

  print_verbose "Download mode: $download_mode"
  print_verbose "Install directory: $INSTALL_DIR"

  # Check dependencies
  check_dependencies

  # Download based on mode
  case "$download_mode" in
    latest)
      download_release
      ;;
    version)
      download_release "$download_arg"
      ;;
    pr)
      download_pr_artifact "$download_arg"
      ;;
  esac

  # Extract and prepare
  extract_and_prepare

  # Handle existing installation
  handle_existing_install

  # Install
  install_app

  # Success message
  echo ""
  print_success "╔══════════════════════════════════════╗"
  print_success "║   Installation Complete! ✓           ║"
  print_success "╚══════════════════════════════════════╝"
  echo ""
  print_info "bgcli has been installed to:"
  echo "  $INSTALL_DIR/$APP_NAME"
  echo ""
  print_info "You can now launch bgcli from your Applications folder."
  echo ""
}

# Run main
main "$@"
