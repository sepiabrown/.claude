#!/usr/bin/env bash

# Color definitions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Fancy header
echo ""
echo -e "${BOLD}Cursor Agent Installer${NC}"
echo ""

# Function to print steps with style
print_step() {
    echo -e "${BLUE}▸${NC} ${1}"
}

# Function to print success
print_success() {
    # Move cursor up one line and clear it
    echo -ne "\033[1A\033[2K"
    echo -e "${GREEN}✓${NC} ${1}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗${NC} ${1}"
}

# Detect OS and Architecture
print_step "Detecting system architecture..."

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     OS="linux";;
    Darwin*)    OS="darwin";;
    MINGW*|MSYS*|CYGWIN*)  OS="win32";;
    *)
        print_error "Unsupported operating system: ${OS}"
        #exit 1
        ;;
esac

# Detect Architecture
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64|amd64)  ARCH="x64";;
    arm64|aarch64) ARCH="arm64";;
    *)
        print_error "Unsupported architecture: ${ARCH}"
        #exit 1
        ;;
esac

print_success "Detected ${OS}/${ARCH}"

# Check Node.js installation
print_step "Checking Node.js installation..."

NODE_MIN_VERSION="18"
NODE_INSTALLED=false
NODE_VERSION_OK=false

if command -v node >/dev/null 2>&1; then
  NODE_INSTALLED=true
  NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)

  if [ "$NODE_VERSION" -ge "$NODE_MIN_VERSION" ]; then
    NODE_VERSION_OK=true
    print_success "Node.js v$(node -v | sed 's/v//') found"
  else
    print_error "Node.js v$NODE_VERSION found, but v${NODE_MIN_VERSION}+ is required"
  fi
else
  print_error "Node.js not found"
fi

# On Windows, offer to install Node.js if missing or outdated
if [ "${OS}" = "win32" ] && [ "$NODE_VERSION_OK" = false ]; then
  echo ""
  echo -e "${YELLOW}Node.js v${NODE_MIN_VERSION}+ is required for cursor-agent.${NC}"
  echo ""

  if [ "$NODE_INSTALLED" = true ]; then
    echo -e "${BOLD}Your current Node.js version (v$NODE_VERSION) is outdated.${NC}"
  else
    echo -e "${BOLD}Node.js is not installed on your system.${NC}"
  fi

  echo ""
  echo -e "Would you like to download and install Node.js automatically? [y/N]"
  read -r INSTALL_NODE

  if [ "$INSTALL_NODE" = "y" ] || [ "$INSTALL_NODE" = "Y" ]; then
    print_step "Downloading Node.js installer..."

    # Download latest LTS Node.js for Windows
    NODE_DOWNLOAD_URL="https://nodejs.org/dist/v22.18.0/node-v22.18.0-x64.msi"
    NODE_INSTALLER="/tmp/node-installer.msi"

    if curl -fsSL "${NODE_DOWNLOAD_URL}" -o "${NODE_INSTALLER}"; then
      print_success "Node.js installer downloaded"

      print_step "Installing Node.js..."
      echo -e "${DIM}  Running installer (this may take a few minutes)...${NC}"

      # Run MSI installer silently
      msiexec.exe //i "$(cygpath -w "${NODE_INSTALLER}")" //qn //norestart

      # Wait for installation to complete
      sleep 5

      # Reload PATH to pick up new Node.js installation
      export PATH="/c/Program Files/nodejs:$PATH"

      if command -v node >/dev/null 2>&1; then
        print_success "Node.js v$(node -v | sed 's/v//') installed successfully"
        rm -f "${NODE_INSTALLER}"
      else
        print_error "Installation completed, but Node.js not found in PATH"
        print_error "Please restart your terminal and run this script again"
        rm -f "${NODE_INSTALLER}"
        exit 1
      fi
    else
      print_error "Failed to download Node.js installer"
      echo ""
      echo -e "${BOLD}Please install Node.js manually:${NC}"
      echo -e "  1. Visit: ${BLUE}https://nodejs.org/${NC}"
      echo -e "  2. Download and install Node.js v${NODE_MIN_VERSION}+ for Windows"
      echo -e "  3. Restart your terminal"
      echo -e "  4. Run this installer again"
      echo ""
      exit 1
    fi
  else
    echo ""
    echo -e "${BOLD}Installation cancelled.${NC}"
    echo ""
    echo -e "${BOLD}Please install Node.js manually:${NC}"
    echo -e "  1. Visit: ${BLUE}https://nodejs.org/${NC}"
    echo -e "  2. Download and install Node.js v${NODE_MIN_VERSION}+ for Windows"
    echo -e "  3. Restart your terminal"
    echo -e "  4. Run this installer again"
    echo ""
    exit 1
  fi
