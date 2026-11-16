Responses recorded on 2026-11-15 from a local Plex Media Server 1.43.5
(`plexinc/pms-docker`, unclaimed) using the Plex Movie and Plex TV Series
agents. The library held a few seconds of generated test video per title;
titles were chosen so the agents matched real metadata ids. Server file
paths are replaced with `/data/redacted.mkv` and descriptive metadata
(summaries, artwork, cast) is removed.

`resources_doc_derived.json` is NOT a recording: it follows the plex.tv
`/api/v2/resources` shape documented by Plex and python-plexapi, because
listing servers needs a real Plex account. Replace it with a redacted
recording once one is available.
