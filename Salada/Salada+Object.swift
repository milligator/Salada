//
//  Salada+Object.swift
//  Salada
//
//  Created by 1amageek on 2017/01/05.
//  Copyright © 2017年 Stamp. All rights reserved.
//

import Foundation
import Firebase

extension Salada {

    public struct ObjectError: Error {
        enum ErrorKind {
            case invalidId
            case invalidFile
            case timeout
        }
        let kind: ErrorKind
        let description: String
    }

    /**
     Object is a class that defines the Scheme to Firebase.
     Once saved Object, save to the server in real time by KVO changes.
     Changes are run even offline.

     Please observe the following rules.
     1. Declaration the Element
     1. Class other than the Foundation description 'decode, 'encode'
     */
    public class Object: NSObject, Referenceable, Tasting {

        public typealias Element = Object

        enum ValueType {

            case string(String, String)
            case int(String, Int)
            case double(String, Double)
            case float(String, Float)
            case bool(String, Bool)
            case date(String, TimeInterval, Date)
            case url(String, String, URL)
            case array(String, [Any])
            case relation(String, [String: Bool], Set<String>)
            case file(String, File)
            case object(String, Any)
            case null

            static func from(key: String, value: Any) -> ValueType {
                switch value.self {
                case is String:         if let value: String        = value as? String      { return .string(key, value)  }
                case is URL:            if let value: URL           = value as? URL         { return .url(key, value.absoluteString, value) }
                case is Date:           if let value: Date          = value as? Date        { return .date(key, value.timeIntervalSince1970, value)}
                case is Int:            if let value: Int           = value as? Int         { return .int(key, Int(value)) }
                case is Double:         if let value: Double        = value as? Double      { return .double(key, Double(value)) }
                case is Float:          if let value: Float         = value as? Float       { return .float(key, Float(value)) }
                case is Bool:           if let value: Bool          = value as? Bool        { return .bool(key, Bool(value)) }
                case is [String]:       if let value: [String]      = value as? [String], !value.isEmpty { return .array(key, value) }
                case is Set<String>:    if let value: Set<String>   = value as? Set<String>, !value.isEmpty { return .relation(key, value.toKeys(), value) }
                case is File:           if let value: File          = value as? File        { return .file(key, value) }
                case is [String: Any]:  if let value: [String: Any] = value as? [String: Any] { return .object(key, value)}
                default: break
                }
                return .null
            }

            static func from(key: String, mirror: Mirror, with snapshot: [String: Any]) -> ValueType {
                let subjectType: Any.Type = mirror.subjectType
                if subjectType == String.self || subjectType == String?.self {
                    if let value: String = snapshot[key] as? String {
                        return .string(key, value)
                    }
                } else if subjectType == URL.self || subjectType == URL?.self {
                    if
                        let value: String = snapshot[key] as? String,
                        let url: URL = URL(string: value)  {
                        return .url(key, value, url)
                    }
                } else if subjectType == Date.self || subjectType == Date?.self {
                    if let value: Double = snapshot[key] as? Double {
                        let date: Date = Date(timeIntervalSince1970: TimeInterval(value))
                        return .date(key, value, date)
                    }
                } else if subjectType == Double.self || subjectType == Double?.self {
                    if let value: Double = snapshot[key] as? Double {
                        return .double(key, Double(value))
                    }
                } else if subjectType == Int.self || subjectType == Int?.self {
                    if let value: Int = snapshot[key] as? Int {
                        return .int(key, Int(value))
                    }
                } else if subjectType == Float.self || subjectType == Float?.self {
                    if let value: Float = snapshot[key] as? Float {
                        return .float(key, Float(value))
                    }
                } else if subjectType == Bool.self || subjectType == Bool?.self {
                    if let value: Bool = snapshot[key] as? Bool {
                        return .bool(key, Bool(value))
                    }
                } else if subjectType == [String].self || subjectType == [String]?.self {
                    if let value: [String] = snapshot[key] as? [String], !value.isEmpty {
                        return .array(key, value)
                    }
                } else if subjectType == Set<String>.self || subjectType == Set<String>?.self {
                    if let value: [String: Bool] = snapshot[key] as? [String: Bool], !value.isEmpty {
                        return .relation(key, value, Set(value.keys))
                    }
                } else if subjectType == [String: Any].self || subjectType == [String: Any]?.self {
                    if let value: [String: Any] = snapshot[key] as? [String: Any] {
                        return .object(key, value)
                    }
                } else if subjectType == File.self || subjectType == File?.self {
                    if let value: String = snapshot[key] as? String {
                        let file: File = File(name: value)
                        return .file(key, file)
                    }
                }
                return .null
            }
        }

