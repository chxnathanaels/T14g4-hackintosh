This build embeds `sof-rpl.ri` (Raptor Lake-P, cAVS 2.5, firmware 2.2.0 IPC3 taken from the T14 Gen 4 Linux install). It is placed in this
directory and embedded at link time:

    kext/LatSOFAudio/Firmware/sof-rpl.ri

To use a different SoC firmware (e.g. `sof-cml.ri` for Comet Lake), download
it from the official Sound Open Firmware binary releases:

    https://github.com/thesofproject/sof-bin/releases

then update the path in BOTH places:

    kext/LatSOFAudio/sof_firmware_embed.s   (.incbin line)
    kext/Makefile                           (make dependency)

SOF firmware is dual-licensed BSD-3-Clause / GPL-2.0 by its upstream
authors (Intel / NXP et al.) — see the sof-bin repository for details.
This project embeds it unmodified at build time only.
