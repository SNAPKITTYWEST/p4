//
// SwitchboardPhaseIII.swift
//
// Phase III — Executable MetaShard Fabric
//
// Requires Phase I + Phase II.
//
// VHDL
// ↓
// Swift structural machine
// ↓
// CMOS / SPICE graph
// ↓
// MetaShard execution graph
// ↓
// deterministic scheduler
// ↓
// delta-cycle propagation
// ↓
// invariant firewall
// ↓
// structural commitment
//

import Foundation

// ============================================================================
// MARK: - Stable Byte Buffer
// ============================================================================

public struct ByteBuffer: Sendable, Equatable {

    public private(set) var bytes: [UInt8]

    public init() {
        self.bytes = []
    }

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    public var count: Int {
        bytes.count
    }

    public mutating func append(_ byte: UInt8) {
        bytes.append(byte)
    }

    public mutating func append(
        contentsOf other: [UInt8]
    ) {
        bytes.append(contentsOf: other)
    }

    public mutating func append(
        _ value: UInt16
    ) {
        append(
            contentsOf: [
                UInt8((value >> 8) & 0xff),
                UInt8(value & 0xff)
            ]
        )
    }

    public mutating func append(
        _ value: UInt32
    ) {
        append(
            contentsOf: [
                UInt8((value >> 24) & 0xff),
                UInt8((value >> 16) & 0xff),
                UInt8((value >> 8) & 0xff),
                UInt8(value & 0xff)
            ]
        )
    }

    public mutating func append(
        _ value: UInt64
    ) {
        append(
            contentsOf: [
                UInt8((value >> 56) & 0xff),
                UInt8((value >> 48) & 0xff),
                UInt8((value >> 40) & 0xff),
                UInt8((value >> 32) & 0xff),
                UInt8((value >> 24) & 0xff),
                UInt8((value >> 16) & 0xff),
                UInt8((value >> 8) & 0xff),
                UInt8(value & 0xff)
            ]
        )
    }

    public mutating func append(
        string: String
    ) {
        let encoded =
            Array(string.utf8)

        append(UInt64(encoded.count))
        append(contentsOf: encoded)
    }
}

// ============================================================================
// MARK: - Deterministic 256-bit Digest
// ============================================================================
//
// Self-contained structural digest.
//
// This is a deterministic commitment primitive for the MetaShard fabric.
// It is intentionally isolated behind Digest256 so it can later be replaced
// with SHA-256 / BLAKE3 without changing graph semantics.
//
// ============================================================================

public struct Digest256:
    Hashable,
    Sendable,
    CustomStringConvertible
{
    public let a: UInt64
    public let b: UInt64
    public let c: UInt64
    public let d: UInt64

    public init(
        a: UInt64,
        b: UInt64,
        c: UInt64,
        d: UInt64
    ) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    public var description: String {

        func hex(_ x: UInt64) -> String {
            String(
                format: "%016llx",
                x
            )
        }

        return
            hex(a)
            + hex(b)
            + hex(c)
            + hex(d)
    }

    public var bytes: [UInt8] {

        func explode(
            _ x: UInt64
        ) -> [UInt8] {

            [
                UInt8((x >> 56) & 0xff),
                UInt8((x >> 48) & 0xff),
                UInt8((x >> 40) & 0xff),
                UInt8((x >> 32) & 0xff),
                UInt8((x >> 24) & 0xff),
                UInt8((x >> 16) & 0xff),
                UInt8((x >> 8) & 0xff),
                UInt8(x & 0xff)
            ]
        }

        return
            explode(a)
            + explode(b)
            + explode(c)
            + explode(d)
    }
}

// ============================================================================
// MARK: - Digest Engine
// ============================================================================

public enum DigestEngine {

    @inline(__always)
    private static func rotateLeft(
        _ x: UInt64,
        _ amount: UInt64
    ) -> UInt64 {

        let n = amount & 63

        if n == 0 {
            return x
        }

        return
            (x << n)
            | (x >> (64 - n))
    }

