/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20230628 (64-bit version)
 * Copyright (c) 2000 - 2023 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of /root/work/xps/EFI/OC/ACPI/SSDT-XOSI.aml, Mon Oct 26 20:23:44 2026
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x000000E9 (233)
 *     Revision         0x02
 *     Checksum         0x34
 *     OEM ID           "T14G4"
 *     OEM Table ID     "XOSI"
 *     OEM Revision     0x00001000 (4096)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20251212 (539300370)
 */
DefinitionBlock ("", "SSDT", 2, "T14G4", "XOSI", 0x00001000)
{
    Method (XOSI, 1, NotSerialized)
    {
        Local0 = Package (0x0C)
            {
                "Windows 2001", 
                "Windows 2001 SP1", 
                "Windows 2001.1", 
                "Windows 2001 SP2", 
                "Windows 2006", 
                "Windows 2009", 
                "Windows 2012", 
                "Windows 2013", 
                "Windows 2015", 
                "Windows 2020",
                "Windows 2021",
                "Windows 2022"
            }
        If (_OSI ("Darwin"))
        {
            Return ((Match (Local0, MEQ, Arg0, MTR, Zero, Zero) != Ones))
        }
        Else
        {
            Return (_OSI (Arg0))
        }
    }
}

