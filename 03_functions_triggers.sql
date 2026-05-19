-- ═══════════════════════════════════════════════════════════════
-- SIGMORA — FUNCTIONS & TRIGGERS
-- Run AFTER 02_rls_policies.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- TRIGGER 1: Auto-create user profile on auth signup
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', '')
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ═══════════════════════════════════════════════════════════════
-- TRIGGER 2: Auto-update updated_at timestamps
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER properties_updated_at
  BEFORE UPDATE ON public.properties
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER investments_updated_at
  BEFORE UPDATE ON public.investments
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER transactions_updated_at
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ═══════════════════════════════════════════════════════════════
-- TRIGGER 3: Auto-calculate BEP and Double days on property save
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.calculate_property_roi_days()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- BEP = 1 / daily_roi_percent (e.g. 1/0.35 = 285.7 → 286 days)
  IF NEW.daily_roi_percent > 0 THEN
    NEW.bep_days    := CEIL(100.0 / NEW.daily_roi_percent);
    NEW.double_days := CEIL(200.0 / NEW.daily_roi_percent);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER property_roi_calc
  BEFORE INSERT OR UPDATE OF daily_roi_percent ON public.properties
  FOR EACH ROW EXECUTE FUNCTION public.calculate_property_roi_days();

-- ═══════════════════════════════════════════════════════════════
-- TRIGGER 4: Update property tokens_sold when investment changes
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.sync_property_tokens_sold()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  total_sold BIGINT;
BEGIN
  SELECT COALESCE(SUM(tokens_owned), 0)
  INTO total_sold
  FROM public.investments
  WHERE property_id = COALESCE(NEW.property_id, OLD.property_id)
    AND is_active = TRUE;

  UPDATE public.properties
  SET tokens_sold = total_sold,
      investor_count = (
        SELECT COUNT(DISTINCT user_id)
        FROM public.investments
        WHERE property_id = COALESCE(NEW.property_id, OLD.property_id)
          AND is_active = TRUE AND tokens_owned > 0
      )
  WHERE id = COALESCE(NEW.property_id, OLD.property_id);

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER sync_tokens_on_investment_change
  AFTER INSERT OR UPDATE OF tokens_owned ON public.investments
  FOR EACH ROW EXECUTE FUNCTION public.sync_property_tokens_sold();

