import Foundation
import SwiftUI

enum GhosttyConfigUpdater {
  private static var configPath: String {
    (NSHomeDirectory() as NSString)
      .appendingPathComponent("Library/Application Support/com.mitchellh.ghostty/config")
  }

  /// Represents a parsed theme configuration from Ghostty config
  private enum ParsedTheme {
    case none
    case single(String)
    case partialLight(String)  // Only light:Theme specified
    case partialDark(String)  // Only dark:Theme specified
    case dual(light: String, dark: String)
  }

  /// Keywords that suggest a dark theme
  private static let darkKeywords = ["dark", "night", "nocturne", "black", "nord"]

  /// Keywords that suggest a light theme
  private static let lightKeywords = ["light", "dawn", "day", "white"]

  /// Determines if a theme name is likely a dark theme based on heuristics
  private static func isLikelyDarkTheme(_ name: String) -> Bool {
    let lowercased = name.lowercased()
    return darkKeywords.contains { lowercased.contains($0) }
  }

  /// Determines if a theme name is likely a light theme based on heuristics
  private static func isLikelyLightTheme(_ name: String) -> Bool {
    let lowercased = name.lowercased()
    return lightKeywords.contains { lowercased.contains($0) }
  }

  /// Extracts a theme name with the given prefix from a comma-separated value string
  /// - Parameters:
  ///   - prefix: The prefix to look for (e.g., "light:" or "dark:")
  ///   - value: The comma-separated theme value string
  /// - Returns: The extracted theme name, or nil if not found
  private static func extractPrefixedTheme(_ prefix: String, from value: String) -> String? {
    let prefixLength = prefix.count
    let parts = value.components(separatedBy: ",")

    for part in parts {
      let trimmedPart = part.trimmingCharacters(in: .whitespaces)
      if trimmedPart.hasPrefix(prefix) {
        let themeName = String(trimmedPart.dropFirst(prefixLength)).trimmingCharacters(in: .whitespaces)
        if !themeName.isEmpty {
          return themeName
        }
      }
    }

    return nil
  }

  /// Parses the theme setting from a Ghostty config file content
  private static func parseTheme(from config: String) -> ParsedTheme {
    let lines = config.components(separatedBy: .newlines)

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Look for theme directive (supports "theme =" and "theme=" formats)
      guard trimmed.hasPrefix("theme") else { continue }

      // Extract the value part after "="
      guard let equalIndex = trimmed.firstIndex(of: "=") else { continue }
      let value = String(trimmed[trimmed.index(after: equalIndex)...])
        .trimmingCharacters(in: .whitespaces)

      let hasLight = value.contains("light:")
      let hasDark = value.contains("dark:")

      // Check for complete dual theme format: "light:...,dark:..."
      if hasLight && hasDark {
        let lightTheme = extractPrefixedTheme("light:", from: value)
        let darkTheme = extractPrefixedTheme("dark:", from: value)

        if let light = lightTheme, let dark = darkTheme {
          return .dual(light: light, dark: dark)
        }
      }

      // Handle partial dual themes (only light: specified, no dark:)
      if hasLight && !hasDark {
        if let theme = extractPrefixedTheme("light:", from: value) {
          return .partialLight(theme)
        }
      }

      // Handle partial dual themes (only dark: specified, no light:)
      if hasDark && !hasLight {
        if let theme = extractPrefixedTheme("dark:", from: value) {
          return .partialDark(theme)
        }
      }

      // Single theme format (no light: or dark: prefixes)
      let themeName = value.trimmingCharacters(in: .whitespaces)
      if !themeName.isEmpty {
        return .single(themeName)
      }
    }

    return .none
  }

  static func updateTheme(for colorScheme: ColorScheme?) {
    guard let currentConfig = try? String(contentsOfFile: configPath, encoding: .utf8) else {
      // No existing config → create with default dual theme
      createNewConfigWithDualTheme(
        light: "Apple System Colors Light",
        dark: "Apple System Colors",
      )
      return
    }

    let parsedTheme = parseTheme(from: currentConfig)

    switch parsedTheme {
    case .none:
      // No theme configured → add default dual theme
      updateExistingConfig(
        currentConfig,
        lightTheme: "Apple System Colors Light",
        darkTheme: "Apple System Colors",
      )

    case .dual:
      // User has dual theme → respect it, don't modify
      return

    case .partialLight(let theme):
      // User specified only light theme → use Apple System Colors for dark
      updateExistingConfig(
        currentConfig,
        lightTheme: theme,
        darkTheme: "Apple System Colors",
      )

    case .partialDark(let theme):
      // User specified only dark theme → use Apple System Colors Light for light
      updateExistingConfig(
        currentConfig,
        lightTheme: "Apple System Colors Light",
        darkTheme: theme,
      )

    case .single(let theme):
      // Single theme → determine mode and create dual
      let lightTheme: String
      let darkTheme: String

      if isLikelyLightTheme(theme) {
        lightTheme = theme
        darkTheme = "Apple System Colors"
      } else {
        // Assume dark (including when isLikelyDarkTheme is true or unclear)
        lightTheme = "Apple System Colors Light"
        darkTheme = theme
      }

      updateExistingConfig(currentConfig, lightTheme: lightTheme, darkTheme: darkTheme)
    }
  }

  private static func updateExistingConfig(_ config: String, lightTheme: String, darkTheme: String) {
    var lines = config.components(separatedBy: .newlines)
    let dualTheme = "light:\(lightTheme),dark:\(darkTheme)"
    var themeLineFound = false

    for index in 0..<lines.count {
      let line = lines[index].trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("theme") {
        lines[index] = "theme = \(dualTheme)"
        themeLineFound = true
        break
      }
    }

    if !themeLineFound {
      lines.append("theme = \(dualTheme)")
    }

    let updatedConfig = lines.joined(separator: "\n")
    try? updatedConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
  }

  private static func createNewConfigWithDualTheme(light: String, dark: String) {
    let configContent = """
      # Supacode Ghostty config
      theme = light:\(light),dark:\(dark)

      """
    try? configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
  }
}
