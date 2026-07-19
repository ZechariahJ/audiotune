import AppKit

/// A single row in the menu: app icon, name, a live volume slider, a mute
/// button, and a percentage readout. Reports changes via closures.
@MainActor
final class AppVolumeRowView: NSView {
    static let rowWidth: CGFloat = 288
    static let rowHeight: CGFloat = 54

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let muteButton = NSButton()
    private let slider = NSSlider()

    var onGainChange: ((Float) -> Void)?
    var onToggleMute: (() -> Void)?

    private(set) var appName = ""
    private var muted = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: Self.rowHeight))
        build()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func build() {
        iconView.imageScaling = .scaleProportionallyUpOrDown

        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right

        muteButton.isBordered = false
        muteButton.bezelStyle = .regularSquare
        muteButton.imagePosition = .imageOnly
        muteButton.target = self
        muteButton.action = #selector(muteTapped)
        muteButton.setButtonType(.momentaryChange)

        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved)

        for v in [iconView, nameLabel, percentLabel, muteButton, slider] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            percentLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            percentLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            percentLabel.widthAnchor.constraint(equalToConstant: 40),

            muteButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            muteButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            muteButton.widthAnchor.constraint(equalToConstant: 18),
            muteButton.heightAnchor.constraint(equalToConstant: 18),

            slider.leadingAnchor.constraint(equalTo: muteButton.trailingAnchor, constant: 8),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            slider.centerYAnchor.constraint(equalTo: muteButton.centerYAnchor),
        ])
    }

    func configure(appName: String, icon: NSImage?, gain: Float, muted: Bool) {
        self.appName = appName
        self.muted = muted
        nameLabel.stringValue = appName
        if let icon {
            let img = icon.copy() as! NSImage
            img.size = NSSize(width: 18, height: 18)
            iconView.image = img
        } else {
            iconView.image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        }
        let shown = muted ? 0 : gain
        slider.floatValue = shown
        updatePercent(shown)
        updateMuteIcon()
    }

    // MARK: - Actions

    @objc private func sliderMoved() {
        let v = slider.floatValue
        if v > 0 { muted = false }
        updatePercent(v)
        updateMuteIcon()
        onGainChange?(v)
    }

    @objc private func muteTapped() {
        // The controller flips mute state and reconfigures this row afterward,
        // so we just forward the intent.
        onToggleMute?()
    }

    private func updatePercent(_ v: Float) {
        percentLabel.stringValue = "\(Int((v * 100).rounded()))%"
    }

    private func updateMuteIcon() {
        let name = (muted || slider.floatValue == 0) ? "speaker.slash.fill" : "speaker.wave.2.fill"
        muteButton.image = NSImage(systemSymbolName: name, accessibilityDescription: muted ? "Unmute" : "Mute")
        muteButton.contentTintColor = muted ? .systemRed : .secondaryLabelColor
    }
}
