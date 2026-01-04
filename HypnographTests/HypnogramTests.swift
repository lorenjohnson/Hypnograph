//
//  HypnographTests.swift
//  HypnographTests
//
//  Created by Loren Johnson on 15.11.25.
//

import Testing
import AVFoundation
import CoreMedia
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit
import HypnoCore
import HypnoEffects
import HypnoRenderer
@testable import Hypnograph

struct HypnographTests {

    @MainActor
    @Test func divineCardManagerCreatesUniqueCards() async throws {
        var clips = makeClips()
        let state = DivineState(
            randomClip: {
                guard !clips.isEmpty else { return nil }
                return clips.removeFirst()
            },
            exclude: { _ in }
        )

        let manager = DivineCardManager(state: state)
        manager.addCardAtOffsetAtCenter()
        manager.addCardAtOffsetAtCenter()

        #expect(manager.cards.count == 2)
        let ids = Set(manager.cards.map { $0.clip.file.id })
        #expect(ids.count == 2)
    }

    @Test func renderEngineBuildsPlayerItemForStillImage() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURL = tempDir.appendingPathComponent("still.png")
        try writeTestImage(to: imageURL, size: CGSize(width: 8, height: 8))

        let duration = CMTime(seconds: 2, preferredTimescale: 600)
        let file = MediaFile(source: .url(imageURL), mediaKind: .image, duration: duration)
        let clip = VideoClip(file: file, startTime: .zero, duration: duration)
        let source = HypnogramSource(clip: clip)
        let recipe = HypnogramRecipe(sources: [source], targetDuration: duration, mode: .montage)

        let engine = RenderEngine()
        let config = RenderEngine.Config(outputSize: CGSize(width: 320, height: 180), frameRate: 30, enableGlobalEffects: true)
        let result = await engine.makePlayerItem(
            recipe: recipe,
            timeline: .montage(targetDuration: duration),
            config: config,
            effectManager: nil
        )

