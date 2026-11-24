import AVFoundation
import CoreMedia

/// Turns scrcpy H.264 packets (Annex B) into sample buffers for an AVSampleBufferDisplayLayer.
/// The layer decodes on the GPU through VideoToolbox.
final class H264Renderer {
    let layer = AVSampleBufferDisplayLayer()
    private var format: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    func reset() {
        format = nil
        sps = nil
        pps = nil
        DispatchQueue.main.async { self.layer.flushAndRemoveImage() }
    }

    /// Splits an Annex B byte stream into NAL units (without start codes).
    private static func nalUnits(_ data: Data) -> [Data] {
        var units: [Data] = []
        let bytes = [UInt8](data)
        let n = bytes.count
        var i = 0
        var start = -1
        while i + 2 < n {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                if start >= 0 {
                    var end = i
                    if end > start, bytes[end - 1] == 0 { end -= 1 } // 4-byte start code
                    if end > start { units.append(Data(bytes[start..<end])) }
                }
                i += 3
                start = i
            } else {
                i += 1
            }
        }
        if start >= 0, start < n { units.append(Data(bytes[start..<n])) }
        return units
    }

    private func updateFormat() {
        guard let sps, let pps else { return }
        var desc: CMVideoFormatDescription?
        let status: OSStatus = sps.withUnsafeBytes { spsBuf in
            pps.withUnsafeBytes { ppsBuf in
                let ptrs: [UnsafePointer<UInt8>] = [
                    spsBuf.bindMemory(to: UInt8.self).baseAddress!,
                    ppsBuf.bindMemory(to: UInt8.self).baseAddress!,
                ]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2,
                    parameterSetPointers: ptrs, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &desc)
            }
        }
        if status == noErr { format = desc }
    }

    func handle(packet: Data) {
        var avcc = Data()
        var paramsChanged = false
        for nal in H264Renderer.nalUnits(packet) {
            guard let first = nal.first else { continue }
            switch first & 0x1F {
            case 7: if nal != sps { sps = nal; paramsChanged = true }
            case 8: if nal != pps { pps = nal; paramsChanged = true }
            case 9: break // access unit delimiter
            default:
                avcc.appendBE(UInt32(nal.count))
                avcc.append(nal)
            }
        }
        if paramsChanged || format == nil { updateFormat() }
        guard !avcc.isEmpty, let format else { return }
        enqueue(avcc, format: format)
    }

    private func enqueue(_ avcc: Data, format: CMVideoFormatDescription) {
        var block: CMBlockBuffer?
        let length = avcc.count
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: length, flags: 0, blockBufferOut: &block) == noErr, let block else { return }
        let copied = avcc.withUnsafeBytes { buf in
            CMBlockBufferReplaceDataBytes(with: buf.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: length)
        }
        guard copied == noErr else { return }

        var sample: CMSampleBuffer?
        var sizes = [length]
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 1, sampleSizeArray: &sizes, sampleBufferOut: &sample) == noErr,
              let sample else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }

        let layer = self.layer
        DispatchQueue.main.async {
            if layer.status == .failed { layer.flush() }
            layer.enqueue(sample)
        }
    }
}
