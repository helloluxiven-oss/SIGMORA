// ═══════════════════════════════════════════════════════════════
// SIGMORA — SUPABASE INTEGRATION LAYER
// File: /js/supabase.js
// Drop this in your project, include before other scripts
// ═══════════════════════════════════════════════════════════════

// ─── 1. INITIALIZE ────────────────────────────────────────────
// Get these from: Supabase Dashboard → Settings → API
const SUPABASE_URL  = 'https://YOUR_PROJECT_ID.supabase.co';
const SUPABASE_ANON = 'YOUR_ANON_PUBLIC_KEY';

// Load Supabase via CDN in your HTML <head>:
// <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>

const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON);

// ═══════════════════════════════════════════════════════════════
// AUTH MODULE
// ═══════════════════════════════════════════════════════════════

const Auth = {

  // Sign up with email
  async signUp(email, password, fullName) {
    const { data, error } = await db.auth.signUp({
      email,
      password,
      options: { data: { full_name: fullName } }
    });
    if (error) throw error;
    return data;
  },

  // Sign in
  async signIn(email, password) {
    const { data, error } = await db.auth.signInWithPassword({ email, password });
    if (error) throw error;

    // Update last_login_at
    await db.from('users').update({ last_login_at: new Date().toISOString() })
          .eq('id', data.user.id);

    return data;
  },

  // Sign out
  async signOut() {
    const { error } = await db.auth.signOut();
    if (error) throw error;
    window.location.href = '/login.html';
  },

  // Get current session
  async getSession() {
    const { data: { session } } = await db.auth.getSession();
    return session;
  },

  // Get current user profile
  async getProfile() {
    const { data: { user } } = await db.auth.getUser();
    if (!user) return null;

    const { data, error } = await db.from('users').select('*').eq('id', user.id).single();
    if (error) throw error;
    return data;
  },

  // Update profile
  async updateProfile(updates) {
    const { data: { user } } = await db.auth.getUser();
    const { data, error } = await db.from('users').update(updates).eq('id', user.id).select().single();
    if (error) throw error;
    return data;
  },

  // Listen for auth changes (call once on page load)
  onAuthChange(callback) {
    return db.auth.onAuthStateChange(callback);
  }
};

// ═══════════════════════════════════════════════════════════════
// PROPERTIES MODULE
// ═══════════════════════════════════════════════════════════════

const Properties = {

  // Fetch all active properties
  async getAll(filters = {}) {
    let query = db.from('v_properties')
      .select('*')
      .eq('status', 'active')
      .order('sort_order', { ascending: true });

    if (filters.country)      query = query.eq('country', filters.country);
    if (filters.type)         query = query.eq('property_type', filters.type);
    if (filters.featured)     query = query.eq('featured', true);
    if (filters.minRoi)       query = query.gte('daily_roi_percent', filters.minRoi);

    const { data, error } = await query;
    if (error) throw error;
    return data;
  },

  // Get single property
  async getById(id) {
    const { data, error } = await db.from('v_properties')
      .select('*').eq('id', id).single();
    if (error) throw error;
    return data;
  },

  // Get by token symbol (e.g. 'DTK')
  async getBySymbol(symbol) {
    const { data, error } = await db.from('v_properties')
      .select('*').eq('token_symbol', symbol.toUpperCase()).single();
    if (error) throw error;
    return data;
  },

  // Admin: Create property
  async create(propertyData) {
    const slug = propertyData.name.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
    const { data, error } = await db.from('properties')
      .insert({ ...propertyData, slug }).select().single();
    if (error) throw error;
    return data;
  },

  // Admin: Update property status
  async updateStatus(id, status) {
    const { data, error } = await db.from('properties')
      .update({ status }).eq('id', id).select().single();
    if (error) throw error;
    return data;
  }
};

// ═══════════════════════════════════════════════════════════════
// INVESTMENTS MODULE
// ═══════════════════════════════════════════════════════════════