-- ═══════════════════════════════════════════════════════════════
-- FUNCTION: buy_tokens
-- The main investment function — handles the full buy flow
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.buy_tokens(
  p_property_id     UUID,
  p_token_amount    BIGINT,
  p_payment_method  TEXT DEFAULT 'wallet_balance',
  p_reinvest        reinvest_mode DEFAULT 'off'
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id         UUID := auth.uid();
  v_property        RECORD;
  v_user            RECORD;
  v_gross_usd       NUMERIC(18,2);
  v_fee_usd         NUMERIC(18,2);
  v_net_usd         NUMERIC(18,2);
  v_fee_pct         NUMERIC(8,4);
  v_tx_id           UUID;
  v_investment_id   UUID;
  v_kyc_threshold   NUMERIC(18,2);
BEGIN
  -- ── 1. Validate user ──────────────────────────────────────
  SELECT * INTO v_user FROM public.users WHERE id = v_user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'User not found');
  END IF;
  IF NOT v_user.is_active THEN
    RETURN jsonb_build_object('success', false, 'error', 'Account is inactive');
  END IF;

  -- ── 2. Validate property ─────────────────────────────────
  SELECT * INTO v_property FROM public.properties WHERE id = p_property_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Property not found');
  END IF;
  IF v_property.status != 'active' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Property is not accepting investments');
  END IF;
  IF p_token_amount < v_property.min_investment_tokens THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Minimum investment is ' || v_property.min_investment_tokens || ' tokens');
  END IF;
  IF (v_property.total_supply - v_property.tokens_sold - v_property.tokens_reserved) < p_token_amount THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not enough tokens available');
  END IF;

  -- ── 3. Calculate amounts ──────────────────────────────────
  v_gross_usd := p_token_amount * v_property.token_price_usd;
  v_fee_pct   := (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'platform_fee_pct');
  v_fee_usd   := ROUND(v_gross_usd * v_fee_pct / 100, 2);
  v_net_usd   := v_gross_usd + v_fee_usd;  -- user pays gross + fee

  -- ── 4. KYC check ─────────────────────────────────────────
  v_kyc_threshold := (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'kyc_threshold_usd');
  IF v_gross_usd >= v_kyc_threshold AND v_user.kyc_status != 'approved' THEN
    RETURN jsonb_build_object('success', false, 'error',
      'KYC verification required for investments above $' || v_kyc_threshold);
  END IF;

  -- ── 5. Check wallet balance ───────────────────────────────
  IF p_payment_method = 'wallet_balance' THEN
    IF v_user.wallet_balance_usd < v_net_usd THEN
      RETURN jsonb_build_object('success', false, 'error',
        'Insufficient wallet balance. Need $' || v_net_usd || ', have $' || v_user.wallet_balance_usd);
    END IF;
  END IF;

  -- ── 6. Deduct from wallet balance ────────────────────────
  IF p_payment_method = 'wallet_balance' THEN
    UPDATE public.users
    SET wallet_balance_usd  = wallet_balance_usd - v_net_usd,
        total_invested_usd  = total_invested_usd + v_gross_usd
    WHERE id = v_user_id;

    -- Ledger entry
    INSERT INTO public.wallet_ledger (user_id, entry_type, amount_usd, balance_before, balance_after, description)
    VALUES (v_user_id, 'debit', v_net_usd, v_user.wallet_balance_usd,
            v_user.wallet_balance_usd - v_net_usd,
            'Token purchase: ' || p_token_amount || ' ' || v_property.token_symbol);
  END IF;

  -- ── 7. Create transaction record ──────────────────────────
  INSERT INTO public.transactions (
    user_id, property_id, tx_type, status,
    token_amount, token_price_usd, gross_amount_usd, fee_amount_usd, net_amount_usd,
    payment_method, processed_at
  ) VALUES (
    v_user_id, p_property_id, 'buy', 'completed',
    p_token_amount, v_property.token_price_usd, v_gross_usd, v_fee_usd, v_net_usd,
    p_payment_method, NOW()
  ) RETURNING id INTO v_tx_id;

  -- ── 8. Upsert investment record ───────────────────────────
  INSERT INTO public.investments (
    user_id, property_id, tokens_owned, avg_buy_price_usd,
    total_invested_usd, reinvest_mode
  ) VALUES (
    v_user_id, p_property_id, p_token_amount,
    v_property.token_price_usd, v_gross_usd, p_reinvest
  )
  ON CONFLICT (user_id, property_id) DO UPDATE SET
    tokens_owned        = investments.tokens_owned + EXCLUDED.tokens_owned,
    avg_buy_price_usd   = (
      (investments.total_invested_usd + EXCLUDED.total_invested_usd)
      / (investments.tokens_owned + EXCLUDED.tokens_owned)
    ),
    total_invested_usd  = investments.total_invested_usd + EXCLUDED.total_invested_usd,
    reinvest_mode       = p_reinvest,
    is_active           = TRUE
  RETURNING id INTO v_investment_id;

  -- Update tx with investment_id
  UPDATE public.transactions SET investment_id = v_investment_id WHERE id = v_tx_id;

  -- ── 9. Audit log ──────────────────────────────────────────
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, new_data)
  VALUES (v_user_id, 'token_purchase', 'investment', v_investment_id,
    jsonb_build_object(
      'property_id', p_property_id,
      'tokens', p_token_amount,
      'usd_amount', v_gross_usd
    )
  );

  -- ── 10. Return success ────────────────────────────────────
  RETURN jsonb_build_object(
    'success',        true,
    'transaction_id', v_tx_id,
    'investment_id',  v_investment_id,
    'tokens_bought',  p_token_amount,
    'gross_usd',      v_gross_usd,
    'fee_usd',        v_fee_usd,
    'total_paid_usd', v_net_usd,
    'message',        'Investment successful! Daily ROI starts tomorrow.'
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- FUNCTION: process_daily_roi
-- Run this daily via Supabase Edge Function / pg_cron
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.process_daily_roi(
  p_payout_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_run_id          UUID := uuid_generate_v4();
  v_total_paid      NUMERIC(18,2) := 0;
  v_recipient_count INTEGER := 0;
  v_rec             RECORD;
  v_roi_amount      NUMERIC(18,2);
  v_fee_usd         NUMERIC(18,2);
  v_net_amount      NUMERIC(18,2);
  v_fee_pct         NUMERIC(8,4);
  v_reinvest_tokens BIGINT;
  v_payout_tx_id    UUID;
  v_reinvest_tx_id  UUID;
BEGIN
  v_fee_pct := (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'platform_fee_pct');

  -- Loop through all active investments that have not been paid today
  FOR v_rec IN
    SELECT
      i.id          AS investment_id,
      i.user_id,
      i.property_id,
      i.tokens_owned,
      i.reinvest_mode,
      i.total_invested_usd,
      i.total_roi_earned_usd,
      i.bep_reached,
      i.double_reached,
      p.daily_roi_percent,
      p.token_price_usd,
      p.token_symbol,
      u.wallet_balance_usd
    FROM public.investments i
    JOIN public.properties p ON p.id = i.property_id
    JOIN public.users u ON u.id = i.user_id
    WHERE i.is_active = TRUE
      AND i.tokens_owned > 0
      AND p.status = 'active'
      AND u.is_active = TRUE
      -- Hasn't been paid today
      AND NOT EXISTS (
        SELECT 1 FROM public.roi_payouts rp
        WHERE rp.investment_id = i.id
          AND rp.payout_date = p_payout_date
      )
  LOOP
    -- Calculate ROI
    v_roi_amount := ROUND(
      v_rec.tokens_owned * v_rec.token_price_usd * v_rec.daily_roi_percent / 100,
      2
    );
    v_fee_usd   := ROUND(v_roi_amount * v_fee_pct / 100, 2);
    v_net_amount := v_roi_amount - v_fee_usd;

    -- Create payout transaction
    INSERT INTO public.transactions (
      user_id, property_id, investment_id,
      tx_type, status, gross_amount_usd, fee_amount_usd, net_amount_usd,
      processed_at, notes
    ) VALUES (
      v_rec.user_id, v_rec.property_id, v_rec.investment_id,
      'payout', 'completed', v_roi_amount, v_fee_usd, v_net_amount,
      NOW(), 'Daily ROI — ' || p_payout_date
    ) RETURNING id INTO v_payout_tx_id;

    -- Handle reinvestment
    IF v_rec.reinvest_mode = 'on' THEN
      -- Calculate how many tokens the ROI buys
      v_reinvest_tokens := FLOOR(v_net_amount / v_rec.token_price_usd);

      IF v_reinvest_tokens > 0 THEN
        -- Add tokens to investment
        UPDATE public.investments
        SET tokens_owned       = tokens_owned + v_reinvest_tokens,
            total_roi_earned_usd = total_roi_earned_usd + v_net_amount,
            last_payout_at     = NOW(),
            last_payout_amount = v_net_amount
        WHERE id = v_rec.investment_id;

        -- Log reinvest transaction
        INSERT INTO public.transactions (
          user_id, property_id, investment_id, tx_type, status,
          token_amount, token_price_usd, gross_amount_usd, fee_amount_usd, net_amount_usd,
          processed_at, reference_id, notes
        ) VALUES (
          v_rec.user_id, v_rec.property_id, v_rec.investment_id,
          'reinvest', 'completed',
          v_reinvest_tokens, v_rec.token_price_usd,
          v_net_amount, 0, v_net_amount,
          NOW(), v_payout_tx_id, 'Auto-reinvest — ' || p_payout_date
        ) RETURNING id INTO v_reinvest_tx_id;
      END IF;

    ELSE
      -- Credit to wallet
      UPDATE public.users
      SET wallet_balance_usd = wallet_balance_usd + v_net_amount,
          total_earned_usd   = total_earned_usd + v_net_amount
      WHERE id = v_rec.user_id;

      -- Ledger entry
      INSERT INTO public.wallet_ledger (
        user_id, tx_id, entry_type, amount_usd,
        balance_before, balance_after, description
      ) VALUES (
        v_rec.user_id, v_payout_tx_id, 'credit', v_net_amount,
        v_rec.wallet_balance_usd,
        v_rec.wallet_balance_usd + v_net_amount,
        'Daily ROI from ' || v_rec.token_symbol
      );

      UPDATE public.investments
      SET total_roi_earned_usd = total_roi_earned_usd + v_net_amount,
          last_payout_at     = NOW(),
          last_payout_amount = v_net_amount
      WHERE id = v_rec.investment_id;
    END IF;

    -- Log the payout
    INSERT INTO public.roi_payouts (
      investment_id, user_id, property_id, payout_date,
      tokens_at_payout, roi_percent, gross_amount_usd, fee_amount_usd, net_amount_usd,
      was_reinvested, tokens_reinvested, reinvest_tx_id,
      status, payout_run_id
    ) VALUES (
      v_rec.investment_id, v_rec.user_id, v_rec.property_id, p_payout_date,
      v_rec.tokens_owned, v_rec.daily_roi_percent,
      v_roi_amount, v_fee_usd, v_net_amount,
      (v_rec.reinvest_mode = 'on' AND v_reinvest_tokens > 0),
      CASE WHEN v_rec.reinvest_mode = 'on' THEN v_reinvest_tokens ELSE NULL END,
      v_reinvest_tx_id,
      'completed', v_run_id
    );

    -- Check BEP milestone
    IF NOT v_rec.bep_reached THEN
      DECLARE
        v_total_earned NUMERIC(18,2);
        v_new_total    NUMERIC(18,2);
      BEGIN
        v_new_total := v_rec.total_roi_earned_usd + v_net_amount;
        IF v_new_total >= v_rec.total_invested_usd THEN
          UPDATE public.investments
          SET bep_reached = TRUE, bep_reached_at = NOW()
          WHERE id = v_rec.investment_id;
        END IF;
      END;
    END IF;

    v_total_paid      := v_total_paid + v_net_amount;
    v_recipient_count := v_recipient_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success',         true,
    'payout_run_id',   v_run_id,
    'payout_date',     p_payout_date,
    'total_paid_usd',  v_total_paid,
    'recipient_count', v_recipient_count
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- FUNCTION: deposit_funds
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.deposit_funds(
  p_amount_usd      NUMERIC,
  p_payment_method  TEXT DEFAULT 'bank_transfer',
  p_reference       TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id     UUID := auth.uid();
  v_min_deposit NUMERIC;
  v_tx_id       UUID;
  v_prev_bal    NUMERIC;
BEGIN
  v_min_deposit := (SELECT value::NUMERIC FROM public.platform_config WHERE key = 'min_deposit_usd');

  IF p_amount_usd < v_min_deposit THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Minimum deposit is $' || v_min_deposit);
  END IF;

  SELECT wallet_balance_usd INTO v_prev_bal FROM public.users WHERE id = v_user_id;

  -- Create pending transaction (admin confirms later)
  INSERT INTO public.transactions (
    user_id, tx_type, status,
    gross_amount_usd, fee_amount_usd, net_amount_usd,
    payment_method, notes
  ) VALUES (
    v_user_id, 'deposit', 'pending',
    p_amount_usd, 0, p_amount_usd,
    p_payment_method, p_reference
  ) RETURNING id INTO v_tx_id;

  RETURN jsonb_build_object(
    'success',        true,
    'transaction_id', v_tx_id,
    'amount',         p_amount_usd,
    'status',         'pending',
    'message',        'Deposit request created. Funds will be credited after confirmation.'
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- FUNCTION: confirm_deposit (admin only)
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.confirm_deposit(p_tx_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx      RECORD;
  v_prev_bal NUMERIC;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required');
  END IF;

  SELECT * INTO v_tx FROM public.transactions
  WHERE id = p_tx_id AND tx_type = 'deposit' AND status = 'pending';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Pending deposit not found');
  END IF;

  SELECT wallet_balance_usd INTO v_prev_bal FROM public.users WHERE id = v_tx.user_id;

  -- Credit user wallet
  UPDATE public.users
  SET wallet_balance_usd = wallet_balance_usd + v_tx.net_amount_usd
  WHERE id = v_tx.user_id;

  -- Update transaction
  UPDATE public.transactions
  SET status = 'completed', processed_at = NOW()
  WHERE id = p_tx_id;

  -- Ledger
  INSERT INTO public.wallet_ledger (user_id, tx_id, entry_type, amount_usd, balance_before, balance_after, description)
  VALUES (v_tx.user_id, p_tx_id, 'credit', v_tx.net_amount_usd, v_prev_bal,
          v_prev_bal + v_tx.net_amount_usd, 'Deposit confirmed');

  -- Audit
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id)
  VALUES (auth.uid(), 'deposit_confirmed', 'transaction', p_tx_id);

  RETURN jsonb_build_object('success', true, 'message', 'Deposit confirmed and wallet credited');
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- FUNCTION: update_kyc_status (admin only)
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_kyc_status(
  p_user_id   UUID,
  p_status    kyc_status,
  p_notes     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_status kyc_status;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin access required');
  END IF;

  SELECT kyc_status INTO v_old_status FROM public.users WHERE id = p_user_id;

  UPDATE public.users
  SET kyc_status      = p_status,
      kyc_notes       = p_notes,
      kyc_reviewed_at = NOW(),
      kyc_reviewed_by = auth.uid()
  WHERE id = p_user_id;

  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, old_data, new_data)
  VALUES (auth.uid(), 'kyc_status_changed', 'user', p_user_id,
    jsonb_build_object('kyc_status', v_old_status),
    jsonb_build_object('kyc_status', p_status, 'notes', p_notes)
  );

  RETURN jsonb_build_object('success', true, 'message', 'KYC status updated to ' || p_status);
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- FUNCTION: get_dashboard_stats (for admin command center)
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_dashboard_stats()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_build_object(
    'total_users',         (SELECT COUNT(*) FROM public.users),
    'verified_users',      (SELECT COUNT(*) FROM public.users WHERE kyc_status = 'approved'),
    'pending_kyc',         (SELECT COUNT(*) FROM public.users WHERE kyc_status = 'submitted'),
    'active_properties',   (SELECT COUNT(*) FROM public.properties WHERE status = 'active'),
    'total_tvl_usd',       (SELECT COALESCE(SUM(total_invested_usd), 0) FROM public.investments WHERE is_active = TRUE),
    'total_investors',     (SELECT COUNT(DISTINCT user_id) FROM public.investments WHERE is_active = TRUE),
    'tokens_sold_today',   (SELECT COALESCE(SUM(token_amount), 0) FROM public.transactions
                            WHERE tx_type = 'buy' AND status = 'completed'
                            AND DATE(created_at) = CURRENT_DATE),
    'revenue_today_usd',   (SELECT COALESCE(SUM(fee_amount_usd), 0) FROM public.transactions
                            WHERE status = 'completed' AND DATE(created_at) = CURRENT_DATE),
    'payouts_today_usd',   (SELECT COALESCE(SUM(net_amount_usd), 0) FROM public.roi_payouts
                            WHERE payout_date = CURRENT_DATE AND status = 'completed'),
    'trading_pnl_today',   (SELECT COALESCE(SUM(pnl_usd), 0) FROM public.trading_positions
                            WHERE status = 'open')
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- FUNCTION: get_user_portfolio (for the portfolio page)
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_user_portfolio()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID := auth.uid();
  v_result    JSONB;
  v_positions JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'investment_id',      i.id,
      'property_id',        p.id,
      'property_name',      p.name,
      'token_symbol',       p.token_symbol,
      'tokens_owned',       i.tokens_owned,
      'token_price_usd',    p.token_price_usd,
      'current_value_usd',  i.tokens_owned * p.token_price_usd,
      'total_invested_usd', i.total_invested_usd,
      'total_earned_usd',   i.total_roi_earned_usd,
      'daily_roi_pct',      p.daily_roi_percent,
      'daily_earning_usd',  ROUND(i.tokens_owned * p.token_price_usd * p.daily_roi_percent / 100, 2),
      'reinvest_mode',      i.reinvest_mode,
      'bep_reached',        i.bep_reached,
      'bep_reached_at',     i.bep_reached_at,
      'days_invested',      EXTRACT(DAY FROM NOW() - i.created_at)::INTEGER,
      'bep_days_remaining', GREATEST(0,
        p.bep_days - EXTRACT(DAY FROM NOW() - i.created_at)::INTEGER
      ),
      'last_payout_at',     i.last_payout_at,
      'last_payout_usd',    i.last_payout_amount
    )
    ORDER BY i.created_at DESC
  ) INTO v_positions
  FROM public.investments i
  JOIN public.properties p ON p.id = i.property_id
  WHERE i.user_id = v_user_id AND i.is_active = TRUE;

  SELECT jsonb_build_object(
    'wallet_balance',      u.wallet_balance_usd,
    'total_invested',      u.total_invested_usd,
    'total_earned',        u.total_earned_usd,
    'kyc_status',          u.kyc_status,
    'positions',           COALESCE(v_positions, '[]'::jsonb)
  ) INTO v_result
  FROM public.users u WHERE u.id = v_user_id;

  RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- FUNCTION: toggle_reinvest
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.toggle_reinvest(
  p_investment_id UUID,
  p_mode reinvest_mode
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  UPDATE public.investments
  SET reinvest_mode = p_mode
  WHERE id = p_investment_id AND user_id = v_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Investment not found');
  END IF;

  RETURN jsonb_build_object('success', true, 'reinvest_mode', p_mode);
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- VIEWS — Convenient read-only aggregations
-- ═══════════════════════════════════════════════════════════════

-- Property summary with funding %
CREATE OR REPLACE VIEW public.v_properties AS
SELECT
  p.*,
  ROUND((p.tokens_sold::NUMERIC / p.total_supply * 100), 2) AS funding_pct,
  (p.total_supply - p.tokens_sold - p.tokens_reserved) AS tokens_available,
  (p.tokens_sold * p.token_price_usd) AS raised_usd,
  ROUND(p.daily_roi_percent * 365, 2) AS annual_roi_percent
FROM public.properties p;

-- User investment summary
CREATE OR REPLACE VIEW public.v_user_investments AS
SELECT
  i.*,
  p.name AS property_name,
  p.token_symbol,
  p.token_price_usd,
  p.daily_roi_percent,
  p.bep_days,
  p.cover_image_url,
  (i.tokens_owned * p.token_price_usd) AS current_value_usd,
  ROUND(i.tokens_owned * p.token_price_usd * p.daily_roi_percent / 100, 2) AS daily_earning_usd,
  EXTRACT(DAY FROM NOW() - i.created_at)::INTEGER AS days_since_investment
FROM public.investments i
JOIN public.properties p ON p.id = i.property_id;

-- Daily payout summary (admin)
CREATE OR REPLACE VIEW public.v_payout_summary AS
SELECT
  payout_date,
  COUNT(DISTINCT user_id) AS recipient_count,
  COUNT(*) AS payout_count,
  SUM(gross_amount_usd) AS gross_total,
  SUM(fee_amount_usd) AS fee_total,
  SUM(net_amount_usd) AS net_total,
  SUM(CASE WHEN was_reinvested THEN net_amount_usd ELSE 0 END) AS reinvested_total,
  payout_run_id
FROM public.roi_payouts
GROUP BY payout_date, payout_run_id
ORDER BY payout_date DESC;