    public static func hash(
        _ bytes: [UInt8]
    ) -> Digest256 {

        var a: UInt64 =
            0x243f6a8885a308d3

        var b: UInt64 =
            0x13198a2e03707344

        var c: UInt64 =
            0xa4093822299f31d0

        var d: UInt64 =
            0x082efa98ec4e6c89

        var index: UInt64 = 0

        for byte in bytes {

            let x =
                UInt64(byte)

            a ^= x
                &+ index

            a &*= 0x100000001b3
            a = rotateLeft(a, 13)

            b ^= a
                &+ (x << 1)

            b &*= 0x9e3779b185ebca87
            b = rotateLeft(b, 17)

            c ^= b
                &+ (x << 7)

            c &*= 0xc2b2ae3d27d4eb4f
            c = rotateLeft(c, 29)

            d ^= c
                &+ (x << 13)

            d &*= 0x165667b19e3779f9
            d = rotateLeft(d, 37)

            index &+= 1
        }

        a ^= UInt64(bytes.count)
        b ^= a >> 7
        c ^= b >> 11
        d ^= c >> 19

        a &*= 0xff51afd7ed558ccd
        b &*= 0xc4ceb9fe1a85ec53
        c &*= 0x9ddfea08eb382d69
        d &*= 0xd6e8feb86659fd93

        a ^= d >> 31
        b ^= a >> 27
        c ^= b >> 33
        d ^= c >> 29

        return Digest256(
            a: a,
            b: b,
            c: c,
            d: d
        )
    }

    public static func hash(
        _ buffer: ByteBuffer
    ) -> Digest256 {

        hash(buffer.bytes)
    }

    public static func combine(
        _ left: Digest256,
        _ right: Digest256
    ) -> Digest256 {

        hash(
            left.bytes
            + right.bytes
        )
    }
}

// ============================================================================
// MARK: - Canonical Logic Encoding
// ============================================================================

public enum LogicCanonicalEncoding {

    public static func encode(
        _ logic: Logic,
        into buffer: inout ByteBuffer
    ) {
        buffer.append(
            logic.rawValue
        )
    }

    public static func encode(
        _ bus: LogicBus,
        into buffer: inout ByteBuffer
    ) {
        buffer.append(
            UInt64(bus.width)
        )

        for index in 0..<bus.width {
            encode(
                bus[index],
                into: &buffer
            )
        }
    }
}

// ============================================================================
// MARK: - Canonical MetaValue Encoding
// ============================================================================

public enum MetaValueCanonicalEncoding {

    private enum Tag: UInt8 {
        case logic = 0x01
        case bus = 0x02
        case unsigned = 0x03
        case signed = 0x04
        case real = 0x05
        case text = 0x06
        case flag = 0x07
    }

    public static func encode(
        _ value: MetaValue,
        into buffer: inout ByteBuffer
    ) {
        switch value {

        case let .logic(value):

            buffer.append(
                Tag.logic.rawValue
            )

            LogicCanonicalEncoding.encode(
                value,
                into: &buffer
            )

        case let .bus(value):

            buffer.append(
                Tag.bus.rawValue
            )

            LogicCanonicalEncoding.encode(
                value,
                into: &buffer
            )

        case let .unsigned(value):

            buffer.append(
                Tag.unsigned.rawValue
            )

            buffer.append(value)

        case let .signed(value):

            buffer.append(
                Tag.signed.rawValue
            )

            buffer.append(
                UInt64(
                    bitPattern: value
                )
            )

        case let .real(value):

            buffer.append(
                Tag.real.rawValue
            )

            buffer.append(
                value.bitPattern
            )

        case let .text(value):

            buffer.append(
                Tag.text.rawValue
            )

            buffer.append(
                string: value
            )

        case let .flag(value):

            buffer.append(
                Tag.flag.rawValue
            )

            buffer.append(
                value ? 1 : 0
            )
        }
    }
}

// ============================================================================
// MARK: - Canonical MetaShard Encoding
// ============================================================================

public enum MetaShardCanonicalEncoding {

    public static func encode(
        _ shard: MetaShard
    ) -> ByteBuffer {

        var buffer =
            ByteBuffer()

        buffer.append(
            shard.id.rawValue
        )

        buffer.append(
            shard.kind.rawValue
        )

        let fields =
            shard.fields.sorted {
                $0.key < $1.key
            }

        buffer.append(
            UInt64(fields.count)
        )

        for field in fields {

            buffer.append(
                string: field.key
            )

            MetaValueCanonicalEncoding.encode(
                field.value,
                into: &buffer
            )
        }

        return buffer
    }

    public static func digest(
        _ shard: MetaShard
    ) -> Digest256 {

        DigestEngine.hash(
            encode(shard)
        )
    }
}

// ============================================================================
// MARK: - Graph Node ID
// ============================================================================

