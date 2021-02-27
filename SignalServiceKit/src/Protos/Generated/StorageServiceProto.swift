//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum StorageServiceProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - StorageServiceProtoStorageItem

public struct StorageServiceProtoStorageItem: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoStorageItemBuilder

    public static func builder(key: Data, value: Data) -> StorageServiceProtoStorageItemBuilder {
        return StorageServiceProtoStorageItemBuilder(key: key, value: value)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageItemBuilder {
        var builder = StorageServiceProtoStorageItemBuilder(key: key, value: value)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoStorageItemBuilder {

        private var proto = StorageServiceProtos_StorageItem()

        fileprivate init() {}

        fileprivate init(key: Data, value: Data) {

            setKey(key)
            setValue(value)
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.key = valueParam
        }

        public mutating func setKey(_ valueParam: Data) {
            proto.key = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setValue(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.value = valueParam
        }

        public mutating func setValue(_ valueParam: Data) {
            proto.value = valueParam
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoStorageItem {
            return try StorageServiceProtoStorageItem(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageItem(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageItem

    public let key: Data

    public let value: Data

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_StorageItem,
                 key: Data,
                 value: Data) {
        self.proto = proto
        self.key = key
        self.value = value
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_StorageItem(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_StorageItem) throws {
        let key = proto.key

        let value = proto.value

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageItem -

        // MARK: - End Validation Logic for StorageServiceProtoStorageItem -

        self.init(proto: proto,
                  key: key,
                  value: value)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageItem {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageItem.StorageServiceProtoStorageItemBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStorageItem? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageItems

public struct StorageServiceProtoStorageItems: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoStorageItemsBuilder

    public static func builder() -> StorageServiceProtoStorageItemsBuilder {
        return StorageServiceProtoStorageItemsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageItemsBuilder {
        var builder = StorageServiceProtoStorageItemsBuilder()
        builder.setItems(items)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoStorageItemsBuilder {

        private var proto = StorageServiceProtos_StorageItems()

        fileprivate init() {}

        public mutating func addItems(_ valueParam: StorageServiceProtoStorageItem) {
            proto.items.append(valueParam.proto)
        }

        public mutating func setItems(_ wrappedItems: [StorageServiceProtoStorageItem]) {
            proto.items = wrappedItems.map { $0.proto }
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoStorageItems {
            return try StorageServiceProtoStorageItems(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageItems(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageItems

    public let items: [StorageServiceProtoStorageItem]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_StorageItems,
                 items: [StorageServiceProtoStorageItem]) {
        self.proto = proto
        self.items = items
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_StorageItems(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_StorageItems) throws {
        var items: [StorageServiceProtoStorageItem] = []
        items = try proto.items.map { try StorageServiceProtoStorageItem($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageItems -

        // MARK: - End Validation Logic for StorageServiceProtoStorageItems -

        self.init(proto: proto,
                  items: items)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageItems {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageItems.StorageServiceProtoStorageItemsBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStorageItems? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageManifest

public struct StorageServiceProtoStorageManifest: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoStorageManifestBuilder

    public static func builder(version: UInt64, value: Data) -> StorageServiceProtoStorageManifestBuilder {
        return StorageServiceProtoStorageManifestBuilder(version: version, value: value)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageManifestBuilder {
        var builder = StorageServiceProtoStorageManifestBuilder(version: version, value: value)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoStorageManifestBuilder {

        private var proto = StorageServiceProtos_StorageManifest()

        fileprivate init() {}

        fileprivate init(version: UInt64, value: Data) {

            setVersion(version)
            setValue(value)
        }

        public mutating func setVersion(_ valueParam: UInt64) {
            proto.version = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setValue(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.value = valueParam
        }

        public mutating func setValue(_ valueParam: Data) {
            proto.value = valueParam
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoStorageManifest {
            return try StorageServiceProtoStorageManifest(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageManifest(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageManifest

    public let version: UInt64

    public let value: Data

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_StorageManifest,
                 version: UInt64,
                 value: Data) {
        self.proto = proto
        self.version = version
        self.value = value
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_StorageManifest(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_StorageManifest) throws {
        let version = proto.version

        let value = proto.value

        // MARK: - Begin Validation Logic for StorageServiceProtoStorageManifest -

        // MARK: - End Validation Logic for StorageServiceProtoStorageManifest -

        self.init(proto: proto,
                  version: version,
                  value: value)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageManifest {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageManifest.StorageServiceProtoStorageManifestBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStorageManifest? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoReadOperation

public struct StorageServiceProtoReadOperation: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoReadOperationBuilder

    public static func builder() -> StorageServiceProtoReadOperationBuilder {
        return StorageServiceProtoReadOperationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoReadOperationBuilder {
        var builder = StorageServiceProtoReadOperationBuilder()
        builder.setReadKey(readKey)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoReadOperationBuilder {

        private var proto = StorageServiceProtos_ReadOperation()

        fileprivate init() {}

        public mutating func addReadKey(_ valueParam: Data) {
            proto.readKey.append(valueParam)
        }

        public mutating func setReadKey(_ wrappedItems: [Data]) {
            proto.readKey = wrappedItems
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoReadOperation {
            return try StorageServiceProtoReadOperation(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoReadOperation(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ReadOperation

    public var readKey: [Data] {
        return proto.readKey
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_ReadOperation) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_ReadOperation(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_ReadOperation) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoReadOperation -

        // MARK: - End Validation Logic for StorageServiceProtoReadOperation -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoReadOperation {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoReadOperation.StorageServiceProtoReadOperationBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoReadOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoWriteOperation

public struct StorageServiceProtoWriteOperation: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoWriteOperationBuilder

    public static func builder() -> StorageServiceProtoWriteOperationBuilder {
        return StorageServiceProtoWriteOperationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoWriteOperationBuilder {
        var builder = StorageServiceProtoWriteOperationBuilder()
        if let _value = manifest {
            builder.setManifest(_value)
        }
        builder.setInsertItem(insertItem)
        builder.setDeleteKey(deleteKey)
        if hasDeleteAll {
            builder.setDeleteAll(deleteAll)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoWriteOperationBuilder {

        private var proto = StorageServiceProtos_WriteOperation()

        fileprivate init() {}

        @available(swift, obsoleted: 1.0)
        public mutating func setManifest(_ valueParam: StorageServiceProtoStorageManifest?) {
            guard let valueParam = valueParam else { return }
            proto.manifest = valueParam.proto
        }

        public mutating func setManifest(_ valueParam: StorageServiceProtoStorageManifest) {
            proto.manifest = valueParam.proto
        }

        public mutating func addInsertItem(_ valueParam: StorageServiceProtoStorageItem) {
            proto.insertItem.append(valueParam.proto)
        }

        public mutating func setInsertItem(_ wrappedItems: [StorageServiceProtoStorageItem]) {
            proto.insertItem = wrappedItems.map { $0.proto }
        }

        public mutating func addDeleteKey(_ valueParam: Data) {
            proto.deleteKey.append(valueParam)
        }

        public mutating func setDeleteKey(_ wrappedItems: [Data]) {
            proto.deleteKey = wrappedItems
        }

        public mutating func setDeleteAll(_ valueParam: Bool) {
            proto.deleteAll = valueParam
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoWriteOperation {
            return try StorageServiceProtoWriteOperation(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoWriteOperation(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_WriteOperation

    public let manifest: StorageServiceProtoStorageManifest?

    public let insertItem: [StorageServiceProtoStorageItem]

    public var deleteKey: [Data] {
        return proto.deleteKey
    }

    public var deleteAll: Bool {
        return proto.deleteAll
    }
    public var hasDeleteAll: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_WriteOperation,
                 manifest: StorageServiceProtoStorageManifest?,
                 insertItem: [StorageServiceProtoStorageItem]) {
        self.proto = proto
        self.manifest = manifest
        self.insertItem = insertItem
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_WriteOperation(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_WriteOperation) throws {
        var manifest: StorageServiceProtoStorageManifest?
        if proto.hasManifest {
            manifest = try StorageServiceProtoStorageManifest(proto.manifest)
        }

        var insertItem: [StorageServiceProtoStorageItem] = []
        insertItem = try proto.insertItem.map { try StorageServiceProtoStorageItem($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoWriteOperation -

        // MARK: - End Validation Logic for StorageServiceProtoWriteOperation -

        self.init(proto: proto,
                  manifest: manifest,
                  insertItem: insertItem)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoWriteOperation {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoWriteOperation.StorageServiceProtoWriteOperationBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoWriteOperation? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoManifestRecordKeyType

public enum StorageServiceProtoManifestRecordKeyType: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case unknown // 0
    case contact // 1
    case groupv1 // 2
    case groupv2 // 3
    case account // 4
    case UNRECOGNIZED(Int)

    public init() {
        self = .unknown
    }

    public init?(rawValue: Int) {
        switch rawValue {
            case 0: self = .unknown
            case 1: self = .contact
            case 2: self = .groupv1
            case 3: self = .groupv2
            case 4: self = .account
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .unknown: return 0
            case .contact: return 1
            case .groupv1: return 2
            case .groupv2: return 3
            case .account: return 4
            case .UNRECOGNIZED(let i): return i
        }
    }
}

private func StorageServiceProtoManifestRecordKeyTypeWrap(_ value: StorageServiceProtos_ManifestRecord.Key.TypeEnum) -> StorageServiceProtoManifestRecordKeyType {
    switch value {
    case .unknown: return .unknown
    case .contact: return .contact
    case .groupv1: return .groupv1
    case .groupv2: return .groupv2
    case .account: return .account
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func StorageServiceProtoManifestRecordKeyTypeUnwrap(_ value: StorageServiceProtoManifestRecordKeyType) -> StorageServiceProtos_ManifestRecord.Key.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .contact: return .contact
    case .groupv1: return .groupv1
    case .groupv2: return .groupv2
    case .account: return .account
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - StorageServiceProtoManifestRecordKey

public struct StorageServiceProtoManifestRecordKey: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoManifestRecordKeyBuilder

    public static func builder(data: Data, type: StorageServiceProtoManifestRecordKeyType) -> StorageServiceProtoManifestRecordKeyBuilder {
        return StorageServiceProtoManifestRecordKeyBuilder(data: data, type: type)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoManifestRecordKeyBuilder {
        var builder = StorageServiceProtoManifestRecordKeyBuilder(data: data, type: type)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoManifestRecordKeyBuilder {

        private var proto = StorageServiceProtos_ManifestRecord.Key()

        fileprivate init() {}

        fileprivate init(data: Data, type: StorageServiceProtoManifestRecordKeyType) {

            setData(data)
            setType(type)
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setData(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.data = valueParam
        }

        public mutating func setData(_ valueParam: Data) {
            proto.data = valueParam
        }

        public mutating func setType(_ valueParam: StorageServiceProtoManifestRecordKeyType) {
            proto.type = StorageServiceProtoManifestRecordKeyTypeUnwrap(valueParam)
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoManifestRecordKey {
            return try StorageServiceProtoManifestRecordKey(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoManifestRecordKey(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ManifestRecord.Key

    public let data: Data

    public let type: StorageServiceProtoManifestRecordKeyType

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_ManifestRecord.Key,
                 data: Data,
                 type: StorageServiceProtoManifestRecordKeyType) {
        self.proto = proto
        self.data = data
        self.type = type
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_ManifestRecord.Key(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_ManifestRecord.Key) throws {
        let data = proto.data

        let type = StorageServiceProtoManifestRecordKeyTypeWrap(proto.type)

        // MARK: - Begin Validation Logic for StorageServiceProtoManifestRecordKey -

        // MARK: - End Validation Logic for StorageServiceProtoManifestRecordKey -

        self.init(proto: proto,
                  data: data,
                  type: type)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoManifestRecordKey {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoManifestRecordKey.StorageServiceProtoManifestRecordKeyBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoManifestRecordKey? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoManifestRecord

public struct StorageServiceProtoManifestRecord: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoManifestRecordBuilder

    public static func builder(version: UInt64) -> StorageServiceProtoManifestRecordBuilder {
        return StorageServiceProtoManifestRecordBuilder(version: version)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoManifestRecordBuilder {
        var builder = StorageServiceProtoManifestRecordBuilder(version: version)
        builder.setKeys(keys)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoManifestRecordBuilder {

        private var proto = StorageServiceProtos_ManifestRecord()

        fileprivate init() {}

        fileprivate init(version: UInt64) {

            setVersion(version)
        }

        public mutating func setVersion(_ valueParam: UInt64) {
            proto.version = valueParam
        }

        public mutating func addKeys(_ valueParam: StorageServiceProtoManifestRecordKey) {
            proto.keys.append(valueParam.proto)
        }

        public mutating func setKeys(_ wrappedItems: [StorageServiceProtoManifestRecordKey]) {
            proto.keys = wrappedItems.map { $0.proto }
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoManifestRecord {
            return try StorageServiceProtoManifestRecord(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoManifestRecord(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ManifestRecord

    public let version: UInt64

    public let keys: [StorageServiceProtoManifestRecordKey]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_ManifestRecord,
                 version: UInt64,
                 keys: [StorageServiceProtoManifestRecordKey]) {
        self.proto = proto
        self.version = version
        self.keys = keys
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_ManifestRecord(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_ManifestRecord) throws {
        let version = proto.version

        var keys: [StorageServiceProtoManifestRecordKey] = []
        keys = try proto.keys.map { try StorageServiceProtoManifestRecordKey($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoManifestRecord -

        // MARK: - End Validation Logic for StorageServiceProtoManifestRecord -

        self.init(proto: proto,
                  version: version,
                  keys: keys)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoManifestRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoManifestRecord.StorageServiceProtoManifestRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoManifestRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoStorageRecordOneOfRecord

public enum StorageServiceProtoStorageRecordOneOfRecord {
    case contact(StorageServiceProtoContactRecord)
    case groupV1(StorageServiceProtoGroupV1Record)
    case groupV2(StorageServiceProtoGroupV2Record)
    case account(StorageServiceProtoAccountRecord)
}

private func StorageServiceProtoStorageRecordOneOfRecordWrap(_ value: StorageServiceProtos_StorageRecord.OneOf_Record) throws -> StorageServiceProtoStorageRecordOneOfRecord {
    switch value {
    case .contact(let value): return .contact(try StorageServiceProtoContactRecord(value))
    case .groupV1(let value): return .groupV1(try StorageServiceProtoGroupV1Record(value))
    case .groupV2(let value): return .groupV2(try StorageServiceProtoGroupV2Record(value))
    case .account(let value): return .account(try StorageServiceProtoAccountRecord(value))
    }
}

private func StorageServiceProtoStorageRecordOneOfRecordUnwrap(_ value: StorageServiceProtoStorageRecordOneOfRecord) -> StorageServiceProtos_StorageRecord.OneOf_Record {
    switch value {
    case .contact(let value): return .contact(value.proto)
    case .groupV1(let value): return .groupV1(value.proto)
    case .groupV2(let value): return .groupV2(value.proto)
    case .account(let value): return .account(value.proto)
    }
}

// MARK: - StorageServiceProtoStorageRecord

public struct StorageServiceProtoStorageRecord: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoStorageRecordBuilder

    public static func builder() -> StorageServiceProtoStorageRecordBuilder {
        return StorageServiceProtoStorageRecordBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoStorageRecordBuilder {
        var builder = StorageServiceProtoStorageRecordBuilder()
        if let _value = record {
            builder.setRecord(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoStorageRecordBuilder {

        private var proto = StorageServiceProtos_StorageRecord()

        fileprivate init() {}

        @available(swift, obsoleted: 1.0)
        public mutating func setRecord(_ valueParam: StorageServiceProtoStorageRecordOneOfRecord?) {
            guard let valueParam = valueParam else { return }
            proto.record = StorageServiceProtoStorageRecordOneOfRecordUnwrap(valueParam)
        }

        public mutating func setRecord(_ valueParam: StorageServiceProtoStorageRecordOneOfRecord) {
            proto.record = StorageServiceProtoStorageRecordOneOfRecordUnwrap(valueParam)
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoStorageRecord {
            return try StorageServiceProtoStorageRecord(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoStorageRecord(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_StorageRecord

    public var record: StorageServiceProtoStorageRecordOneOfRecord? {
        guard hasRecord else {
            return nil
        }
        guard let record = proto.record else {
            owsFailDebug("record was unexpectedly nil")
            return nil
        }
        guard let unwrappedRecord = try? StorageServiceProtoStorageRecordOneOfRecordWrap(record) else {
            owsFailDebug("failed to unwrap record")
            return nil
        }
        return unwrappedRecord
    }
    public var hasRecord: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_StorageRecord) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_StorageRecord(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_StorageRecord) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoStorageRecord -

        // MARK: - End Validation Logic for StorageServiceProtoStorageRecord -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoStorageRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoStorageRecord.StorageServiceProtoStorageRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoStorageRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoContactRecordIdentityState

public enum StorageServiceProtoContactRecordIdentityState: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case `default` // 0
    case verified // 1
    case unverified // 2
    case UNRECOGNIZED(Int)

    public init() {
        self = .`default`
    }

    public init?(rawValue: Int) {
        switch rawValue {
            case 0: self = .`default`
            case 1: self = .verified
            case 2: self = .unverified
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .`default`: return 0
            case .verified: return 1
            case .unverified: return 2
            case .UNRECOGNIZED(let i): return i
        }
    }
}

private func StorageServiceProtoContactRecordIdentityStateWrap(_ value: StorageServiceProtos_ContactRecord.IdentityState) -> StorageServiceProtoContactRecordIdentityState {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func StorageServiceProtoContactRecordIdentityStateUnwrap(_ value: StorageServiceProtoContactRecordIdentityState) -> StorageServiceProtos_ContactRecord.IdentityState {
    switch value {
    case .default: return .default
    case .verified: return .verified
    case .unverified: return .unverified
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - StorageServiceProtoContactRecord

public struct StorageServiceProtoContactRecord: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoContactRecordBuilder

    public static func builder() -> StorageServiceProtoContactRecordBuilder {
        return StorageServiceProtoContactRecordBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoContactRecordBuilder {
        var builder = StorageServiceProtoContactRecordBuilder()
        if let _value = serviceUuid {
            builder.setServiceUuid(_value)
        }
        if let _value = serviceE164 {
            builder.setServiceE164(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = identityKey {
            builder.setIdentityKey(_value)
        }
        if let _value = identityState {
            builder.setIdentityState(_value)
        }
        if let _value = givenName {
            builder.setGivenName(_value)
        }
        if let _value = familyName {
            builder.setFamilyName(_value)
        }
        if let _value = username {
            builder.setUsername(_value)
        }
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        if hasWhitelisted {
            builder.setWhitelisted(whitelisted)
        }
        if hasArchived {
            builder.setArchived(archived)
        }
        if hasMarkedUnread {
            builder.setMarkedUnread(markedUnread)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoContactRecordBuilder {

        private var proto = StorageServiceProtos_ContactRecord()

        fileprivate init() {}

        @available(swift, obsoleted: 1.0)
        public mutating func setServiceUuid(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.serviceUuid = valueParam
        }

        public mutating func setServiceUuid(_ valueParam: String) {
            proto.serviceUuid = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setServiceE164(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.serviceE164 = valueParam
        }

        public mutating func setServiceE164(_ valueParam: String) {
            proto.serviceE164 = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setProfileKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.profileKey = valueParam
        }

        public mutating func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setIdentityKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.identityKey = valueParam
        }

        public mutating func setIdentityKey(_ valueParam: Data) {
            proto.identityKey = valueParam
        }

        public mutating func setIdentityState(_ valueParam: StorageServiceProtoContactRecordIdentityState) {
            proto.identityState = StorageServiceProtoContactRecordIdentityStateUnwrap(valueParam)
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setGivenName(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.givenName = valueParam
        }

        public mutating func setGivenName(_ valueParam: String) {
            proto.givenName = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setFamilyName(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.familyName = valueParam
        }

        public mutating func setFamilyName(_ valueParam: String) {
            proto.familyName = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setUsername(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.username = valueParam
        }

        public mutating func setUsername(_ valueParam: String) {
            proto.username = valueParam
        }

        public mutating func setBlocked(_ valueParam: Bool) {
            proto.blocked = valueParam
        }

        public mutating func setWhitelisted(_ valueParam: Bool) {
            proto.whitelisted = valueParam
        }

        public mutating func setArchived(_ valueParam: Bool) {
            proto.archived = valueParam
        }

        public mutating func setMarkedUnread(_ valueParam: Bool) {
            proto.markedUnread = valueParam
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoContactRecord {
            return try StorageServiceProtoContactRecord(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoContactRecord(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_ContactRecord

    public var serviceUuid: String? {
        guard hasServiceUuid else {
            return nil
        }
        return proto.serviceUuid
    }
    public var hasServiceUuid: Bool {
        return !proto.serviceUuid.isEmpty
    }

    public var serviceE164: String? {
        guard hasServiceE164 else {
            return nil
        }
        return proto.serviceE164
    }
    public var hasServiceE164: Bool {
        return !proto.serviceE164.isEmpty
    }

    public var profileKey: Data? {
        guard hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    public var hasProfileKey: Bool {
        return !proto.profileKey.isEmpty
    }

    public var identityKey: Data? {
        guard hasIdentityKey else {
            return nil
        }
        return proto.identityKey
    }
    public var hasIdentityKey: Bool {
        return !proto.identityKey.isEmpty
    }

    public var identityState: StorageServiceProtoContactRecordIdentityState? {
        guard hasIdentityState else {
            return nil
        }
        return StorageServiceProtoContactRecordIdentityStateWrap(proto.identityState)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedIdentityState: StorageServiceProtoContactRecordIdentityState {
        if !hasIdentityState {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: ContactRecord.identityState.")
        }
        return StorageServiceProtoContactRecordIdentityStateWrap(proto.identityState)
    }
    public var hasIdentityState: Bool {
        return true
    }

    public var givenName: String? {
        guard hasGivenName else {
            return nil
        }
        return proto.givenName
    }
    public var hasGivenName: Bool {
        return !proto.givenName.isEmpty
    }

    public var familyName: String? {
        guard hasFamilyName else {
            return nil
        }
        return proto.familyName
    }
    public var hasFamilyName: Bool {
        return !proto.familyName.isEmpty
    }

    public var username: String? {
        guard hasUsername else {
            return nil
        }
        return proto.username
    }
    public var hasUsername: Bool {
        return !proto.username.isEmpty
    }

    public var blocked: Bool {
        return proto.blocked
    }
    public var hasBlocked: Bool {
        return true
    }

    public var whitelisted: Bool {
        return proto.whitelisted
    }
    public var hasWhitelisted: Bool {
        return true
    }

    public var archived: Bool {
        return proto.archived
    }
    public var hasArchived: Bool {
        return true
    }

    public var markedUnread: Bool {
        return proto.markedUnread
    }
    public var hasMarkedUnread: Bool {
        return true
    }

    public var hasValidService: Bool {
        return serviceAddress != nil
    }
    public let serviceAddress: SignalServiceAddress?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_ContactRecord) {
        self.proto = proto

        let hasServiceUuid = !proto.serviceUuid.isEmpty
        let hasServiceE164 = !proto.serviceE164.isEmpty
        let serviceUuid: String? = proto.serviceUuid
        let serviceE164: String? = proto.serviceE164
        self.serviceAddress = {
            guard hasServiceE164 || hasServiceUuid else { return nil }

            let uuidString: String? = {
                guard hasServiceUuid else { return nil }

                guard let serviceUuid = serviceUuid else {
                    owsFailDebug("serviceUuid was unexpectedly nil")
                    return nil
                }

                return serviceUuid
            }()

            let phoneNumber: String? = {
                guard hasServiceE164 else {
                    return nil
                }

                guard let serviceE164 = serviceE164 else {
                    owsFailDebug("serviceE164 was unexpectedly nil")
                    return nil
                }

                guard !serviceE164.isEmpty else {
                    owsFailDebug("serviceE164 was unexpectedly empty")
                    return nil
                }

                return serviceE164
            }()

            let address = SignalServiceAddress(uuidString: uuidString, phoneNumber: phoneNumber, trustLevel: .high)
            guard address.isValid else {
                owsFailDebug("address was unexpectedly invalid")
                return nil
            }

            return address
        }()
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_ContactRecord(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_ContactRecord) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoContactRecord -

        // MARK: - End Validation Logic for StorageServiceProtoContactRecord -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoContactRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoContactRecord.StorageServiceProtoContactRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoContactRecord? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoGroupV1Record

public struct StorageServiceProtoGroupV1Record: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoGroupV1RecordBuilder

    public static func builder(id: Data) -> StorageServiceProtoGroupV1RecordBuilder {
        return StorageServiceProtoGroupV1RecordBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoGroupV1RecordBuilder {
        var builder = StorageServiceProtoGroupV1RecordBuilder(id: id)
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        if hasWhitelisted {
            builder.setWhitelisted(whitelisted)
        }
        if hasArchived {
            builder.setArchived(archived)
        }
        if hasMarkedUnread {
            builder.setMarkedUnread(markedUnread)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoGroupV1RecordBuilder {

        private var proto = StorageServiceProtos_GroupV1Record()

        fileprivate init() {}

        fileprivate init(id: Data) {

            setId(id)
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setId(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.id = valueParam
        }

        public mutating func setId(_ valueParam: Data) {
            proto.id = valueParam
        }

        public mutating func setBlocked(_ valueParam: Bool) {
            proto.blocked = valueParam
        }

        public mutating func setWhitelisted(_ valueParam: Bool) {
            proto.whitelisted = valueParam
        }

        public mutating func setArchived(_ valueParam: Bool) {
            proto.archived = valueParam
        }

        public mutating func setMarkedUnread(_ valueParam: Bool) {
            proto.markedUnread = valueParam
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoGroupV1Record {
            return try StorageServiceProtoGroupV1Record(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoGroupV1Record(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_GroupV1Record

    public let id: Data

    public var blocked: Bool {
        return proto.blocked
    }
    public var hasBlocked: Bool {
        return true
    }

    public var whitelisted: Bool {
        return proto.whitelisted
    }
    public var hasWhitelisted: Bool {
        return true
    }

    public var archived: Bool {
        return proto.archived
    }
    public var hasArchived: Bool {
        return true
    }

    public var markedUnread: Bool {
        return proto.markedUnread
    }
    public var hasMarkedUnread: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_GroupV1Record,
                 id: Data) {
        self.proto = proto
        self.id = id
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_GroupV1Record(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_GroupV1Record) throws {
        let id = proto.id

        // MARK: - Begin Validation Logic for StorageServiceProtoGroupV1Record -

        // MARK: - End Validation Logic for StorageServiceProtoGroupV1Record -

        self.init(proto: proto,
                  id: id)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoGroupV1Record {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoGroupV1Record.StorageServiceProtoGroupV1RecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoGroupV1Record? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoGroupV2Record

public struct StorageServiceProtoGroupV2Record: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoGroupV2RecordBuilder

    public static func builder(masterKey: Data) -> StorageServiceProtoGroupV2RecordBuilder {
        return StorageServiceProtoGroupV2RecordBuilder(masterKey: masterKey)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoGroupV2RecordBuilder {
        var builder = StorageServiceProtoGroupV2RecordBuilder(masterKey: masterKey)
        if hasBlocked {
            builder.setBlocked(blocked)
        }
        if hasWhitelisted {
            builder.setWhitelisted(whitelisted)
        }
        if hasArchived {
            builder.setArchived(archived)
        }
        if hasMarkedUnread {
            builder.setMarkedUnread(markedUnread)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoGroupV2RecordBuilder {

        private var proto = StorageServiceProtos_GroupV2Record()

        fileprivate init() {}

        fileprivate init(masterKey: Data) {

            setMasterKey(masterKey)
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setMasterKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.masterKey = valueParam
        }

        public mutating func setMasterKey(_ valueParam: Data) {
            proto.masterKey = valueParam
        }

        public mutating func setBlocked(_ valueParam: Bool) {
            proto.blocked = valueParam
        }

        public mutating func setWhitelisted(_ valueParam: Bool) {
            proto.whitelisted = valueParam
        }

        public mutating func setArchived(_ valueParam: Bool) {
            proto.archived = valueParam
        }

        public mutating func setMarkedUnread(_ valueParam: Bool) {
            proto.markedUnread = valueParam
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoGroupV2Record {
            return try StorageServiceProtoGroupV2Record(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoGroupV2Record(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_GroupV2Record

    public let masterKey: Data

    public var blocked: Bool {
        return proto.blocked
    }
    public var hasBlocked: Bool {
        return true
    }

    public var whitelisted: Bool {
        return proto.whitelisted
    }
    public var hasWhitelisted: Bool {
        return true
    }

    public var archived: Bool {
        return proto.archived
    }
    public var hasArchived: Bool {
        return true
    }

    public var markedUnread: Bool {
        return proto.markedUnread
    }
    public var hasMarkedUnread: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_GroupV2Record,
                 masterKey: Data) {
        self.proto = proto
        self.masterKey = masterKey
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_GroupV2Record(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_GroupV2Record) throws {
        let masterKey = proto.masterKey

        // MARK: - Begin Validation Logic for StorageServiceProtoGroupV2Record -

        // MARK: - End Validation Logic for StorageServiceProtoGroupV2Record -

        self.init(proto: proto,
                  masterKey: masterKey)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoGroupV2Record {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoGroupV2Record.StorageServiceProtoGroupV2RecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoGroupV2Record? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoAccountRecordPinnedConversationContact

public struct StorageServiceProtoAccountRecordPinnedConversationContact: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoAccountRecordPinnedConversationContactBuilder

    public static func builder() -> StorageServiceProtoAccountRecordPinnedConversationContactBuilder {
        return StorageServiceProtoAccountRecordPinnedConversationContactBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoAccountRecordPinnedConversationContactBuilder {
        var builder = StorageServiceProtoAccountRecordPinnedConversationContactBuilder()
        if let _value = uuid {
            builder.setUuid(_value)
        }
        if let _value = e164 {
            builder.setE164(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoAccountRecordPinnedConversationContactBuilder {

        private var proto = StorageServiceProtos_AccountRecord.PinnedConversation.Contact()

        fileprivate init() {}

        @available(swift, obsoleted: 1.0)
        public mutating func setUuid(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.uuid = valueParam
        }

        public mutating func setUuid(_ valueParam: String) {
            proto.uuid = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setE164(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.e164 = valueParam
        }

        public mutating func setE164(_ valueParam: String) {
            proto.e164 = valueParam
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoAccountRecordPinnedConversationContact {
            return try StorageServiceProtoAccountRecordPinnedConversationContact(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoAccountRecordPinnedConversationContact(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_AccountRecord.PinnedConversation.Contact

    public var uuid: String? {
        guard hasUuid else {
            return nil
        }
        return proto.uuid
    }
    public var hasUuid: Bool {
        return !proto.uuid.isEmpty
    }

    public var e164: String? {
        guard hasE164 else {
            return nil
        }
        return proto.e164
    }
    public var hasE164: Bool {
        return !proto.e164.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_AccountRecord.PinnedConversation.Contact) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_AccountRecord.PinnedConversation.Contact(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_AccountRecord.PinnedConversation.Contact) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoAccountRecordPinnedConversationContact -

        // MARK: - End Validation Logic for StorageServiceProtoAccountRecordPinnedConversationContact -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoAccountRecordPinnedConversationContact {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoAccountRecordPinnedConversationContact.StorageServiceProtoAccountRecordPinnedConversationContactBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoAccountRecordPinnedConversationContact? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier

public enum StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier {
    case contact(StorageServiceProtoAccountRecordPinnedConversationContact)
    case legacyGroupID(Data)
    case groupMasterKey(Data)
}

private func StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifierWrap(_ value: StorageServiceProtos_AccountRecord.PinnedConversation.OneOf_Identifier) throws -> StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier {
    switch value {
    case .contact(let value): return .contact(try StorageServiceProtoAccountRecordPinnedConversationContact(value))
    case .legacyGroupID(let value): return .legacyGroupID(value)
    case .groupMasterKey(let value): return .groupMasterKey(value)
    }
}

private func StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifierUnwrap(_ value: StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier) -> StorageServiceProtos_AccountRecord.PinnedConversation.OneOf_Identifier {
    switch value {
    case .contact(let value): return .contact(value.proto)
    case .legacyGroupID(let value): return .legacyGroupID(value)
    case .groupMasterKey(let value): return .groupMasterKey(value)
    }
}

// MARK: - StorageServiceProtoAccountRecordPinnedConversation

public struct StorageServiceProtoAccountRecordPinnedConversation: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoAccountRecordPinnedConversationBuilder

    public static func builder() -> StorageServiceProtoAccountRecordPinnedConversationBuilder {
        return StorageServiceProtoAccountRecordPinnedConversationBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoAccountRecordPinnedConversationBuilder {
        var builder = StorageServiceProtoAccountRecordPinnedConversationBuilder()
        if let _value = identifier {
            builder.setIdentifier(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoAccountRecordPinnedConversationBuilder {

        private var proto = StorageServiceProtos_AccountRecord.PinnedConversation()

        fileprivate init() {}

        @available(swift, obsoleted: 1.0)
        public mutating func setIdentifier(_ valueParam: StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier?) {
            guard let valueParam = valueParam else { return }
            proto.identifier = StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifierUnwrap(valueParam)
        }

        public mutating func setIdentifier(_ valueParam: StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier) {
            proto.identifier = StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifierUnwrap(valueParam)
        }

        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoAccountRecordPinnedConversation {
            return try StorageServiceProtoAccountRecordPinnedConversation(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoAccountRecordPinnedConversation(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_AccountRecord.PinnedConversation

    public var identifier: StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifier? {
        guard hasIdentifier else {
            return nil
        }
        guard let identifier = proto.identifier else {
            owsFailDebug("identifier was unexpectedly nil")
            return nil
        }
        guard let unwrappedIdentifier = try? StorageServiceProtoAccountRecordPinnedConversationOneOfIdentifierWrap(identifier) else {
            owsFailDebug("failed to unwrap identifier")
            return nil
        }
        return unwrappedIdentifier
    }
    public var hasIdentifier: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_AccountRecord.PinnedConversation) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_AccountRecord.PinnedConversation(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_AccountRecord.PinnedConversation) throws {
        // MARK: - Begin Validation Logic for StorageServiceProtoAccountRecordPinnedConversation -

        // MARK: - End Validation Logic for StorageServiceProtoAccountRecordPinnedConversation -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoAccountRecordPinnedConversation {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoAccountRecordPinnedConversation.StorageServiceProtoAccountRecordPinnedConversationBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoAccountRecordPinnedConversation? {
        return try! self.build()
    }
}

#endif

// MARK: - StorageServiceProtoAccountRecordPhoneNumberSharingMode

public enum StorageServiceProtoAccountRecordPhoneNumberSharingMode: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case everybody // 0
    case contactsOnly // 1
    case nobody // 2
    case UNRECOGNIZED(Int)

    public init() {
        self = .everybody
    }

    public init?(rawValue: Int) {
        switch rawValue {
            case 0: self = .everybody
            case 1: self = .contactsOnly
            case 2: self = .nobody
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .everybody: return 0
            case .contactsOnly: return 1
            case .nobody: return 2
            case .UNRECOGNIZED(let i): return i
        }
    }
}

private func StorageServiceProtoAccountRecordPhoneNumberSharingModeWrap(_ value: StorageServiceProtos_AccountRecord.PhoneNumberSharingMode) -> StorageServiceProtoAccountRecordPhoneNumberSharingMode {
    switch value {
    case .everybody: return .everybody
    case .contactsOnly: return .contactsOnly
    case .nobody: return .nobody
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func StorageServiceProtoAccountRecordPhoneNumberSharingModeUnwrap(_ value: StorageServiceProtoAccountRecordPhoneNumberSharingMode) -> StorageServiceProtos_AccountRecord.PhoneNumberSharingMode {
    switch value {
    case .everybody: return .everybody
    case .contactsOnly: return .contactsOnly
    case .nobody: return .nobody
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - StorageServiceProtoAccountRecord

public struct StorageServiceProtoAccountRecord: Codable, CustomDebugStringConvertible {

    // MARK: - StorageServiceProtoAccountRecordBuilder

    public static func builder() -> StorageServiceProtoAccountRecordBuilder {
        return StorageServiceProtoAccountRecordBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> StorageServiceProtoAccountRecordBuilder {
        var builder = StorageServiceProtoAccountRecordBuilder()
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = givenName {
            builder.setGivenName(_value)
        }
        if let _value = familyName {
            builder.setFamilyName(_value)
        }
        if let _value = avatarURL {
            builder.setAvatarURL(_value)
        }
        if hasNoteToSelfArchived {
            builder.setNoteToSelfArchived(noteToSelfArchived)
        }
        if hasReadReceipts {
            builder.setReadReceipts(readReceipts)
        }
        if hasSealedSenderIndicators {
            builder.setSealedSenderIndicators(sealedSenderIndicators)
        }
        if hasTypingIndicators {
            builder.setTypingIndicators(typingIndicators)
        }
        if hasProxiedLinkPreviews {
            builder.setProxiedLinkPreviews(proxiedLinkPreviews)
        }
        if hasNoteToSelfMarkedUnread {
            builder.setNoteToSelfMarkedUnread(noteToSelfMarkedUnread)
        }
        if hasLinkPreviews {
            builder.setLinkPreviews(linkPreviews)
        }
        if let _value = phoneNumberSharingMode {
            builder.setPhoneNumberSharingMode(_value)
        }
        if hasNotDiscoverableByPhoneNumber {
            builder.setNotDiscoverableByPhoneNumber(notDiscoverableByPhoneNumber)
        }
        builder.setPinnedConversations(pinnedConversations)
        if hasPreferContactAvatars {
            builder.setPreferContactAvatars(preferContactAvatars)
        }

        if hasHideGroupChatAvatars {
            builder.setHideGroupChatAvatars(hideGroupChatAvatars)
        }

        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }

    public struct StorageServiceProtoAccountRecordBuilder {

        private var proto = StorageServiceProtos_AccountRecord()

        fileprivate init() {}

        @available(swift, obsoleted: 1.0)
        public mutating func setProfileKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.profileKey = valueParam
        }

        public mutating func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setGivenName(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.givenName = valueParam
        }

        public mutating func setGivenName(_ valueParam: String) {
            proto.givenName = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setFamilyName(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.familyName = valueParam
        }

        public mutating func setFamilyName(_ valueParam: String) {
            proto.familyName = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public mutating func setAvatarURL(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.avatarURL = valueParam
        }

        public mutating func setAvatarURL(_ valueParam: String) {
            proto.avatarURL = valueParam
        }

        public mutating func setNoteToSelfArchived(_ valueParam: Bool) {
            proto.noteToSelfArchived = valueParam
        }

        public mutating func setReadReceipts(_ valueParam: Bool) {
            proto.readReceipts = valueParam
        }

        public mutating func setSealedSenderIndicators(_ valueParam: Bool) {
            proto.sealedSenderIndicators = valueParam
        }

        public mutating func setTypingIndicators(_ valueParam: Bool) {
            proto.typingIndicators = valueParam
        }

        public mutating func setProxiedLinkPreviews(_ valueParam: Bool) {
            proto.proxiedLinkPreviews = valueParam
        }

        public mutating func setNoteToSelfMarkedUnread(_ valueParam: Bool) {
            proto.noteToSelfMarkedUnread = valueParam
        }

        public mutating func setLinkPreviews(_ valueParam: Bool) {
            proto.linkPreviews = valueParam
        }

        public mutating func setPhoneNumberSharingMode(_ valueParam: StorageServiceProtoAccountRecordPhoneNumberSharingMode) {
            proto.phoneNumberSharingMode = StorageServiceProtoAccountRecordPhoneNumberSharingModeUnwrap(valueParam)
        }

        public mutating func setNotDiscoverableByPhoneNumber(_ valueParam: Bool) {
            proto.notDiscoverableByPhoneNumber = valueParam
        }

        public mutating func addPinnedConversations(_ valueParam: StorageServiceProtoAccountRecordPinnedConversation) {
            proto.pinnedConversations.append(valueParam.proto)
        }

        public mutating func setPinnedConversations(_ wrappedItems: [StorageServiceProtoAccountRecordPinnedConversation]) {
            proto.pinnedConversations = wrappedItems.map { $0.proto }
        }

        public mutating func setPreferContactAvatars(_ valueParam: Bool) {
            proto.preferContactAvatars = valueParam
        }

        public mutating func setHideGroupChatAvatars(_ valueParam: Bool) {
            proto.hideGroupChatAvatars = valueParam
        }
        
        public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
            proto.unknownFields = unknownFields
        }

        public func build() throws -> StorageServiceProtoAccountRecord {
            return try StorageServiceProtoAccountRecord(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try StorageServiceProtoAccountRecord(proto).serializedData()
        }
    }

    fileprivate let proto: StorageServiceProtos_AccountRecord

    public let pinnedConversations: [StorageServiceProtoAccountRecordPinnedConversation]

    public var profileKey: Data? {
        guard hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    public var hasProfileKey: Bool {
        return !proto.profileKey.isEmpty
    }

    public var givenName: String? {
        guard hasGivenName else {
            return nil
        }
        return proto.givenName
    }
    public var hasGivenName: Bool {
        return !proto.givenName.isEmpty
    }

    public var familyName: String? {
        guard hasFamilyName else {
            return nil
        }
        return proto.familyName
    }
    public var hasFamilyName: Bool {
        return !proto.familyName.isEmpty
    }

    public var avatarURL: String? {
        guard hasAvatarURL else {
            return nil
        }
        return proto.avatarURL
    }
    public var hasAvatarURL: Bool {
        return !proto.avatarURL.isEmpty
    }

    public var noteToSelfArchived: Bool {
        return proto.noteToSelfArchived
    }
    public var hasNoteToSelfArchived: Bool {
        return true
    }

    public var readReceipts: Bool {
        return proto.readReceipts
    }
    public var hasReadReceipts: Bool {
        return true
    }

    public var sealedSenderIndicators: Bool {
        return proto.sealedSenderIndicators
    }
    public var hasSealedSenderIndicators: Bool {
        return true
    }

    public var typingIndicators: Bool {
        return proto.typingIndicators
    }
    public var hasTypingIndicators: Bool {
        return true
    }

    public var proxiedLinkPreviews: Bool {
        return proto.proxiedLinkPreviews
    }
    public var hasProxiedLinkPreviews: Bool {
        return true
    }

    public var noteToSelfMarkedUnread: Bool {
        return proto.noteToSelfMarkedUnread
    }
    public var hasNoteToSelfMarkedUnread: Bool {
        return true
    }

    public var linkPreviews: Bool {
        return proto.linkPreviews
    }
    public var hasLinkPreviews: Bool {
        return true
    }

    public var phoneNumberSharingMode: StorageServiceProtoAccountRecordPhoneNumberSharingMode? {
        guard hasPhoneNumberSharingMode else {
            return nil
        }
        return StorageServiceProtoAccountRecordPhoneNumberSharingModeWrap(proto.phoneNumberSharingMode)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedPhoneNumberSharingMode: StorageServiceProtoAccountRecordPhoneNumberSharingMode {
        if !hasPhoneNumberSharingMode {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccountRecord.phoneNumberSharingMode.")
        }
        return StorageServiceProtoAccountRecordPhoneNumberSharingModeWrap(proto.phoneNumberSharingMode)
    }
    public var hasPhoneNumberSharingMode: Bool {
        return true
    }

    public var notDiscoverableByPhoneNumber: Bool {
        return proto.notDiscoverableByPhoneNumber
    }
    public var hasNotDiscoverableByPhoneNumber: Bool {
        return true
    }

    public var preferContactAvatars: Bool {
        return proto.preferContactAvatars
    }
    public var hasPreferContactAvatars: Bool {
        return true
    }

    public var hideGroupChatAvatars: Bool {
        return proto.hideGroupChatAvatars
    }
    public var hasHideGroupChatAvatars: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: StorageServiceProtos_AccountRecord,
                 pinnedConversations: [StorageServiceProtoAccountRecordPinnedConversation]) {
        self.proto = proto
        self.pinnedConversations = pinnedConversations
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try StorageServiceProtos_AccountRecord(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: StorageServiceProtos_AccountRecord) throws {
        var pinnedConversations: [StorageServiceProtoAccountRecordPinnedConversation] = []
        pinnedConversations = try proto.pinnedConversations.map { try StorageServiceProtoAccountRecordPinnedConversation($0) }

        // MARK: - Begin Validation Logic for StorageServiceProtoAccountRecord -

        // MARK: - End Validation Logic for StorageServiceProtoAccountRecord -

        self.init(proto: proto,
                  pinnedConversations: pinnedConversations)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension StorageServiceProtoAccountRecord {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension StorageServiceProtoAccountRecord.StorageServiceProtoAccountRecordBuilder {
    public func buildIgnoringErrors() -> StorageServiceProtoAccountRecord? {
        return try! self.build()
    }
}

#endif
