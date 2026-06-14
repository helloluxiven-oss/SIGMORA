# SIGMORA — Tokenized Investment Platform
# Claude Code Project Configuration

## What This Project Is
SIGMORA is a full-stack Web3 real estate tokenization + prop trading platform.
Single HTML file frontend + Supabase backend + Vercel hosting.

---

## Stack

| Layer | Tech |
|---|---|
| Frontend | Single HTML file (index.html) — vanilla JS, no framework |
| Backend | Supabase (PostgreSQL + Auth + Storage + Edge Functions) |
| Hosting | Vercel (static site) |
| AI Chat | Anthropic Claude Haiku via Supabase Edge Function |
| Email | Resend API via Supabase Edge Function |
| Charts | Chart.js + TradingView widget |
| Prices | CoinGecko → Binance → Simulation fallback |

---

## Credentials & Config

- **Supabase Project ID:** tbjtgmwnktplxyyibtcc
- **Supabase Region:** ap-southeast-1
- **Supabase URL:** https://tbjtgmwnktplxyyibtcc.supabase.co
- **Supabase Anon Key:** eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRianRnbXdua3RwbHh5eWlidGNjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3OTEzMTgsImV4cCI6MjA5MDM2NzMxOH0.K-yIUlIcGGFBfjsslMpnuKg3mGek9OZNrJrwTv5v8a8
- **Vercel Team:** helloluxiven-2866s-projects
- **Vercel Project ID:** prj_4LcoazI7UYxkMrX1nWCEwFw05yXF
- **Live URL:** https://sigmora-n6obtwczk-helloluxiven-2866s-projects.vercel.app
- **Miro Board:** https://miro.com/app/board/uXjVGioEYjQ=/
- **Test User:** kartikaykhandelwal73@gmail.com (role: super_admin)

---

## File Structure

```
sigmora-project/
├── index.html          ← The entire frontend (~480KB, ~4770 lines)
├── vercel.json         ← Vercel deployment config
├── CLAUDE.md           ← This file
└── .claude/
    └── mcp.json        ← MCP server connections
```

---

## Key Rules — NEVER Break These

1. **No API keys in index.html** — all secrets live in Supabase Edge Function secrets
2. **Always run Node syntax check before saving:** `node --check index.html` won't work — extract script block first
3. **Brace balance must always match** — count `{` === `}`  before saving
4. **Single HTML file** — do NOT split into multiple files unless explicitly asked
5. **No npm/build step** — vanilla JS only, CDN imports only
6. **Test after every change** — open index.html in browser, check console for errors
7. **Preserve all existing features** — never remove working code when adding new features

---

## Database (Supabase — 16 Tables)

### Core Tables
- **users** — investors + admins (role: user/admin/super_admin)
- **properties** — tokenized real estate listings
- **investments** — user token holdings per property
- **roi_payouts** — daily ROI payout records
- **roi_payout_runs** — cron job execution log
- **transactions** — all financial events

### Platform Tables
- **notifications** — in-app inbox per user
- **platform_config** — key-value settings store
- **property_photos** — gallery images (Supabase Storage)
- **investment_tiers** — 5 SGM tiers (Starter→Platinum)
- **sgm_transactions** — SGM token movement log

### Trading Tables
- **trader_applications** — prop trader application lifecycle
- **prop_traders** — active funded traders
- **trading_positions** — live/closed trading positions

### System Tables
- **sigma_chat_log** — AI chatbot rate limiting
- **email_log** — outbound email tracking

### Key RPCs
- `get_my_profile()` — full user profile, self-heals
- `get_dashboard_summary()` — single call: profile + properties + activity + notifications
- `touch_last_login()` — update last_login_at
- `run_daily_roi_payouts()` — full ROI engine
- `admin_trigger_roi_payout()` — manual admin trigger
- `get_user_tier(total_invested)` — returns tier 1-5
- `usd_to_sgm(usd)` — convert at 10:1 rate

### Cron Jobs
- `sigmora_daily_roi_payout` — runs at 00:05 UTC daily

---

## Edge Functions (Supabase)

### sigma-chat
- Route: POST /functions/v1/sigma-chat
- Purpose: Claude AI chatbot proxy (keeps API key server-side)
- Model: claude-haiku-4-5-20251001
- Rate limit: 30 msgs/hr/user
- Secret needed: ANTHROPIC_API_KEY

### send-email
- Route: POST /functions/v1/send-email
- Purpose: Branded transactional emails via Resend
- Trigger: DB trigger on notifications INSERT
- Secrets needed: RESEND_API_KEY + FROM_EMAIL

---

## SGM Token Economics

