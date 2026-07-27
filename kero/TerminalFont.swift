//
//  TerminalFont.swift
//  kero
//

import AppKit
import CoreText

/// Terminal font handling, same approach as Otty: bundle JetBrains Mono
/// with the app so the default looks identical on every machine. Glyphs the
/// primary face lacks (CJK, symbols) come from an optional CJK fallback
/// (Ghostty-style second `font-family`) and then the Symbols Nerd Font; with
/// no CJK fallback set, CoreText's system cascade fills the gap.
enum TerminalFont {
    static let defaultSize: CGFloat = 13
    static let bundledFamily = "JetBrains Mono"
    private static let symbolsFontName = "SymbolsNFM"

    /// Registers the bundled JetBrains Mono faces (Regular/Bold/Italic/
    /// BoldItalic) and the Symbols Nerd Font for this process only, so
    /// nothing is installed system-wide. Must run before the first
    /// terminal view is created.
    static func registerBundledFonts() {
        // Xcode's synchronized groups flatten Fonts/ into Contents/Resources.
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    /// The terminal font for the current settings (family + size + CJK
    /// fallback cascade).
    @MainActor
    static func current() -> NSFont {
        let settings = AppSettings.shared
        return resolve(
            family: settings.fontFamily,
            cjkFamily: settings.fontFamilyCJK,
            size: CGFloat(settings.fontSize)
        )
    }

    /// Resolves a family name to a terminal-ready font. Empty family means
    /// the bundled default; an unknown family falls back to it too.
    ///
    /// Cascade order matches the Ghostty config Kero emits: optional CJK
    /// face, then the bundled Symbols Nerd Font for PUA icons. JetBrains Mono
    /// covers Powerline separators itself, so those never hit the fallback.
    static func resolve(
        family: String,
        cjkFamily: String = "",
        size: CGFloat
    ) -> NSFont {
        let base: NSFont
        if !family.isEmpty, family != bundledFamily,
           let chosen = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) {
            base = chosen
        } else if let bundled = NSFont(name: "JetBrainsMono-Regular", size: size) {
            base = bundled
        } else {
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
        var cascade: [NSFontDescriptor] = []
        if !cjkFamily.isEmpty,
           let cjk = NSFontManager.shared.font(
               withFamily: cjkFamily, traits: [], weight: 5, size: size
           ) {
            cascade.append(cjk.fontDescriptor)
        }
        cascade.append(NSFontDescriptor(name: symbolsFontName, size: size))
        let descriptor = base.fontDescriptor.addingAttributes([
            .cascadeList: cascade
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// Fixed-pitch families available for the primary font picker, bundled
    /// default first. The symbols-only fallback font is not a usable primary.
    static func selectableFamilies() -> [String] {
        let families = NSFontManager.shared.availableFontFamilies
            .filter { family in
                guard !family.hasPrefix("Symbols Nerd Font"),
                      family != bundledFamily, !family.hasPrefix("."),
                      let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 13)
                else { return false }
                return font.isFixedPitch
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return [bundledFamily] + families
    }

    /// Families that can draw a sample Han character — used for the CJK
    /// fallback picker. Preferred faces that exist on this Mac are listed
    /// first so PingFang SC is easy to find.
    static func cjkFallbackFamilies() -> [String] {
        let han = Character(UnicodeScalar(0x6C49)!) // 汉
        let preferred = [
            "PingFang SC",
            "PingFang TC",
            "PingFang HK",
            "Hiragino Sans GB",
            "Songti SC",
            "Heiti SC",
            "STHeiti",
            "Noto Sans CJK SC",
            "Noto Sans SC",
            "Source Han Sans SC",
            "Sarasa Gothic SC",
            "Maple Mono NF CN",
        ]
        let covering = NSFontManager.shared.availableFontFamilies.filter { family in
            guard !family.hasPrefix("."),
                  family != bundledFamily,
                  !family.hasPrefix("Symbols Nerd Font"),
                  let font = NSFontManager.shared.font(
                      withFamily: family, traits: [], weight: 5, size: 13
                  )
            else { return false }
            return font.coveredCharacterSet.contains(han.unicodeScalars.first!)
        }
        let coveringSet = Set(covering)
        let head = preferred.filter { coveringSet.contains($0) }
        let tail = covering
            .filter { !Set(head).contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return head + tail
    }
}
