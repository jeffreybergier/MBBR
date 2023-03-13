//
//  ContentView.swift
//  MBBR
//
//  Created by Jeffrey Bergier on 2023/03/10.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            Text("Hello, world!")
        }
        .padding()
        .task {
            let url = URL(string: "file:///Users/jeffberg/Downloads/jeffreybergier_aad4eb.bar/feed.json")!
            let parser = Parser(feedJSONURL: url)
            let blog = try! await parser.decode()
            print(blog.posts.count)
            
//            let before: [Int] = (0...10_000).map { $0 }
//            let after = await before.parallelMap { "::\($0)::" }
//            print(after)
//            print("done")
        }
        .onAppear() {

        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