- **Rate:** 1 SGM = $10 USDT (fixed)
- **5 Tiers:**
  - Level 1 Starter: $100 min, 10 SGM
  - Level 2 Growth: $250 min, 25 SGM, +0.01% bonus ROI
  - Level 3 Premium: $500 min, 50 SGM, +0.025% bonus ROI
  - Level 4 Elite: $1,000 min, 100 SGM, +0.05% bonus ROI
  - Level 5 Platinum: $2,500 min, 250 SGM, +0.10% bonus ROI

---

## Frontend Architecture

### CSS Variables (Design System)
- `--v1: #7c3aed` (primary purple)
- `--neon: #00f5d4` (teal accent)
- `--mint: #10b981` (green)
- `--gold: #fbbf24` (amber)
- `--rose: #f43f5e` (red)

### Helper Functions
- `$(id)` → getElementById
- `setText(id, val)` → set textContent
- `fmtUSD(n)` → format as USD
- `fmtPct(n)` → format as percentage
- `fmtDate(d)` → format date
- `showToast(msg, type, duration)` → show notification toast

### Auth Flow
- `initAuthListener()` — onAuthStateChange with _appReady guard
- `showDashboard(user)` — swap screens + load data
- `showAuthScreen()` — reset all state + stop intervals
- `doSignIn()` — _signingIn guard prevents double-submit
- `doSignOut()` — clears all state

### Key Page Loaders
- `loadDashboard()` / `loadDashboardFast()` — dashboard data
- `loadUserProfile()` — user profile + sidebar binding
- `renderTierUI()` — SGM tier badge + progress bar
- `loadTraders()` — trader roster + application system
- `loadBuyTokens()` — buy tokens + tier banner
- `openPropertyModal(propId)` — property detail + gallery
- `adminRunPayouts()` — manual ROI payout trigger

### Price Ticker
- 3-source: CoinGecko → Binance → Simulation
- `_fetchWithTimeout(url, ms)` — cross-browser AbortController
- Interval: 30 seconds, stored as `window._priceInterval`

---

## Trader Application Lifecycle

```
pending → under_review → demo_issued → challenge_1 → challenge_2 → challenge_passed → funded
                                                                                    ↘ rejected
```

- Step 1 challenge: +8% profit in 30 days, max 5% daily loss, max 10% drawdown
- Step 2 challenge: +5% profit in 60 days, same rules
- Funded: $10K–$200K capital, 80% profit to trader

---

## MT5 Web Terminal

- Embedded via iframe in Trading Desk page
- URL: https://trade.mql5.com/trade
- Login form stores credentials from trader_applications table
- `launchMT5Terminal()` — builds URL + loads iframe
- `switchTradingTab(tab)` — toggle TradingView / MT5

---

## What's Pending (Needs Activation)

1. **ANTHROPIC_API_KEY** → add to Supabase Edge Function secrets → SIGMA chat works
2. **RESEND_API_KEY + FROM_EMAIL** → add to secrets → emails work
3. **Supabase Site URL** → set to live Vercel URL in auth settings
4. **Real property data** → update properties table
5. **USDT deposit addresses** → add per user
6. **Custom domain** → configure in Vercel + update Supabase Site URL

---

## Common Tasks for Claude Code

### Add a new feature to the frontend
"Add [feature] to the [page] section in index.html. Follow the existing CSS variable system and vanilla JS patterns. No frameworks. Check brace balance before saving."

### Fix a bug
"There's a bug where [description]. Check index.html lines [range]. Fix without touching any other functionality."

### Update Supabase
"Write a SQL migration to [description]. Follow the existing RLS pattern: users see own data, admins see all. Add performance indexes for any new FK columns."

### Deploy to Vercel
"Deploy the current index.html to Vercel project sigmora in team helloluxiven-2866s-projects."

### Check Supabase data
"Query the Supabase project tbjtgmwnktplxyyibtcc to show [data]. Use the service role key from environment."

---

## MCP Servers Connected

- **Supabase MCP** — full DB access (read/write with service role)
- **Vercel MCP** — deploy, list projects, check deployment status
- **Miro MCP** — update workflow board at https://miro.com/app/board/uXjVGioEYjQ=/

---

## Important Warnings

- The JS in index.html is all in one `<script>` block — no modules
- `AbortSignal.timeout` is replaced with `_fetchWithTimeout()` — don't revert this
- `_signingIn` and `_appReady` guards are critical — never remove them
- Ticker intervals are stored as `window._tickerInterval` and `window._priceInterval` — clean up on sign-out
- `console.log` is removed from production paths — don't add it back
- All RLS policies use `(SELECT auth.uid())` subquery pattern — don't simplify to `auth.uid()` directly
