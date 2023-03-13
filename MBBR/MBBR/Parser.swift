//
//  Parser.swift
//  MBBR
//
//  Created by Jeffrey Bergier on 2023/03/10.
//

import AppKit

public struct RAW_MicroBlog: Codable {
    
    public var items: [RAW_Post]
    public var title: String
    public var icon: URL
    public var feed_url: URL
    public var home_page_url: URL
    public var version: URL
    
    public struct RAW_Post: Codable {
        public var date_published: String
        public var url: URL
        public var content_text: String
        public var content_html: String
    }
    
    /// returns clean version with no posts
    internal var clean: MicroBlog {
        .init(posts: [],
              title: self.title,
              icon: self.icon,
              feedURL: self.feed_url,
              webURL: self.home_page_url,
              version: self.version)
    }
}

public struct MicroBlog {
    
    public var posts:   [Post]
    public var title:   String
    public var icon:    URL
    public var feedURL: URL
    public var webURL:  URL
    public var version: URL
    
    public struct Post {
        
        public struct Attachments {
            public var webURL:   Set<URL> = []
            public var imageURL: Set<URL> = []
        }
        
        public var webURL: URL
        public var datePublished: Date
        public var attachments: Attachments
        public var contentPlain: String
        public var contentRich: NSAttributedString
        /// UTF16 Data
        public var contentHTML: Data
    }
}


public struct Parser {
    
    public static var imageExtensions: Set<String> = ["png", "jpg", "jpeg"]
    private static let calendar = Calendar(identifier: .gregorian)
    private static let timeZone = TimeZone.gmt
    private static let dateFormatter = ISO8601DateFormatter()
    
    public var feedJSONURL: URL
    public var baseURL: URL { self.feedJSONURL.deletingLastPathComponent() }
    
    public init(feedJSONURL: URL) {
        self.feedJSONURL = feedJSONURL
    }
    
    public func decode() async throws -> MicroBlog {
        let output = try await self.step0_decode()
        return output
    }
    
    private func step0_decode() async throws -> MicroBlog {
        let data     = try Data(contentsOf: self.feedJSONURL)
        let raw      = try JSONDecoder().decode(RAW_MicroBlog.self, from: data)
        var output   = raw.clean
        output.posts = try await raw.items.parallelMap { rawPost in
            var post = try self.step1_generatePost(for: rawPost)
            post.attachments = try self.step2_generateAttachments(for: post.contentRich,
                                                                  postURL: post.webURL,
                                                                  publishDate: post.datePublished)
            return post
        }
        return output
    }
    
    /// Returns a new post but with no attachments. Do that later
    private func step1_generatePost(for raw: RAW_MicroBlog.RAW_Post) throws -> MicroBlog.Post {
        precondition(Thread.isMainThread)
        guard
            let htmlData = raw.content_html.data(using: .utf16),
            let richString = NSAttributedString(html: htmlData,
                                                baseURL: self.baseURL,
                                                documentAttributes: nil)
        else {
            throw NSError(domain: "com.saturdayapps.MBBR.parser", code: -1001)
        }
        guard let date = Parser.dateFormatter.date(from: raw.date_published) else {
            throw NSError(domain: "com.saturdayapps.MBBR.parser", code: -1002)
        }
        return .init(webURL: raw.url,
                     datePublished: date,
                     attachments: .init(),
                     contentPlain: richString.string,
                     contentRich: richString,
                     contentHTML: htmlData)
    }
    
    private func step2_generateAttachments(for contentRich: NSAttributedString, postURL: URL, publishDate: Date) throws -> MicroBlog.Post.Attachments {
        let range = NSRange(location: 0, length: contentRich.length)
        var output: MicroBlog.Post.Attachments = .init()
        var outputError: Error?
        contentRich.enumerateAttributes(in: range, options: []) { keys, range, stop in
            // Link attachment finding code
            if let link = keys[.link] as? URL {
                if let link = self.step3_localImageURL(from: link, postURL: postURL) {
                    output.imageURL.insert(link)
                } else {
                    // Don't know what this is, so just drop it in as-is
                    output.webURL.insert(link)
                }
            }
            // Image attachment finding code
            if let attachment = keys[.attachment] as? NSTextAttachment,
               let fileName = attachment.fileWrapper?.preferredFilename
            {
                do {
                    let link = try self.step4_generateFakeFileURL(fileName: fileName,
                                                                  publishDate: publishDate)
                    output.imageURL.insert(link)
                } catch {
                    outputError = error
                    stop.pointee = true
                }
            }
        }
        
        if let outputError {
            throw outputError
        }
        
        return output
    }
    
    /// generates local URL from complete Web URL
    private func step3_localImageURL(from linkURL: URL, postURL: URL) -> URL? {
        let linkExt  = linkURL.pathExtension
        let linkPath = linkURL.path
        guard
            let linkHost = linkURL.host,
            linkHost == postURL.host,
            Parser.imageExtensions.contains(linkExt)
        else { return nil }
        let output = self.baseURL.appending(path: linkPath)
        #if DEBUG
        if ((try? output.checkResourceIsReachable()) ?? false) == false {
            NSLog("Couldn't Find Image: \(output)")
        }
        #endif
        return output
    }
    
    
    private func step4_generateFakeFileURL(fileName: String, publishDate: Date) throws -> URL {
        let components = Parser.calendar.dateComponents(in: Parser.timeZone, from: publishDate)
        let yearString = String(components.year ?? -1)
        let output = self.baseURL
            .appending(path: "uploads", directoryHint: .isDirectory)
            .appending(path: yearString, directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
        #if DEBUG
        if ((try? output.checkResourceIsReachable()) ?? false) == false {
            NSLog("Couldn't Find Image: \(output)")
        }
        #endif
        return output
    }
}


extension Sequence {
    internal func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values = [T]()
        for element in self {
            try await values.append(transform(element))
        }
        return values
    }
}

extension RandomAccessCollection {
    /// Processes a map in parallel and returns the transformed collection in the same order
    internal func parallelMap<T>(priority: TaskPriority = .userInitiated,
                                 _ transform: @escaping (Element) async throws -> T) async rethrows -> [T]
    {
        typealias TransformTuple = (Int, T)
        return try await withThrowingTaskGroup(of: TransformTuple.self) { group in
            var output: [T?] = .init(repeating: nil, count: self.count)
            for (idx, element) in self.enumerated() {
                group.addTask(priority: priority) {
                    let transformed = try await transform(element)
                    return (idx, transformed)
                }
            }
            // Tasks return in order done, not in the order requested.
            // Using Enumerated and Tuple allows them to be placed in order.
            for try await transformedTuple in group {
                output[transformedTuple.0] = transformedTuple.1
            }
            return output as! [T]
        }
    }
}
