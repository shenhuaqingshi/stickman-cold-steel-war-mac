import AVFoundation
import Foundation

/// 纯原生零外部音频文件依赖的多声道冷兵器音效与战鼓号角合成引擎
/// 启动时使用物理建模与泛音列合成预烘焙 12 组立体声 PCM 缓冲，通过 8 路 `AVAudioPlayerNode` 混音池零延迟并发播放。
@MainActor
public final class BattleAudioEngine {
    public static let shared = BattleAudioEngine()

    public var masterVolume: Float = 0.85 {
        didSet {
            let clamped = max(0.0, min(1.0, masterVolume))
            engine.mainMixerNode.outputVolume = isMuted ? 0.0 : clamped
        }
    }

    public var isMuted: Bool = false {
        didSet {
            engine.mainMixerNode.outputVolume = isMuted ? 0.0 : max(0.0, min(1.0, masterVolume))
        }
    }

    private let engine = AVAudioEngine()
    private let sampleRate: Double = 44_100.0
    private let format: AVAudioFormat
    private var players: [AVAudioPlayerNode] = []
    private var playerCursor: Int = 0
    private var buffers: [BattleSoundCue: AVAudioPCMBuffer] = [:]
    private var isEngineRunning: Bool = false
    private var lastPlayTimestamps: [BattleSoundCue: TimeInterval] = [:]

