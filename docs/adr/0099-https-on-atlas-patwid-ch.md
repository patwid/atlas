# 0099. Serve Atlas over HTTPS on atlas.patwid.ch

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (registered patwid.ch at Infomaniak and chose the name and the Let's Encrypt e-mail); agent (the details below)

## Context

[0092](0092-plain-http-on-the-ip-until-there-is-a-domain.md) let the server run on `http://204.168.179.170` until there was a domain,
giving up encrypted passwords, the offline app shell and Strava. The owner now has `patwid.ch` at Infomaniak and has pointed
`atlas.patwid.ch` at the server with an `A` record (TTL 300 while setting up).

The server does not use its IPv6 address yet: Hetzner assigned `2a01:4f9:c014:7b4b::/64`, but `enp1s0` has only its IPv4 address
and a link-local `fe80::` one. The owner chose to leave IPv6 off for now.

## Options considered

1. **`https://atlas.patwid.ch`, IPv4 only for now**: the change 0092 planned (`publicUrl` and `acmeEmail`), nothing else.
2. **Also add IPv6 and an `AAAA` record in the same change**: the server's network is run by NetworkManager, so the address
   would go into its profile for `enp1s0`; changing the live network during the same deploy that first fetches a certificate
   makes a failure harder to place and could cut the SSH connection.

## Decision

We take option 1: `publicUrl = "https://atlas.patwid.ch"` and `acmeEmail` set in `nix/hosts/atlas/default.nix`. Caddy gets the
certificate from Let's Encrypt on its own and the module adds `Strict-Transport-Security` again. No `AAAA` record until the server
answers on IPv6: with one, Let's Encrypt and IPv6 clients would try an address that does not answer.

## Consequences

- Passwords and tokens are encrypted, the app shell works offline, and Strava can be set up (`docs/deploy.md`, step 6).
- The old `http://204.168.179.170` address no longer serves the app; sessions and local data stored for that origin do not
  carry over, so users sign in again.
- `DEPLOY_HOST` stays the IP: the deploy connects over SSH and only the health check uses `publicUrl`.
- IPv6 is follow-up work: `2a01:4f9:c014:7b4b::1/64` with the gateway `fe80::1` in a NetworkManager profile for `enp1s0`
  (Hetzner sends no router advertisements), then the `AAAA` record.