        switch result {
        case .success(let item):
            #expect(item.clipStartTimes.count == 1)
            #expect(item.stillImagesBySourceIndex[0] != nil)
        case .failure(let error):
            #expect(Bool(false), "Expected player item, got error: \(error)")
        }
    }

    @Test func renderEngineBuildsSingleSourcePlayerItem() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURL = tempDir.appendingPathComponent("single.png")
        try writeTestImage(to: imageURL, size: CGSize(width: 4, height: 4))

        let duration = CMTime(seconds: 1, preferredTimescale: 600)
        let file = MediaFile(source: .url(imageURL), mediaKind: .image, duration: duration)
        let clip = VideoClip(file: file, startTime: .zero, duration: duration)
        let source = HypnogramSource(clip: clip)

        let engine = RenderEngine()
        let result = await engine.makePlayerItemForSource(
            source,
            sourceIndex: 0,
            outputSize: CGSize(width: 160, height: 90),
            frameRate: 30,
            enableEffects: true,
            effectManager: nil
        )

        switch result {
        case .success:
            #expect(true)
        case .failure(let error):
            #expect(Bool(false), "Expected player item, got error: \(error)")
        }
    }

    @Test func renderEngineBuildsSingleSourcePlayerItemForVideo() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoURL = tempDir.appendingPathComponent("single.mov")
        let frameRate = 30
        let frameCount = 4
        try await writeTestVideo(to: videoURL, size: CGSize(width: 16, height: 16), frameCount: frameCount, frameRate: frameRate)

        let duration = CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(frameRate))
        let file = MediaFile(source: .url(videoURL), mediaKind: .video, duration: duration)
        let clip = VideoClip(file: file, startTime: .zero, duration: duration)
        let source = HypnogramSource(clip: clip)

        let engine = RenderEngine()
        let result = await engine.makePlayerItemForSource(
            source,
            sourceIndex: 0,
            outputSize: CGSize(width: 160, height: 90),
            frameRate: frameRate,
            enableEffects: true,
            effectManager: nil
        )

        switch result {
        case .success:
            #expect(true)
        case .failure(let error):
            #expect(Bool(false), "Expected player item, got error: \(error)")
        }
    }

    @Test func renderEngineExportsStillMontageAsPNG() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let imageURL = tempDir.appendingPathComponent("export.png")
        try writeTestImage(to: imageURL, size: CGSize(width: 8, height: 8))

        let duration = CMTime(seconds: 1, preferredTimescale: 600)
        let file = MediaFile(source: .url(imageURL), mediaKind: .image, duration: duration)
        let clip = VideoClip(file: file, startTime: .zero, duration: duration)
        let source = HypnogramSource(clip: clip)
        let recipe = HypnogramRecipe(sources: [source], targetDuration: duration, mode: .montage)

        let outputURL = tempDir.appendingPathComponent("export-output.png")
        let config = RenderEngine.Config(outputSize: CGSize(width: 128, height: 72), frameRate: 30, enableGlobalEffects: true)

        let engine = RenderEngine()
        let result = await engine.export(
            recipe: recipe,
            timeline: .montage(targetDuration: duration),
            outputURL: outputURL,
            config: config
        )

        switch result {
        case .success(let url):
            #expect(url.path == outputURL.path)
            #expect(FileManager.default.fileExists(atPath: url.path))
        case .failure(let error):
            #expect(Bool(false), "Expected export success, got error: \(error)")
        }
    }

    @Test func renderEngineExportsVideo() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoURL = tempDir.appendingPathComponent("export-source.mov")
        let frameRate = 30
        let frameCount = 5
        try await writeTestVideo(to: videoURL, size: CGSize(width: 16, height: 16), frameCount: frameCount, frameRate: frameRate)

        let duration = CMTime(value: CMTimeValue(frameCount), timescale: CMTimeScale(frameRate))
        let file = MediaFile(source: .url(videoURL), mediaKind: .video, duration: duration)
        let clip = VideoClip(file: file, startTime: .zero, duration: duration)
        let source = HypnogramSource(clip: clip)
        let recipe = HypnogramRecipe(sources: [source], targetDuration: duration, mode: .montage)

        let outputURL = tempDir.appendingPathComponent("export-output.mov")
        let config = RenderEngine.Config(outputSize: CGSize(width: 128, height: 72), frameRate: frameRate, enableGlobalEffects: true)

        let engine = RenderEngine()
        let result = await engine.export(
            recipe: recipe,
            timeline: .montage(targetDuration: duration),
            outputURL: outputURL,
            config: config
        )

        switch result {
        case .success(let url):
            #expect(url.path == outputURL.path)
            #expect(FileManager.default.fileExists(atPath: url.path))
        case .failure(let error):
            #expect(Bool(false), "Expected export success, got error: \(error)")
        }
    }

    @Test func effectManagerDetectsTemporalLookback() {
        let duration = CMTime(seconds: 1, preferredTimescale: 600)
        let file = MediaFile(
            source: .url(URL(fileURLWithPath: "/tmp/placeholder.png")),
            mediaKind: .image,
            duration: duration
        )
        let clip = VideoClip(file: file, startTime: .zero, duration: duration)
        let chain = EffectChain(name: "Temporal", effects: [EffectDefinition(type: "FrameDifferenceEffect")])
        let source = HypnogramSource(clip: clip, effectChain: chain)
        let recipe = HypnogramRecipe(sources: [source], targetDuration: duration)

        let manager = EffectManager()
        manager.recipeProvider = { recipe }

        #expect(manager.maxRequiredLookback == 2)
        #expect(manager.usesFrameBuffer)
    }

    @Test func hypnogramRecipeCodableRoundTrip() throws {
        let duration = CMTime(seconds: 3, preferredTimescale: 600)
        let file = MediaFile(source: .url(URL(fileURLWithPath: "/tmp/recipe.mov")), mediaKind: .video, duration: duration)
        let clip = VideoClip(file: file, startTime: .zero, duration: duration)
        let transform = CGAffineTransform(a: 1, b: 0.1, c: -0.1, d: 1, tx: 5, ty: -3)
        let chain = EffectChain(name: "Global", effects: [EffectDefinition(type: "BasicEffect")])
        let source = HypnogramSource(clip: clip, transforms: [transform], blendMode: BlendMode.sourceOver, effectChain: chain)
        let recipe = HypnogramRecipe(sources: [source], targetDuration: duration, playRate: 0.8, effectChain: chain, mode: .sequence)

        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(HypnogramRecipe.self, from: data)

        #expect(decoded.sources.count == 1)
        #expect(decoded.targetDuration.seconds == recipe.targetDuration.seconds)
        #expect(decoded.playRate == recipe.playRate)
        #expect(decoded.mode == recipe.mode)

        let decodedTransform = decoded.sources[0].transforms[0]
        #expect(decodedTransform.a == transform.a)
        #expect(decodedTransform.b == transform.b)
        #expect(decodedTransform.c == transform.c)
        #expect(decodedTransform.d == transform.d)
        #expect(decodedTransform.tx == transform.tx)
        #expect(decodedTransform.ty == transform.ty)
    }

    @Test func hypnogramRecipeEnsureEffectChainNames() {
        let duration = CMTime(seconds: 1, preferredTimescale: 600)
        let file = MediaFile(source: .url(URL(fileURLWithPath: "/tmp/ensure.mov")), mediaKind: .video, duration: duration)
        let clip = VideoClip(file: file, startTime: .zero, duration: duration)
        let sourceChain = EffectChain(name: nil, effects: [EffectDefinition(type: "BasicEffect")])
        let source = HypnogramSource(clip: clip, effectChain: sourceChain)

        var recipe = HypnogramRecipe(
            sources: [source],
            targetDuration: duration,
            effectChain: EffectChain(name: nil, effects: [EffectDefinition(type: "BasicEffect")])
        )

        recipe.ensureEffectChainNames()

        #expect(recipe.effectChain.name != nil)
        #expect(recipe.sources[0].effectChain.name != nil)
    }

    @Test func mediaSourcesLibraryRandomClipForImage() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await withTemporaryCoreConfig(tempDir.appendingPathComponent("core", isDirectory: true)) {
            let imageURL = tempDir.appendingPathComponent("library-image.png")
            try writeTestImage(to: imageURL, size: CGSize(width: 10, height: 10))

            let library = MediaSourcesLibrary(sources: [tempDir.path], allowedMediaTypes: [.images])
            guard let clip = library.randomClip(clipLength: 1.25) else {
                #expect(Bool(false), "Expected image clip from library")
                return
            }

            #expect(clip.file.mediaKind == .image)
            #expect(abs(clip.duration.seconds - 1.25) < 0.01)
        }
    }

    @Test func mediaSourcesLibraryRandomClipForVideo() async throws {
        let tempDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await withTemporaryCoreConfig(tempDir.appendingPathComponent("core", isDirectory: true)) {
            let videoURL = tempDir.appendingPathComponent("library-video.mov")
            try await writeTestVideo(to: videoURL, size: CGSize(width: 12, height: 12), frameCount: 4, frameRate: 30)

            let library = MediaSourcesLibrary(sources: [tempDir.path], allowedMediaTypes: [.videos])
            guard let clip = library.randomClip(clipLength: 0.5) else {
                #expect(Bool(false), "Expected video clip from library")
                return
            }

            #expect(clip.file.mediaKind == .video)
            #expect(clip.duration.seconds <= 0.5 + 0.01)
            #expect(clip.startTime.seconds >= 0)
        }
    }

    @Test func quickLookParsesRecipeJSON() throws {
        let duration = CMTime(seconds: 2, preferredTimescale: 600)
        let file = MediaFile(source: .url(URL(fileURLWithPath: "/tmp/quicklook.mov")), mediaKind: .video, duration: duration)
        let clip = VideoClip(file: file, startTime: .zero, duration: duration)
        let source = HypnogramSource(clip: clip)

        let snapshotData = try makeSnapshotData(size: CGSize(width: 6, height: 6))
        let snapshotBase64 = snapshotData.base64EncodedString()
        var recipe = HypnogramRecipe(sources: [source], targetDuration: duration, mode: .montage)
        recipe.snapshot = snapshotBase64
        recipe.effectChain = EffectChain(name: "Global", effects: [
            EffectDefinition(type: "BasicEffect"),
            EffectDefinition(type: "FrameDifferenceEffect")
        ])

        let data = try JSONEncoder().encode(recipe)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            #expect(Bool(false), "Expected JSON object")
            return
        }

        let sources = json["sources"] as? [[String: Any]]
        let effectChain = json["effectChain"] as? [String: Any]
        let effects = effectChain?["effects"] as? [[String: Any]]
        let targetDuration = json["targetDuration"] as? [String: Any]
        let seconds = targetDuration?["seconds"] as? Double

        #expect(sources?.count == 1)
        #expect(effects?.count == 2)
        #expect(seconds == duration.seconds)
        #expect((json["snapshot"] as? String)?.isEmpty == false)
    }

    private func makeClips() -> [VideoClip] {
        [
            makeClip(name: "clip-a.mov"),
            makeClip(name: "clip-b.mov")
        ]
    }

    private func makeClip(name: String) -> VideoClip {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        let duration = CMTime(seconds: 5, preferredTimescale: 600)
        let file = MediaFile(source: .url(url), mediaKind: .video, duration: duration)
        return VideoClip(file: file, startTime: .zero, duration: duration)
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "hypnograph-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeTestImage(to url: URL, size: CGSize) throws {
        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
        let context = CIContext()
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw TestImageError.failedToCreateCGImage
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw TestImageError.failedToCreateDestination
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.failedToWriteImage
        }
    }

    private func writeTestVideo(
        to url: URL,
        size: CGSize,
        frameCount: Int,
        frameRate: Int
    ) async throws {
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)

        guard writer.canAdd(input) else {
            throw TestVideoError.failedToAddInput
        }
        writer.add(input)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            guard let pixelBuffer = makePixelBuffer(size: size, colorSpace: colorSpace, frameIndex: frameIndex) else {
                throw TestVideoError.failedToCreatePixelBuffer
            }

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        input.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }

    private func makePixelBuffer(size: CGSize, colorSpace: CGColorSpace, frameIndex: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let context = CGContext(
            data: baseAddress,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )

        guard let ctx = context else { return nil }

        let hue = CGFloat((frameIndex % 8)) / 8.0
        ctx.setFillColor(CGColor(red: hue, green: 0.2, blue: 1.0 - hue, alpha: 1.0))
        ctx.fill(CGRect(origin: .zero, size: size))

        return pixelBuffer
    }

    private func withTemporaryCoreConfig(_ appSupportDirectory: URL, _ body: () async throws -> Void) async throws {
        let previous = HypnoCoreConfig.shared
        let fm = FileManager.default
        if !fm.fileExists(atPath: appSupportDirectory.path) {
            try fm.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        }
        HypnoCoreConfig.shared = HypnoCoreConfig(appSupportDirectory: appSupportDirectory)
        defer { HypnoCoreConfig.shared = previous }
        try await body()
    }

    private func makeSnapshotData(size: CGSize) throws -> Data {
        let image = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
        let context = CIContext()
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw TestImageError.failedToCreateCGImage
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw TestImageError.failedToWriteImage
        }
        return data
    }

    private enum TestImageError: Error {
        case failedToCreateCGImage
        case failedToCreateDestination
        case failedToWriteImage
    }

    private enum TestVideoError: Error {
        case failedToAddInput
        case failedToCreatePixelBuffer
    }
}