        // MARK: Referenceable

        public class var _modelName: String {
            return String(describing: Mirror(reflecting: self).subjectType).components(separatedBy: ".").first!.lowercased()
        }

        public class var _version: String {
            return "v1"
        }

        public static var _path: String {
            return "\(self._version)/\(self._modelName)"
        }

        // MARK: Initialize

        public override init() {
            self.localTimestamp = Date()
        }

        convenience required public init?(snapshot: FIRDataSnapshot) {
            self.init()
            _setSnapshot(snapshot)
        }

        convenience required public init?(id: String) {
            self.init()
            self._id = id
        }

        fileprivate var tmpID: String = UUID().uuidString
        fileprivate var _id: String?

        public var id: String {
            if let id: String = self.snapshot?.key { return id }
            if let id: String = self._id { return id }
            return tmpID
        }

        /// Upload tasks
        public var uploadTasks: [String: FIRStorageUploadTask] = [:]

        public var snapshot: FIRDataSnapshot? {
            didSet {
                if let snapshot: FIRDataSnapshot = snapshot {
                    self.hasObserve = true
                    guard let snapshot: [String: Any] = snapshot.value as? [String: Any] else { return }
                    self.serverCreatedAtTimestamp = value["_createdAt"] as? Double
                    self.serverUpdatedAtTimestamp = value["_updatedAt"] as? Double
                    Mirror(reflecting: self).children.forEach { (key, value) in
                        if let key: String = key {
                            if !self.ignore.contains(key) {
                                if let _: Any = self.decode(key, value: snapshot[key]) {
                                    self.addObserver(self, forKeyPath: key, options: [.new, .old], context: nil)
                                    return
                                }
                                let mirror: Mirror = Mirror(reflecting: value)
                                switch ValueType.from(key: key, mirror: mirror, with: snapshot) {
                                case .string(let key, let value): self.setValue(value, forKey: key)
                                case .int(let key, let value): self.setValue(value, forKey: key)
                                case .float(let key, let value): self.setValue(value, forKey: key)
                                case .double(let key, let value): self.setValue(value, forKey: key)
                                case .bool(let key, let value): self.setValue(value, forKey: key)
                                case .url(let key, _, let value): self.setValue(value, forKey: key)
                                case .date(let key, _, let value): self.setValue(value, forKey: key)
                                case .array(let key, let value): self.setValue(value, forKey: key)
                                case .relation(let key, _, let value): self.setValue(value, forKey: key)
                                case .file(let key, let file):
                                    file.parent = self
                                    file.keyPath = key
                                    self.setValue(file, forKey: key)
                                case .object(let key, let value): self.setValue(value, forKey: key)
                                case .null: break
                                }

                                self.addObserver(self, forKeyPath: key, options: [.new, .old], context: nil)
                            }
                        }
                    }
                }
            }
        }

        fileprivate func _setSnapshot(_ snapshot: FIRDataSnapshot) {
            self.snapshot = snapshot
        }

        /**
         The date when this object was created
         */
        public var createdAt: Date {
            if let serverTimestamp: Double = self.serverCreatedAtTimestamp {
                let timestamp: TimeInterval = TimeInterval(serverTimestamp / 1000)
                return Date(timeIntervalSince1970: timestamp)
            }
            return self.localTimestamp
        }

        /**
         The date when this object was updated
         */
        public var updatedAt: Date {
            if let serverTimestamp: Double = self.serverCreatedAtTimestamp {
                let timestamp: TimeInterval = TimeInterval(serverTimestamp / 1000)
                return Date(timeIntervalSince1970: timestamp)
            }
            return self.localTimestamp
        }

        fileprivate var localTimestamp: Date

        fileprivate var serverCreatedAtTimestamp: Double?

        fileprivate var serverUpdatedAtTimestamp: Double?

        // MARK: Ignore

        public var ignore: [String] {
            return []
        }

        fileprivate var hasObserve: Bool = false

