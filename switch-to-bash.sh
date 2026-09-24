#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "=== CachyOS Shell & Konsole Automator ==="

# 1. Change user's system login shell to Bash
echo "[*] Updating system default shell to Bash..."
if chsh -s /usr/bin/bash; then
    echo "[✓] System shell successfully set to Bash."
else
    echo "[✗] Failed to change system shell. You might need to supply your password."
    exit 1
fi

# 2. Define Konsole paths
KONSOLE_DIR="$HOME/.local/share/konsole"
KONSOLE_RC="$HOME/.config/konsolerc"
PROFILE_NAME="BashDefault"
PROFILE_FILE="$KONSOLE_DIR/$PROFILE_NAME.profile"

# Ensure the Konsole data directory exists
mkdir -p "$KONSOLE_DIR"

# 3. Create the new Konsole profile via CLI file generation
echo "[*] Creating new Konsole profile: $PROFILE_NAME..."
cat << EOF > "$PROFILE_FILE"
[General]
Command=/usr/bin/bash
Name=$PROFILE_NAME
Parent=FALLBACK/

[Appearance]
ColorScheme=Breeze
EOF
echo "[✓] Profile created at $PROFILE_FILE"

# 4. Set the new profile as the default in konsolerc
echo "[*] Setting $PROFILE_NAME as the default Konsole profile..."
if [ -f "$KONSOLE_RC" ]; then
    # If [Desktop Entry] section exists, ensure DefaultProfile is updated
    if grep -q "\[Desktop Entry\]" "$KONSOLE_RC"; then
        # Check if DefaultProfile key already exists under [Desktop Entry]
        if grep -q "DefaultProfile=" "$KONSOLE_RC"; then
            sed -i "s/^DefaultProfile=.*/DefaultProfile=$PROFILE_NAME.profile/g" "$KONSOLE_RC"
        else
            # Insert it right below [Desktop Entry]
            sed -i "/\[Desktop Entry\]/a DefaultProfile=$PROFILE_NAME.profile" "$KONSOLE_RC"
        fi
    else
        # If [Desktop Entry] doesn't exist at all, append it
        cat << EOF >> "$KONSOLE_RC"

[Desktop Entry]
DefaultProfile=$PROFILE_NAME.profile
EOF
    fi
else
    # Create konsolerc if it doesn't exist
    cat << EOF > "$KONSOLE_RC"
[Desktop Entry]
DefaultProfile=$PROFILE_NAME.profile
EOF
fi
echo "[✓] Konsole default profile updated."

echo "========================================="
echo "Done! Please log out and log back in for all changes to take effect."
