import Foundation
import AVFoundation
import UIKit

@MainActor
public protocol WarningPlaying {
    func playWarning()
}

@MainActor
public final class WarningPlayer: WarningPlaying {
    private let audioSession: AVAudioSession
    private var audioPlayer: AVAudioPlayer?
    private var warningsEnabledProvider: () -> Bool

    public init(
        audioSession: AVAudioSession = .sharedInstance(),
        warningsEnabledProvider: @escaping () -> Bool = { true }
    ) {
        self.audioSession = audioSession
        self.warningsEnabledProvider = warningsEnabledProvider
    }

    public func updateWarningsEnabledProvider(_ provider: @escaping () -> Bool) {
        self.warningsEnabledProvider = provider
    }

    public func playWarning() {
        guard warningsEnabledProvider() else { return }

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)

        UIAccessibility.post(
            notification: .announcement,
            argument: "Bạn đã rời vị trí học 30 giây"
        )

        playBundledChimeIfAvailable()
    }

    private func playBundledChimeIfAvailable() {
        guard let url = Bundle.main.url(forResource: "reminder", withExtension: "wav") else {
            return
        }
        do {
            // Respect silent switch and device volume via ambient category
            try audioSession.setCategory(.ambient, options: [.mixWithOthers])
            try audioSession.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
        } catch {
            // Haptic + VoiceOver still fire; do not override system volume or crash on audio session error
        }
    }
}
