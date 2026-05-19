-- ═══════════════════════════════════════════════════════════════
-- SIGMORA — COMPLETE SUPABASE SCHEMA
-- Version: 1.0 MVP → Scalable
-- Run this in: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ═══════════════════════════════════════════════════════════════
-- ENUMS — Type-safe status/role constants
-- ═══════════════════════════════════════════════════════════════

CREATE TYPE user_role         AS ENUM ('user', 'admin', 'super_admin');
CREATE TYPE kyc_status        AS ENUM ('pending', 'submitted', 'approved', 'rejected', 'flagged');
CREATE TYPE property_status   AS ENUM ('draft', 'pending_approval', 'active', 'sold_out', 'paused', 'closed');
CREATE TYPE property_type     AS ENUM ('commercial', 'residential', 'mixed_use', 'industrial', 'retail');
CREATE TYPE transaction_type  AS ENUM ('buy', 'sell', 'reinvest', 'payout', 'deposit', 'withdrawal', 'fee');
CREATE TYPE tx_status         AS ENUM ('pending', 'processing', 'completed', 'failed', 'refunded');
CREATE TYPE reinvest_mode     AS ENUM ('on', 'off');
CREATE TYPE fund_status       AS ENUM ('open', 'funded', 'active', 'exited', 'closed');
CREATE TYPE trader_status     AS ENUM ('active', 'suspended', 'review');
CREATE TYPE payout_status     AS ENUM ('scheduled', 'processing', 'completed', 'failed');
CREATE TYPE startup_stage     AS ENUM ('pre_seed', 'seed', 'seed_plus', 'pre_series_a', 'series_a', 'series_b');

