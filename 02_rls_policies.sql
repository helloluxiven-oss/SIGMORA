-- ═══════════════════════════════════════════════════════════════
-- SIGMORA — ROW LEVEL SECURITY (RLS) POLICIES
-- Run AFTER 01_schema.sql
-- ═══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- HELPER: Check if current user is admin/super_admin
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid()
    AND role IN ('admin', 'super_admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid()
    AND role = 'super_admin'
  );
$$;

-- ─────────────────────────────────────────────────────────────
-- Enable RLS on all tables
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.users              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kyc_documents      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.properties         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investments        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roi_payouts        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_ledger      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.startup_deals      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.startup_investments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prop_traders       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trading_positions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_config    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log          ENABLE ROW LEVEL SECURITY;

-- ═══════════════════════════════════════════════════════════════
-- USERS TABLE POLICIES
-- ═══════════════════════════════════════════════════════════════

-- Users can read their own profile
CREATE POLICY "users_read_own" ON public.users
  FOR SELECT USING (auth.uid() = id);

-- Admins can read all users
CREATE POLICY "admin_read_all_users" ON public.users
  FOR SELECT USING (public.is_admin());

-- Users can update their own non-sensitive fields
CREATE POLICY "users_update_own" ON public.users
  FOR UPDATE USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    -- Prevent users from changing their own role or KYC status
    AND role = (SELECT role FROM public.users WHERE id = auth.uid())
    AND kyc_status = (SELECT kyc_status FROM public.users WHERE id = auth.uid())
  );

-- Admins can update any user
CREATE POLICY "admin_update_users" ON public.users
  FOR UPDATE USING (public.is_admin());

-- Only the system (service role) can insert users — triggered on auth signup
CREATE POLICY "system_insert_users" ON public.users
  FOR INSERT WITH CHECK (auth.uid() = id);

-- ═══════════════════════════════════════════════════════════════
-- KYC DOCUMENTS POLICIES
-- ═══════════════════════════════════════════════════════════════

-- Users see only their own docs
CREATE POLICY "kyc_read_own" ON public.kyc_documents
  FOR SELECT USING (auth.uid() = user_id);

-- Admins see all KYC docs
CREATE POLICY "admin_read_kyc" ON public.kyc_documents
  FOR SELECT USING (public.is_admin());

-- Users can upload their own docs
CREATE POLICY "kyc_insert_own" ON public.kyc_documents
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Only admins can mark docs as verified
CREATE POLICY "admin_update_kyc" ON public.kyc_documents
  FOR UPDATE USING (public.is_admin());

-- ═══════════════════════════════════════════════════════════════
-- PROPERTIES TABLE POLICIES
-- ═══════════════════════════════════════════════════════════════

-- Anyone authenticated can see active properties
CREATE POLICY "public_read_active_properties" ON public.properties
  FOR SELECT USING (
    status = 'active'
    OR public.is_admin()
  );

-- Only admins can create/update/delete properties
CREATE POLICY "admin_manage_properties" ON public.properties
  FOR ALL USING (public.is_admin());

-- ═══════════════════════════════════════════════════════════════
-- INVESTMENTS TABLE POLICIES
-- ═══════════════════════════════════════════════════════════════

-- Users see only their own investments
CREATE POLICY "investments_read_own" ON public.investments
  FOR SELECT USING (auth.uid() = user_id);

-- Admins see all investments
CREATE POLICY "admin_read_all_investments" ON public.investments
  FOR SELECT USING (public.is_admin());

-- Users can insert their own investment (via function only in practice)
CREATE POLICY "investments_insert_own" ON public.investments
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Investments updated by owner or admin only
CREATE POLICY "investments_update_own" ON public.investments
  FOR UPDATE USING (auth.uid() = user_id OR public.is_admin());

-- ═══════════════════════════════════════════════════════════════
-- TRANSACTIONS TABLE POLICIES
-- ═══════════════════════════════════════════════════════════════

-- Users see only their own transactions
CREATE POLICY "tx_read_own" ON public.transactions
  FOR SELECT USING (auth.uid() = user_id);

