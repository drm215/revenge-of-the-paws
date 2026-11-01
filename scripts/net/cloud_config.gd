class_name CloudConfig
extends RefCounted

## Supabase project used for cloud saves (see server/supabase.sql). The anon key is meant to be
## public: row-level security on the `saves` table keeps each player to their own row.
## Leave URL empty to turn cloud saves off.

const URL := "https://yzbnwyeiiwgqezxgrlzv.supabase.co"
const ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl6Ym53eWVpaXdncWV6eGdybHp2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1NjA5MjcsImV4cCI6MjEwOTEzNjkyN30.kv4G5kRPRJZvaokBIT12A6Dlg0Vnjy18y7qN6iwPbQs"
## Where email links (confirm account, reset password) lead from non-web builds.
const SITE_URL := "https://revengeofthepaws.com"