-- ═══════════════════════════════════════════════════════════════
-- TABLE 1: users (extends Supabase auth.users)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.users (
  id                UUID          PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email             TEXT          UNIQUE NOT NULL,
  full_name         TEXT,
  phone             TEXT,
  country           TEXT,
  city              TEXT,

  -- Web3
  wallet_address    TEXT          UNIQUE,
  wallet_chain      TEXT          DEFAULT 'ethereum',

  -- Role & KYC
  role              user_role     NOT NULL DEFAULT 'user',
  kyc_status        kyc_status    NOT NULL DEFAULT 'pending',
  kyc_submitted_at  TIMESTAMPTZ,
  kyc_reviewed_at   TIMESTAMPTZ,
  kyc_reviewed_by   UUID          REFERENCES public.users(id),
  kyc_notes         TEXT,

  -- Financial
  wallet_balance_usd  NUMERIC(18,2)  NOT NULL DEFAULT 0.00,
  total_invested_usd  NUMERIC(18,2)  NOT NULL DEFAULT 0.00,
  total_earned_usd    NUMERIC(18,2)  NOT NULL DEFAULT 0.00,

  -- Preferences
  reinvest_default  reinvest_mode NOT NULL DEFAULT 'off',
  timezone          TEXT          DEFAULT 'UTC',
  notification_email BOOLEAN      DEFAULT TRUE,
  notification_sms   BOOLEAN      DEFAULT FALSE,

  -- Meta
  referral_code     TEXT          UNIQUE DEFAULT substr(md5(random()::text), 1, 8),
  referred_by       UUID          REFERENCES public.users(id),
  is_active         BOOLEAN       NOT NULL DEFAULT TRUE,
  last_login_at     TIMESTAMPTZ,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- TABLE 2: kyc_documents
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.kyc_documents (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID          NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  doc_type        TEXT          NOT NULL, -- 'passport', 'aadhar', 'pan', 'driving_license'
  doc_number      TEXT,
  file_url        TEXT          NOT NULL,
  selfie_url      TEXT,
  country_issued  TEXT,
  expiry_date     DATE,
  verified        BOOLEAN       DEFAULT FALSE,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- TABLE 3: properties (tokenized real estate listings)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.properties (
  id                  UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Identity
  name                TEXT          NOT NULL,
  slug                TEXT          UNIQUE NOT NULL,
  description         TEXT,
  property_type       property_type NOT NULL DEFAULT 'commercial',
  status              property_status NOT NULL DEFAULT 'draft',

  -- Location
  country             TEXT          NOT NULL,
  city                TEXT          NOT NULL,
  address             TEXT,
  latitude            NUMERIC(10,7),
  longitude           NUMERIC(10,7),

  -- Financials
  total_value_usd     NUMERIC(18,2) NOT NULL,
  token_symbol        TEXT          NOT NULL UNIQUE, -- e.g. 'DTK', 'MBK'
  token_price_usd     NUMERIC(18,6) NOT NULL,
  total_supply        BIGINT        NOT NULL,
  tokens_sold         BIGINT        NOT NULL DEFAULT 0,
  tokens_reserved     BIGINT        NOT NULL DEFAULT 0,
  min_investment_tokens BIGINT      NOT NULL DEFAULT 1,

  -- ROI
  daily_roi_percent   NUMERIC(8,4)  NOT NULL, -- e.g. 0.3500 = 0.35%
  annual_yield_percent NUMERIC(8,4),
  bep_days            INTEGER,       -- auto-calculated
  double_days         INTEGER,       -- auto-calculated

  -- Images & Media
  cover_image_url     TEXT,
  gallery_urls        TEXT[],
  documents_urls      TEXT[],

  -- Admin
  created_by          UUID          REFERENCES public.users(id),
  approved_by         UUID          REFERENCES public.users(id),
  approved_at         TIMESTAMPTZ,
  launch_date         DATE,
  close_date          DATE,

  -- Blockchain (for future Web3)
  contract_address    TEXT,
  blockchain_network  TEXT          DEFAULT 'ethereum',
  token_standard      TEXT          DEFAULT 'ERC-20',

  -- Meta
  featured            BOOLEAN       DEFAULT FALSE,
  sort_order          INTEGER       DEFAULT 0,
  investor_count      INTEGER       NOT NULL DEFAULT 0,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- Constraints
  CONSTRAINT tokens_sold_valid CHECK (tokens_sold >= 0 AND tokens_sold <= total_supply),
  CONSTRAINT price_positive    CHECK (token_price_usd > 0),
  CONSTRAINT roi_positive      CHECK (daily_roi_percent > 0)
);

-- ═══════════════════════════════════════════════════════════════
-- TABLE 4: investments (token ownership — the core table)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.investments (
  id                  UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID          NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  property_id         UUID          NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,

  -- Holdings
  tokens_owned        BIGINT        NOT NULL DEFAULT 0,
  avg_buy_price_usd   NUMERIC(18,6) NOT NULL,
  total_invested_usd  NUMERIC(18,2) NOT NULL DEFAULT 0.00,

  -- ROI
  total_roi_earned_usd  NUMERIC(18,2) NOT NULL DEFAULT 0.00,
  last_payout_at        TIMESTAMPTZ,
  last_payout_amount    NUMERIC(18,2) NOT NULL DEFAULT 0.00,
  reinvest_mode         reinvest_mode NOT NULL DEFAULT 'off',

  -- Phase tracking
  bep_reached           BOOLEAN       NOT NULL DEFAULT FALSE,
  bep_reached_at        TIMESTAMPTZ,
  double_reached        BOOLEAN       NOT NULL DEFAULT FALSE,
  double_reached_at     TIMESTAMPTZ,

  -- Status
  is_active             BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- One investment record per user per property
  UNIQUE (user_id, property_id),
  CONSTRAINT tokens_positive CHECK (tokens_owned >= 0)
);

-- ═══════════════════════════════════════════════════════════════
-- TABLE 5: transactions (complete audit trail)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.transactions (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID          NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  property_id       UUID          REFERENCES public.properties(id),  -- NULL for deposits/withdrawals
  investment_id     UUID          REFERENCES public.investments(id),

  -- Transaction details
  tx_type           transaction_type NOT NULL,
  status            tx_status     NOT NULL DEFAULT 'pending',

  -- Amounts
  token_amount      BIGINT,               -- tokens bought/sold
  token_price_usd   NUMERIC(18,6),
  gross_amount_usd  NUMERIC(18,2) NOT NULL,
  fee_amount_usd    NUMERIC(18,2) NOT NULL DEFAULT 0.00,
  net_amount_usd    NUMERIC(18,2) NOT NULL,

  -- References
  payment_method    TEXT,                 -- 'wallet_balance', 'usdt_trc20', etc.
  blockchain_tx_hash TEXT,               -- for Web3 txns
  reference_id      UUID,                -- for reinvest: points to payout tx

  -- Metadata
  notes             TEXT,
  processed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- TABLE 6: roi_payouts (daily ROI distribution log)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.roi_payouts (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  investment_id     UUID          NOT NULL REFERENCES public.investments(id) ON DELETE RESTRICT,
  user_id           UUID          NOT NULL REFERENCES public.users(id),
  property_id       UUID          NOT NULL REFERENCES public.properties(id),

  -- Payout details
  payout_date       DATE          NOT NULL DEFAULT CURRENT_DATE,
  tokens_at_payout  BIGINT        NOT NULL,
  roi_percent       NUMERIC(8,4)  NOT NULL,
  gross_amount_usd  NUMERIC(18,2) NOT NULL,
  fee_amount_usd    NUMERIC(18,2) NOT NULL DEFAULT 0.00,
  net_amount_usd    NUMERIC(18,2) NOT NULL,

  -- Reinvest
  was_reinvested    BOOLEAN       NOT NULL DEFAULT FALSE,
  tokens_reinvested BIGINT,
  reinvest_tx_id    UUID          REFERENCES public.transactions(id),

  -- Status
  status            payout_status NOT NULL DEFAULT 'completed',
  payout_run_id     UUID,         -- batch run identifier

  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- One payout per investment per day
  UNIQUE (investment_id, payout_date)
);

-- ═══════════════════════════════════════════════════════════════
-- TABLE 7: wallet_ledger (platform wallet movements)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.wallet_ledger (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID          NOT NULL REFERENCES public.users(id),
  tx_id           UUID          REFERENCES public.transactions(id),
  entry_type      TEXT          NOT NULL, -- 'credit', 'debit'
  amount_usd      NUMERIC(18,2) NOT NULL,
  balance_before  NUMERIC(18,2) NOT NULL,
  balance_after   NUMERIC(18,2) NOT NULL,
  description     TEXT,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- TABLE 8: startup_deals (Entrepreneur Fund)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.startup_deals (
  id                    UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  name                  TEXT          NOT NULL,
  slug                  TEXT          UNIQUE NOT NULL,
  tagline               TEXT,
  description           TEXT,
  sector                TEXT,
  stage                 startup_stage NOT NULL DEFAULT 'seed',
  status                fund_status   NOT NULL DEFAULT 'open',

  -- Financials
  ask_amount_usd        NUMERIC(18,2) NOT NULL,
  funded_amount_usd     NUMERIC(18,2) NOT NULL DEFAULT 0,
  min_investment_usd    NUMERIC(18,2) NOT NULL DEFAULT 1000,
  projected_roi_min     NUMERIC(6,2),
  projected_roi_max     NUMERIC(6,2),
  target_exit_months    INTEGER,

  -- Founder info
  founder_name          TEXT,
  founder_email         TEXT,
  website_url           TEXT,
  pitch_deck_url        TEXT,
  current_arr_usd       NUMERIC(18,2),
  monthly_growth_pct    NUMERIC(6,2),

  -- Media
  logo_url              TEXT,
  cover_image_url       TEXT,
  tags                  TEXT[],

  -- Admin
  reviewed_by           UUID          REFERENCES public.users(id),
  approved_at           TIMESTAMPTZ,
  investor_count        INTEGER       NOT NULL DEFAULT 0,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- TABLE 9: startup_investments
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.startup_investments (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID          NOT NULL REFERENCES public.users(id),
  startup_id        UUID          NOT NULL REFERENCES public.startup_deals(id),
  amount_usd        NUMERIC(18,2) NOT NULL,
  equity_percent    NUMERIC(8,4),
  status            TEXT          NOT NULL DEFAULT 'active',
  returns_usd       NUMERIC(18,2) NOT NULL DEFAULT 0,
  invested_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  exited_at         TIMESTAMPTZ,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- TABLE 10: prop_traders
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.prop_traders (
  id                  UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID          REFERENCES public.users(id),
  full_name           TEXT          NOT NULL,
  strategy            TEXT,
  experience_years    INTEGER,
  status              trader_status NOT NULL DEFAULT 'active',

  -- Allocation
  allocated_usd       NUMERIC(18,2) NOT NULL DEFAULT 0,
  max_drawdown_pct    NUMERIC(6,2)  NOT NULL DEFAULT 10.00,

  -- Performance
  mtd_pnl_usd         NUMERIC(18,2) NOT NULL DEFAULT 0,
  ytd_pnl_usd         NUMERIC(18,2) NOT NULL DEFAULT 0,
  all_time_pnl_usd    NUMERIC(18,2) NOT NULL DEFAULT 0,
  win_rate_pct        NUMERIC(6,2),
  total_trades        INTEGER       NOT NULL DEFAULT 0,

  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- TABLE 11: trading_positions
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.trading_positions (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  trader_id       UUID          NOT NULL REFERENCES public.prop_traders(id),
  pair            TEXT          NOT NULL,    -- e.g. 'EUR/USD'
  side            TEXT          NOT NULL,    -- 'long', 'short'
  entry_price     NUMERIC(18,6) NOT NULL,
  current_price   NUMERIC(18,6),
  exit_price      NUMERIC(18,6),
  lot_size_usd    NUMERIC(18,2) NOT NULL,
  pnl_usd         NUMERIC(18,2) NOT NULL DEFAULT 0,
  status          TEXT          NOT NULL DEFAULT 'open', -- 'open', 'closed'
  opened_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  closed_at       TIMESTAMPTZ,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- TABLE 12: platform_config (admin-controlled settings)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.platform_config (
  key             TEXT          PRIMARY KEY,
  value           TEXT          NOT NULL,
  description     TEXT,
  updated_by      UUID          REFERENCES public.users(id),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Default config values
INSERT INTO public.platform_config (key, value, description) VALUES
  ('platform_fee_pct',        '1.00',    'Transaction fee percentage'),
  ('daily_payout_time_utc',   '09:00',   'Daily ROI payout time in UTC'),
  ('min_deposit_usd',         '10',      'Minimum deposit amount USD'),
  ('min_withdrawal_usd',      '50',      'Minimum withdrawal amount USD'),
  ('kyc_threshold_usd',       '1000',    'KYC required above this investment amount'),
  ('platform_active',         'true',    'Global platform on/off switch'),
  ('trading_desk_active',     'true',    'Prop trading desk on/off'),
  ('new_listings_open',       'true',    'Accept new property submissions'),
  ('funding_applications_open','true',   'Accept startup funding applications'),
  ('maintenance_mode',        'false',   'Maintenance mode');

-- ═══════════════════════════════════════════════════════════════
-- TABLE 13: audit_log (admin action tracking)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.audit_log (
  id          UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  actor_id    UUID          REFERENCES public.users(id),
  action      TEXT          NOT NULL,  -- 'kyc_approved', 'property_listed', etc.
  target_type TEXT,                    -- 'user', 'property', 'investment'
  target_id   UUID,
  old_data    JSONB,
  new_data    JSONB,
  ip_address  INET,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- INDEXES — For query performance
-- ═══════════════════════════════════════════════════════════════

-- Users
CREATE INDEX idx_users_email          ON public.users(email);
CREATE INDEX idx_users_wallet         ON public.users(wallet_address);
CREATE INDEX idx_users_kyc_status     ON public.users(kyc_status);
CREATE INDEX idx_users_role           ON public.users(role);

-- Properties
CREATE INDEX idx_properties_status    ON public.properties(status);
CREATE INDEX idx_properties_token     ON public.properties(token_symbol);
CREATE INDEX idx_properties_country   ON public.properties(country);
CREATE INDEX idx_properties_featured  ON public.properties(featured);

-- Investments
CREATE INDEX idx_investments_user     ON public.investments(user_id);
CREATE INDEX idx_investments_property ON public.investments(property_id);
CREATE INDEX idx_investments_active   ON public.investments(is_active);

-- Transactions
CREATE INDEX idx_tx_user              ON public.transactions(user_id);
CREATE INDEX idx_tx_property          ON public.transactions(property_id);
CREATE INDEX idx_tx_type              ON public.transactions(tx_type);
CREATE INDEX idx_tx_status            ON public.transactions(status);
CREATE INDEX idx_tx_created           ON public.transactions(created_at DESC);

-- ROI Payouts
CREATE INDEX idx_payouts_user         ON public.roi_payouts(user_id);
CREATE INDEX idx_payouts_investment   ON public.roi_payouts(investment_id);
CREATE INDEX idx_payouts_date         ON public.roi_payouts(payout_date DESC);
CREATE INDEX idx_payouts_run          ON public.roi_payouts(payout_run_id);

-- Wallet Ledger
CREATE INDEX idx_ledger_user          ON public.wallet_ledger(user_id);
CREATE INDEX idx_ledger_created       ON public.wallet_ledger(created_at DESC);

-- Audit Log
CREATE INDEX idx_audit_actor          ON public.audit_log(actor_id);
CREATE INDEX idx_audit_target         ON public.audit_log(target_id);
CREATE INDEX idx_audit_created        ON public.audit_log(created_at DESC);
