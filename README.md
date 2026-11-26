# LatSOFAudio for ThinkPad T14 Gen 4 (Raptor Lake-P, 8086:51CA)

Experimental port of [macintelk/LatSOFAudio](https://github.com/macintelk/LatSOFAudio)
(fork of [pokipoi/LatSOF-Audio](https://github.com/pokipoi/LatSOF-Audio)) for the T14 Gen 4 built-in
digital microphones. Untested on this hardware.

Changes from upstream:
- matches the Raptor Lake-P/U/H cAVS controller 8086:51CA (Linux drives it with the TGL ops)
- embeds `sof-rpl.ri` (SOF 2.2.0, IPC3) from this laptop's Linux install instead of `sof-tgl.ri`
- built with a macOS 13 minimum so it can load on Ventura

Linux on this laptop: 2 DMICs in NHLT (48 kHz, 2 ch), IPC3 firmware `intel/sof/sof-rpl.ri`,
topology `sof-hda-generic-2ch.tplg`.

MIT (see LICENSE); SOF firmware BSD-3-Clause/GPL-2.0 (see LICENSE.sof).
