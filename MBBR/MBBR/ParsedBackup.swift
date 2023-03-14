//
//  ParsedBackup.swift
//  MBBR
//
//  Created by Jeffrey Bergier on 2023/03/14.
//

import SwiftUI

@propertyWrapper
public struct ParsedBackup: DynamicProperty {
    
    public struct Value {
        public var url: URL?
        public var data: MicroBlog?
        public var error: Error?
    }
    
    @State private var value = Value()
    
    public init() {}
    
    public var wrappedValue: Value {
        get { self.value }
        nonmutating set { self.newValue(newValue) }
    }
    
    private func newValue(_ newValue: Value) {
        let oldValue = self.value
        if newValue.url != oldValue.url {
            let newNewValue = Value(url: newValue.url)
            self.value = newNewValue
            Parser.decode(fromJSONURL: newValue.url!) {
                switch $0 {
                case .success(let data):
                    self.value.error = nil
                    self.value.data = data
                case .failure(let error):
                    self.value.data = nil
                    self.value.error = error
                }
            }
        } else {
            self.value = newValue
        }
    }
}
