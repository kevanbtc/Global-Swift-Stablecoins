#!/bin/bash

# GitHub Authentication Setup Script for Global-Swift-Stablecoins
# This script sets up SSH key authentication for GitHub

set -e

echo "🔐 Setting up GitHub SSH Authentication for kevanbtc/Global-Swift-Stablecoins"
echo "============================================================================"

# Check if SSH key already exists
SSH_KEY_PATH="$HOME/.ssh/github_unykorn"
if [ -f "$SSH_KEY_PATH" ]; then
    echo "⚠️  SSH key already exists at $SSH_KEY_PATH"
    echo "Do you want to overwrite it? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Keeping existing SSH key."
        exit 0
    fi
fi

# Generate SSH key
echo "🔑 Generating SSH key..."
ssh-keygen -t ed25519 -C "kevanbtc@github.com" -f "$SSH_KEY_PATH" -N ""

# Start SSH agent and add key
echo "🚀 Starting SSH agent and adding key..."
eval "$(ssh-agent -s)"
ssh-add "$SSH_KEY_PATH"

# Display public key
echo ""
echo "📋 Copy the following SSH public key and add it to your GitHub account:"
echo "   GitHub Settings → SSH and GPG keys → New SSH key"
echo ""
echo "----- BEGIN SSH PUBLIC KEY -----"
cat "${SSH_KEY_PATH}.pub"
echo "----- END SSH PUBLIC KEY -----"
echo ""

# Create SSH config for GitHub
SSH_CONFIG="$HOME/.ssh/config"
if [ ! -f "$SSH_CONFIG" ]; then
    touch "$SSH_CONFIG"
fi

# Check if GitHub config already exists
if ! grep -q "Host github.com" "$SSH_CONFIG"; then
    echo "📝 Adding GitHub SSH config..."
    cat >> "$SSH_CONFIG" << EOF

# GitHub SSH Configuration
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_unykorn
    IdentitiesOnly yes
EOF
else
    echo "ℹ️  GitHub SSH config already exists"
fi

# Set proper permissions
chmod 600 "$SSH_CONFIG"
chmod 600 "$SSH_KEY_PATH"
chmod 644 "${SSH_KEY_PATH}.pub"

# Configure Git
echo "⚙️  Configuring Git..."
git config --global user.name "kevanbtc"
git config --global user.email "kevanbtc@github.com"

# Test SSH connection
echo "🧪 Testing SSH connection to GitHub..."
echo "When prompted, type 'yes' to add GitHub to known hosts"
ssh -T git@github.com -o StrictHostKeyChecking=no

if [ $? -eq 1 ]; then
    echo "✅ SSH authentication successful!"
else
    echo "❌ SSH authentication failed. Please check your setup."
    exit 1
fi

# Initialize or update repository
REPO_DIR="Global-Swift-Stablecoins"
if [ ! -d "$REPO_DIR" ]; then
    echo "📥 Cloning repository..."
    git clone git@github.com:kevanbtc/Global-Swift-Stablecoins.git
else
    echo "📤 Repository already exists. Setting remote origin..."
    cd "$REPO_DIR"
    git remote set-url origin git@github.com:kevanbtc/Global-Swift-Stablecoins.git
fi

echo ""
echo "🎉 Setup complete! You can now push to GitHub using:"
echo "   cd Global-Swift-Stablecoins"
echo "   git add ."
echo "   git commit -m 'Your commit message'"
echo "   git push origin main"
echo ""
echo "📚 Remember to add the SSH public key to your GitHub account if you haven't already!"
