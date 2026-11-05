# SomaFM cross-platform spec

Omarchy is the reference. "Not built" means the macOS app does not do it yet, not that it is out of scope.
The Omarchy colours below come from `preview.png` (theme-driven there); the macOS colours were sampled from it.

## Shared behaviour

- Streams: SomaFM's public channel catalog; each station's highest-quality playlists are probed and the highest-bitrate verified stream is used.
- Now playing: the station's current-song JSON is requested every 20 s while playing.
- Bar item: outlined box containing a single-column output-level meter and the station name; with **Show track name** on, ` - Track — Artist` follows.
- Level meter: measured on the decoded stream before any volume setting, so system volume and the SomaFM slider do not affect it. RMS, mapped from about -45 dB to -8 dB.
- Right-click the bar item: pause / resume.
- Popup: title and **Advanced settings** toggle; now-playing card (station, status, track); Play/Pause, Stop, Copy song; SomaFM volume slider; **Stations** and **History** tabs; search; station list with Favourites first.
- Advanced settings: Validate streams, Sort (A–Z / Most played), Reset listening times, Startup playback, Sleep timer (off, 15, 30, 60, 90 min), Show track name.
- Station rows: artwork, title (★ for favourites), description, bitrate, accumulated listening time. Right-click toggles favourite. Choosing a station does not close the popup.
- History: last 30 observed songs, newest first, no consecutive duplicates; click to copy.
- Persisted: station cache, favourites, sort, listening totals, volume, last station, startup playback, show track, history. The sleep timer is session-only.

## Colours (macOS, sampled from `preview.png`)

Background `#14241F`, text `#CCCDA7`, secondary `#989C80`, accent `#60A387`, card `#24322A`, row `#1D2C25`, current row `#223C33`, button border `#69715C`.

## Status

| Feature | Omarchy | macOS |
|---|---|---|
| Bar box with level meter and station name | yes | yes |
| Show track name in bar | yes, scrolls long titles | yes, static, cut at 32 characters |
| Show track name default | on | **off** |
| Track details on hover | no | yes (tooltip: station, track, bitrate, codec, state) |
| Level meter | yes | yes, source of truth differs (FFmpeg PCM vs `MTAudioProcessingTap`); scaling is not verified identical |
| Popup layout and controls | yes | yes, sampled colours, monospace font |
| Copy song | `wl-copy` | system pasteboard |
| History (30), Startup playback, Sleep timer, last station | yes | yes |
| Station search | filters by all typed words; Enter plays first match | single substring match; **no Enter-to-play** |
| Reconnect with retries and alternative streams | yes (up to six, rotating) | **not built** |
| Distinct buffering / reconnecting / failed states | yes | partial (connecting, buffering, failed; no reconnecting) |
| Media keys / now-playing controls | MPRIS | `MPRemoteCommandCenter` (play, pause, toggle, stop; no volume) |
| Volume via media controls | yes | **not built** |
| Popup close | outside click, or Escape in the search field | outside click or Escape |
| Settings file | `~/.config/omarchy/somafm-stations.json` | `~/Library/Application Support/SomaFMMinimal/stations.json` |
| Automated tests | yes | **none** |
| Dark / light | follows Omarchy theme | always dark |

The macOS app was last run and checked by hand for the bar item and popup layout. The sleep timer, startup playback, history, Escape-to-close and the media keys have not been verified on macOS.
