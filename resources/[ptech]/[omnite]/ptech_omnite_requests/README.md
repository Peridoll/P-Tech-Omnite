# P-Tech Omnite Requests

Configurable request and delivery boards for FiveM roleplay servers using Qbox.

## Install

1. Copy `ptech_omnite_requests` into the server's resources directory.
2. Configure board locations, permissions, form fields, delivery items, and rewards in `config/config.lua`.
3. Add `ensure ptech_omnite_requests` after `qbx_core`, `ox_lib`, `ox_target`, `oxmysql`, and `ox_inventory` in `server.cfg`.

## Current features

- General and job boards with separate view, post, accept, deliver, and manage permissions.
- Accepted missions with individual acceptance records and a configurable maximum acceptance count.
- Delivery missions with a maximum total quantity and payment per delivered item.
- Server-side permission, distance, inventory, and quantity validation.
- MySQL persistence for missions and individual acceptance records.

Board coordinates, access rules, inventory item names, and payment values are examples until configured for the target server. See the repository's `DEVELOPMENT.md` for design and pending decisions.
