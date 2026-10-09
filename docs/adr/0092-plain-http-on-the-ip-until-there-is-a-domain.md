# 0092. Plain HTTP on the server's IP address until there is a domain

- Status: Superseded by [0099](0099-https-on-atlas-patwid-ch.md)
- Date: 2026-10-09
- Deciders: owner (asked to use HTTP with the IP address for now); agent (the details below)

## Context

[0091](0091-deploy-to-hetzner-with-caddy.md) serves Atlas over HTTPS on a domain. There is no domain yet, and the owner wants the
server running before there is one.

## Options considered

1. **`http://<IP>`**: works today with nothing else to set up.
2. **A wildcard-DNS name such as `<ip-with-dashes>.sslip.io`**: resolves to the server's IP, so Caddy gets a Let's Encrypt
   certificate and everything works as with a domain, but the name depends on a third party's DNS service.
3. **Wait for a domain.**

## Decision

We allow option 1. `hosts/atlas/default.nix` takes the whole `publicUrl` instead of a domain; with an `http://` address Caddy serves
port 80 without TLS (Caddy does this by itself for an `http://` site address), the Let's Encrypt e-mail is not needed, and the module
leaves out `Strict-Transport-Security`, which only makes sense over HTTPS. Switching to a domain later means changing `publicUrl`
to `https://...` and setting the e-mail; nothing else.

## Consequences

What plain HTTP gives up, until the switch:

- **Passwords and session tokens cross the internet unencrypted**, for the app and for PocketBase's admin UI. Anyone on the path
  (a public Wi-Fi, for example) can read them and take over the account, including the superuser. Use test accounts and test data only.
- **No offline app shell**: browsers allow service workers only on HTTPS (0013), so the app does not open without a connection. Data
  stays in IndexedDB and syncing works as before.
- **No Strava**: Strava's callback domain and webhook expect a domain name, so Strava stays unconfigured (the app says so, 0027).
- Option 2 would avoid all three at no cost and with no code change (`publicUrl = "https://<ip-with-dashes>.sslip.io"`), and remains the
  suggested step before real users or real passwords.
