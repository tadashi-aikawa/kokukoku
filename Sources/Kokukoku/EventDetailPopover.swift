import AppKit
import KokukokuCore

/// 予定行のクリックで表示する詳細ポップオーバー。
/// タイトル・時間帯・場所・説明文・参加者・アクションボタンを載せる
@MainActor
final class EventDetailPopover: NSPopover, NSPopoverDelegate {
    var onDismiss: (() -> Void)?
    /// 表示中の予定のインデックス。同じ予定への再決定をトグル(閉じる)と判定するために持つ
    let eventIndex: Int

    init(eventRow: CalendarEventRow, eventIndex: Int) {
        self.eventIndex = eventIndex
        super.init()
        let vc = EventDetailViewController(eventRow: eventRow)
        vc.onAction = { [weak self] in self?.close() }
        contentViewController = vc
        behavior = .transient
        appearance = NSAppearance(named: .darkAqua)
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func popoverDidClose(_ notification: Notification) {
        onDismiss?()
    }
}

@MainActor
private final class EventDetailViewController: NSViewController {
    private let eventRow: CalendarEventRow
    var onAction: (() -> Void)?

    init(eventRow: CalendarEventRow) {
        self.eventRow = eventRow
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let titleLabel = makeLabel(eventRow.title, fontSize: 14, bold: true)
        stack.addArrangedSubview(titleLabel)

        let timeLabel = makeLabel(
            "\(eventRow.startText) - \(eventRow.endText)", fontSize: 12,
            color: .secondaryLabelColor)
        stack.addArrangedSubview(timeLabel)

        if let location = eventRow.locationText {
            let locationLabel = makeLabel(location, fontSize: 12, color: .secondaryLabelColor)
            stack.addArrangedSubview(locationLabel)
        }

        if let notes = eventRow.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            stack.addArrangedSubview(makeSeparator())
            let notesLabel = makeHTMLLabel(notes, fontSize: 11, color: .labelColor, maxLines: 8)
            stack.addArrangedSubview(notesLabel)
        }

        if !eventRow.attendees.isEmpty {
            stack.addArrangedSubview(makeSeparator())
            let header = makeLabel("参加者", fontSize: 11, bold: true, color: .secondaryLabelColor)
            stack.addArrangedSubview(header)
            for attendee in eventRow.attendees {
                let label = makeLabel(
                    attendeeText(attendee), fontSize: 11,
                    bold: attendee.isOrganizer, color: .labelColor)
                stack.addArrangedSubview(label)
            }
        }

        let hasButtons = eventRow.meetURL != nil || eventRow.detailURL != nil
        if hasButtons {
            stack.addArrangedSubview(makeSeparator())
            let buttonStack = NSStackView()
            buttonStack.orientation = .horizontal
            buttonStack.spacing = 8
            if eventRow.meetURL != nil {
                buttonStack.addArrangedSubview(makeButton("Meetに参加", action: #selector(openMeet)))
            }
            if eventRow.detailURL != nil {
                buttonStack.addArrangedSubview(
                    makeButton("カレンダーで開く", action: #selector(openCalendar)))
            }
            stack.addArrangedSubview(buttonStack)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            container.widthAnchor.constraint(equalToConstant: 300),
        ])

        self.view = container
    }

    @objc private func openMeet() {
        if let url = eventRow.meetURL {
            NSWorkspace.shared.open(url)
            onAction?()
        }
    }

    @objc private func openCalendar() {
        if let url = eventRow.detailURL {
            NSWorkspace.shared.open(url)
            onAction?()
        }
    }

    private func attendeeText(_ attendee: CalendarEvent.Attendee) -> String {
        let indicator: String
        switch attendee.status {
        case .accepted: indicator = "✓"
        case .tentative: indicator = "△"
        case .pending: indicator = "○"
        case .declined: indicator = "✕"
        case .unknown: indicator = "―"
        }
        let name = attendee.displayName
        var tags: [String] = []
        if attendee.isOrganizer { tags.append("主催") }
        if attendee.isCurrentUser { tags.append("自分") }
        let suffix = tags.isEmpty ? "" : " (\(tags.joined(separator: "・")))"
        return "\(indicator) \(name)\(suffix)"
    }

    private func makeLabel(
        _ text: String,
        fontSize: CGFloat,
        bold: Bool = false,
        color: NSColor = .labelColor,
        maxLines: Int = 0
    ) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font =
            bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
        label.textColor = color
        label.isSelectable = true
        label.maximumNumberOfLines = maxLines
        if maxLines > 0 {
            label.lineBreakMode = .byTruncatingTail
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func makeHTMLLabel(
        _ html: String,
        fontSize: CGFloat,
        color: NSColor,
        maxLines: Int = 0
    ) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.isSelectable = true
        // リンクをクリック可能にしつつ、クリック時に field editor が
        // プレーンテキスト化して装飾が剥がれるのを防ぐ (QA1487)
        label.allowsEditingTextAttributes = true
        label.maximumNumberOfLines = maxLines
        if maxLines > 0 {
            label.lineBreakMode = .byTruncatingTail
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let source = html.contains("<") ? html : html.replacingOccurrences(of: "\n", with: "<br>")
        let styledHTML =
            "<div style=\"font-family: -apple-system, sans-serif; font-size: \(fontSize)px;\">\(source)</div>"
        if let data = styledHTML.data(using: .utf8),
            let parsed = try? NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil)
        {
            if parsed.length > 0, parsed.string.hasSuffix("\n") {
                parsed.deleteCharacters(in: NSRange(location: parsed.length - 1, length: 1))
            }
            let range = NSRange(location: 0, length: parsed.length)
            parsed.enumerateAttribute(.link, in: range) { link, subRange, _ in
                if link == nil {
                    parsed.addAttribute(.foregroundColor, value: color, range: subRange)
                }
            }
            label.attributedStringValue = parsed
        } else {
            label.stringValue = html
        }

        return label
    }

    private func makeSeparator() -> NSBox {
        let sep = NSBox()
        sep.boxType = .separator
        return sep
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 11)
        return button
    }
}
