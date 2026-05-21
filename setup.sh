#!/bin/bash
# SIGMORA — Claude Code Setup Script
# Run this once on your machine to get started

echo "🚀 SIGMORA Claude Code Setup"
echo "=============================="

# 1. Check if Claude Code is installed
if command -v claude &> /dev/null; then
    echo "✅ Claude Code already installed"
else
    echo "📦 Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | sh
    echo "✅ Claude Code installed"
fi

# 2. Show next steps
echo ""
echo "=============================="
echo "NEXT STEPS:"
echo "=============================="
echo ""
echo "1. Open .claude/mcp.json and replace:"
echo "   YOUR_SERVICE_ROLE_KEY_HERE → your Supabase service role key"
echo "   YOUR_VERCEL_TOKEN_HERE → your Vercel token (vercel.com/account/tokens)"
echo ""
echo "2. Run Claude Code in this folder:"
echo "   claude"
echo ""
echo "3. First time? Authenticate with your Anthropic account (browser opens)"
echo ""
echo "4. Once inside, type:"
echo "   /init"
echo "   (Claude will scan your project and understand the full codebase)"
echo ""
echo "5. Try your first command:"
echo "   'Check the index.html for any console errors or syntax issues'"
echo ""
echo "=============================="
echo "📋 Your Supabase service role key:"
echo "   Go to: supabase.com/dashboard/project/tbjtgmwnktplxyyibtcc/settings/api"
echo "   Copy the 'service_role' key (NOT the anon key)"
echo ""
echo "📋 Your Vercel token:"
echo "   Go to: vercel.com/account/tokens"
echo "   Create new token → copy it"
echo "=============================="
