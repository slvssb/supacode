import Foundation
import SwiftUI

enum GhosttyConfigUpdater {
  private static var configPath: String {
    (NSHomeDirectory() as NSString)
      .appendingPathComponent("Library/Application Support/com.mitchellh.ghostty/config")
  }

  private static func themeName(for colorScheme: ColorScheme?) -> String {
    colorScheme == .dark ? "Apple System Colors" : "Apple System Colors Light"
  }

  static func updateTheme(for colorScheme: ColorScheme?) {
    let theme = themeName(for: colorScheme)

    if let currentConfig = try? String(contentsOfFile: configPath, encoding: .utf8) {
      updateExistingConfig(currentConfig, theme: theme)
    } else {
      createNewConfig(theme: theme)
    }
  }

  private static func updateExistingConfig(_ config: String, theme: String) {
    var lines = config.components(separatedBy: .newlines)
    var themeLineFound = false

    for i in 0..<lines.count {
      let line = lines[i].trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("theme") {
        lines[i] = "theme = \(theme)"
        themeLineFound = true
        break
      }
    }

    if !themeLineFound {
      lines.append("theme = \(theme)")
    }

    let updatedConfig = lines.joined(separator: "\n")
    try? updatedConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
  }

  private static func createNewConfig(theme: String) {
    let configContent = """
    # Supacode Ghostty config
    theme = \(theme)

    """
    try? configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
  }
}
