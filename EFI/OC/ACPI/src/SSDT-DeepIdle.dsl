/*
 * SSDT-DeepIdle (T14 Gen 4): S0 low-power idle sleep for macOS.
 * The firmware has Modern Standby only (_S3 gated off by S0ID=1), so macOS sleeps in Deep Idle.
 * AppleACPIPlatform looks for \_SB.LPS0 and \_GPE.LXEN. Darwin only.
 * Based on rodgod-rr/Dell-G15-5530-Hackintosh (same approach, OC-Little AOAC).
 */
DefinitionBlock ("", "SSDT", 2, "T14G4", "DeepIdl", 0x00001000)
{
    Scope (\_SB)
    {
        Method (LPS0, 0, NotSerialized)
        {
            If (_OSI ("Darwin")) { Return (One) }
            Return (Zero)
        }
    }
    Scope (\_GPE)
    {
        Method (LXEN, 0, NotSerialized)
        {
            If (_OSI ("Darwin")) { Return (One) }
            Return (Zero)
        }
    }
}
