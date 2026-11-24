/*
 * SSDT-LIDWAKE (T14 Gen 4): lid and power button wake from Deep Idle.
 * macOS arms the GPE in a device's optional PRW0 for S0 sleep ("acpi-wake-s0-gpe").
 * The lid's _PRW GPE (0x17) is not raised by the EC in S0; point PRW0 at the EC's own GPE
 * (\_SB.PC00.LPCB.EC _GPE = 0x6E), as Linux s2idle keeps the EC GPE armed.
 * Side effect: other EC events (battery, charger) may also wake the Mac.
 */
DefinitionBlock ("", "SSDT", 2, "T14G4", "LidWake", 0x00001000)
{
    External (\_SB.LID, DeviceObj)
    Scope (\_SB.LID)
    {
        Name (PRW0, Package (0x02) { 0x6E, 0x03 })
    }
}
