# DeliGo Web

The Web build must receive public runtime configuration through the hosting build environment. Do not commit `.env`, service-account files, private keys, or provider secrets.

Required build defines:

```text
SUPABASE_URL
SUPABASE_ANON_KEY

Optional browser map define:

```text
MAPTILER_KEY
```

`MAPTILER_KEY` is used only by the Web map renderer. Restrict it in MapTiler
to the production and preview domains and configure quotas. Android continues
using its existing Google Maps implementation.
```

Optional browser keys must be restricted by domain and quota before being configured in the hosting provider. The application falls back to these compile-time defines when no local configuration asset is present.
