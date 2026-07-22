import AppKit
import KokukokuCore

/// 予定行のクリックで表示する詳細ポップオーバー。
/// タイトル・時間帯・場所・説明文・参加者・アクションボタンを載せる
@MainActor
final class EventDetailPopover: NSPopover, NSPopoverDelegate {
    var onDismiss: (() -> Void)?
    /// ユーザー操作(ESC・transientの外クリック)による閉じ要求時に呼ばれ、
    /// falseを返すとpopover自身のアニメーション付きクローズを止められる
    /// (呼び出し側がパネルごと即時に閉じる場合に使う)。プログラムからの close() では呼ばれない
    var onUserCloseRequest: (() -> Bool)?
    /// 表示中の予定を再描画後も追跡するための安定ID
    let eventKey: CalendarEvent.EventKey
    /// 表示中の予定の現在の表示インデックス
    private(set) var eventIndex: Int

    init(eventRow: CalendarEventRow, eventIndex: Int, maximumContentHeight: CGFloat) {
        self.eventKey = eventRow.eventKey
        self.eventIndex = eventIndex
        super.init()
        let vc = EventDetailViewController(
            eventRow: eventRow, maximumContentHeight: maximumContentHeight)
        vc.onAction = { [weak self] in self?.close() }
        contentViewController = vc
        contentSize = vc.preferredContentSize
        behavior = .transient
        appearance = NSAppearance(named: .darkAqua)
        // 既定のポップアニメーション(拡縮入り)は非Retinaでカクつくため無効化し、
        // 表示は軽量フェードインに置き換える。クローズは常に即時
        animates = false
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func popoverWillShow(_ notification: Notification) {
        // 表示完了後に透明化すると一瞬だけ不透明フレームが見えるため、表示前に隠す
        contentViewController?.view.window?.alphaValue = 0
    }

    func popoverDidShow(_ notification: Notification) {
        // ウィンドウのalpha合成だけのフェードインは拡縮と違い再ラスタライズが
        // 走らないため、非Retinaディスプレイでも滑らかに表示できる
        guard let window = contentViewController?.view.window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    /// 同じ安定IDの予定について、再描画後の内容と表示位置を反映する
    func update(
        eventRow: CalendarEventRow,
        eventIndex: Int,
        maximumContentHeight: CGFloat
    ) {
        guard eventRow.eventKey == eventKey,
            let viewController = contentViewController as? EventDetailViewController
        else { return }
        self.eventIndex = eventIndex
        viewController.update(
            eventRow: eventRow, maximumContentHeight: maximumContentHeight)
        contentSize = viewController.preferredContentSize
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        onUserCloseRequest?() ?? true
    }

    /// h/l・←→でpopover内のアクションボタンのフォーカスを移動し、結果を返す。
    /// .closePopover(先頭ボタンからの後退)のときは呼び出し側がpopupを閉じる
    func moveButtonFocus(_ delta: Int) -> EventPopoverButtonFocus.Move {
        (contentViewController as? EventDetailViewController)?.moveButtonFocus(delta) ?? .none
    }

    /// フォーカス中のボタンを押す。フォーカスがなければfalse(呼び出し側の既定動作に任せる)
    func activateFocusedButton() -> Bool {
        (contentViewController as? EventDetailViewController)?.activateFocusedButton() ?? false
    }

    func popoverDidClose(_ notification: Notification) {
        onDismiss?()
    }
}

@MainActor
private final class EventDetailViewController: NSViewController {
    private static let contentWidth: CGFloat = 300
    private static let horizontalPadding: CGFloat = 14

    private var eventRow: CalendarEventRow
    private var maximumContentHeight: CGFloat
    var onAction: (() -> Void)?
    private var actionButtons: [NSButton] = []
    private var focusedButtonIndex: Int?

    private struct BodyScroll {
        var scrollView: NSScrollView
        var fullHeight: CGFloat
        var heightConstraint: NSLayoutConstraint
    }

    init(eventRow: CalendarEventRow, maximumContentHeight: CGFloat) {
        self.eventRow = eventRow
        self.maximumContentHeight = maximumContentHeight
        super.init(nibName: nil, bundle: nil)
        _ = view
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        rebuildContent()
    }

    /// 表示内容を現在のeventRowから組み直す。表示中でもビュー本体は差し替えず
    /// サブビューだけ再構築する(NSPopoverは表示時のviewインスタンスを保持し続けるため)
    private func rebuildContent() {
        NSLayoutConstraint.deactivate(view.constraints)
        view.subviews.forEach { $0.removeFromSuperview() }
        actionButtons = []
        let container = view

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

        let bodyScroll = makeBodyScrollView()
        if let scrollView = bodyScroll?.scrollView {
            let separator = makeSeparator()
            stack.addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.addArrangedSubview(scrollView)
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let hasButtons = eventRow.meetURL != nil || eventRow.detailURL != nil
        if hasButtons {
            let separator = makeSeparator()
            stack.addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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
            container.widthAnchor.constraint(equalToConstant: Self.contentWidth),
        ])

        container.layoutSubtreeIfNeeded()
        var fittingHeight = container.fittingSize.height
        if let bodyScroll, fittingHeight > maximumContentHeight {
            let overflow = fittingHeight - maximumContentHeight
            bodyScroll.heightConstraint.constant = max(bodyScroll.fullHeight - overflow, 60)
            bodyScroll.scrollView.hasVerticalScroller = true
            container.layoutSubtreeIfNeeded()
            fittingHeight = container.fittingSize.height
        }
        preferredContentSize = NSSize(
            width: Self.contentWidth,
            height: min(fittingHeight, maximumContentHeight))
    }

    /// 再取得された予定内容を表示へ反映する。表示データが同じならスクロール位置を維持する
    func update(eventRow: CalendarEventRow, maximumContentHeight: CGFloat) {
        guard eventRow != self.eventRow || maximumContentHeight != self.maximumContentHeight else {
            return
        }
        let previousFocusedButtonIndex = focusedButtonIndex
        self.eventRow = eventRow
        self.maximumContentHeight = maximumContentHeight
        rebuildContent()
        if let previousFocusedButtonIndex,
            previousFocusedButtonIndex < actionButtons.count
        {
            focusButton(at: previousFocusedButtonIndex)
        } else {
            focusedButtonIndex = nil
        }
    }

    /// 説明文と参加者一覧を1つのスクロール領域へ収める
    private func makeBodyScrollView() -> BodyScroll? {
        let notes = eventRow.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard notes?.isEmpty == false || !eventRow.attendees.isEmpty else { return nil }

        let bodyStack = NSStackView()
        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 6
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        if let notes, !notes.isEmpty {
            bodyStack.addArrangedSubview(makeHTMLLabel(notes, fontSize: 11, color: .labelColor))
        }
        if !eventRow.attendees.isEmpty {
            if notes?.isEmpty == false {
                let separator = makeSeparator()
                bodyStack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: bodyStack.widthAnchor).isActive = true
            }
            let header = makeLabel(
                "参加者", fontSize: 11, bold: true, color: .secondaryLabelColor)
            bodyStack.addArrangedSubview(header)
            for attendee in eventRow.attendees {
                bodyStack.addArrangedSubview(
                    makeLabel(
                        attendeeText(attendee), fontSize: 11,
                        bold: attendee.isOrganizer, color: .labelColor))
            }
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = EventDetailDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(bodyStack)
        scrollView.documentView = documentView

        let bodyWidth = Self.contentWidth - Self.horizontalPadding * 2
        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalToConstant: bodyWidth),
            bodyStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            bodyStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            bodyStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            bodyStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
        ])
        documentView.layoutSubtreeIfNeeded()
        let bodyHeight = max(bodyStack.fittingSize.height, 1)

