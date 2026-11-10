/* Hide the ACPI root hub under macOS so USBToolBox enumerates every port (pre-mapping setup). */
DefinitionBlock ("", "SSDT", 2, "T14G4", "UsbReset", 0x00001000)
{
    External (_SB_.PC00.XHCI.RHUB, DeviceObj)
    External (_SB_.PCI0.XHCI.RHUB, DeviceObj)
    External (_SB_.PC00.XHC_.RHUB, DeviceObj)
    External (_SB_.PCI0.XHC_.RHUB, DeviceObj)
    If (CondRefOf (\_SB.PC00.XHCI.RHUB))
    {
        Scope (\_SB.PC00.XHCI.RHUB)
        {
            Method (_STA, 0, NotSerialized) { If (_OSI ("Darwin")) { Return (Zero) } Return (0x0F) }
        }
    }
    ElseIf (CondRefOf (\_SB.PCI0.XHC.RHUB))
    {
        Scope (\_SB.PCI0.XHC.RHUB)
        {
            Method (_STA, 0, NotSerialized) { If (_OSI ("Darwin")) { Return (Zero) } Return (0x0F) }
        }
    }
}
