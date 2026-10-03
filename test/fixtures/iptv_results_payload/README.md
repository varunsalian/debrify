Captured from the original IPTV State at `d93428fb` with the registered step-0
seams, before extraction, on Flutter 3.44.8. Tests compare unsorted JSON strings:
map insertion order and optional fields are part of the contract.

The episode fixture uses the real Xtream service cache warmed from a temporary
local HTTP panel. Only its variable loopback server address is replaced with
`<panel>` in the captured JSON; keys, values and array order remain exact.
