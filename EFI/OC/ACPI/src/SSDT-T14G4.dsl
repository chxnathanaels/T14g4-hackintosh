/*
 * SSDT-T14G4: combined, path-guarded fixes for ThinkPad T14 Gen 4 (Intel, Raptor Lake)
 * Every block only applies under macOS (_OSI "Darwin") and only if the target path exists,
 * so a wrong guess about the DSDT is skipped instead of breaking the table.
 *  - AWAC/RTC: STAS=1 so the legacy RTC is used (macOS has no AWAC driver)
 *  - USBX: USB port power properties
 *  - MCHC + SBUS/BUS0: memory controller and SMBus devices macOS expects
 *  - PNLF: backlight device for the internal panel
 */
DefinitionBlock ("", "SSDT", 2, "T14G4", "T14FIX", 0x00001000)
{
    External (STAS, IntObj)
    External (_SB_.PC00, DeviceObj)
    External (_SB_.PCI0, DeviceObj)
    External (_SB_.PC00.SBUS, DeviceObj)
    External (_SB_.PCI0.SBUS, DeviceObj)
    External (_SB_.PC00.GFX0, DeviceObj)
    External (_SB_.PCI0.GFX0, DeviceObj)
    External (_SB_.PC00.MCHC, DeviceObj)
    External (_SB_.PCI0.MCHC, DeviceObj)

    Scope (\_SB)
    {
        Device (USBX)
        {
            Name (_ADR, Zero)
            Method (_DSM, 4, NotSerialized)
            {
                If (!Arg2) { Return (Buffer (One) { 0x03 }) }
                Return (Package (0x04) { "kUSBSleepPortCurrentLimit", 0x0BB8, "kUSBWakePortCurrentLimit", 0x0BB8 })
            }
            Method (_STA, 0, NotSerialized)
            {
                If (_OSI ("Darwin")) { Return (0x0F) }
                Return (Zero)
            }
        }

        /* AWAC -> legacy RTC. Done in a device _INI so it never collides with an existing \_INI or \_SB._INI */
        Device (RTCF)
        {
            Name (_HID, "T14R0000")
            Method (_INI, 0, NotSerialized)
            {
                If (_OSI ("Darwin"))
                {
                    If (CondRefOf (\STAS)) { \STAS = One }
                }
            }
            Method (_STA, 0, NotSerialized)
            {
                If (_OSI ("Darwin")) { Return (0x0B) }
                Return (Zero)
            }
        }
    }

    If (CondRefOf (\_SB.PC00))
    {
        If (!CondRefOf (\_SB.PC00.MCHC))
        {
            Scope (\_SB.PC00)
            {
                Device (MCHC)
                {
                    Name (_ADR, Zero)
                    Method (_STA, 0, NotSerialized)
                    {
                        If (_OSI ("Darwin")) { Return (0x0F) }
                        Return (Zero)
                    }
                }
            }
        }
    }
    ElseIf (CondRefOf (\_SB.PCI0))
    {
        If (!CondRefOf (\_SB.PCI0.MCHC))
        {
            Scope (\_SB.PCI0)
            {
                Device (MCHC)
                {
                    Name (_ADR, Zero)
                    Method (_STA, 0, NotSerialized)
                    {
                        If (_OSI ("Darwin")) { Return (0x0F) }
                        Return (Zero)
                    }
                }
            }
        }
    }

    If (CondRefOf (\_SB.PC00.SBUS))
    {
        Scope (\_SB.PC00.SBUS)
        {
            Device (BUS0)
            {
                Name (_CID, "smbus")
                Name (_ADR, Zero)
                Method (_STA, 0, NotSerialized)
                {
                    If (_OSI ("Darwin")) { Return (0x0F) }
                    Return (Zero)
                }
            }
        }
    }
    ElseIf (CondRefOf (\_SB.PCI0.SBUS))
    {
        Scope (\_SB.PCI0.SBUS)
        {
            Device (BUS0)
            {
                Name (_CID, "smbus")
                Name (_ADR, Zero)
                Method (_STA, 0, NotSerialized)
                {
                    If (_OSI ("Darwin")) { Return (0x0F) }
                    Return (Zero)
                }
            }
        }
    }

    If (CondRefOf (\_SB.PC00.GFX0))
    {
        Scope (\_SB.PC00.GFX0)
        {
            Device (PNLF)
            {
                Name (_HID, EisaId ("APP0002"))
                Name (_CID, "backlight")
                Name (_UID, 0x13)
                Method (_STA, 0, NotSerialized)
                {
                    If (_OSI ("Darwin")) { Return (0x0B) }
                    Return (Zero)
                }
            }
        }
    }
    ElseIf (CondRefOf (\_SB.PCI0.GFX0))
    {
        Scope (\_SB.PCI0.GFX0)
        {
            Device (PNLF)
            {
                Name (_HID, EisaId ("APP0002"))
                Name (_CID, "backlight")
                Name (_UID, 0x13)
                Method (_STA, 0, NotSerialized)
                {
                    If (_OSI ("Darwin")) { Return (0x0B) }
                    Return (Zero)
                }
            }
        }
    }
}
