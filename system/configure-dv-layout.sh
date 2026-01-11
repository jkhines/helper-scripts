#!/usr/bin/env bash
#
# configure-dv-layout.sh
#
# Creates a standalone "dv" XKB layout code for US Dvorak on Pop!_OS 24.04
# with COSMIC desktop, and configures COSMIC to use it as a separate input source.
#
# Usage:
#   ./configure-dv-layout.sh [--apply]   # Default: apply changes (--apply is optional)
#   ./configure-dv-layout.sh --rollback  # Restore from backups and remove dv layout
#
# Requirements:
#   - Pop!_OS 24.04 with COSMIC desktop
#   - sudo privileges
#   - Standard tools: bash, coreutils, grep, sed, awk
#   - Optional: xmlstarlet (for cleaner XML editing)
#
# Testing / Verification:
#   - Check dv symbols file exists: ls -la /usr/share/X11/xkb/symbols/dv
#   - Check evdev.lst has dv: grep -E '^[[:space:]]*dv[[:space:]]' /usr/share/X11/xkb/rules/evdev.lst
#   - Check evdev.xml has dv: grep -A2 '<name>dv</name>' /usr/share/X11/xkb/rules/evdev.xml
#   - Check COSMIC config: grep layout ~/.config/cosmic/com.system76.CosmicComp/v1/xkb_config
#
# Backups are stored with timestamps in the same directory as the original files.
# Backup naming: <filename>.backup-YYYYMMDD-HHMMSS
#

set -euo pipefail

# Configuration paths
XKB_SYMBOLS_DIR="/usr/share/X11/xkb/symbols"
XKB_RULES_DIR="/usr/share/X11/xkb/rules"
DV_SYMBOLS_FILE="${XKB_SYMBOLS_DIR}/dv"
EVDEV_XML="${XKB_RULES_DIR}/evdev.xml"
EVDEV_LST="${XKB_RULES_DIR}/evdev.lst"
BASE_XML="${XKB_RULES_DIR}/base.xml"
BASE_LST="${XKB_RULES_DIR}/base.lst"
COSMIC_CONFIG_DIR="${HOME}/.config/cosmic/com.system76.CosmicComp/v1"
COSMIC_XKB_CONFIG="${COSMIC_CONFIG_DIR}/xkb_config"

# Backup directory tracking file (stores paths of backups for rollback)
BACKUP_MANIFEST="${HOME}/.config/cosmic/.dv-layout-backups"

# Timestamp for backups
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

die() {
    log_error "$1"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check XKB directories exist
    [[ -d "$XKB_SYMBOLS_DIR" ]] || die "XKB symbols directory not found: $XKB_SYMBOLS_DIR"
    [[ -d "$XKB_RULES_DIR" ]] || die "XKB rules directory not found: $XKB_RULES_DIR"

    # Check required files exist
    [[ -f "$EVDEV_XML" ]] || die "evdev.xml not found: $EVDEV_XML"
    [[ -f "$EVDEV_LST" ]] || die "evdev.lst not found: $EVDEV_LST"
    [[ -f "$BASE_XML" ]] || die "base.xml not found: $BASE_XML"
    [[ -f "$BASE_LST" ]] || die "base.lst not found: $BASE_LST"

    # Check us(dvorak) exists in XKB symbols
    [[ -f "${XKB_SYMBOLS_DIR}/us" ]] || die "US symbols file not found: ${XKB_SYMBOLS_DIR}/us"
    grep -q 'xkb_symbols.*"dvorak"' "${XKB_SYMBOLS_DIR}/us" || die "dvorak variant not found in US symbols"

    # Check COSMIC config directory exists or can be created
    if [[ ! -d "$COSMIC_CONFIG_DIR" ]]; then
        log_warn "COSMIC config directory does not exist: $COSMIC_CONFIG_DIR"
        log_warn "Will create it when applying configuration."
    fi

    # Check for sudo
    if ! command -v sudo &>/dev/null; then
        die "sudo is required but not found"
    fi

    log_info "Prerequisites check passed."
}