const Investments = {

  // Buy tokens — calls the secure DB function
  async buyTokens(propertyId, tokenAmount, reinvestMode = 'off', paymentMethod = 'wallet_balance') {
    const { data, error } = await db.rpc('buy_tokens', {
      p_property_id:    propertyId,
      p_token_amount:   tokenAmount,
      p_payment_method: paymentMethod,
      p_reinvest:       reinvestMode
    });
    if (error) throw error;
    if (!data.success) throw new Error(data.error);
    return data;
  },

  // Get user's full portfolio
  async getPortfolio() {
    const { data, error } = await db.rpc('get_user_portfolio');
    if (error) throw error;
    return data;
  },

  // Get user's investments (simple version)
  async getMyInvestments() {
    const { data, error } = await db.from('v_user_investments')
      .select('*').eq('is_active', true).order('created_at', { ascending: false });
    if (error) throw error;
    return data;
  },

  // Toggle reinvest
  async toggleReinvest(investmentId, mode) {
    const { data, error } = await db.rpc('toggle_reinvest', {
      p_investment_id: investmentId,
      p_mode: mode
    });
    if (error) throw error;
    return data;
  },

  // Get ROI payout history
  async getPayoutHistory(limit = 30) {
    const { data, error } = await db.from('roi_payouts')
      .select(`*, properties(name, token_symbol)`)
      .order('created_at', { ascending: false })
      .limit(limit);
    if (error) throw error;
    return data;
  }
};

// ═══════════════════════════════════════════════════════════════
// TRANSACTIONS MODULE
// ═══════════════════════════════════════════════════════════════

const Transactions = {

  // Get user's transaction history
  async getHistory(filters = {}) {
    let query = db.from('transactions')
      .select(`*, properties(name, token_symbol)`)
      .order('created_at', { ascending: false });

    if (filters.type)   query = query.eq('tx_type', filters.type);
    if (filters.limit)  query = query.limit(filters.limit);
    else                query = query.limit(50);

    const { data, error } = await query;
    if (error) throw error;
    return data;
  },

  // Deposit funds
  async deposit(amountUsd, paymentMethod, reference) {
    const { data, error } = await db.rpc('deposit_funds', {
      p_amount_usd:     amountUsd,
      p_payment_method: paymentMethod,
      p_reference:      reference || null
    });
    if (error) throw error;
    return data;
  },

  // Get wallet ledger
  async getLedger(limit = 20) {
    const { data, error } = await db.from('wallet_ledger')
      .select('*').order('created_at', { ascending: false }).limit(limit);
    if (error) throw error;
    return data;
  }
};

// ═══════════════════════════════════════════════════════════════
// ADMIN MODULE
// ═══════════════════════════════════════════════════════════════

const Admin = {

  // Dashboard stats
  async getDashboardStats() {
    const { data, error } = await db.rpc('get_dashboard_stats');
    if (error) throw error;
    return data;
  },

  // All users
  async getUsers(filters = {}) {
    let query = db.from('users').select('*').order('created_at', { ascending: false });
    if (filters.kyc_status) query = query.eq('kyc_status', filters.kyc_status);
    if (filters.role)       query = query.eq('role', filters.role);
    if (filters.limit)      query = query.limit(filters.limit);
    const { data, error } = await query;
    if (error) throw error;
    return data;
  },

  // Update KYC status
  async updateKyc(userId, status, notes = '') {
    const { data, error } = await db.rpc('update_kyc_status', {
      p_user_id: userId,
      p_status:  status,
      p_notes:   notes
    });
    if (error) throw error;
    return data;
  },

  // Confirm deposit
  async confirmDeposit(txId) {
    const { data, error } = await db.rpc('confirm_deposit', { p_tx_id: txId });
    if (error) throw error;
    return data;
  },

  // Trigger daily ROI payout (run via edge function in production)
  async runDailyPayout(date) {
    const { data, error } = await db.rpc('process_daily_roi', {
      p_payout_date: date || new Date().toISOString().split('T')[0]
    });
    if (error) throw error;
    return data;
  },

  // Get payout summary
  async getPayoutSummary() {
    const { data, error } = await db.from('v_payout_summary').select('*').limit(30);
    if (error) throw error;
    return data;
  },

  // Get all pending transactions
  async getPendingTransactions() {
    const { data, error } = await db.from('transactions')
      .select(`*, users(email, full_name)`)
      .eq('status', 'pending')
      .order('created_at', { ascending: true });
    if (error) throw error;
    return data;
  },

  // Update platform config
  async setConfig(key, value) {
    const { data, error } = await db.from('platform_config')
      .update({ value, updated_at: new Date().toISOString() })
      .eq('key', key).select().single();
    if (error) throw error;
    return data;
  },

  // Get audit log
  async getAuditLog(limit = 100) {
    const { data, error } = await db.from('audit_log')
      .select(`*, users!actor_id(email, full_name)`)
      .order('created_at', { ascending: false })
      .limit(limit);
    if (error) throw error;
    return data;
  }
};

