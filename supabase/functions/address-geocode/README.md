# address-geocode

Server-side geocoding ng `addresses` rows na **TEXT-ONLY** ang na-save (walang
`latitude` / `longitude`).

## Bakit ito kailangan

Ang pin ng rider maps (Live Tracking, Navigate to Lender, CI) ay galing sa
`addresses.latitude` / `addresses.longitude` — parehong kailangang non-null
(`destinationFromAddresses()` sa
`lib/presentation/shared/widgets/map/map_anim_utils.dart`).

Ang mga address form (registration, KYC, profile edit, walk-in wizard) ay
street/barangay/city/province **text lang** ang isinusulat, kaya `NULL` ang
coords at walang pin — **"No saved map pin for this task"** kahit may address sa
file.

Ang client-side fallback (`package:geocoding`) ay **android/ios lang** ang
implementation:

- sa Flutter **web** walang geocoder → laging fail → walang pin;
- sa **mobile** nag-geocode ito pero hindi nase-save, kaya paulit-ulit bawat
  open at wala pa ring pin sa ibang screens.

Kaya: isang beses na geocode sa server → i-save sa `addresses` → lahat ng
client (web + mobile) at lahat ng screens ay may naka-save nang pin.

## Setup (isang beses)

1. **Google Cloud** → APIs & Services → **enable ang "Geocoding API"**.
2. Gumawa ng **server key** (Credentials → Create credentials → API key) at
   i-restrict sa Geocoding API. **Huwag** lagyan ng "HTTP referrers (websites)"
   restriction — ang server-side call ay walang browser referer at
   tatanggihan ito (`REQUEST_DENIED: API keys with referer restrictions cannot
   be used with this API`).
3. Itakda ang secrets:

   ```bash
   supabase secrets set GOOGLE_GEOCODING_API_KEY=AIza...
   # opsyonal: para sa one-off maintenance mula sa terminal/CI
   supabase secrets set GEOCODE_BACKFILL_SECRET=$(openssl rand -hex 24)
   ```

   Fallback: kung naka-set na ang `GOOGLE_MAPS_API_KEY` sa project secrets, iyon
   ang gagamitin kapag wala ang `GOOGLE_GEOCODING_API_KEY` — basta't walang
   referrer restriction ang key.

## Backfill ng mga lumang address (ang nag-aayos ng lumang tasks)

```bash
SUPABASE_URL=https://<project-ref>.supabase.co
ANON_KEY=<anon/publishable key>
SECRET=<GEOCODE_BACKFILL_SECRET>

# Ulit-ulitin hanggang "remaining": 0 — ang bawat tawag ay may limit (default 50,
# max 200) para hindi lumampas sa wall-clock/quota.
curl -sX POST "$SUPABASE_URL/functions/v1/address-geocode?fn=backfill&limit=100" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "x-backfill-secret: $SECRET"
# → {"ok":true,"fn":"backfill","limit":100,"scanned":37,"geocoded":31,"failed":6,"skipped":0,"remaining":0}
```

Isang lender lang:

```bash
curl -sX POST "$SUPABASE_URL/functions/v1/address-geocode?fn=one&user_id=<uuid>" \
  -H "Authorization: Bearer $ANON_KEY" -H "x-backfill-secret: $SECRET"
# o ?fn=one&address_id=<uuid>
```

Kung walang secret header, kailangan ng **staff JWT** (`head_manager` o
`employee`) para sa `backfill`; `one` ay pwede rin sa `rider`.

### Verification

```sql
SELECT count(*) FROM addresses WHERE latitude IS NULL OR longitude IS NULL;
SELECT id, street, barangay, city, province, latitude, longitude
FROM addresses ORDER BY updated_at DESC LIMIT 10;
```

Kung tumaas ang `failed`, tingnan ang function logs — karaniwan ay
`REQUEST_DENIED` (hindi naka-enable ang Geocoding API, o may referrer
restriction ang key) o `ZERO_RESULTS` (kulang ang address: ang query ay
kailangang may hindi bababa sa 2 bahagi, hal. street + barangay).

## Awtomatiko na pagkatapos nito

Ang `_shared/geocode.ts` ay naka-hook sa mga write path — `users-create`,
`users-manage`, `kyc-submit`, `in-office-view` — at nag-geocode sa
**background** (`EdgeRuntime.waitUntil`, hindi hinihintay ng response), kaya ang
mga bagong address ay may coords agad. Ang edit ng address ay **inaayos muli**
ang pin (`overwrite`), dahil stale na ito kapag nagbago ang text.