        public var value: [String: Any] {
            let mirror = Mirror(reflecting: self)
            var object: [String: Any] = [:]
            mirror.children.forEach { (key, value) in
                if let key: String = key {
                    if !self.ignore.contains(key) {
                        if let newValue: Any = self.encode(key, value: value) {
                            object[key] = newValue
                            return
                        }

                        switch ValueType.from(key: key, value: value) {
                        case .string(let key, let value): object[key] = value
                        case .double(let key, let value): object[key] = value
                        case .int(let key, let value): object[key] = value
                        case .float(let key, let value): object[key] = value
                        case .bool(let key, let value): object[key] = value
                        case .url(let key, let value, _): object[key] = value
                        case .date(let key, let value, _): object[key] = value
                        case .array(let key, let value): object[key] = value
                        case .relation(let key, let value, _): object[key] = value
                        case .file(let key, let value):
                            value.parent = self
                            value.keyPath = key
                        case .object(let key, let value): object[key] = value
                        case .null: break
                        }

                    }
                }
            }
            return object
        }

        // MARK: - Encode, Decode

        /// Model -> Firebase
        public func encode(_ key: String, value: Any?) -> Any? {
            return nil
        }

        /// Snapshot -> Model
        public func decode(_ key: String, value: Any?) -> Any? {
            return nil
        }

        // MARK: - Save

        public func save() {
            self.save(nil)
        }

        /**
         Save the new Object to Firebase. Save will fail in the off-line.
         - parameter completion: If successful reference will return. An error will return if it fails.
         */
        public func save(_ completion: ((FIRDatabaseReference?, Error?) -> Void)?) {

            if self.id == self.tmpID || self.id == self._id {

                var value: [String: Any] = self.value

                let timestamp: AnyObject = FIRServerValue.timestamp() as AnyObject

                value["_createdAt"] = timestamp
                value["_updatedAt"] = timestamp

                var ref: FIRDatabaseReference
                if let id: String = self._id {
                    ref = type(of: self).databaseRef.child(id)
                } else {
                    ref = type(of: self).databaseRef.childByAutoId()
                }

                ref.runTransactionBlock({ (data) -> FIRTransactionResult in

                    if data.value != nil {
                        data.value = value
                        return .success(withValue: data)
                    }

                    return .success(withValue: data)

                }, andCompletionBlock: { (error, committed, snapshot) in

                    type(of: self).databaseRef.child(ref.key).observeSingleEvent(of: .value, with: { (snapshot) in
                        self.snapshot = snapshot

                        // File save
                        self.saveFiles(block: { (error) in
                            completion?(ref, error as Error?)
                        })

                    })

                }, withLocalEvents: false)

            } else {
                let error: ObjectError = ObjectError(kind: .invalidId, description: "It has been saved with an invalid ID.")
                completion?(nil, error)
            }
        }

        var timeout: Float = 20
        let uploadQueue: DispatchQueue = DispatchQueue(label: "salada.upload.queue")

        private func saveFiles(block: ((Error?) -> Void)?) {

            DispatchQueue.global(qos: .default).async {
                let group: DispatchGroup = DispatchGroup()
                var uploadTasks: [FIRStorageUploadTask] = []
                var hasError: Error? = nil
                let workItem: DispatchWorkItem = DispatchWorkItem {
                    for (key, value) in Mirror(reflecting: self).children {

                        guard let key: String = key else {
                            break
                        }

                        if self.ignore.contains(key) {
                            break
                        }

                        let mirror: Mirror = Mirror(reflecting: value)
                        let subjectType: Any.Type = mirror.subjectType
                        if subjectType == File?.self || subjectType == File.self {
                            if let file: File = value as? File {
                                group.enter()
                                if let task: FIRStorageUploadTask = file.save(key, completion: { (meta, error) in
                                    if let error: Error = error {
                                        hasError = error
                                        uploadTasks.forEach({ (task) in
                                            task.cancel()
                                        })
                                        group.leave()
                                        return
                                    }
                                    group.leave()
                                }) {
                                    uploadTasks.append(task)
                                }
                            }
                        }
                    }
                }

                self.uploadQueue.async(group: group, execute: workItem)
                group.notify(queue: DispatchQueue.main, execute: {
                    block?(hasError)
                })
                switch group.wait(timeout: .now() + Double(Int64(4 * Double(NSEC_PER_SEC)))) {
                case .success: break
                case .timedOut:
                    uploadTasks.forEach({ (task) in
                        task.cancel()
                    })
                    let error: ObjectError = ObjectError(kind: .timeout, description: "Save the file timeout.")
                    block?(error)
                }
            }
        }

