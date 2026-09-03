import Foundation

public struct HTTPRequest: Sendable, Equatable {
  public var url: URL
  public var method: String
  public var headers: [String: String]
  public var body: Data?

  public init(
    url: URL,
    method: String = "GET",
    headers: [String: String] = [:],
    body: Data? = nil
  ) {
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
  }

  public func adding(_ name: String, _ value: String) -> HTTPRequest {
    var copy = self
    copy.headers[name] = value
    return copy
  }
}

public struct HTTPResponse: Sendable, Equatable {
  public let statusCode: Int
  public let body: Data

  public init(statusCode: Int, body: Data) {
    self.statusCode = statusCode
    self.body = body
  }

  public var isSuccess: Bool { (200..<300).contains(statusCode) }

  public var text: String {
    String(decoding: body, as: UTF8.self)
  }
}

/// The network, behind a protocol for the same reason `CommandRunning` is: so a
/// test can answer a request without one.
public protocol HTTPRequesting: Sendable {
  func perform(_ request: HTTPRequest) throws -> HTTPResponse
  /// Streams a response straight to disk. App binaries are too big to hold in
  /// memory, and the caller wants a file anyway.
  func download(_ request: HTTPRequest, to destination: URL) throws
}

/// Synchronous on purpose.
///
/// Every other client in this package blocks and throws, and the interface
/// already runs slow work on its own queue with a spinner. An async island in
/// the middle would have to be bridged back at every call site.
public struct URLSessionRequester: HTTPRequesting {
  private let session: URLSession
  private let timeout: TimeInterval

  public init(timeout: TimeInterval = 60) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = 600
    self.session = URLSession(configuration: configuration)
    self.timeout = timeout
  }

  public func perform(_ request: HTTPRequest) throws -> HTTPResponse {
    let outcome = try wait { completion in
      let task = session.dataTask(with: urlRequest(for: request)) { data, response, error in
        completion(data, response, error)
      }
      task.resume()
      return task
    }
    guard let http = outcome.response as? HTTPURLResponse else {
      throw SimctlBuddyError.networkFailed("No response from \(request.url.host ?? "the server").")
    }
    return HTTPResponse(statusCode: http.statusCode, body: outcome.data ?? Data())
  }

  public func download(_ request: HTTPRequest, to destination: URL) throws {
    var moved: URL?
    let outcome = try wait { completion in
      let task = session.downloadTask(with: urlRequest(for: request)) { url, response, error in
        // The temporary file is deleted the moment this callback returns, so it
        // has to be moved here rather than after the wait.
        if let url {
          do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: url, to: destination)
            moved = destination
          } catch {
            completion(nil, response, error)
            return
          }
        }
        completion(nil, response, error)
      }
      task.resume()
      return task
    }
    guard let http = outcome.response as? HTTPURLResponse else {
      throw SimctlBuddyError.networkFailed("No response from \(request.url.host ?? "the server").")
    }
    guard (200..<300).contains(http.statusCode) else {
      try? FileManager.default.removeItem(at: destination)
      throw SimctlBuddyError.networkFailed(
        "Downloading the build failed with HTTP \(http.statusCode).")
    }
    guard moved != nil else {
      throw SimctlBuddyError.networkFailed("The download produced no file.")
    }
  }

  // MARK: - Plumbing

  private struct Outcome {
    var data: Data?
    var response: URLResponse?
  }

  private func urlRequest(for request: HTTPRequest) -> URLRequest {
    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method
    urlRequest.httpBody = request.body
    for (name, value) in request.headers {
      urlRequest.setValue(value, forHTTPHeaderField: name)
    }
    return urlRequest
  }

  private func wait(
    _ start: (@escaping (Data?, URLResponse?, (any Error)?) -> Void) -> URLSessionTask
  ) throws -> Outcome {
    let semaphore = DispatchSemaphore(value: 0)
    // The callback runs on the session's own queue, so the boxed result needs a
    // lock even though only one write ever happens.
    let box = ResultBox()
    _ = start { data, response, error in
      box.set(data: data, response: response, error: error)
      semaphore.signal()
    }
    semaphore.wait()
    if let error = box.error {
      throw SimctlBuddyError.networkFailed(error.localizedDescription)
    }
    return Outcome(data: box.data, response: box.response)
  }

  private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _data: Data?
    private var _response: URLResponse?
    private var _error: (any Error)?

    func set(data: Data?, response: URLResponse?, error: (any Error)?) {
      lock.lock()
      _data = data
      _response = response
      _error = error
      lock.unlock()
    }

    var data: Data? { lock.withLock { _data } }
    var response: URLResponse? { lock.withLock { _response } }
    var error: (any Error)? { lock.withLock { _error } }
  }
}

extension NSLock {
  fileprivate func withLock<T>(_ body: () -> T) -> T {
    lock()
    defer { unlock() }
    return body()
  }
}
