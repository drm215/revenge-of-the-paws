class_name CloudConfig
extends RefCounted

## Supabase project used for cloud saves (see server/supabase.sql). The anon key is meant to be
## public: row-level security on the `saves` table keeps each player to their own row.
## Leave URL empty to turn cloud saves off.

const URL := ""
const ANON_KEY := ""
## Where email links (confirm account, reset password) lead from non-web builds.
const SITE_URL := "https://revengeofthepaws.com"
