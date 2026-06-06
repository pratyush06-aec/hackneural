# Hacktropica Referral Dashboard

A lightweight, high-performance referral management dashboard built with vanilla HTML, CSS, and JavaScript, powered by a **Supabase** backend. It is designed to track clicks on custom referral links and monitor successful sign-ups (referrals) on a target platform (Neural).

## 🚀 Features
- **Secure Authentication**: Password-protected dashboard utilizing Supabase Auth.
- **Link Management**: Create and manage custom referral codes.
- **Click Tracking**: Intercepts link clicks to log analytics before instantly redirecting users.
- **Conversion Analytics**: Visualizes daily click statistics and conversion rates using Chart.js.
- **Zero-Build Frontend**: No bundlers, Node.js, or npm required. Just deploy static HTML/JS files to any static host.

## 📂 Project Structure

- `index.html`: The secure login page. It validates configuration from `config.js` and handles Supabase authentication.
- `dashboard.html`: The core dashboard UI. Handles fetching analytics, managing referral links, and rendering charts.
- `track.html`: A lightweight redirect script. It records a click event in the Supabase database and instantly forwards the user to the destination page.
- `config.js`: The central configuration file holding the Supabase credentials and dashboard URL.
- `setup.sql`: The primary SQL schema to set up Supabase tables (`referral_links`, `link_clicks`), indexes, Row Level Security (RLS) policies, and RPC (Remote Procedure Call) functions.
- `auto_create_link.sql`: An SQL script to create a database trigger (`trg_auto_create_referral_link`) that automatically creates a referral link in the dashboard if an unknown username is detected in a new referral.
- `fix_functions.sql`: An optional SQL script to strictly re-apply RPC helper functions without touching the table definitions.
- Branding assets: `logo.svg`, `primary_white.png`, and `secondary_white.png` used across the UI.

## 🏗️ Architecture & Flow

### 1. The Tracking Flow (Click & Redirect)
1. You share a link like: `https://your-domain.com/track.html?ref=TWITTER_CAMPAIGN`.
2. A user clicks the link and lands on `track.html`.
3. `track.html` makes a fire-and-forget REST API call to Supabase to log a row in the `link_clicks` table.
4. The user is instantly redirected to the destination (e.g., `https://helloneural.ai/preorder?ref=TWITTER_CAMPAIGN`).

### 2. The Conversion Flow (Sign Up)
1. The user lands on the destination site and submits their email.
2. The destination site fires the `record_referral(p_username)` RPC function on Supabase.
3. This increments the sign-up count in the `referrals` table for that specific `ref_code`.
4. (Optional) If it's a completely new ref code, the trigger from `auto_create_link.sql` automatically registers it in the dashboard.

### 3. The Analytics Flow (Dashboard)
1. You log in to `dashboard.html`.
2. The dashboard calls `get_link_stats()` and `get_daily_stats()` RPCs.
3. It joins data from the `referral_links`, `link_clicks`, and `referrals` tables to compute overall conversion rates and graph daily clicks.

## 🛠️ Setup & Installation

### Step 1: Supabase Database Setup
1. Create a new [Supabase](https://supabase.com) project.
2. Ensure you have a baseline `referrals` table with `username` (TEXT) and `count` (INTEGER) columns.
3. Go to the **SQL Editor** in the Supabase dashboard.
4. Copy the contents of `setup.sql` and run the query to establish all tables, RLS policies, and functions.
5. (Optional) Run `auto_create_link.sql` to enable auto-registration of unknown ref codes.

### Step 2: Create Admin Account
1. In the Supabase dashboard, navigate to **Authentication** > **Users**.
2. Click **Add user** > **Create new user**.
3. Set an email and password. This will be your exclusive login for the dashboard.

### Step 3: Frontend Configuration
Open `config.js` in a text editor and update the following variables:
```javascript
const SUPABASE_URL = 'https://YOUR-PROJECT-ID.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-KEY-HERE';
const DASHBOARD_URL = 'https://your-dashboard-domain.com'; // No trailing slash
```

### Step 4: Deployment
Upload the entire codebase directory to any static web host (e.g., Bluehost, Vercel, Netlify, or GitHub Pages).

### Step 5: Target Site Integration
On the target site (e.g., `helloneural.ai`), you must trigger the conversion event when a user successfully signs up. Use the Supabase client to call the RPC function with the captured reference code:
```javascript
// Example frontend snippet
await supabase.rpc('record_referral', { p_username: 'THE_REF_CODE' });
```

## 🔒 Security
- **Row Level Security (RLS)**: The database is secured at the row level. Only authenticated dashboard users can read data.
- **Anon Interactions**: `track.html` and the target site snippet only have privileges to insert clicks and increment referral counts via strictly defined paths. They cannot read or delete data.
