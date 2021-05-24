//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class DisplayableText: NSObject {

    private struct Content {
        let textValue: CVTextValue
        let naturalAlignment: NSTextAlignment

        var stringValue: String { textValue.stringValue }
    }

    private let _fullContent: AtomicValue<Content>
    private var fullContent: Content {
        get { _fullContent.get() }
        set { _fullContent.set(newValue) }
    }

    private let _truncatedContent = AtomicOptional<Content>(nil)
    private var truncatedContent: Content? {
        get { _truncatedContent.get() }
        set { _truncatedContent.set(newValue) }
    }

    public var fullTextValue: CVTextValue {
        fullContent.textValue
    }

    public var truncatedTextValue: CVTextValue? {
        truncatedContent?.textValue
    }

    public var displayTextValue: CVTextValue {
        return truncatedContent?.textValue ?? fullContent.textValue
    }

    public func textValue(isTextExpanded: Bool) -> CVTextValue {
        if isTextExpanded {
            return fullTextValue
        } else {
            return displayTextValue
        }
    }

    @objc
    public var fullAttributedText: NSAttributedString {
        switch fullContent.textValue {
        case .text(let text):
            return NSAttributedString(string: text)
        case .attributedText(let attributedText):
            return attributedText
        }
    }

    @objc
    public var fullTextNaturalAlignment: NSTextAlignment {
        return fullContent.naturalAlignment
    }

    @objc
    public var displayAttributedText: NSAttributedString {
        let content = truncatedContent ?? fullContent
        switch content.textValue {
        case .text(let text):
            return NSAttributedString(string: text)
        case .attributedText(let attributedText):
            return attributedText
        }
    }

    @objc
    public var displayTextNaturalAlignment: NSTextAlignment {
        return truncatedContent?.naturalAlignment ?? fullContent.naturalAlignment
    }

    @objc
    public var isTextTruncated: Bool {
        return truncatedContent != nil
    }

    private static let maxInlineText = 1024 * 8

    @objc
    public var canRenderTruncatedTextInline: Bool {
        return isTextTruncated && fullLengthWithNewLineScalar <= Self.maxInlineText
    }

    @objc
    public let fullLengthWithNewLineScalar: Int

    @objc public let jumbomojiCount: UInt

    @objc
    public static let kMaxJumbomojiCount: UInt = 5

    // This value is a bit arbitrary since we don't need to be 100% correct about 
    // rendering "Jumbomoji".  It allows us to place an upper bound on worst-case
    // performacne.
    @objc
    static let kMaxCharactersPerEmojiCount: UInt = 10

    // MARK: Initializers

    private init(fullContent: Content, truncatedContent: Content?) {
        self._fullContent = AtomicValue(fullContent)
        self._truncatedContent.set(truncatedContent)
        self.jumbomojiCount = DisplayableText.jumbomojiCount(in: fullContent.stringValue)
        self.fullLengthWithNewLineScalar = DisplayableText.fullLengthWithNewLineScalar(in: fullContent.stringValue)

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .ThemeDidChange,
            object: nil
        )
    }

    @objc
    private func themeDidChange() {
        // When the theme changes, we must refresh any mention attributes.
        func updateContent(_ content: Content) -> Content {
            switch content.textValue {
            case .text:
                // We only need to update attributedText.
                return content
            case .attributedText(let attributedText):
                let mutableFullText = NSMutableAttributedString(attributedString: attributedText)
                Mention.refreshAttributes(in: mutableFullText)
                return Content(textValue: .attributedText(attributedText: mutableFullText),
                               naturalAlignment: content.naturalAlignment)
            }
        }

        // When the theme changes, we must refresh any mention attributes.
        fullContent = updateContent(fullContent)

        if let truncatedContent = truncatedContent {
            self.truncatedContent = updateContent(truncatedContent)
        }
    }

    // MARK: Emoji

    // If the string is...
    //
    // * Non-empty
    // * Only contains emoji
    // * Contains <= kMaxJumbomojiCount emoji
    //
    // ...return the number of emoji (to be treated as "Jumbomoji") in the string.
    private class func jumbomojiCount(in string: String) -> UInt {
        if string == "" {
            return 0
        }
        if string.count > Int(kMaxJumbomojiCount * kMaxCharactersPerEmojiCount) {
            return 0
        }
        guard string.containsOnlyEmoji else {
            return 0
        }
        let emojiCount = string.glyphCount
        if UInt(emojiCount) > kMaxJumbomojiCount {
            return 0
        }
        return UInt(emojiCount)
    }

    // For perf we use a static linkDetector. It doesn't change and building DataDetectors is
    // surprisingly expensive. This should be fine, since NSDataDetector is an NSRegularExpression
    // and NSRegularExpressions are thread safe.
    private static let linkDetector: NSDataDetector? = {
        return try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    private static let hostRegex: NSRegularExpression? = {
        let pattern = "^(?:https?:\\/\\/)?([^:\\/\\s]+)(.*)?$"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    @objc
    public lazy var shouldAllowLinkification: Bool = {
        guard let linkDetector: NSDataDetector = DisplayableText.linkDetector else {
            owsFailDebug("linkDetector was unexpectedly nil")
            return false
        }

        func isValidLink(linkText: String) -> Bool {
            guard let hostRegex = DisplayableText.hostRegex else {
                owsFailDebug("hostRegex was unexpectedly nil")
                return false
            }

            guard let hostText = hostRegex.parseFirstMatch(inText: linkText) else {
                owsFailDebug("hostText was unexpectedly nil")
                return false
            }

            let strippedHost = hostText.replacingOccurrences(of: ".", with: "") as NSString

            if strippedHost.isOnlyASCII {
                return true
            } else if strippedHost.hasAnyASCII {
                // mix of ascii and non-ascii is invalid
                return false
            } else {
                // IDN
                return true
            }
        }

        let rawText = fullContent.stringValue

        for match in linkDetector.matches(in: rawText, options: [], range: rawText.entireRange) {
            guard let matchURL: URL = match.url else {
                continue
            }

            // We extract the exact text from the `fullText` rather than use match.url.host
            // because match.url.host actually escapes non-ascii domains into puny-code.
            //
            // But what we really want is to check the text which will ultimately be presented to
            // the user.
            let rawTextOfMatch = (rawText as NSString).substring(with: match.range)
            guard isValidLink(linkText: rawTextOfMatch) else {
                return false
            }
        }
        return true
    }()

    // MARK: Filter Methods

    private static let newLineRegex = try! NSRegularExpression(pattern: "\n", options: [])
    private static let newLineScalar = 16

    private class func fullLengthWithNewLineScalar(in string: String) -> Int {
        let numberOfNewLines = newLineRegex.numberOfMatches(
            in: string,
            options: [],
            range: string.entireRange
        )
        return string.utf16.count + numberOfNewLines * newLineScalar
    }

    @objc
    public class var empty: DisplayableText {
        return DisplayableText(
            fullContent: .init(textValue: .text(text: ""), naturalAlignment: .natural),
            truncatedContent: nil
        )
    }

    @objc
    public class func displayableTextForTests(_ text: String) -> DisplayableText {
        return DisplayableText(
            fullContent: .init(textValue: .text(text: text),
                               naturalAlignment: text.naturalTextAlignment),
            truncatedContent: nil
        )
    }

    @objc
    public class func displayableText(withMessageBody messageBody: MessageBody, mentionStyle: Mention.Style, transaction: SDSAnyReadTransaction) -> DisplayableText {
        let textValue = messageBody.textValue(style: mentionStyle,
                                              attributes: [:],
                                              shouldResolveAddress: { _ in true }, // Resolve all mentions in messages.
                                              transaction: transaction.unwrapGrdbRead)
        let fullContent = Content(
            textValue: textValue,
            naturalAlignment: textValue.stringValue.naturalTextAlignment
        )

        // Only show up to N characters of text.
        let kMaxTextDisplayLength = 512
        let kMaxSnippetNewLines = 15
        let truncatedContent: Content?

        if fullContent.stringValue.count > kMaxTextDisplayLength {
            var snippetLength = kMaxTextDisplayLength

            // Message bubbles by default should be short. We don't ever
            // want to show more than X new lines in the truncated text.
            let newLineMatches = newLineRegex.matches(
                in: fullContent.stringValue,
                options: [],
                range: NSRange(location: 0, length: kMaxTextDisplayLength)
            )
            if newLineMatches.count > kMaxSnippetNewLines {
                snippetLength = newLineMatches[kMaxSnippetNewLines - 1].range.location
            }

            switch textValue {
            case .text(let text):
                let truncatedText = (text.substring(to: snippetLength)
                                        .ows_stripped()
                                        + "…")
                truncatedContent = Content(textValue: .text(text: truncatedText),
                                           naturalAlignment: truncatedText.naturalTextAlignment)
            case .attributedText(let attributedText):
                var mentionRange = NSRange()
                let possibleOverlappingMention = attributedText.attribute(
                    .mention,
                    at: snippetLength,
                    longestEffectiveRange: &mentionRange,
                    in: attributedText.entireRange
                )

                // There's a mention overlapping our normal truncate point, we want to truncate sooner
                // so we don't "split" the mention.
                if possibleOverlappingMention != nil && mentionRange.location < snippetLength {
                    snippetLength = mentionRange.location
                }

                // Trim whitespace before _AND_ after slicing the snipper from the string.
                let truncatedAttributedText = attributedText
                    .attributedSubstring(from: NSRange(location: 0, length: snippetLength))
                    .ows_stripped()
                    .stringByAppendingString("…")

                truncatedContent = Content(textValue: .attributedText(attributedText: truncatedAttributedText),
                                           naturalAlignment: truncatedAttributedText.string.naturalTextAlignment)
            }
        } else {
            truncatedContent = nil
        }

        return DisplayableText(fullContent: fullContent, truncatedContent: truncatedContent)
    }
}
