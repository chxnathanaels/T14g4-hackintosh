NootedGreen build for the ThinkPad T14 Gen 4 sleep test: upstream sgiammori/NootedGreen 95f8189 plus
patches/t14-sleep.patch (skip AppleIntelBaseController::hwSaveNVRAM, which panics on sleep entry on Tahoe;
XE-FWSNAP ported from the X1 Carbon G11 fork). CI commits the kext to out/.