// ═══════════════════════════════════════════════════════════════
// STARTUPS MODULE
// ═══════════════════════════════════════════════════════════════

const Startups = {
  async getDeals(status = 'open') {
    const { data, error } = await db.from('startup_deals')
      .select('*').in('status', ['open', 'funded', 'active'])
      .order('created_at', { ascending: false });
    if (error) throw error;
    return data;
  },

  async invest(startupId, amountUsd) {
    const { data: { user } } = await db.auth.getUser();

    // Check balance
    const { data: userRow } = await db.from('users')
      .select('wallet_balance_usd').eq('id', user.id).single();

    if (userRow.wallet_balance_usd < amountUsd) {
      throw new Error('Insufficient wallet balance');
    }

    // Deduct + insert
    const { error: e1 } = await db.from('users')
      .update({ wallet_balance_usd: userRow.wallet_balance_usd - amountUsd })
      .eq('id', user.id);
    if (e1) throw e1;

    const { data, error } = await db.from('startup_investments')
      .insert({ user_id: user.id, startup_id: startupId, amount_usd: amountUsd })
      .select().single();
    if (error) throw error;
    return data;
  }
};

// ═══════════════════════════════════════════════════════════════
// REAL-TIME SUBSCRIPTIONS
// ═══════════════════════════════════════════════════════════════

const Realtime = {

  // Listen for new payouts on your investments
  onNewPayout(userId, callback) {
    return db.channel('my-payouts')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'roi_payouts',
        filter: `user_id=eq.${userId}`
      }, callback)
      .subscribe();
  },

  // Listen for wallet balance changes
  onWalletUpdate(userId, callback) {
    return db.channel('my-wallet')
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'users',
        filter: `id=eq.${userId}`
      }, callback)
      .subscribe();
  },

  // Listen for new transactions
  onNewTransaction(userId, callback) {
    return db.channel('my-transactions')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'transactions',
        filter: `user_id=eq.${userId}`
      }, callback)
      .subscribe();
  },

  // Admin: Watch live platform activity
  onAnyTransaction(callback) {
    return db.channel('platform-activity')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'transactions'
      }, callback)
      .subscribe();
  },

  unsubscribe(channel) {
    db.removeChannel(channel);
  }
};

// ═══════════════════════════════════════════════════════════════
// UTILITY: Route Guard
// Use on every protected page
// ═══════════════════════════════════════════════════════════════

async function requireAuth(adminRequired = false) {
  const session = await Auth.getSession();
  if (!session) {
    window.location.href = '/login.html';
    return null;
  }
  if (adminRequired) {
    const profile = await Auth.getProfile();
    if (!['admin', 'super_admin'].includes(profile.role)) {
      window.location.href = '/dashboard.html';
      return null;
    }
    return profile;
  }
  return session;
}

// ═══════════════════════════════════════════════════════════════
// Export all modules (if using modules)
// OR just use them as globals if plain HTML
// ═══════════════════════════════════════════════════════════════

// If using ES modules:
// export { db, Auth, Properties, Investments, Transactions, Admin, Startups, Realtime };