public struct GraphNodeID:
    Hashable,
    Sendable,
    Comparable,
    CustomStringConvertible
{
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (
        lhs: GraphNodeID,
        rhs: GraphNodeID
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        String(
            rawValue,
            radix: 16
        )
    }
}

// ============================================================================
// MARK: - Dependency Edge
// ============================================================================

public enum DependencyKind:
    UInt8,
    Sendable
{
    case data
    case control
    case carry
    case invariant
    case provenance
    case physical
}

// ============================================================================
// MARK: - Graph Edge
// ============================================================================

public struct MetaShardEdge:
    Hashable,
    Sendable
{
    public let source: GraphNodeID
    public let target: GraphNodeID
    public let kind: DependencyKind

    public init(
        source: GraphNodeID,
        target: GraphNodeID,
        kind: DependencyKind
    ) {
        self.source = source
        self.target = target
        self.kind = kind
    }
}

// ============================================================================
// MARK: - Executable Shard Node
// ============================================================================

public struct ExecutableShard:
    Sendable
{
    public let nodeID: GraphNodeID
    public var shard: MetaShard

    public init(
        nodeID: GraphNodeID,
        shard: MetaShard
    ) {
        self.nodeID = nodeID
        self.shard = shard
    }
}

// ============================================================================
// MARK: - MetaShard Graph Errors
// ============================================================================

public enum MetaShardGraphError:
    Error,
    Sendable,
    CustomStringConvertible
{
    case duplicateNode(GraphNodeID)
    case missingNode(GraphNodeID)
    case selfDependency(GraphNodeID)
    case cycleDetected
    case duplicateEdge

    public var description: String {

        switch self {

        case let .duplicateNode(node):
            return
                "duplicate MetaShard node \(node)"

        case let .missingNode(node):
            return
                "missing MetaShard node \(node)"

        case let .selfDependency(node):
            return
                "MetaShard self dependency \(node)"

        case .cycleDetected:
            return
                "MetaShard dependency cycle detected"

        case .duplicateEdge:
            return
                "duplicate MetaShard dependency edge"
        }
    }
}

// ============================================================================
// MARK: - MetaShard Graph
// ============================================================================

public struct MetaShardGraph:
    Sendable
{
    public private(set) var nodes:
        [GraphNodeID: ExecutableShard]

    public private(set) var edges:
        Set<MetaShardEdge>

    public init() {
        nodes = [:]
        edges = []
    }

    public mutating func insert(
        _ node: ExecutableShard
    ) throws {

        guard nodes[node.nodeID] == nil
        else {
            throw MetaShardGraphError
                .duplicateNode(
                    node.nodeID
                )
        }

        nodes[node.nodeID] = node
    }

    public mutating func connect(
        source: GraphNodeID,
        target: GraphNodeID,
        kind: DependencyKind
    ) throws {

        guard source != target
        else {
            throw MetaShardGraphError
                .selfDependency(source)
        }

        guard nodes[source] != nil
        else {
            throw MetaShardGraphError
                .missingNode(source)
        }

        guard nodes[target] != nil
        else {
            throw MetaShardGraphError
                .missingNode(target)
        }

        let edge =
            MetaShardEdge(
                source: source,
                target: target,
                kind: kind
            )

        guard edges.insert(edge).inserted
        else {
            throw MetaShardGraphError
                .duplicateEdge
        }
    }

    public func successors(
        of node: GraphNodeID
    ) -> [GraphNodeID] {

        edges
            .filter {
                $0.source == node
            }
            .map(\.target)
            .sorted()
    }

    public func predecessors(
        of node: GraphNodeID
    ) -> [GraphNodeID] {

        edges
            .filter {
                $0.target == node
            }
            .map(\.source)
            .sorted()
    }

    public func topologicalOrder()
        throws -> [GraphNodeID]
    {
        var indegree:
            [GraphNodeID: Int] = [:]

        for node in nodes.keys {
            indegree[node] = 0
        }

        for edge in edges {
            indegree[edge.target, default: 0]
                += 1
        }

        var ready =
            indegree
            .filter {
                $0.value == 0
            }
            .map(\.key)
            .sorted()

        var result:
            [GraphNodeID] = []

        var mutableDegree =
            indegree

        while !ready.isEmpty {

            let node =
                ready.removeFirst()

            result.append(node)

            for successor
                in successors(of: node)
            {
                mutableDegree[
                    successor,
                    default: 0
                ] -= 1

                if mutableDegree[successor] == 0 {
                    ready.append(successor)
                    ready.sort()
                }
            }
        }

        guard result.count
            == nodes.count
        else {
            throw MetaShardGraphError
                .cycleDetected
        }

        return result
    }
}

