# Art brief (for when you want generated art)

Nothing here has been generated yet — the village draws itself procedurally.
Generation costs credits, so per `CLAUDE.md` Claude must quote the cost and get
a yes before running any of these.

**Reference image:** `map/village_layout.png` (960×672, 24px tiles). Pass it as
the layout reference so buildings land on the right tiles.

**Shared style line** (append to every prompt so assets match):
> cozy top-down 3/4 view pixel-art village, 24px tile grid, soft daylight from top-left, muted warm palette, clean outlines, transparent background

| Asset | File | Size | Prompt |
|---|---|---|---|
| Ground | `ground.png` | 960×672 | Grass field with sand-coloured paths and a small pond exactly matching the reference layout, no buildings |
| Town Hall | `town_hall.png` | 144×96 | Brick town hall with clock tower, red roof, door bottom-centre |
| Library | `library.png` | 144×96 | Blue-slate library with tall arched windows and book sign |
| Post Office | `post_office.png` | 144×96 | Mustard-yellow post office with envelope sign and red mailbox |
| Cafe | `cafe.png` | 144×96 | Rose-brick café with striped awning and two outdoor tables |
| Noticeboard | `noticeboard.png` | 48×24 | Wooden noticeboard with pinned papers |
| Park | `park.png` | 168×120 | Small park with bench, flower beds and path loop |
| Homes | `home_<id>.png` | 96×72 | Small cottage, roof colour matches villager (`#5b7fa6`, `#c9a24a`, `#b5654a`, `#6f8f5a`) |
| Villagers | `<id>.png` | 24×28 | Chibi villager facing camera; Ada librarian with glasses, Bo postmaster with cap and satchel, Cy mayor with sash, Dee scribe with quill |

After saving files here, set their filenames in `assets/manifest.json`.
Anything left `null` keeps the procedural art.