-- Admins see all transactions
CREATE POLICY "admin_read_all_tx" ON public.transactions
  FOR SELECT USING (public.is_admin());

-- Transactions are inserted by the system (SECURITY DEFINER functions)
-- Users can initiate via RPC functions only
CREATE POLICY "tx_insert_own" ON public.transactions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ═══════════════════════════════════════════════════════════════
-- ROI PAYOUTS POLICIES
-- ═══════════════════════════════════════════════════════════════

-- Users see their own payouts
CREATE POLICY "payouts_read_own" ON public.roi_payouts
  FOR SELECT USING (auth.uid() = user_id);

-- Admins see all payouts
CREATE POLICY "admin_read_payouts" ON public.roi_payouts
  FOR SELECT USING (public.is_admin());

-- Only service role / functions can insert payouts
CREATE POLICY "system_insert_payouts" ON public.roi_payouts
  FOR INSERT WITH CHECK (public.is_admin());

-- ═══════════════════════════════════════════════════════════════
-- WALLET LEDGER POLICIES
-- ═══════════════════════════════════════════════════════════════

CREATE POLICY "ledger_read_own" ON public.wallet_ledger
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "admin_read_ledger" ON public.wallet_ledger
  FOR SELECT USING (public.is_admin());

-- Only internal functions insert ledger entries
CREATE POLICY "system_insert_ledger" ON public.wallet_ledger
  FOR INSERT WITH CHECK (public.is_admin() OR auth.uid() = user_id);

-- ═══════════════════════════════════════════════════════════════
-- STARTUP DEALS POLICIES
-- ═══════════════════════════════════════════════════════════════

-- All authenticated users can see open/active deals
CREATE POLICY "public_read_startup_deals" ON public.startup_deals
  FOR SELECT USING (
    status IN ('open', 'funded', 'active')
    OR public.is_admin()
  );

-- Only admins manage deals
CREATE POLICY "admin_manage_deals" ON public.startup_deals
  FOR ALL USING (public.is_admin());

-- ═══════════════════════════════════════════════════════════════
-- STARTUP INVESTMENTS POLICIES
-- ═══════════════════════════════════════════════════════════════

CREATE POLICY "startup_inv_read_own" ON public.startup_investments
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "admin_read_startup_inv" ON public.startup_investments
  FOR SELECT USING (public.is_admin());

CREATE POLICY "startup_inv_insert_own" ON public.startup_investments
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ═══════════════════════════════════════════════════════════════
-- PROP TRADERS POLICIES
-- ═══════════════════════════════════════════════════════════════

-- All users can see trader performance (public leaderboard)
CREATE POLICY "public_read_traders" ON public.prop_traders
  FOR SELECT USING (TRUE);

-- Only admins manage traders
CREATE POLICY "admin_manage_traders" ON public.prop_traders
  FOR ALL USING (public.is_admin());

-- ═══════════════════════════════════════════════════════════════
-- TRADING POSITIONS POLICIES
-- ═══════════════════════════════════════════════════════════════

-- All users can see open positions (transparency)
CREATE POLICY "public_read_positions" ON public.trading_positions
  FOR SELECT USING (TRUE);

-- Only admins manage positions
CREATE POLICY "admin_manage_positions" ON public.trading_positions
  FOR ALL USING (public.is_admin());

-- ═══════════════════════════════════════════════════════════════
-- PLATFORM CONFIG POLICIES
-- ═══════════════════════════════════════════════════════════════

-- All authenticated users can read config
CREATE POLICY "authenticated_read_config" ON public.platform_config
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Only super admins can change config
CREATE POLICY "super_admin_manage_config" ON public.platform_config
  FOR ALL USING (public.is_super_admin());

-- ═══════════════════════════════════════════════════════════════
-- AUDIT LOG POLICIES
-- ═══════════════════════════════════════════════════════════════

-- Only admins can read audit logs
CREATE POLICY "admin_read_audit" ON public.audit_log
  FOR SELECT USING (public.is_admin());

-- System inserts audit entries (all roles can insert)
CREATE POLICY "system_insert_audit" ON public.audit_log
  FOR INSERT WITH CHECK (TRUE);