        let heightConstraint = scrollView.heightAnchor.constraint(equalToConstant: bodyHeight)
        heightConstraint.isActive = true
        return BodyScroll(
            scrollView: scrollView,
            fullHeight: bodyHeight,
            heightConstraint: heightConstraint)
    }

    /// フォーカス位置を移動し、フォーカス中のボタンをデフォルトボタン
    /// (アクセントカラー)の見た目にして示す。移動結果を返し、
    /// .closePopover の判断は呼び出し側に委ねる
    func moveButtonFocus(_ delta: Int) -> EventPopoverButtonFocus.Move {
        let move = EventPopoverButtonFocus.moved(
            from: focusedButtonIndex, delta: delta, count: actionButtons.count)
        if case .focus(let next) = move {
            focusButton(at: next)
        }
        return move
    }

    private func focusButton(at index: Int) {
        focusedButtonIndex = index
        for (buttonIndex, button) in actionButtons.enumerated() {
            button.keyEquivalent = buttonIndex == index ? "\r" : ""
        }
    }

    func activateFocusedButton() -> Bool {
        guard let focusedButtonIndex else { return false }
        actionButtons[focusedButtonIndex].performClick(nil)
        return true
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
        actionButtons.append(button)
        return button
    }
}

/// スクロール開始位置を説明文・参加者一覧の先頭にするための反転ドキュメントビュー
private final class EventDetailDocumentView: NSView {
    override var isFlipped: Bool { true }
}
