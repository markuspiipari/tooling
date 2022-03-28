import XCTest
@testable import Tooling

final class ToolingTests: XCTestCase {
  func testLogLevels() {
    XCTAssert(LogLevel(name: "debug") == .debug)
    XCTAssert(LogLevel(name: "verbose") == .verbose)
    XCTAssert(LogLevel(name: "info") == .info)
    XCTAssert(LogLevel(name: "warning") == .warning)
    XCTAssert(LogLevel(name: "error") == .error)
    XCTAssert(LogLevel(name: "fatal") == .fatal)
    XCTAssert(LogLevel(name: "muted") == .muted)
    XCTAssert(LogLevel(name: "asdfasdfasdf") == nil)
  }

  func testLogging() throws {
    // Test shared log initialization
    defer {
      Log.deinitialize()
    }

    let logURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("test.log")
    let fileLogStream = try FileLogStream(url: logURL)
    Log.initialize(level: .debug, streams: [StandardOutputLogStream(), fileLogStream])

    // Test debug logging
    let log = Log.shared
    log.info("Logging to stdout and \(logURL.path)")
    log.info("Log level: \(log.level)")

    LogLevel.allCases.forEach {
      let didLog = log.log(atLevel: $0, "\($0.title) message", sourceFile: #file, line: #line, function: #function)
      let isMuted = $0 == .muted
      XCTAssert(didLog != isMuted)
    }

    // Test info logging
    log.level = .info
    log.info("Log level: \(log.level)")

    LogLevel.allCases.forEach {
      let didLog = log.log(atLevel: $0, "\($0.title) message", sourceFile: #file, line: #line, function: #function)
      XCTAssert(didLog == ($0 != .muted && $0.rawValue >= LogLevel.info.rawValue))
    }
  }

  func logOutput(from tool: Tool, _ exitStatus: Tool.ExitStatus) {
    guard let output = String(data: exitStatus.output, encoding: .utf8) else {
      return Log.shared.error("Cannot decode output from '\(tool.name)' as UTF-8 text")
    }
    Log.shared.info("'\(tool.name)' output:")
    Log.shared.print(atLevel: .info, output)
  }

  func testTool() throws {
    defer {
      Log.deinitialize()
    }
    Log.shared.level = .debug

    guard let tool = Tool(resolving: "date") else {
      return XCTFail()
    }
    XCTAssertEqual("/bin/date", tool.url.path)

    tool.log = Log.shared.sublog(withTitle: tool.name)
    tool.options = [.inheritEnvironment, .logCommandLine, .logEnvironment]

    do {
      let result = try tool(["-R"])
      logOutput(from: tool, result)
    } catch {
      Log.shared.error("Tool failed", error: error)
    }

    Log.shared.info("Tool completed succesfully")
  }

  func testToolCommands() {
    defer {
      Log.deinitialize()
    }
    Log.shared.level = .debug

    guard let launchctl = LaunchctlTester() else {
      return XCTFail()
    }

    launchctl.log = Log.shared.sublog(withTitle: launchctl.name)
    launchctl.options = [.inheritEnvironment, .logCommandLine, .logEnvironment]

    do {
      logOutput(from: launchctl, try launchctl.help())
    } catch {

    }

  }
}

class LaunchctlTester: Tool {
  init?() {
    super.init(resolving: "launchctl")
  }

  lazy var help: Command = {
    return Command(tool: self, name: "help")
  }()
}