// ============================================================================
// MARK: - Merkle Commitment
// ============================================================================

public enum MetaShardMerkle {

    public static func root(
        shards: [MetaShard]
    ) -> Digest256 {

        guard !shards.isEmpty
        else {
            return DigestEngine.hash([])
        }

        var level =
            shards
            .sorted {
                $0.id.rawValue
                    < $1.id.rawValue
            }
            .map {
                MetaShardCanonicalEncoding
                    .digest($0)
            }

        while level.count > 1 {

            var next:
                [Digest256] = []

            var index = 0

            while index < level.count {

                let left =
                    level[index]

                let right: Digest256

                if index + 1 < level.count {
                    right =
                        level[index + 1]
                } else {
                    right = left
                }

                next.append(
                    DigestEngine.combine(
                        left,
                        right
                    )
                )

                index += 2
            }

            level = next
        }

        return level[0]
    }

    public static func root(
        graph: MetaShardGraph
    ) -> Digest256 {

        let shards =
            graph.nodes.values
            .map(\.shard)

        return root(
            shards: shards
        )
    }
}

// ============================================================================
// MARK: - Simulation Time
// ============================================================================

public struct SimulationTime:
    Hashable,
    Sendable,
    Comparable,
    CustomStringConvertible
{
    public let tick: UInt64
    public let delta: UInt32

    public init(
        tick: UInt64,
        delta: UInt32 = 0
    ) {
        self.tick = tick
        self.delta = delta
    }

    public static func < (
        lhs: SimulationTime,
        rhs: SimulationTime
    ) -> Bool {

        if lhs.tick != rhs.tick {
            return lhs.tick < rhs.tick
        }

        return lhs.delta < rhs.delta
    }

    public var description: String {
        "\(tick):\(delta)"
    }

    public func nextDelta()
        -> SimulationTime
    {
        SimulationTime(
            tick: tick,
            delta: delta &+ 1
        )
    }

    public func nextTick()
        -> SimulationTime
    {
        SimulationTime(
            tick: tick &+ 1,
            delta: 0
        )
    }
}

// ============================================================================
// MARK: - Runtime Signal ID
// ============================================================================

public struct RuntimeSignalID:
    Hashable,
    Sendable,
    Comparable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) {
        precondition(!rawValue.isEmpty)
        self.rawValue = rawValue
    }

    public static func < (
        lhs: RuntimeSignalID,
        rhs: RuntimeSignalID
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        rawValue
    }
}

// ============================================================================
// MARK: - Runtime Signal Value
// ============================================================================

public enum RuntimeSignalValue:
    Sendable,
    Equatable
{
    case logic(Logic)
    case bus(LogicBus)
    case state(SwitchboardState)
    case unsigned(UInt64)
}

// ============================================================================
// MARK: - Runtime Signal
// ============================================================================

public struct RuntimeSignal:
    Sendable
{
    public let id: RuntimeSignalID
    public var value: RuntimeSignalValue
    public var version: UInt64

    public init(
        id: RuntimeSignalID,
        value: RuntimeSignalValue
    ) {
        self.id = id
        self.value = value
        self.version = 0
    }

    public mutating func assign(
        _ newValue: RuntimeSignalValue
    ) -> Bool {

        guard value != newValue
        else {
            return false
        }

        value = newValue
        version &+= 1

        return true
    }
}

// ============================================================================
// MARK: - Provenance
// ============================================================================

public enum ProvenanceKind:
    UInt8,
    Sendable
{
    case externalInput
    case combinational
    case sequential
    case invariant
    case physical
}

// ============================================================================
// MARK: - Signal Transaction
// ============================================================================

public struct SignalTransaction:
    Sendable
{
    public let signal: RuntimeSignalID
    public let value: RuntimeSignalValue
    public let time: SimulationTime

    public let source:
        GraphNodeID?

    public let provenance:
        ProvenanceKind

    public init(
        signal: RuntimeSignalID,
        value: RuntimeSignalValue,
        time: SimulationTime,
        source: GraphNodeID?,
        provenance: ProvenanceKind
    ) {
        self.signal = signal
        self.value = value
        self.time = time
        self.source = source
        self.provenance = provenance
    }
}

// ============================================================================
// MARK: - Event Sequence
// ============================================================================

