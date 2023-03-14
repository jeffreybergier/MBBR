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


public enum Parser {
    
    public static var imageExtensions: Set<String> = ["png", "jpg", "jpeg"]
    private static let calendar = Calendar(identifier: .gregorian)
    private static let timeZone = TimeZone(identifier: "GMT")!
    private static let dateFormatter = ISO8601DateFormatter()
    
    public static func decode(fromJSONURL jsonURL: URL, completion: @escaping (Result<MicroBlog, Error>) -> Void) {
        do {
            let baseURL = jsonURL.deletingLastPathComponent()
            let rawData = try self.MAINTHREAD_decodeRAW(fromJSONURL: jsonURL)
            rawData.1.queueMap(priority: .userInitiated) { rawPost, richContent, htmlData in
                try self.BACKGROUND_cleanPost(for: rawPost, with: richContent, htmlData: htmlData, baseURL: baseURL)
            } completion: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let posts):
                        var output = rawData.0.clean
                        output.posts = posts
                        completion(.success(output))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    internal static func MAINTHREAD_decodeRAW(fromJSONURL jsonURL: URL) throws -> (RAW_MicroBlog, [(RAW_MicroBlog.RAW_Post, NSAttributedString, Data)]) {
        let data      = try Data(contentsOf: jsonURL)
        let rawBlog   = try JSONDecoder().decode(RAW_MicroBlog.self, from: data)
        let baseURL   = jsonURL.deletingLastPathComponent()
        let rawPosts  = try rawBlog.items.map { try self.generateAttributedStrings(for: $0, baseURL: baseURL) }
        return (rawBlog, rawPosts)
    }
    
    /// Returns a new post but with no attachments. Do that later
    private static func generateAttributedStrings(for raw: RAW_MicroBlog.RAW_Post, baseURL: URL) throws -> (RAW_MicroBlog.RAW_Post, NSAttributedString, Data) {
        precondition(Thread.isMainThread)
        guard
            let htmlData = raw.content_html.data(using: .utf16),
            let richString = NSAttributedString(html: htmlData,
                                                baseURL: baseURL,
                                                documentAttributes: nil)
        else {
            throw NSError(domain: "com.saturdayapps.MBBR.parser", code: -1001)
        }
        return (raw, richString, htmlData)
    }
    
    internal static func BACKGROUND_cleanPost(for rawPost: RAW_MicroBlog.RAW_Post, with richContent: NSAttributedString, htmlData: Data, baseURL: URL) throws -> MicroBlog.Post {
        // get the date and URL
        let postURL = rawPost.url
        guard let datePublished = Parser.dateFormatter.date(from: rawPost.date_published) else {
            throw NSError(domain: "com.saturdayapps.MBBR.parser", code: -1002)
        }

        // Process the string for attachments
        let range = NSRange(location: 0, length: richContent.length)
        var attachment: MicroBlog.Post.Attachments = .init()
        var attachmentError: Error?
        richContent.enumerateAttributes(in: range, options: []) { keys, range, stop in
            // Link attachment finding code
            if let link = keys[.link] as? URL {
                if let link = self.cleanPost_localImageURL(from: link, postURL: postURL, baseURL: baseURL) {
                    attachment.imageURL.insert(link)
                } else {
                    // Don't know what this is, so just drop it in as-is
                    attachment.webURL.insert(link)
                }
            }
            // Image attachment finding code
            if let textAttachment = keys[.attachment] as? NSTextAttachment,
               let fileName = textAttachment.fileWrapper?.preferredFilename
            {
                do {
                    let link = try self.cleanPost_generateFakeFileURL(fileName: fileName,
                                                                      publishDate: datePublished,
                                                                      baseURL: baseURL)
                    attachment.imageURL.insert(link)
                } catch {
                    attachmentError = error
                    stop.pointee = true
                }
            }
        }
        
        if let attachmentError {
            throw attachmentError
        }
        
        return .init(webURL: postURL,
                     datePublished: datePublished,
                     attachments: attachment,
                     contentPlain: richContent.string,
                     contentRich: richContent,
                     contentHTML: htmlData)
    }
    
    /// generates local URL from complete Web URL
    private static func cleanPost_localImageURL(from linkURL: URL, postURL: URL, baseURL: URL) -> URL? {
        let linkExt  = linkURL.pathExtension
        let linkPath = linkURL.path
        guard
            let linkHost = linkURL.host,
            linkHost == postURL.host,
            Parser.imageExtensions.contains(linkExt)
        else { return nil }
        let output = baseURL.appendingPathComponent(linkPath)
        #if DEBUG
        if ((try? output.checkResourceIsReachable()) ?? false) == false {
            NSLog("Couldn't Find Image: \(output)")
        }
        #endif
        return output
    }
    
    
    private static func cleanPost_generateFakeFileURL(fileName: String, publishDate: Date, baseURL: URL) throws -> URL {
        let components = Parser.calendar.dateComponents(in: Parser.timeZone, from: publishDate)
        let yearString = String(components.year ?? -1)
        let output = baseURL
            .appendingPathComponent("uploads")
            .appendingPathComponent(yearString)
            .appendingPathComponent(fileName)
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
    
    /// Transforms a collection with a concurrent queue. Collection is guaranteed to be in correct order. If a transform throws an error, the entire operation is abandoned. Completion called on arbitrary serial queue.
    internal func queueMap<T>(priority: DispatchQoS, transform: @escaping (Element) throws -> T, completion: @escaping (Result<[T], Error>) -> Void) {
        let transformQueue = DispatchQueue(label: "RandomAccessCollection.QeueuMap.Transform", qos: priority, attributes: .concurrent)
        let writeQueue = DispatchQueue(label: "RandomAccessCollection.QeueuMap.WriteQueue", qos: priority)
        var output: [T?] = .init(repeating: nil, count: self.count)
        var count = 0
        var stop = false
        for (idx, element) in self.enumerated() {
            guard stop == false else { break }
            transformQueue.async {
                do {
                    let transformed = try transform(element)
                    writeQueue.sync {
                        output[idx] = transformed
                        count += 1
                        guard count >= self.count else { return }
                        stop = true
                        completion(.success(output as! [T]))
                    }
                } catch {
                    writeQueue.sync {
                        stop = true
                        completion(.failure(error))
                    }
                }
            }
        }
    }
}