    private init() {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
            ?? AVAudioFormat(standardFormatWithSampleRate: 44_100.0, channels: 1)!
        self.format = fmt

        for _ in 0..<8 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: fmt)
            players.append(node)
        }
        engine.mainMixerNode.outputVolume = masterVolume
        bakeAllSoundBuffers()
    }

    public func play(_ cue: BattleSoundCue, volumeScale: Float = 1.0) {
        guard !isMuted, masterVolume > 0.01 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let minCooldown: TimeInterval = {
            switch cue {
            case .swordClash, .bowVolley: return 0.11
            case .uiClick: return 0.04
            default: return 0.08
            }
        }()
        if let prev = lastPlayTimestamps[cue], now - prev < minCooldown {
            return
        }
        lastPlayTimestamps[cue] = now

        ensureEngineStarted()
        guard isEngineRunning, let buf = buffers[cue], !players.isEmpty else { return }

        let node = players[playerCursor]
        playerCursor = (playerCursor + 1) % players.count
        if node.isPlaying {
            node.stop()
        }
        node.volume = max(0.05, min(1.0, volumeScale))
        // 轻微随机立体声声像偏移增加百人战场空间立体感
        node.pan = cue == .uiClick ? 0.0 : Float.random(in: -0.28...0.28)
        node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        node.play()
    }

    private func ensureEngineStarted() {
        guard !isEngineRunning else { return }
        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            isEngineRunning = false
        }
    }

    // MARK: - 物理建模程序化波形预烘焙

    private func bakeAllSoundBuffers() {
        // 1. 出征/冲锋低沉古罗马铜角 (War Horn)
        buffers[.warHorn] = synthesizeBuffer(duration: 0.92) { t, dur in
            let env = min(1.0, t / 0.09) * exp(-max(0.0, t - 0.35) * 3.2) * (1.0 - max(0.0, (t - dur + 0.08) / 0.08))
            let vib = 1.0 + 0.004 * sin(2.0 * .pi * 5.5 * t)
            let f0 = 130.81 * vib // C3
            let brass = 0.48 * sin(2.0 * .pi * f0 * t)
                + 0.32 * sin(2.0 * .pi * f0 * 2.0 * t)
                + 0.22 * sin(2.0 * .pi * f0 * 3.0 * t)
                + 0.12 * sin(2.0 * .pi * f0 * 4.0 * t)
                + 0.16 * sin(2.0 * .pi * (f0 * 1.5) * t) // 五度共鸣 G3
            return Float(brass * env * 0.46)
        }

        // 2. 变阵与进军牛皮大鼓双连击 (Drum March)
        buffers[.drumMarch] = synthesizeBuffer(duration: 0.42) { t, _ in
            func hit(_ dt: Double, amp: Double) -> Double {
                guard dt >= 0.0 else { return 0.0 }
                let pitchEnv = 54.0 + 62.0 * exp(-dt * 28.0)
                let body = sin(2.0 * .pi * pitchEnv * dt) * exp(-dt * 11.5)
                let skin = ( Self.hashNoise(dt * 9200.0) ) * exp(-dt * 55.0) * 0.35
                return (body + skin) * amp
            }
            let s = hit(t, amp: 0.72) + hit(t - 0.14, amp: 0.92)
            return Float(s * 0.58)
        }

        // 3. 刀剑甲胄金铁交鸣 (Sword Clash)
        buffers[.swordClash] = synthesizeBuffer(duration: 0.26) { t, _ in
            let ring = (0.42 * sin(2.0 * .pi * 1490.0 * t)
                + 0.30 * sin(2.0 * .pi * 2380.0 * t)
                + 0.20 * sin(2.0 * .pi * 3710.0 * t)
                + 0.14 * sin(2.0 * .pi * 5240.0 * t)) * exp(-t * 19.0)
            let scrape = Self.hashNoise(t * 16_000.0) * exp(-t * 46.0) * 0.42
            return Float((ring + scrape) * 0.42)
        }

        // 4. 0.25s 精准弹反清脆剑鸣 (Perfect Parry Ring)
        buffers[.parryRing] = synthesizeBuffer(duration: 0.55) { t, _ in
            let env = exp(-t * 6.8)
            let tone = 0.45 * sin(2.0 * .pi * 1975.0 * t)
                + 0.32 * sin(2.0 * .pi * 2960.0 * t)
                + 0.22 * sin(2.0 * .pi * 4435.0 * t)
            let spark = Self.hashNoise(t * 22_000.0) * exp(-t * 60.0) * 0.35
            return Float((tone * env + spark) * 0.55)
        }

        // 5. 弓弩齐射弦响破空 (Bow Volley)
        buffers[.bowVolley] = synthesizeBuffer(duration: 0.24) { t, _ in
            let f = 220.0 * exp(-t * 4.5)
            let twang = sin(2.0 * .pi * f * t) * exp(-t * 24.0) * 0.50
            let whooshEnv = sin(min(.pi, t / 0.20 * .pi)) * exp(-t * 8.0)
            let whoosh = Self.hashNoise(t * 6400.0) * whooshEnv * 0.32
            return Float((twang + whoosh) * 0.45)
        }

        // 6. 投石巨石与神机火雷轰鸣 (Boulder Boom)
        buffers[.boulderBoom] = synthesizeBuffer(duration: 0.58) { t, _ in
            let f = 36.0 + 78.0 * exp(-t * 14.0)
            let boom = sin(2.0 * .pi * f * t) * exp(-t * 6.5) * 0.78
            let rumble = Self.hashNoise(t * 2800.0) * exp(-t * 7.5) * 0.45
            return Float((boom + rumble) * 0.62)
        }

        // 7. 营建木石夯筑敲击 (Build Hammer)
        buffers[.buildHammer] = synthesizeBuffer(duration: 0.30) { t, _ in
            func tap(_ dt: Double) -> Double {
                guard dt >= 0.0 else { return 0.0 }
                let wood = sin(2.0 * .pi * 420.0 * dt) * exp(-dt * 36.0) * 0.6
                    + sin(2.0 * .pi * 890.0 * dt) * exp(-dt * 48.0) * 0.35
                let click = Self.hashNoise(dt * 12_000.0) * exp(-dt * 80.0) * 0.3
                return wood + click
            }
            return Float((tap(t) + tap(t - 0.12) * 0.85) * 0.48)
        }

        // 8. 军械铁匠铺铁砧锻打 (Forge Clang)
        buffers[.forgeClang] = synthesizeBuffer(duration: 0.48) { t, _ in
            func anvil(_ dt: Double, pitch: Double) -> Double {
                guard dt >= 0.0 else { return 0.0 }
                return (0.55 * sin(2.0 * .pi * pitch * dt)
                    + 0.30 * sin(2.0 * .pi * pitch * 2.02 * dt)
                    + 0.18 * sin(2.0 * .pi * pitch * 3.14 * dt)) * exp(-dt * 10.5)
            }
            return Float((anvil(t, pitch: 1318.5) + anvil(t - 0.16, pitch: 1568.0)) * 0.48)
        }

        // 9. 文明时代演进恢弘礼号 (Age Fanfare)
        buffers[.ageFanfare] = synthesizeBuffer(duration: 1.15) { t, _ in
            let noteFreq: Double
            if t < 0.24 { noteFreq = 261.63 }      // C4
            else if t < 0.48 { noteFreq = 329.63 } // E4
            else if t < 0.72 { noteFreq = 392.00 } // G4
            else { noteFreq = 523.25 }             // C5
            let localT = t < 0.72 ? t.truncatingRemainder(dividingBy: 0.24) : (t - 0.72)
            let env = min(1.0, localT / 0.025) * exp(-localT * (t < 0.72 ? 4.2 : 2.6))
            let horn = 0.50 * sin(2.0 * .pi * noteFreq * t)
                + 0.28 * sin(2.0 * .pi * noteFreq * 2.0 * t)
                + 0.16 * sin(2.0 * .pi * noteFreq * 3.0 * t)
            let drum = sin(2.0 * .pi * (55.0 + 40.0 * exp(-t * 18.0)) * t) * exp(-t * 8.0) * 0.35
            return Float((horn * env + drum) * 0.52)
        }

        // 10. 大捷凯旋号角 (Victory Fanfare)
        buffers[.victoryFanfare] = synthesizeBuffer(duration: 1.35) { t, _ in
            let f: Double = t < 0.20 ? 293.66 : (t < 0.40 ? 369.99 : (t < 0.62 ? 440.0 : 587.33))
            let lt = t < 0.62 ? t.truncatingRemainder(dividingBy: 0.21) : (t - 0.62)
            let env = min(1.0, lt / 0.02) * exp(-lt * 2.4)
            let sig = (0.52 * sin(2.0 * .pi * f * t) + 0.30 * sin(2.0 * .pi * f * 2.0 * t) + 0.20 * sin(2.0 * .pi * f * 1.5 * t)) * env
            return Float(sig * 0.50)
        }

        // 11. 战败低沉暮钟 (Defeat Bell)
        buffers[.defeatBell] = synthesizeBuffer(duration: 1.10) { t, _ in
            let env = exp(-t * 3.2)
            let bell = 0.58 * sin(2.0 * .pi * 146.83 * t) + 0.28 * sin(2.0 * .pi * 220.0 * t) + 0.14 * sin(2.0 * .pi * 311.13 * t)
            return Float(bell * env * 0.50)
        }

        // 12. 古铜按钮微点击音 (UI Click)
        buffers[.uiClick] = synthesizeBuffer(duration: 0.065) { t, _ in
            let sig = sin(2.0 * .pi * 920.0 * t) * exp(-t * 75.0) * 0.55
                + sin(2.0 * .pi * 1840.0 * t) * exp(-t * 110.0) * 0.30
            return Float(sig * 0.36)
        }
    }

    private func synthesizeBuffer(
        duration: Double,
        generator: (Double, Double) -> Float
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(max(1, Int(sampleRate * duration)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        let channels = Int(format.channelCount)
        guard let channelData = buffer.floatChannelData else { return nil }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let sample = max(-0.98, min(0.98, generator(t, duration)))
            for ch in 0..<channels {
                channelData[ch][frame] = sample
            }
        }
        return buffer
    }

    @inline(__always)
    nonisolated private static func hashNoise(_ seed: Double) -> Double {
        let x = sin(seed * 12.9898 + 78.233) * 43_758.5453
        return (x - floor(x)) * 2.0 - 1.0
    }
}