elif [ "$NODE_VERSION_OK" = false ]; then
  # Non-Windows platforms
  echo ""
  echo -e "${RED}Node.js v${NODE_MIN_VERSION}+ is required but not found.${NC}"
  echo ""
  echo -e "${BOLD}Please install Node.js:${NC}"

  if [ "${OS}" = "darwin" ]; then
    echo -e "  ${DIM}Using Homebrew:${NC}"
    echo -e "  ${BLUE}brew install node${NC}"
    echo ""
    echo -e "  ${DIM}Or download from:${NC}"
    echo -e "  ${BLUE}https://nodejs.org/${NC}"
  elif [ "${OS}" = "linux" ]; then
    echo -e "  ${DIM}Using package manager:${NC}"
    echo -e "  ${BLUE}# Ubuntu/Debian${NC}"
    echo -e "  ${BLUE}curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -${NC}"
    echo -e "  ${BLUE}sudo apt-get install -y nodejs${NC}"
    echo ""
    echo -e "  ${BLUE}# Fedora/RHEL${NC}"
    echo -e "  ${BLUE}curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -${NC}"
    echo -e "  ${BLUE}sudo dnf install -y nodejs${NC}"
    echo ""
    echo -e "  ${DIM}Or download from:${NC}"
    echo -e "  ${BLUE}https://nodejs.org/${NC}"
  fi

  echo ""
  exit 1
fi

# Installation steps
print_step "Creating installation directory..."
# Create temporary directory for atomic download inside versions folder
TEMP_EXTRACT_DIR="$HOME/.local/share/cursor-agent/versions/.tmp-2025.11.06-8fe8a63-$(date +%s)"
mkdir -p "${TEMP_EXTRACT_DIR}"

print_success "Directory created"


print_step "Downloading Cursor Agent package..."
# On Windows, download the darwin (macOS) package and we'll replace binaries later
if [ "${OS}" = "win32" ]; then
  DOWNLOAD_URL="https://downloads.cursor.com/lab/2025.11.06-8fe8a63/darwin/arm64/agent-cli-package.tar.gz"
  echo -e "${DIM}  Download URL: ${DOWNLOAD_URL} (macOS package, will be patched for Windows)${NC}"
else
  DOWNLOAD_URL="https://downloads.cursor.com/lab/2025.11.06-8fe8a63/${OS}/${ARCH}/agent-cli-package.tar.gz"
  echo -e "${DIM}  Download URL: ${DOWNLOAD_URL}${NC}"
fi

# Cleanup function
cleanup() {
    rm -rf "${TEMP_EXTRACT_DIR}"
}
trap cleanup EXIT

# Download with progress bar and better error handling
if curl -fSL --progress-bar "${DOWNLOAD_URL}" \
  | tar --strip-components=1 -xzf - -C "${TEMP_EXTRACT_DIR}"; then
  echo -ne "\033[1A\033[2K"
  echo -ne "\033[1A\033[2K"
  echo -ne "\033[1A\033[2K"
  print_success "Package downloaded and extracted"