# Create backup of a file and record it in manifest
backup_file() {
    local file="$1"
    local backup_path="${file}.backup-${TIMESTAMP}"

    if [[ -f "$file" ]]; then
        if [[ "$file" == /usr/* ]]; then
            sudo cp -p "$file" "$backup_path"
        else
            cp -p "$file" "$backup_path"
        fi
        log_info "Backed up: $file -> $backup_path"
        echo "$backup_path" >> "$BACKUP_MANIFEST"
    fi
}

# Initialize backup manifest
init_backup_manifest() {
    mkdir -p "$(dirname "$BACKUP_MANIFEST")"
    echo "# DV Layout Backups - $TIMESTAMP" > "$BACKUP_MANIFEST"
}

# Create the dv symbols file
create_dv_symbols() {
    log_info "Creating dv symbols file..."

    if [[ -f "$DV_SYMBOLS_FILE" ]]; then
        if grep -q 'include.*us(dvorak)' "$DV_SYMBOLS_FILE" 2>/dev/null; then
            log_info "dv symbols file already exists with correct content. Skipping."
            return 0
        else
            backup_file "$DV_SYMBOLS_FILE"
        fi
    fi

    local symbols_content='// DV layout - standalone Dvorak layout code
// Maps to existing us(dvorak) symbols

default partial alphanumeric_keys
xkb_symbols "basic" {
    include "us(dvorak)"
    name[Group1] = "English (DV)";
};
'

    echo "$symbols_content" | sudo tee "$DV_SYMBOLS_FILE" > /dev/null
    sudo chmod 644 "$DV_SYMBOLS_FILE"
    log_info "Created: $DV_SYMBOLS_FILE"
}

# Add dv to an XKB rules .lst file (evdev.lst/base.lst)
add_layout_to_lst() {
    local lst_file="$1"
    local label="$2"

    log_info "Adding dv to ${label}..."

    if grep -qE '^[[:space:]]*dv[[:space:]]+' "$lst_file"; then
        log_info "dv already present in ${label}. Skipping."
        return 0
    fi

    backup_file "$lst_file"

    local tmp_file
    tmp_file="$(mktemp "/tmp/$(basename "$lst_file").XXXX")"

    sudo awk '
    /^! layout/ { print; in_layout = 1; next }
    in_layout && /^[[:space:]]+[a-z]/ && !added {
        print
        print "  dv              English (Dvorak)"
        added = 1
        next
    }
    /^!/ && in_layout { in_layout = 0 }
    { print }
    ' "$lst_file" > "$tmp_file"

    sudo mv "$tmp_file" "$lst_file"
    sudo chmod 644 "$lst_file"

    if grep -qE '^[[:space:]]*dv[[:space:]]+' "$lst_file"; then
        log_info "Successfully added dv to ${label}"
    else
        die "Failed to add dv to ${label}"
    fi
}

# Shared XML block for new layout
DV_LAYOUT_XML_BLOCK='    <layout>
      <configItem>
        <name>dv</name>
        <shortDescription>dv</shortDescription>
        <description>English (Dvorak)</description>
        <languageList>
          <iso639Id>eng</iso639Id>
        </languageList>
      </configItem>
    </layout>'

# Add dv to an XKB rules .xml file (evdev.xml/base.xml)
add_layout_to_xml() {
    local xml_file="$1"
    local label="$2"

    log_info "Adding dv to ${label}..."

    if grep -q '<name>dv</name>' "$xml_file"; then
        log_info "dv already present in ${label}. Skipping."
        return 0
    fi

    backup_file "$xml_file"

    if command -v xmlstarlet &>/dev/null; then
        log_info "Using xmlstarlet for XML editing..."
        sudo xmlstarlet ed -L \
            -s "//layoutList" -t elem -n "layout" -v "" \
            -s "//layoutList/layout[last()]" -t elem -n "configItem" -v "" \
            -s "//layoutList/layout[last()]/configItem" -t elem -n "name" -v "dv" \
            -s "//layoutList/layout[last()]/configItem" -t elem -n "shortDescription" -v "dv" \
            -s "//layoutList/layout[last()]/configItem" -t elem -n "description" -v "English (Dvorak)" \
            -s "//layoutList/layout[last()]/configItem" -t elem -n "languageList" -v "" \
            -s "//layoutList/layout[last()]/configItem/languageList" -t elem -n "iso639Id" -v "eng" \
            "$xml_file"
    else
        log_info "xmlstarlet not found. Using sed/awk for XML editing..."
        local tmp_file
        tmp_file="$(mktemp "/tmp/$(basename "$xml_file").XXXX")"
        sudo awk -v block="$DV_LAYOUT_XML_BLOCK" '
        /<\/layoutList>/ { print block }
        { print }
        ' "$xml_file" > "$tmp_file"

        sudo mv "$tmp_file" "$xml_file"
        sudo chmod 644 "$xml_file"
    fi

    if grep -q '<name>dv</name>' "$xml_file"; then
        log_info "Successfully added dv to ${label}"
    else
        die "Failed to add dv to ${label}"
    fi
}

# Configure COSMIC XKB settings
configure_cosmic() {
    log_info "Configuring COSMIC compositor XKB settings..."

    # Create directory if it doesn't exist
    mkdir -p "$COSMIC_CONFIG_DIR"

    if [[ -f "$COSMIC_XKB_CONFIG" ]]; then
        # Check if already configured with dv
        if grep -qE 'layout:\s*"us,dv"' "$COSMIC_XKB_CONFIG"; then
            log_info "COSMIC already configured with us,dv layout. Skipping."
            return 0
        fi
        backup_file "$COSMIC_XKB_CONFIG"

        # Warn if "dk" (Danish) is found - common typo for "dv" (Dvorak)
        if grep -qE 'layout:\s*"[^"]*dk' "$COSMIC_XKB_CONFIG"; then
            log_warn "Found 'dk' (Danish) in layout - this may be a typo for 'dv' (Dvorak)"
        fi

        # COSMIC uses RON format (Rusty Object Notation), not JSON
        # Format: layout: "us,us", variant: "dvorak,", etc.
        # Update layout to us,dv and variant to "," (empty variants for both)
        # Apply both transformations in a single pass to avoid issues
        sed -i -E \
            -e 's/(layout:\s*)"[^"]*"/\1"us,dv"/' \
            -e 's/(variant:\s*)"[^"]*"/\1","/' \
            "$COSMIC_XKB_CONFIG"

        log_info "Updated COSMIC xkb_config with us,dv layout"
    else
        # Create new config file in RON format
        local new_config='(
    rules: "",
    model: "",
    layout: "us,dv",
    variant: ",",
    options: None,
    repeat_delay: 600,
    repeat_rate: 25,
)'
        echo "$new_config" > "$COSMIC_XKB_CONFIG"
        log_info "Created new COSMIC xkb_config with us,dv layout"
    fi

    # Verify
    if grep -qE 'layout:\s*"us,dv"' "$COSMIC_XKB_CONFIG"; then
        log_info "COSMIC configuration verified."
    else
        die "Failed to configure COSMIC xkb_config"
    fi
}

# Remove dv entries from an XKB rules .lst file
remove_from_lst() {
    local lst_file="$1"
    local label="$2"

    log_info "Removing dv from ${label}..."

    if ! grep -qE '^[[:space:]]*dv[[:space:]]+' "$lst_file"; then
        log_info "dv not present in ${label}. Skipping."
        return 0
    fi

    sudo sed -i '/^[[:space:]]*dv[[:space:]]\+/d' "$lst_file"
    log_info "Removed dv from ${label}"
}

# Remove dv entries from an XKB rules .xml file
remove_from_xml() {
    local xml_file="$1"
    local label="$2"

    log_info "Removing dv from ${label}..."

    if ! grep -q '<name>dv</name>' "$xml_file"; then
        log_info "dv not present in ${label}. Skipping."
        return 0
    fi

    if command -v xmlstarlet &>/dev/null; then
        sudo xmlstarlet ed -L -d "//layoutList/layout[configItem/name='dv']" "$xml_file"
    else
        local tmp_file
        tmp_file="$(mktemp "/tmp/$(basename "$xml_file").XXXX")"
        sudo awk '
        /<layout>/ { buffer = $0; in_layout = 1; next }
        in_layout {
            buffer = buffer "\n" $0
            if (/<\/layout>/) {
                if (buffer !~ /<name>dv<\/name>/) {
                    print buffer
                }
                in_layout = 0
                buffer = ""
            }
            next
        }
        { print }
        ' "$xml_file" > "$tmp_file"
        sudo mv "$tmp_file" "$xml_file"
        sudo chmod 644 "$xml_file"
    fi

    log_info "Removed dv from ${label}"
}

# Remove dv symbols file
remove_dv_symbols() {
    log_info "Removing dv symbols file..."

    if [[ -f "$DV_SYMBOLS_FILE" ]]; then
        sudo rm -f "$DV_SYMBOLS_FILE"
        log_info "Removed: $DV_SYMBOLS_FILE"
    else
        log_info "dv symbols file not found. Skipping."
    fi
}

# Restore COSMIC config from backup
restore_cosmic_config() {
    log_info "Restoring COSMIC config..."

    if [[ -f "$BACKUP_MANIFEST" ]]; then
        local cosmic_backup
        cosmic_backup=$(grep "xkb_config.backup" "$BACKUP_MANIFEST" 2>/dev/null | tail -1 || true)
        if [[ -n "$cosmic_backup" && -f "$cosmic_backup" ]]; then
            cp "$cosmic_backup" "$COSMIC_XKB_CONFIG"
            log_info "Restored COSMIC config from: $cosmic_backup"
            return 0
        fi
    fi

    # If no backup, just remove dv from the layout (handles RON format)
    if [[ -f "$COSMIC_XKB_CONFIG" ]]; then
        sed -i -E 's/(layout:\s*)"us,dv"/\1"us"/' "$COSMIC_XKB_CONFIG"
        sed -i -E 's/(variant:\s*)","/\1""/' "$COSMIC_XKB_CONFIG"
        log_info "Updated COSMIC config to remove dv layout"
    fi
}

# Apply all changes
apply() {
    log_info "Starting dv layout configuration..."
    check_prerequisites
    init_backup_manifest

    create_dv_symbols
    add_layout_to_lst "$EVDEV_LST" "evdev.lst"
    add_layout_to_lst "$BASE_LST" "base.lst"
    add_layout_to_xml "$EVDEV_XML" "evdev.xml"
    add_layout_to_xml "$BASE_XML" "base.xml"
    configure_cosmic

    echo ""
    log_info "=========================================="
    log_info "Configuration complete!"
    log_info "=========================================="
    echo ""
    log_info "Backups recorded in: $BACKUP_MANIFEST"
    echo ""
    log_info "NEXT STEPS:"
    log_info "  1. Log out and log back in for COSMIC to pick up the new layout."
    log_info "  2. Open Settings > Keyboard > Input Sources to verify 'dv' appears."
    log_info "  3. Use Super+Space (or configured shortcut) to switch between us and dv."
    echo ""
    log_info "VERIFICATION COMMANDS:"
    log_info "  grep -E '^[[:space:]]*dv[[:space:]]' /usr/share/X11/xkb/rules/evdev.lst"
    log_info "  grep -A2 '<name>dv</name>' /usr/share/X11/xkb/rules/evdev.xml"
    log_info "  cat ~/.config/cosmic/com.system76.CosmicComp/v1/xkb_config"
    echo ""
    log_info "To rollback: $0 --rollback"
}

# Rollback all changes
rollback() {
    log_info "Starting rollback..."

    remove_dv_symbols
    remove_from_lst "$EVDEV_LST" "evdev.lst"
    remove_from_lst "$BASE_LST" "base.lst"
    remove_from_xml "$EVDEV_XML" "evdev.xml"
    remove_from_xml "$BASE_XML" "base.xml"
    restore_cosmic_config

    echo ""
    log_info "=========================================="
    log_info "Rollback complete!"
    log_info "=========================================="
    echo ""
    log_info "NEXT STEPS:"
    log_info "  1. Log out and log back in for changes to take effect."
    echo ""
}

# Print usage
usage() {
    echo "Usage: $0 [--apply|--rollback]"
    echo ""
    echo "Options:"
    echo "  --apply     Apply dv layout configuration (default)"
    echo "  --rollback  Restore from backups and remove dv layout"
    echo "  --help      Show this help message"
    echo ""
}

# Main
main() {
    local mode="${1:---apply}"

    case "$mode" in
        --apply|-a)
            apply
            ;;
        --rollback|-r)
            rollback
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $mode"
            usage
            exit 1
            ;;
    esac
}

main "$@"
