import Foundation
import XCTest

@testable import AIUsage

final class BehaviorTests: XCTestCase {
    private struct Expected: Decodable {
        let rowKeys: [String]
        let rowValues: [Double]
        let panelText: [String]
        let history: [String: Double]
    }

    private struct Scenario: Decodable {
        let name: String
        let envelope: Envelope
        let expected: Expected
    }

    func testSharedFrontendScenarios() throws {
        // Resolve from this source file, independent of SwiftPM's working directory.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", root.appendingPathComponent("scripts/frontend-fixtures.py").path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let cases = try JSONDecoder().decode([Scenario].self, from: data)
        XCTAssertFalse(cases.isEmpty)
        for scenario in cases {
            let provider = try XCTUnwrap(scenario.envelope.providers.first)
            XCTAssertEqual(provider.visibleQuotaWindows.map(\.key), scenario.expected.rowKeys, scenario.name)
            XCTAssertEqual(provider.visibleQuotaWindows.map(\.pct), scenario.expected.rowValues, scenario.name)
            XCTAssertEqual(MenuBarTitle.readings(for: provider, limit: 10).map(\.text),
                           scenario.expected.panelText, scenario.name)
            XCTAssertEqual(provider.historyValues, scenario.expected.history, scenario.name)
        }
    }
}