public struct EventSequence:
    Hashable,
    Sendable,
    Comparable
{
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (
        lhs: EventSequence,
        rhs: EventSequence
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// ============================================================================
// MARK: - Scheduled Event
// ============================================================================

public struct ScheduledEvent:
    Sendable,
    Comparable
{
    public let sequence:
        EventSequence

    public let transaction:
        SignalTransaction

    public static func < (
        lhs: ScheduledEvent,
        rhs: ScheduledEvent
    ) -> Bool {

        if lhs.transaction.time
            != rhs.transaction.time
        {
            return lhs.transaction.time
                < rhs.transaction.time
        }

        return lhs.sequence
            < rhs.sequence
    }
}

// ============================================================================
// MARK: - Deterministic Event Queue
// ============================================================================

public struct EventQueue:
    Sendable
{
    private var events:
        [ScheduledEvent]

    private var nextSequence:
        UInt64

    public init() {
        events = []
        nextSequence = 0
    }

    public var isEmpty: Bool {
        events.isEmpty
    }

    public var count: Int {
        events.count
    }

    public mutating func schedule(
        _ transaction: SignalTransaction
    ) {
        let event =
            ScheduledEvent(
                sequence:
                    EventSequence(
                        nextSequence
                    ),
                transaction:
                    transaction
            )

        nextSequence &+= 1

        events.append(event)

        events.sort()
    }

    public mutating func pop()
        -> ScheduledEvent?
    {
        guard !events.isEmpty
        else {
            return nil
        }

        return events.removeFirst()
    }

    public func peek()
        -> ScheduledEvent?
    {
        events.first
    }
}

// ============================================================================
// MARK: - Runtime Store
// ============================================================================

public enum RuntimeStoreError:
    Error,
    Sendable
{
    case duplicateSignal(RuntimeSignalID)
    case missingSignal(RuntimeSignalID)
    case typeMismatch(RuntimeSignalID)
}

public struct RuntimeStore:
    Sendable
{
    public private(set) var signals:
        [RuntimeSignalID: RuntimeSignal]

    public init() {
        signals = [:]
    }

    public mutating func declare(
        _ signal: RuntimeSignal
    ) throws {

        guard signals[signal.id] == nil
        else {
            throw RuntimeStoreError
                .duplicateSignal(
                    signal.id
                )
        }

        signals[signal.id] = signal
    }

    public func read(
        _ id: RuntimeSignalID
    ) throws -> RuntimeSignalValue {

        guard let signal =
            signals[id]
        else {
            throw RuntimeStoreError
                .missingSignal(id)
        }

        return signal.value
    }

    @discardableResult
    public mutating func write(
        _ id: RuntimeSignalID,
        value: RuntimeSignalValue
    ) throws -> Bool {

        guard var signal =
            signals[id]
        else {
            throw RuntimeStoreError
                .missingSignal(id)
        }

        let changed =
            signal.assign(value)

        signals[id] = signal

        return changed
    }
}

// ============================================================================
// MARK: - Typed Reads
// ============================================================================

extension RuntimeStore {

    public func logic(
        _ id: RuntimeSignalID
    ) throws -> Logic {

        switch try read(id) {

        case let .logic(value):
            return value

        default:
            throw RuntimeStoreError
                .typeMismatch(id)
        }
    }

    public func bus(
        _ id: RuntimeSignalID
    ) throws -> LogicBus {

        switch try read(id) {

        case let .bus(value):
            return value

        default:
            throw RuntimeStoreError
                .typeMismatch(id)
        }
    }

    public func state(
        _ id: RuntimeSignalID
    ) throws -> SwitchboardState {

        switch try read(id) {

        case let .state(value):
            return value

        default:
            throw RuntimeStoreError
                .typeMismatch(id)
        }
    }

    public func unsigned(
        _ id: RuntimeSignalID
    ) throws -> UInt64 {

        switch try read(id) {

        case let .unsigned(value):
            return value

        default:
            throw RuntimeStoreError
                .typeMismatch(id)
        }
    }
}

// ============================================================================
// MARK: - Switchboard Runtime Signal Names
// ============================================================================

public enum SwitchboardRuntimeSignal {

    public static let a =
        RuntimeSignalID("a")

    public static let b =
        RuntimeSignalID("b")

    public static let reset =
        RuntimeSignalID("reset")

    public static let state =
        RuntimeSignalID("state")

    public static let nextState =
        RuntimeSignalID("state.next")

    public static let internalSum =
        RuntimeSignalID("sum.internal")

    public static let outputSum =
        RuntimeSignalID("sum.output")

    public static let c0 =
        RuntimeSignalID("carry.c0")

    public static let c1 =
        RuntimeSignalID("carry.c1")

    public static let c2 =
        RuntimeSignalID("carry.c2")

    public static let c3 =
        RuntimeSignalID("carry.c3")

    public static let overflow =
        RuntimeSignalID("overflow")

    public static let enable =
        RuntimeSignalID("enable")

    public static let cycle =
        RuntimeSignalID("cycle")
}

// ============================================================================
// MARK: - Runtime Initialization
// ============================================================================

public enum SwitchboardRuntimeFactory {

    public static func build()
        throws -> RuntimeStore
    {
        var store =
            RuntimeStore()

        try store.declare(
            RuntimeSignal(
                id: SwitchboardRuntimeSignal.a,
                value:
                    .bus(
                        .zero(width: 4)
                    )
            )
        )

        try store.declare(
            RuntimeSignal(
                id: SwitchboardRuntimeSignal.b,
                value:
                    .bus(
                        .zero(width: 4)
                    )
            )
        )

        try store.declare(
            RuntimeSignal(
                id: SwitchboardRuntimeSignal.reset,
                value:
                    .logic(.zero)
            )
        )

        try store.declare(
            RuntimeSignal(
                id: SwitchboardRuntimeSignal.state,
                value:
                    .state(.idle)
            )
        )

        try store.declare(
            RuntimeSignal(
                id: SwitchboardRuntimeSignal.nextState,
                value:
                    .state(.idle)
            )
        )

        try store.declare(
            RuntimeSignal(
                id: SwitchboardRuntimeSignal.internalSum,
                value:
                    .bus(
                        .zero(width: 4)
                    )
            )
        )

        try store.declare(
            RuntimeSignal(
                id: SwitchboardRuntimeSignal.outputSum,
                value:
                    .bus(
                        .highImpedance(
                            width: 4
                        )
                    )
            )
        )

        for carry in [
            SwitchboardRuntimeSignal.c0,
            SwitchboardRuntimeSignal.c1,
            SwitchboardRuntimeSignal.c2,
            SwitchboardRuntimeSignal.c3
        ] {
            try store.declare(
                RuntimeSignal(
                    id: carry,
                    value:
                        .logic(.zero)
                )
            )
        }

        try store.declare(
            RuntimeSignal(
                id: SwitchboardRuntimeSignal.overflow,
                value:
                    .logic(.zero)
            )
        )

        try store.declare(
            RuntimeSignal(
                id: SwitchboardRuntimeSignal.enable,
                value:
                    .logic(.zero)
            )
        )

        try store.declare(
            RuntimeSignal(
                id: SwitchboardRuntimeSignal.cycle,
                value:
                    .unsigned(0)
            )
        )

        return store
    }
}

// ============================================================================
// MARK: - Execution Context
// ============================================================================

public struct ExecutionContext:
    Sendable
{
    public var store:
        RuntimeStore

    public var queue:
        EventQueue

    public var time:
        SimulationTime

    public init(
        store: RuntimeStore,
        queue: EventQueue = EventQueue(),
        time: SimulationTime =
            SimulationTime(tick: 0)
    ) {
        self.store = store
        self.queue = queue
        self.time = time
    }
}

// ============================================================================
// MARK: - Executable Operation
// ============================================================================

public enum OperationKind:
    Sendable
{
    case datapath
    case stateDecode
    case outputGate
    case overflow
    case invariant
    case sequential
}

// ============================================================================
// MARK: - Operation Descriptor
// ============================================================================

public struct OperationDescriptor:
    Sendable
{
    public let node:
        GraphNodeID

    public let kind:
        OperationKind

    public let inputs:
        [RuntimeSignalID]

    public let outputs:
        [RuntimeSignalID]

    public init(
        node: GraphNodeID,
        kind: OperationKind,
        inputs: [RuntimeSignalID],
        outputs: [RuntimeSignalID]
    ) {
        self.node = node
        self.kind = kind
        self.inputs = inputs
        self.outputs = outputs
    }
}

// ============================================================================
// MARK: - Runtime Operation
// ============================================================================

public protocol RuntimeOperation:
    Sendable
{
    var descriptor:
        OperationDescriptor
    {
        get
    }

    func evaluate(
        context: ExecutionContext
    ) throws -> [SignalTransaction]
}

// ============================================================================
// MARK: - Datapath Operation
// ============================================================================

public struct DatapathOperation:
    RuntimeOperation
{
    public let descriptor:
        OperationDescriptor

    public init(
        node: GraphNodeID
    ) {
        descriptor =
            OperationDescriptor(
                node: node,
                kind: .datapath,
                inputs: [
                    SwitchboardRuntimeSignal.a,
                    SwitchboardRuntimeSignal.b
                ],
                outputs: [
                    SwitchboardRuntimeSignal.internalSum,
                    SwitchboardRuntimeSignal.c0,
                    SwitchboardRuntimeSignal.c1,
                    SwitchboardRuntimeSignal.c2,
                    SwitchboardRuntimeSignal.c3
                ]
            )
    }

    public func evaluate(
        context: ExecutionContext
    ) throws -> [SignalTransaction] {

        let a =
            try context.store.bus(
                SwitchboardRuntimeSignal.a
            )

        let b =
            try context.store.bus(
                SwitchboardRuntimeSignal.b
            )

        let result =
            RippleAdder4.evaluate(
                a: a,
                b: b
            )

        let time =
            context.time.nextDelta()

        return [
            SignalTransaction(
                signal:
                    SwitchboardRuntimeSignal.internalSum,
                value:
                    .bus(result.sum),
                time: time,
                source: descriptor.node,
                provenance:
                    .combinational
            ),

            SignalTransaction(
                signal:
                    SwitchboardRuntimeSignal.c0,
                value:
                    .logic(result.carry.c0),
                time: time,
                source: descriptor.node,
                provenance:
                    .combinational
            ),

            SignalTransaction(
                signal:
                    SwitchboardRuntimeSignal.c1,
                value:
                    .logic(result.carry.c1),
                time: time,
                source: descriptor.node,
                provenance:
                    .combinational
            ),

            SignalTransaction(
                signal:
                    SwitchboardRuntimeSignal.c2,
                value:
                    .logic(result.carry.c2),
                time: time,
                source: descriptor.node,
                provenance:
                    .combinational
            ),

            SignalTransaction(
                signal:
                    SwitchboardRuntimeSignal.c3,
                value:
                    .logic(result.carry.c3),
                time: time,
                source: descriptor.node,
                provenance:
                    .combinational
            )
        ]
    }
}

// ============================================================================
// MARK: - FSM Decode Operation
// ============================================================================

public struct FSMDecodeOperation:
    RuntimeOperation
{
    public let descriptor:
        OperationDescriptor

    public init(
        node: GraphNodeID
    ) {
        descriptor =
            OperationDescriptor(
                node: node,
                kind: .stateDecode,
                inputs: [
                    SwitchboardRuntimeSignal.a,
                    SwitchboardRuntimeSignal.b,
                    SwitchboardRuntimeSignal.reset,
                    SwitchboardRuntimeSignal.state
                ],
                outputs: [
                    SwitchboardRuntimeSignal.nextState
                ]
            )
    }

    public func evaluate(
        context: ExecutionContext
    ) throws -> [SignalTransaction] {

        let a =
            try context.store.bus(
                SwitchboardRuntimeSignal.a
            )

        let b =
            try context.store.bus(
                SwitchboardRuntimeSignal.b
            )

        let reset =
            try context.store.logic(
                SwitchboardRuntimeSignal.reset
            )

        let state =
            try context.store.state(
                SwitchboardRuntimeSignal.state
            )

        let next: SwitchboardState

        if reset == .one {

            next = .idle

        } else {

            switch state {

            case .idle:

                var active = false

                for index in 0..<4 {
                    if a[index] == .one ||
                        b[index] == .one {
                        active = true
                        break
                    }
                }

                next =
                    active
                    ? .read
                    : .idle

            case .read:
                next = .write

            case .write:
                next = .idle
            }
        }

        return [
            SignalTransaction(
                signal:
                    SwitchboardRuntimeSignal.nextState,
                value:
                    .state(next),
                time:
                    context.time.nextDelta(),
                source:
                    descriptor.node,
                provenance:
                    .combinational
            )
        ]
    }
}

// ============================================================================
// MARK: - Enable Decode
// ============================================================================

public struct EnableOperation:
    RuntimeOperation
{
    public let descriptor:
        OperationDescriptor

    public init(
        node: GraphNodeID
    ) {
        descriptor =
            OperationDescriptor(
                node: node,
                kind: .stateDecode,
                inputs: [
                    SwitchboardRuntimeSignal.state
                ],
                outputs: [
                    SwitchboardRuntimeSignal.enable
                ]
            )
    }

    public func evaluate(
        context: ExecutionContext
    ) throws -> [SignalTransaction] {

        let state =
            try context.store.state(
                SwitchboardRuntimeSignal.state
            )

        let enable: Logic =
            state == .read
            ? .one
            : .zero

        return [
            SignalTransaction(
                signal:
                    SwitchboardRuntimeSignal.enable,
                value:
                    .logic(enable),
                time:
                    context.time.nextDelta(),
                source:
                    descriptor.node,
                provenance:
                    .combinational
            )
        ]
    }
}

// ============================================================================
// MARK: - Output Gate
// ============================================================================

public struct OutputGateOperation:
    RuntimeOperation
{
    public let descriptor:
        OperationDescriptor

    public init(
        node: GraphNodeID
    ) {
        descriptor =
            OperationDescriptor(
                node: node,
                kind: .outputGate,
                inputs: [
                    SwitchboardRuntimeSignal.internalSum,
                    SwitchboardRuntimeSignal.enable
                ],
                outputs: [
                    SwitchboardRuntimeSignal.outputSum
                ]
            )
    }

    public func evaluate(
        context: ExecutionContext
    ) throws -> [SignalTransaction] {

        let internalSum =
            try context.store.bus(
                SwitchboardRuntimeSignal.internalSum
            )

        let enable =
            try context.store.logic(
                SwitchboardRuntimeSignal.enable
            )

        let output: LogicBus

        switch enable {

        case .one:
            output = internalSum

        case .zero:
            output =
                .highImpedance(
                    width: 4
                )

        case .x, .z:
            output =
                .unknown(
                    width: 4
                )
        }

        return [
            SignalTransaction(
                signal:
                    SwitchboardRuntimeSignal.outputSum,
                value:
                    .bus(output),
                time:
                    context.time.nextDelta(),
                source:
                    descriptor.node,
                provenance:
                    .combinational
            )
        ]
    }
}

// ============================================================================
// MARK: - Overflow Operation
// ============================================================================

public struct OverflowOperation:
    RuntimeOperation
{
    public let descriptor:
        OperationDescriptor

    public init(
        node: GraphNodeID
    ) {
        descriptor =
            OperationDescriptor(
                node: node,
                kind: .overflow,
                inputs: [
                    SwitchboardRuntimeSignal.c3
                ],
                outputs: [
                    SwitchboardRuntimeSignal.overflow
                ]
            )
    }

    public func evaluate(
        context: ExecutionContext
    ) throws -> [SignalTransaction] {

        let carry =
            try context.store.logic(
                SwitchboardRuntimeSignal.c3
            )

        return [
            SignalTransaction(
                signal:
                    SwitchboardRuntimeSignal.overflow,
                value:
                    .logic(carry),
                time:
                    context.time.nextDelta(),
                source:
                    descriptor.node,
                provenance:
                    .combinational
            )
        ]
    }
}

// ============================================================================
// MARK: - Sequential State Commit
// ============================================================================

public struct SequentialStateOperation:
    RuntimeOperation
{
    public let descriptor:
        OperationDescriptor

    public init(
        node: GraphNodeID
    ) {
        descriptor =
            OperationDescriptor(
                node: node,
                kind: .sequential,
                inputs: [
                    SwitchboardRuntimeSignal.nextState,
                    SwitchboardRuntimeSignal.cycle
                ],
                outputs: [
                    SwitchboardRuntimeSignal.state,
                    SwitchboardRuntimeSignal.cycle
                ]
            )
    }

    public func evaluate(
        context: ExecutionContext
    ) throws -> [SignalTransaction] {

        let nextState =
            try context.store.state(
                SwitchboardRuntimeSignal.nextState
            )

        let cycle =
            try context.store.unsigned(
                SwitchboardRuntimeSignal.cycle
            )

        let time =
            context.time.nextTick()

        return [
            SignalTransaction(
                signal:
                    SwitchboardRuntimeSignal.state,
                value:
                    .state(nextState),
                time: time,
                source: descriptor.node,
                provenance:
                    .sequential
            ),

            SignalTransaction(
                signal:
                    SwitchboardRuntimeSignal.cycle,
                value:
                    .unsigned(cycle &+ 1),
                time: time,
                source: descriptor.node,
                provenance:
                    .sequential
            )
        ]
    }
}
