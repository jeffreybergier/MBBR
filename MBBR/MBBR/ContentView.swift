//
//  ContentView.swift
//  MBBR
//
//  Created by Jeffrey Bergier on 2023/03/10.
//

import SwiftUI

struct ContentView: View {
    
    @ParsedBackup private var data
    
    var body: some View {
        VStack {
            Text(String(describing: self.data.data?.posts.count ?? -1))
        }
        .padding()
        .onAppear {
            let url = URL(string: "file:///Users/jeffberg/Downloads/jeffreybergier_aad4eb.bar/feed.json")!
            self.data.url = url
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
