#!/bin/bash

# Push Global-Swift-Stablecoins to GitHub Script
# This script initializes the repository and pushes all code to GitHub

set -e

echo "🚀 Pushing Global-Swift-Stablecoins to GitHub"
echo "=============================================="

# Check if we're in the right directory
if [ ! -d "contracts" ] || [ ! -d "scripts" ]; then
    echo "❌ Error: Please run this script from the root of the stablecoin and cbdc project directory"
    exit 1
fi

# Check if GitHub auth is set up
if ! ssh -T git@github.com -o StrictHostKeyChecking=no 2>&1 | grep -q "successfully authenticated"; then
    echo "⚠️  SSH authentication not set up. Please run ./setup-github-auth.sh first"
    echo "   Or manually add your SSH key to GitHub: https://github.com/settings/keys"
    exit 1
fi

# Initialize Git if not already done
if [ ! -d ".git" ]; then
    echo "📝 Initializing Git repository..."
    git init
    git branch -M main
fi

# Set remote origin
echo "🔗 Setting up remote origin..."
git remote remove origin 2>/dev/null || true
git remote add origin git@github.com:kevanbtc/Global-Swift-Stablecoins.git

# Add all files
echo "📦 Adding all files to Git..."
git add .

# Commit
echo "💾 Creating commit..."
git commit -m "Initial commit: Global Swift Stablecoins Infrastructure

- Complete Unykorn L1 blockchain infrastructure
- CBDC and stablecoin contracts
- SWIFT integration and ISO20022 compliance
- DeFi protocols and institutional finance
- AI and quantum governance systems
- Cross-border settlement rails
- Regulatory compliance engines
- Real-time monitoring and reporting

Chain ID: 7777
RPC: http://localhost:8545
Currency: Unykorn Ether (UNYETH)"

# Push to GitHub
echo "⬆️  Pushing to GitHub..."
git push -u origin main

echo ""
echo "✅ Successfully pushed to GitHub!"
echo "🌐 Repository: https://github.com/kevanbtc/Global-Swift-Stablecoins"
echo ""
echo "📋 Next steps:"
echo "   - Enable GitHub Pages if needed"
echo "   - Set up CI/CD workflows"
echo "   - Add collaborators"
echo "   - Create issues and project boards"
