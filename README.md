# SIGMORA — Tokenized Real Estate Investment Platform

> Web3 · RWA · Prop Trading · SGM Token

**Live Platform:** [sigmora-ten.vercel.app](https://sigmora-ten.vercel.app)

---

## What is SIGMORA?

SIGMORA is a tokenized real estate investment platform that allows global retail investors to own fractional shares of premium properties and earn daily ROI. Built on Web3 principles with a native platform currency (SGM Token).

---

## Platform Features

### For Investors
- 🏛️ **Tokenized Properties** — fractional ownership from $100
- 💰 **Daily ROI Payouts** — automated at 00:05 UTC via pg_cron
- 📊 **Live Portfolio Dashboard** — real-time performance tracking
- 🔄 **Auto-Reinvest** — compound your returns automatically
- 💎 **SGM Tier System** — 5 tiers (Starter → Platinum) with bonus ROI

### For Traders
- 🖥️ **MT5 Web Terminal** — embedded live trading in browser
- 📋 **Prop Trading Program** — 2-step challenge for funded accounts
- 💼 **Funded Accounts** — $10K–$200K capital, 80% profit split

### Platform
- 🤖 **SIGMA AI Chatbot** — Claude-powered assistant
- 🪪 **KYC Verification** — document upload and admin review
- 🔔 **Real-time Alerts** — instant notifications via Supabase Realtime
- 📧 **Email Notifications** — branded transactional emails

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Single HTML file — Vanilla JS, no framework |
| Backend | Supabase (PostgreSQL + Auth + Storage + Edge Functions) |
| Hosting | Vercel (static deployment) |
| AI | Anthropic Claude (Haiku via Edge Function) |
| Email | Resend API |
| Charts | Chart.js + TradingView Widget |
| Trading | MT5 Web Terminal (MetaQuotes) |

---

## SGM Token Economics

- **Rate:** 1 SGM = $10 USDT (fixed, stable)
- **5 Investment Tiers:**

| Tier | Min Investment | SGM | Bonus ROI |
|---|---|---|---|
| 🌱 Starter | $100 | 10 SGM | — |
| 📈 Growth | $250 | 25 SGM | +0.01%/day |
| 💎 Premium | $500 | 50 SGM | +0.025%/day |
| ⭐ Elite | $1,000 | 100 SGM | +0.05%/day |
| 👑 Platinum | $2,500 | 250 SGM | +0.10%/day |

---

## Architecture

```
User → SIGMORA Frontend (index.html)
         ↓
    Supabase Auth (JWT)
         ↓
    PostgreSQL (16 tables, RLS)
         ↓
    Edge Functions (sigma-chat, send-email)
         ↓
    Anthropic API + Resend API
```

---

## Repository Structure

```
SIGMORA/
├── index.html              # Full platform frontend (~560KB)
├── vercel.json             # Deployment configuration
├── 01_schema.sql           # Database schema
├── 02_rls_policies.sql     # Row Level Security policies
├── 03_functions_triggers.sql # DB functions, triggers, cron
├── 04_supabase_sdk.js      # Supabase SDK reference
└── design-system/sigmora/  # UI/UX documentation
```

---

## Money Flow

```
USDT Deposit → Admin Approves → SGM Credited → Invest in Property
                                                      ↓
                                              Daily ROI (cron)
                                                      ↓
                                         Wallet Balance or Reinvest
                                                      ↓
                                              USDT Withdrawal
```

---

## Security

- All tables protected with Row Level Security (RLS)
- API keys server-side only (Supabase Edge Function secrets)
- KYC required before investing
- TX hash verification for deposits
- Role-based access control (user/admin/super_admin)

---

## Status

🟢 **Platform Live** | 🟢 **DB Active** | 🟢 **Realtime Enabled** | ⏳ **Email pending API key** | ⏳ **AI Chat pending API key**

---

*Built with Claude · Powered by Supabase · Deployed on Vercel*