        // MARK: - Transaction

        /**
         Set new value. Save will fail in the off-line.
         - parameter key:
         - parameter value:
         - parameter completion: If successful reference will return. An error will return if it fails.
         */

        private var transactionBlock: ((FIRDatabaseReference?, Error?) -> Void)?

        public func transaction(key: String, value: Any, completion: ((FIRDatabaseReference?, Error?) -> Void)?) {

            self.transactionBlock = completion
            self.setValue(value, forKey: key)

        }

        // MARK: - Delete

        open func remove() {
            let id: String = self.id
            type(of: self).databaseRef.child(id).removeValue()
        }

        // MARK: - KVO

        override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

            guard let keyPath: String = keyPath else {
                super.observeValue(forKeyPath: nil, of: object, change: change, context: context)
                return
            }

            guard let object: NSObject = object as? NSObject else {
                super.observeValue(forKeyPath: keyPath, of: nil, change: change, context: context)
                return
            }

            let keys: [String] = Mirror(reflecting: self).children.flatMap({ return $0.label })
            if keys.contains(keyPath) {

                if let value: Any = object.value(forKey: keyPath) as Any? {
                    if let _: File = value as? File {
                        if let change: [NSKeyValueChangeKey: Any] = change as [NSKeyValueChangeKey: Any]? {
                            let new: File = change[.newKey] as! File
                            if let old: File = change[.oldKey] as? File {
                                if old.name != new.name {
                                    new.parent = self
                                    new.keyPath = keyPath
                                    old.parent = self
                                    old.keyPath = keyPath
                                    _ = new.save(keyPath, completion: { (meta, error) in
                                        old.remove()
                                    })
                                }
                            } else {
                                new.parent = self
                                _ = new.save(keyPath)
                            }
                        }
                    } else if let _: Set<String> = value as? Set<String> {

                        if let change: [NSKeyValueChangeKey: Any] = change as [NSKeyValueChangeKey: Any]? {

                            let new: Set<String> = change[.newKey] as! Set<String>
                            let old: Set<String> = change[.oldKey] as! Set<String>

                            // Added
                            new.subtracting(old).forEach({ (id) in
                                updateValue(keyPath, child: id, value: true)
                            })

                            // Remove
                            old.subtracting(new).forEach({ (id) in
                                updateValue(keyPath, child: id, value: nil)
                            })

                        }
                    } else if let values: [String] = value as? [String] {
                        if values.isEmpty { return }
                        updateValue(keyPath, child: nil, value: value)
                    } else if let value: String = value as? String {
                        updateValue(keyPath, child: nil, value: value)
                    } else {
                        updateValue(keyPath, child: nil, value: value)
                    }
                }
            } else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        }

        // update value & update timestamp
        // Value will be deleted if the nil.
        private func updateValue(_ keyPath: String, child: String?, value: Any?) {
            let reference: FIRDatabaseReference = type(of: self).databaseRef.child(self.id)
            let timestamp: AnyObject = FIRServerValue.timestamp() as AnyObject

            if let value: Any = value {
                var path: String = keyPath
                if let child: String = child {
                    path = "\(keyPath)/\(child)"
                }
                //reference.updateChildValues([path: value, "_updatedAt": timestamp])
                reference.updateChildValues([path: value, "_updatedAt": timestamp], withCompletionBlock: { (error, ref) in
                    self.transactionBlock?(ref, error)
                    self.transactionBlock = nil
                })
            } else {
                if let childKey: String = child {
                    reference.child(keyPath).child(childKey).removeValue()
                }
            }
        }
        
        // MARK: - deinit
        
        deinit {
            if self.hasObserve {
                Mirror(reflecting: self).children.forEach { (key, value) in
                    if let key: String = key {
                        if !self.ignore.contains(key) {
                            self.removeObserver(self, forKeyPath: key)
                        }
                    }
                }
            }
        }

        // MARK: -

        override open var description: String {
            return "Salada.Object"
        }

    }
    
}

extension Salada.Object {
    open override var hashValue: Int {
        return self.id.hash
    }
}

func == (lhs: Salada.Object, rhs: Salada.Object) -> Bool {
    return lhs.id == rhs.id
}