else
    print_error "Download failed. Please check your internet connection and try again."
    print_error "If the problem persists, the package might not be available for ${OS}/${ARCH}."
    cleanup
    exit 1
fi

print_step "Finalizing installation..."
# Atomically move from temp to final destination
FINAL_DIR="$HOME/.local/share/cursor-agent/versions/2025.11.06-8fe8a63"
rm -rf "${FINAL_DIR}"
if mv "${TEMP_EXTRACT_DIR}" "${FINAL_DIR}"; then
  print_success "Package installed successfully"
else
    print_error "Failed to install package. Please check permissions."
    cleanup
    exit 1
fi

# On Windows, replace macOS binaries with Windows-compatible versions
if [ "${OS}" = "win32" ]; then
  print_step "Patching for Windows compatibility..."

  # Download ripgrep for Windows
  print_step "  Downloading ripgrep for Windows..."
  RG_VERSION="14.1.0"
  RG_URL="https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-x86_64-pc-windows-msvc.zip"
  curl -fsSL "${RG_URL}" -o /tmp/rg.zip
  unzip -q -o /tmp/rg.zip -d /tmp/
  cp "/tmp/ripgrep-${RG_VERSION}-x86_64-pc-windows-msvc/rg.exe" "${FINAL_DIR}/rg.exe"
  rm -rf /tmp/rg.zip "/tmp/ripgrep-${RG_VERSION}-x86_64-pc-windows-msvc"
  print_success "  ripgrep installed"

  # Download merkle-tree native module for Windows
  print_step "  Downloading merkle-tree-napi for Windows..."
  MERKLE_VERSION="v0.0.5"
  MERKLE_URL="https://github.com/btc-vision/rust-merkle-tree/releases/download/${MERKLE_VERSION}/rust-merkle-tree.win32-x64-msvc.node"
  curl -fsSL "${MERKLE_URL}" -o "${FINAL_DIR}/merkle-tree-napi.win32-x64-msvc.node"
  print_success "  merkle-tree-napi installed"

  # Download node-sqlite3 for Windows via npm
  print_step "  Installing node-sqlite3 for Windows via npm..."
  SQLITE_VERSION="5.1.7"
  TEMP_NPM_DIR="/tmp/sqlite3-install-$$"
  mkdir -p "${TEMP_NPM_DIR}"
  (cd "${TEMP_NPM_DIR}" && npm init -y > /dev/null 2>&1 && npm install sqlite3@${SQLITE_VERSION} --no-save > /dev/null 2>&1)
  if [ -f "${TEMP_NPM_DIR}/node_modules/sqlite3/build/Release/node_sqlite3.node" ]; then
    cp "${TEMP_NPM_DIR}/node_modules/sqlite3/build/Release/node_sqlite3.node" "${FINAL_DIR}/node_sqlite3.node"
    print_success "  node-sqlite3 installed"
  else
    print_error "  Failed to build node-sqlite3"
  fi
  rm -rf "${TEMP_NPM_DIR}"

  # Patch index.js to use native require() instead of webpack's __webpack_require__() for merkle-tree
  print_step "  Patching index.js for Windows native modules..."
  sed -i 's/nativeBinding = __webpack_require__(Object(function webpackMissingModule() { var e = new Error("Cannot find module '\''\.\/merkle-tree-napi\.win32-x64-msvc\.node'\''"); e\.code = '\''MODULE_NOT_FOUND'\''; throw e; }()));/nativeBinding = require(".\/merkle-tree-napi.win32-x64-msvc.node");/' "${FINAL_DIR}/index.js"
  print_success "  index.js patched"

  print_success "Windows compatibility patches applied"
fi


print_step "Creating bin directory..."
mkdir -p ~/.local/bin
print_success "Bin directory ready"


print_step "Creating cursor-agent executable..."
# Remove any existing symlink or file
rm -f ~/.local/bin/cursor-agent

if [ "${OS}" = "win32" ]; then
  # On Windows, create a wrapper script that uses system node
  cat > ~/.local/bin/cursor-agent << 'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail

# Point directly to the installation directory
INSTALL_DIR="$HOME/.local/share/cursor-agent/versions/2025.11.06-8fe8a63"
MAIN_JS="$INSTALL_DIR/index.js"

# Use system node instead of bundled node (which is Linux-only)
# On Windows, prefer node.exe from Program Files to avoid spawn ENOENT errors
if [[ -f "/c/Program Files/nodejs/node.exe" ]]; then
  exec "/c/Program Files/nodejs/node.exe" --use-system-ca "$MAIN_JS" "$@"
else
  exec node --use-system-ca "$MAIN_JS" "$@"
fi
WRAPPER_EOF
  chmod +x ~/.local/bin/cursor-agent
  print_success "Wrapper script created (using system node)"
else
  # On Unix systems, create symlink to the cursor-agent executable
  ln -s ~/.local/share/cursor-agent/versions/2025.11.06-8fe8a63/cursor-agent ~/.local/bin/cursor-agent
  print_success "Symlink created"
fi

# Success message
echo ""
echo -e "${BOLD}${GREEN}✨ Installation Complete! ${NC}"
echo ""
echo ""

# Determine configured shells
CURRENT_SHELL="$(basename $SHELL)"
SHOW_BASH=false
SHOW_ZSH=false
SHOW_FISH=false

case "${CURRENT_SHELL}" in
  bash) SHOW_BASH=true ;;
  zsh) SHOW_ZSH=true ;;
  fish) SHOW_FISH=true ;;
esac

# Also consider presence of config files as configured
if [ -f "$HOME/.bashrc" ] || [ -f "$HOME/.bash_profile" ]; then SHOW_BASH=true; fi
if [ -f "$HOME/.zshrc" ]; then SHOW_ZSH=true; fi
if [ -f "$HOME/.config/fish/config.fish" ]; then SHOW_FISH=true; fi

# Next steps with style
echo -e "${BOLD}Next Steps${NC}"
echo ""
echo -e "${BOLD}1.${NC} Add ~/.local/bin to your PATH:"

if [ "${SHOW_BASH}" = true ]; then
  echo -e "   ${DIM}For bash:${NC}"
  echo -e "   ${BOLD}${BLUE}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc${NC}"
  echo -e "   ${BOLD}${BLUE}source ~/.bashrc${NC}"
  echo ""
fi

if [ "${SHOW_ZSH}" = true ]; then
  echo -e "   ${DIM}For zsh:${NC}"
  echo -e "   ${BOLD}${BLUE}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc${NC}"
  echo -e "   ${BOLD}${BLUE}source ~/.zshrc${NC}"
  echo ""
fi

if [ "${SHOW_FISH}" = true ]; then
  echo -e "   ${DIM}For fish:${NC}"
  echo -e "   ${BOLD}${BLUE}mkdir -p \$HOME/.config/fish${NC}"
  echo -e "   ${BOLD}${BLUE}echo 'fish_add_path \$HOME/.local/bin' >> \$HOME/.config/fish/config.fish${NC}"
  echo -e "   ${BOLD}${BLUE}source \$HOME/.config/fish/config.fish${NC}"
  echo ""
fi

# Fallback if no known shells detected/configured
if [ "${SHOW_BASH}" != true ] && [ "${SHOW_ZSH}" != true ] && [ "${SHOW_FISH}" != true ]; then
  echo -e "   ${DIM}Add to PATH manually:${NC}"
  echo -e "   ${BOLD}${BLUE}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
  echo ""
fi

echo -e "${BOLD}2.${NC} Start using Cursor Agent:"
echo -e "   ${BOLD}cursor-agent${NC}"
echo ""
echo ""
echo -e "${BOLD}${CYAN}Happy coding! 🚀${NC}"
echo ""
