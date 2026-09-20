//
// SwitchboardPhaseIV.swift
//
// Phase IV — HDL Runtime / Waveform / SPICE Verification Layer
//
// Requires Phase I–III.
//
// Major additions:
//
// 1. IEEE-like std_logic resolution
// 2. multi-driver nets
// 3. sensitivity-driven processes
// 4. inertial / transport transactions
// 5. deterministic clock generation
// 6. setup / hold timing monitors
// 7. VCD waveform emission
// 8. SPICE PWL stimulus
// 9. SPICE measurement assertions
// 10. logical ↔ physical provenance
//
// ============================================================================

import Foundation

// ============================================================================
// MARK: - Extended std_logic
// ============================================================================
//
// VHDL std_logic has:
//
//   U X 0 1 Z W L H -
//
// Phase I used the compact:
//
//   0 1 X Z
//
// Phase IV introduces the complete resolution domain while retaining conversion
// to the compact execution domain.
//
// ============================================================================

@frozen
public enum StdLogic:
    UInt8,
    CaseIterable,
    Sendable
{
    case u = 0
    case x = 1
    case zero = 2
    case one = 3
    case z = 4
    case weakX = 5
    case weakZero = 6
    case weakOne = 7
    case dash = 8
}

extension StdLogic: CustomStringConvertible {

    public var description: String {

        switch self {

        case .u:
            return "U"

        case .x:
            return "X"

        case .zero:
            return "0"

        case .one:
            return "1"

        case .z:
            return "Z"

        case .weakX:
            return "W"

        case .weakZero:
            return "L"

        case .weakOne:
            return "H"

        case .dash:
            return "-"
        }
    }
}

// ============================================================================
// MARK: - Compact Logic Conversion
// ============================================================================

extension StdLogic {

    public init(
        compact logic: Logic
    ) {
        switch logic {

        case .zero:
            self = .zero

        case .one:
            self = .one

        case .x:
            self = .x

        case .z:
            self = .z
        }
    }

    public var compact: Logic {

        switch self {

        case .zero,
             .weakZero:
            return .zero

        case .one,
             .weakOne:
            return .one

        case .z:
            return .z

        case .u,
             .x,
             .weakX,
             .dash:
            return .x
        }
    }
}

// ============================================================================
// MARK: - std_logic Resolution
// ============================================================================
//
// Explicit pair resolution.
//
// This is kept centralized. Nothing else in the simulator gets to invent
// multi-driver behavior.
//
// ============================================================================

public enum StdLogicResolver {

    public static func resolve(
        _ lhs: StdLogic,
        _ rhs: StdLogic
    ) -> StdLogic {

        if lhs == rhs {
            return lhs
        }

        if lhs == .u || rhs == .u {
            return .u
        }

        if lhs == .dash ||
            rhs == .dash {
            return .x
        }

        if lhs == .z {
            return rhs
        }

        if rhs == .z {
            return lhs
        }

        if lhs == .x ||
            rhs == .x {
            return .x
        }

        switch (lhs, rhs) {

        // Strong conflict

        case (.zero, .one),
             (.one, .zero):
            return .x

        // Strong zero dominates weak

        case (.zero, .weakZero),
             (.weakZero, .zero):
            return .zero

        case (.zero, .weakOne),
             (.weakOne, .zero):
            return .zero

        case (.zero, .weakX),
             (.weakX, .zero):
            return .zero

        // Strong one dominates weak

        case (.one, .weakOne),
             (.weakOne, .one):
            return .one

        case (.one, .weakZero),
             (.weakZero, .one):
            return .one

        case (.one, .weakX),
             (.weakX, .one):
            return .one

        // Weak combinations

        case (.weakZero, .weakOne),
             (.weakOne, .weakZero):
            return .weakX

        case (.weakZero, .weakX),
             (.weakX, .weakZero):
            return .weakX

        case (.weakOne, .weakX),
             (.weakX, .weakOne):
            return .weakX

        default:
            return .x
        }
    }

    public static func resolve(
        _ drivers: [StdLogic]
    ) -> StdLogic {

        guard let first =
            drivers.first
        else {
            return .z
        }

        return drivers
            .dropFirst()
            .reduce(first) {
                resolve($0, $1)
            }
    }
}

// ============================================================================
// MARK: - Resolved Bus
// ============================================================================

public struct StdLogicBus:
    Sendable,
    Equatable
{
    private var bits:
        [StdLogic]

    public let width:
        Int

    public init(
        width: Int,
        fill: StdLogic = .u
    ) {
        precondition(width > 0)

        self.width = width
        self.bits =
            Array(
                repeating: fill,
                count: width
            )
    }

    public init(
        compact bus: LogicBus
    ) {
        self.width =
            bus.width

        self.bits =
            (0..<bus.width)
            .map {
                StdLogic(
                    compact: bus[$0]
                )
            }
    }

    public subscript(
        _ index: Int
    ) -> StdLogic {

        get {
            precondition(
                index >= 0 &&
                index < width
            )

            return bits[index]
        }

        set {
            precondition(
                index >= 0 &&
                index < width
            )

            bits[index] =
                newValue
        }
    }

    public var compact:
        LogicBus
    {
        LogicBus(
            (0..<width)
            .map {
                bits[$0].compact
            }
        )
    }
}

// ============================================================================
// MARK: - Driver ID
// ============================================================================

public struct DriverID:
    Hashable,
    Sendable,
    Comparable,
    CustomStringConvertible
{
    public let rawValue:
        String

    public init(
        _ rawValue: String
    ) {
        precondition(
            !rawValue.isEmpty
        )

        self.rawValue =
            rawValue
    }

    public static func < (
        lhs: DriverID,
        rhs: DriverID
    ) -> Bool {

        lhs.rawValue
            < rhs.rawValue
    }

    public var description:
        String
    {
        rawValue
    }
}

// ============================================================================
// MARK: - Resolved Scalar Net
// ============================================================================

public struct ResolvedNet:
    Sendable
{
    public let id:
        RuntimeSignalID

    private var drivers:
        [DriverID: StdLogic]

    public private(set) var value:
        StdLogic

    public private(set) var version:
        UInt64

    public init(
        id: RuntimeSignalID
    ) {
        self.id = id
        self.drivers = [:]
        self.value = .z
        self.version = 0
    }

    public var driverCount:
        Int
    {
        drivers.count
    }

    public func driverValue(
        _ driver: DriverID
    ) -> StdLogic? {

        drivers[driver]
    }

    @discardableResult
    public mutating func drive(
        driver: DriverID,
        value: StdLogic
    ) -> Bool {

        drivers[driver] =
            value

        let ordered =
            drivers
            .keys
            .sorted()
            .compactMap {
                drivers[$0]
            }

        let resolved =
            StdLogicResolver.resolve(
                ordered
            )

        guard resolved != self.value
        else {
            return false
        }

        self.value =
            resolved

        self.version &+= 1

        return true
    }

    @discardableResult
    public mutating func release(
        driver: DriverID
    ) -> Bool {

        drivers[driver] =
            .z

        let ordered =
            drivers
            .keys
            .sorted()
            .compactMap {
                drivers[$0]
            }

        let resolved =
            StdLogicResolver.resolve(
                ordered
            )

        guard resolved != value
        else {
            return false
        }

        value =
            resolved

        version &+= 1

        return true
    }
}

// ============================================================================
// MARK: - Resolved Vector Net
// ============================================================================

public struct ResolvedVectorNet:
    Sendable
{
    public let id:
        RuntimeSignalID

    public let width:
        Int

    private var drivers:
        [DriverID: StdLogicBus]

    public private(set) var value:
        StdLogicBus

    public private(set) var version:
        UInt64

    public init(
        id: RuntimeSignalID,
        width: Int
    ) {
        precondition(width > 0)

        self.id = id
        self.width = width

        self.drivers = [:]

        self.value =
            StdLogicBus(
                width: width,
                fill: .z
            )

        self.version = 0
    }

    @discardableResult
    public mutating func drive(
        driver: DriverID,
        value newBus: StdLogicBus
    ) -> Bool {

        precondition(
            newBus.width == width
        )

        drivers[driver] =
            newBus

        var resolved =
            StdLogicBus(
                width: width,
                fill: .z
            )

        let orderedDrivers =
            drivers.keys.sorted()

        for bit in 0..<width {

            let values =
                orderedDrivers
                .compactMap {
                    drivers[$0]?[bit]
                }

            resolved[bit] =
                StdLogicResolver.resolve(
                    values
                )
        }

        guard resolved != value
        else {
            return false
        }

        value =
            resolved

        version &+= 1

        return true
    }
}

// ============================================================================
// MARK: - Delay Model
// ============================================================================

public enum DelayMode:
    UInt8,
    Sendable
{
    case transport
    case inertial
}

// ============================================================================
// MARK: - HDL Duration
// ============================================================================

public struct HDLDuration:
    Hashable,
    Sendable,
    Comparable
{
    public let femtoseconds:
        UInt64

    public init(
        femtoseconds: UInt64
    ) {
        self.femtoseconds =
            femtoseconds
    }

    public static func < (
        lhs: HDLDuration,
        rhs: HDLDuration
    ) -> Bool {

        lhs.femtoseconds
            < rhs.femtoseconds
    }

    public static let zero =
        HDLDuration(
            femtoseconds: 0
        )

    public static func picoseconds(
        _ value: UInt64
    ) -> HDLDuration {

        HDLDuration(
            femtoseconds:
                value * 1_000
        )
    }

    public static func nanoseconds(
        _ value: UInt64
    ) -> HDLDuration {

        HDLDuration(
            femtoseconds:
                value * 1_000_000
        )
    }
}

// ============================================================================
// MARK: - Physical Simulation Time
// ============================================================================

public struct HDLTime:
    Hashable,
    Sendable,
    Comparable,
    CustomStringConvertible
{
    public let femtoseconds:
        UInt64

    public let delta:
        UInt32

    public init(
        femtoseconds: UInt64,
        delta: UInt32 = 0
    ) {
        self.femtoseconds =
            femtoseconds

        self.delta =
            delta
    }

    public static func < (
        lhs: HDLTime,
        rhs: HDLTime
    ) -> Bool {

        if lhs.femtoseconds
            != rhs.femtoseconds
        {
            return
                lhs.femtoseconds
                < rhs.femtoseconds
        }

        return
            lhs.delta
            < rhs.delta
    }

    public var description:
        String
    {
        "\(femtoseconds)fs:\(delta)"
    }

    public func advanced(
        by duration: HDLDuration
    ) -> HDLTime {

        HDLTime(
            femtoseconds:
                femtoseconds
                &+ duration.femtoseconds,
            delta: 0
        )
    }

    public func nextDelta()
        -> HDLTime
    {
        HDLTime(
            femtoseconds:
                femtoseconds,
            delta:
                delta &+ 1
        )
    }
}

// ============================================================================
// MARK: - Driver Transaction
// ============================================================================

public struct DriverTransaction:
    Sendable
{
    public let net:
        RuntimeSignalID

    public let driver:
        DriverID

    public let value:
        StdLogic

    public let time:
        HDLTime

    public let mode:
        DelayMode

    public let reject:
        HDLDuration

    public let source:
        GraphNodeID?

    public init(
        net: RuntimeSignalID,
        driver: DriverID,
        value: StdLogic,
        time: HDLTime,
        mode: DelayMode,
        reject: HDLDuration = .zero,
        source: GraphNodeID? = nil
    ) {
        self.net = net
        self.driver = driver
        self.value = value
        self.time = time
        self.mode = mode
        self.reject = reject
        self.source = source
    }
}

// ============================================================================
// MARK: - Driver Event
// ============================================================================

public struct DriverEvent:
    Sendable,
    Comparable
{
    public let sequence:
        UInt64

    public let transaction:
        DriverTransaction

    public static func < (
        lhs: DriverEvent,
        rhs: DriverEvent
    ) -> Bool {

        if lhs.transaction.time
            != rhs.transaction.time
        {
            return
                lhs.transaction.time
                < rhs.transaction.time
        }

        return
            lhs.sequence
            < rhs.sequence
    }
}

// ============================================================================
// MARK: - Delay Queue
// ============================================================================

public struct DelayQueue:
    Sendable
{
    private var events:
        [DriverEvent]

    private var sequence:
        UInt64

    public init() {
        events = []
        sequence = 0
    }

    public var isEmpty:
        Bool
    {
        events.isEmpty
    }

    public var count:
        Int
    {
        events.count
    }

    public mutating func schedule(
        _ transaction: DriverTransaction
    ) {
        if transaction.mode
            == .inertial
        {
            cancelRejectedTransactions(
                by: transaction
            )
        }

        events.append(
            DriverEvent(
                sequence: sequence,
                transaction:
                    transaction
            )
        )

        sequence &+= 1

        events.sort()
    }

    private mutating func
        cancelRejectedTransactions(
            by incoming: DriverTransaction
        )
    {
        let threshold =
            incoming.time
            .femtoseconds
            >= incoming.reject
            .femtoseconds
            ? incoming.time
            .femtoseconds
            - incoming.reject
            .femtoseconds
            : 0

        events.removeAll {

            let tx =
                $0.transaction

            guard tx.net
                == incoming.net,
                tx.driver
                == incoming.driver
            else {
                return false
            }

            return
                tx.time.femtoseconds
                >= threshold
                &&
                tx.time.femtoseconds
                <= incoming.time
                .femtoseconds
        }
    }

    public mutating func pop()
        -> DriverEvent?
    {
        guard !events.isEmpty
        else {
            return nil
        }

        return events.removeFirst()
    }
}

// ============================================================================
// MARK: - Sensitivity Set
// ============================================================================

public struct SensitivitySet:
    Sendable
{
    public let signals:
        Set<RuntimeSignalID>

    public init(
        _ signals: Set<RuntimeSignalID>
    ) {
        self.signals =
            signals
    }

    public func contains(
        _ signal: RuntimeSignalID
    ) -> Bool {

        signals.contains(
            signal
        )
    }
}

// ============================================================================
// MARK: - HDL Process ID
// ============================================================================

public struct HDLProcessID:
    Hashable,
    Sendable,
    Comparable,
    CustomStringConvertible
{
    public let rawValue:
        String

    public init(
        _ rawValue: String
    ) {
        precondition(
            !rawValue.isEmpty
        )

        self.rawValue =
            rawValue
    }

    public static func < (
        lhs: HDLProcessID,
        rhs: HDLProcessID
    ) -> Bool {

        lhs.rawValue
            < rhs.rawValue
    }

    public var description:
        String
    {
        rawValue
    }
}

// ============================================================================
// MARK: - Process Descriptor
// ============================================================================

public struct HDLProcessDescriptor:
    Sendable
{
    public let id:
        HDLProcessID

    public let sensitivity:
        SensitivitySet

    public let node:
        GraphNodeID

    public init(
        id: HDLProcessID,
        sensitivity: SensitivitySet,
        node: GraphNodeID
    ) {
        self.id = id
        self.sensitivity =
            sensitivity
        self.node = node
    }
}

// ============================================================================
// MARK: - Process Registry
// ============================================================================

public struct ProcessRegistry:
    Sendable
{
    private var descriptors:
        [HDLProcessID:
            HDLProcessDescriptor]

    public init() {
        descriptors = [:]
    }

    public mutating func register(
        _ descriptor:
            HDLProcessDescriptor
    ) {
        precondition(
            descriptors[
                descriptor.id
            ] == nil
        )

        descriptors[
            descriptor.id
        ] = descriptor
    }

    public func sensitiveProcesses(
        to signal: RuntimeSignalID
    ) -> [HDLProcessDescriptor] {

        descriptors
            .values
            .filter {
                $0.sensitivity
                    .contains(signal)
            }
            .sorted {
                $0.id < $1.id
            }
    }
}

// ============================================================================
// MARK: - Switchboard Graph Node IDs
// ============================================================================

public enum SwitchboardGraphNode {

    public static let datapath =
        GraphNodeID(0x01)

    public static let fsm =
        GraphNodeID(0x02)

    public static let enable =
        GraphNodeID(0x03)

    public static let outputGate =
        GraphNodeID(0x04)

    public static let overflow =
        GraphNodeID(0x05)

    public static let sequential =
        GraphNodeID(0x06)
}

// ============================================================================
// MARK: - Switchboard Process Registry
// ============================================================================

public enum SwitchboardProcessRegistry {

    public static func build()
        -> ProcessRegistry
    {
        var registry =
            ProcessRegistry()

        registry.register(
            HDLProcessDescriptor(
                id:
                    HDLProcessID(
                        "datapath"
                    ),
                sensitivity:
                    SensitivitySet(
                        [
                            SwitchboardRuntimeSignal.a,
                            SwitchboardRuntimeSignal.b
                        ]
                    ),
                node:
                    SwitchboardGraphNode.datapath
            )
        )

        registry.register(
            HDLProcessDescriptor(
                id:
                    HDLProcessID(
                        "fsm_comb"
                    ),
                sensitivity:
                    SensitivitySet(
                        [
                            SwitchboardRuntimeSignal.a,
                            SwitchboardRuntimeSignal.b,
                            SwitchboardRuntimeSignal.reset,
                            SwitchboardRuntimeSignal.state
                        ]
                    ),
                node:
                    SwitchboardGraphNode.fsm
            )
        )

        registry.register(
            HDLProcessDescriptor(
                id:
                    HDLProcessID(
                        "enable_decode"
                    ),
                sensitivity:
                    SensitivitySet(
                        [
                            SwitchboardRuntimeSignal.state
                        ]
                    ),
                node:
                    SwitchboardGraphNode.enable
            )
        )

        registry.register(
            HDLProcessDescriptor(
                id:
                    HDLProcessID(
                        "output_gate"
                    ),
                sensitivity:
                    SensitivitySet(
                        [
                            SwitchboardRuntimeSignal.internalSum,
                            SwitchboardRuntimeSignal.enable
                        ]
                    ),
                node:
                    SwitchboardGraphNode.outputGate
            )
        )

        registry.register(
            HDLProcessDescriptor(
                id:
                    HDLProcessID(
                        "overflow"
                    ),
                sensitivity:
                    SensitivitySet(
                        [
                            SwitchboardRuntimeSignal.c3
                        ]
                    ),
                node:
                    SwitchboardGraphNode.overflow
            )
        )

        return registry
    }
}

// ============================================================================
// MARK: - Clock Edge
// ============================================================================

public enum ClockEdge:
    UInt8,
    Sendable
{
    case rising
    case falling
}

// ============================================================================
// MARK: - Clock Specification
// ============================================================================

public struct ClockSpecification:
    Sendable
{
    public let signal:
        RuntimeSignalID

    public let period:
        HDLDuration

    public let highTime:
        HDLDuration

    public let phase:
        HDLDuration

    public init(
        signal: RuntimeSignalID,
        period: HDLDuration,
        highTime: HDLDuration,
        phase: HDLDuration = .zero
    ) {
        precondition(
            highTime.femtoseconds
            < period.femtoseconds
        )

        self.signal = signal
        self.period = period
        self.highTime = highTime
        self.phase = phase
    }
}

// ============================================================================
// MARK: - Clock Transition
// ============================================================================

public struct ClockTransition:
    Sendable
{
    public let time:
        HDLTime

    public let value:
        StdLogic

    public let edge:
        ClockEdge
}

// ============================================================================
// MARK: - Clock Generator
// ============================================================================

public enum ClockGenerator {

    public static func transitions(
        specification:
            ClockSpecification,
        cycles: Int
    ) -> [ClockTransition] {

        precondition(
            cycles >= 0
        )

        var output:
            [ClockTransition] = []

        var base =
            specification.phase
            .femtoseconds

        for _ in 0..<cycles {

            output.append(
                ClockTransition(
                    time:
                        HDLTime(
                            femtoseconds:
                                base
                        ),
                    value:
                        .one,
                    edge:
                        .rising
                )
            )

            output.append(
                ClockTransition(
                    time:
                        HDLTime(
                            femtoseconds:
                                base
                                &+ specification
                                .highTime
                                .femtoseconds
                        ),
                    value:
                        .zero,
                    edge:
                        .falling
                )
            )

            base &+=
                specification
                .period
                .femtoseconds
        }

        return output
    }
}

// ============================================================================
// MARK: - Timing Requirement
// ============================================================================

public struct TimingRequirement:
    Sendable
{
    public let setup:
        HDLDuration

    public let hold:
        HDLDuration

    public init(
        setup: HDLDuration,
        hold: HDLDuration
    ) {
        self.setup = setup
        self.hold = hold
    }
}

// ============================================================================
// MARK: - Signal Transition History
// ============================================================================

public struct SignalTransitionRecord:
    Sendable
{
    public let signal:
        RuntimeSignalID

    public let time:
        HDLTime

    public init(
        signal: RuntimeSignalID,
        time: HDLTime
    ) {
        self.signal = signal
        self.time = time
    }
}

public struct TransitionHistory:
    Sendable
{
    private var history:
        [RuntimeSignalID:
            [HDLTime]]

    public init() {
        history = [:]
    }

    public mutating func record(
        signal: RuntimeSignalID,
        at time: HDLTime
    ) {
        history[
            signal,
            default: []
        ]
        .append(time)
    }

    public func lastTransition(
        of signal: RuntimeSignalID,
        beforeOrAt time: HDLTime
    ) -> HDLTime? {

        history[signal]?
            .filter {
                $0 <= time
            }
            .max()
    }

    public func firstTransition(
        of signal: RuntimeSignalID,
        after time: HDLTime
    ) -> HDLTime? {

        history[signal]?
            .filter {
                $0 > time
            }
            .min()
    }
}

// ============================================================================
// MARK: - Timing Violation
// ============================================================================

public enum TimingViolation:
    Error,
    Sendable,
    CustomStringConvertible
{
    case setup(
        signal: RuntimeSignalID,
        margin: UInt64
    )

    case hold(
        signal: RuntimeSignalID,
        margin: UInt64
    )

    public var description:
        String
    {
        switch self {

        case let .setup(
            signal,
            margin
        ):
            return
                "setup violation \(signal), margin=\(margin)fs"

        case let .hold(
            signal,
            margin
        ):
            return
                "hold violation \(signal), margin=\(margin)fs"
        }
    }
}

// ============================================================================
// MARK: - Timing Monitor
// ============================================================================

public enum TimingMonitor {

    public static func check(
        dataSignals:
            [RuntimeSignalID],
        edge:
            HDLTime,
        requirement:
            TimingRequirement,
        history:
            TransitionHistory
    ) throws {

        for signal in dataSignals {

            if let previous =
                history.lastTransition(
                    of: signal,
                    beforeOrAt: edge
                )
            {
                let distance =
                    edge.femtoseconds
                    - previous.femtoseconds

                if distance
                    < requirement
                    .setup
                    .femtoseconds
                {
                    throw TimingViolation
                        .setup(
                            signal: signal,
                            margin:
                                distance
                        )
                }
            }

            if let next =
                history.firstTransition(
                    of: signal,
                    after: edge
                )
            {
                let distance =
                    next.femtoseconds
                    - edge.femtoseconds

                if distance
                    < requirement
                    .hold
                    .femtoseconds
                {
                    throw TimingViolation
                        .hold(
                            signal: signal,
                            margin:
                                distance
                        )
                }
            }
        }
    }
}

// ============================================================================
// MARK: - VCD Identifier
// ============================================================================

public struct VCDIdentifier:
    Hashable,
    Sendable
{
    public let rawValue:
        String

    public init(
        _ rawValue: String
    ) {
        self.rawValue =
            rawValue
    }
}

// ============================================================================
// MARK: - VCD Variable
// ============================================================================

public struct VCDVariable:
    Sendable
{
    public let signal:
        RuntimeSignalID

    public let identifier:
        VCDIdentifier

    public let width:
        Int

    public let reference:
        String

    public init(
        signal: RuntimeSignalID,
        identifier: VCDIdentifier,
        width: Int,
        reference: String
    ) {
        self.signal = signal
        self.identifier =
            identifier
        self.width = width
        self.reference =
            reference
    }
}

// ============================================================================
// MARK: - VCD Symbol Allocator
// ============================================================================

public struct VCDSymbolAllocator {

    private var index:
        UInt64 = 0

    public init() {}

    public mutating func next()
        -> VCDIdentifier
    {
        var value =
            index

        index &+= 1

        var bytes:
            [UInt8] = []

        repeat {
            let digit =
                UInt8(
                    value % 94
                )

            bytes.append(
                33 + digit
            )

            value /= 94

        } while value > 0

        return VCDIdentifier(
            String(
                bytes:
                    bytes,
                encoding:
                    .ascii
            )!
        )
    }
}

// ============================================================================
// MARK: - VCD Value
// ============================================================================

public enum VCDValue:
    Sendable
{
    case scalar(StdLogic)
    case vector(StdLogicBus)
}

// ============================================================================
// MARK: - VCD Change
// ============================================================================

public struct VCDChange:
    Sendable
{
    public let time:
        UInt64

    public let variable:
        VCDVariable

    public let value:
        VCDValue
}

// ============================================================================
// MARK: - VCD Serializer
// ============================================================================

public enum VCDSerializer {

    private static func scalar(
        _ logic: StdLogic
    ) -> String {

        switch logic {

        case .zero,
             .weakZero:
            return "0"

        case .one,
             .weakOne:
            return "1"

        case .z:
            return "z"

        case .u,
             .x,
             .weakX,
             .dash:
            return "x"
        }
    }

    private static func vector(
        _ bus: StdLogicBus
    ) -> String {

        var result =
            ""

        for index in stride(
            from: bus.width - 1,
            through: 0,
            by: -1
        ) {
            result +=
                scalar(
                    bus[index]
                )
        }

        return result
    }

    public static func serialize(
        module: String,
        variables: [VCDVariable],
        changes: [VCDChange]
    ) -> String {

        var text = ""

        text += "$date\n"
        text += " deterministic\n"
        text += "$end\n"

        text += "$version\n"
        text += " Switchboard Phase IV\n"
        text += "$end\n"

        text += "$timescale 1fs $end\n"

        text += "$scope module "
        text += module
        text += " $end\n"

        for variable in variables {

            text += "$var wire "
            text += String(
                variable.width
            )

            text += " "
            text += variable
                .identifier
                .rawValue

            text += " "
            text += variable.reference
            text += " $end\n"
        }

        text += "$upscope $end\n"
        text += "$enddefinitions $end\n"

        var currentTime:
            UInt64? = nil

        let ordered =
            changes.sorted {

                if $0.time != $1.time {
                    return
                        $0.time
                        < $1.time
                }

                return
                    $0.variable
                    .identifier
                    .rawValue
                    <
                    $1.variable
                    .identifier
                    .rawValue
            }

        for change in ordered {

            if currentTime
                != change.time
            {
                currentTime =
                    change.time

                text += "#"
                text += String(
                    change.time
                )
                text += "\n"
            }

            switch change.value {

            case let .scalar(value):

                text +=
                    scalar(value)

                text +=
                    change.variable
                    .identifier
                    .rawValue

                text += "\n"

            case let .vector(value):

                text += "b"
                text += vector(value)
                text += " "
                text +=
                    change.variable
                    .identifier
                    .rawValue

                text += "\n"
            }
        }

        return text
    }
}

// ============================================================================
// MARK: - Switchboard VCD Layout
// ============================================================================

public enum SwitchboardVCDLayout {

    public static func variables()
        -> [VCDVariable]
    {
        var allocator =
            VCDSymbolAllocator()

        return [
            VCDVariable(
                signal:
                    SwitchboardRuntimeSignal.a,
                identifier:
                    allocator.next(),
                width: 4,
                reference: "a"
            ),

            VCDVariable(
                signal:
                    SwitchboardRuntimeSignal.b,
                identifier:
                    allocator.next(),
                width: 4,
                reference: "b"
            ),

            VCDVariable(
                signal:
                    SwitchboardRuntimeSignal.internalSum,
                identifier:
                    allocator.next(),
                width: 4,
                reference:
                    "sum_internal"
            ),

            VCDVariable(
                signal:
                    SwitchboardRuntimeSignal.outputSum,
                identifier:
                    allocator.next(),
                width: 4,
                reference:
                    "sum"
            ),

            VCDVariable(
                signal:
                    SwitchboardRuntimeSignal.c0,
                identifier:
                    allocator.next(),
                width: 1,
                reference: "c0"
            ),

            VCDVariable(
                signal:
                    SwitchboardRuntimeSignal.c1,
                identifier:
                    allocator.next(),
                width: 1,
                reference: "c1"
            ),

            VCDVariable(
                signal:
                    SwitchboardRuntimeSignal.c2,
                identifier:
                    allocator.next(),
                width: 1,
                reference: "c2"
            ),

            VCDVariable(
                signal:
                    SwitchboardRuntimeSignal.c3,
                identifier:
                    allocator.next(),
                width: 1,
                reference: "c3"
            ),

            VCDVariable(
                signal:
                    SwitchboardRuntimeSignal.overflow,
                identifier:
                    allocator.next(),
                width: 1,
                reference:
                    "overflow"
            ),

            VCDVariable(
                signal:
                    SwitchboardRuntimeSignal.enable,
                identifier:
                    allocator.next(),
                width: 1,
                reference:
                    "enable"
            )
        ]
    }
}

// ============================================================================
// MARK: - SPICE Voltage Levels
// ============================================================================

public struct SPICELogicLevels:
    Sendable
{
    public let low:
        Double

    public let high:
        Double

    public init(
        low: Double = 0.0,
        high: Double = 1.8
    ) {
        precondition(
            high > low
        )

        self.low = low
        self.high = high
    }
}

// ============================================================================
// MARK: - Digital Stimulus Point
// ============================================================================

public struct DigitalStimulusPoint:
    Sendable
{
    public let time:
        HDLTime

    public let value:
        Logic

    public init(
        time: HDLTime,
        value: Logic
    ) {
        self.time = time
        self.value = value
    }
}

// ============================================================================
// MARK: - SPICE PWL Generator
// ============================================================================

public enum SPICEPWLGenerator {

    public static func voltage(
        for logic: Logic,
        levels: SPICELogicLevels
    ) -> Double {

        switch logic {

        case .zero:
            return levels.low

        case .one:
            return levels.high

        case .x:
            return
                (
                    levels.low
                    + levels.high
                )
                / 2.0

        case .z:
            return levels.low
        }
    }

    public static func source(
        name: String,
        node: String,
        points: [DigitalStimulusPoint],
        levels: SPICELogicLevels =
            SPICELogicLevels()
    ) -> String {

        var text =
            "V\(name) \(node) 0 PWL("

        let ordered =
            points.sorted {
                $0.time < $1.time
            }

        for (
            index,
            point
        ) in ordered.enumerated() {

            if index > 0 {
                text += " "
            }

            let seconds =
                Double(
                    point.time
                    .femtoseconds
                )
                * 1e-15

            let volt =
                voltage(
                    for: point.value,
                    levels: levels
                )

            text += String(
                format: "%.15g",
                seconds
            )

            text += " "

            text += String(
                format: "%.6g",
                volt
            )
        }

        text += ")"

        return text
    }
}

// ============================================================================
// MARK: - SPICE Measurement Assertion
// ============================================================================

public struct SPICEMeasurement:
    Sendable
{
    public let name: String
    public let expression: String
    public let from: HDLTime
    public let to: HDLTime

    public init(
        name: String,
        expression: String,
        from: HDLTime,
        to: HDLTime
    ) {
        self.name = name
        self.expression = expression
        self.from = from
        self.to = to
    }

    public var spice: String {

        let fromSeconds =
            Double(from.femtoseconds) * 1e-15

        let toSeconds =
            Double(to.femtoseconds) * 1e-15

        return String(
            format:
                ".meas tran %@ %@ from=%.15g to=%.15g",
            name,
            expression,
            fromSeconds,
            toSeconds
        )
    }
}

// ============================================================================
// MARK: - Logical / Physical Provenance Link
// ============================================================================

public struct ProvenanceLink:
    Sendable
{
    public let logicalSignal:
        RuntimeSignalID

    public let physicalNet:
        PhysicalNet

    public let direction:
        PinDirection

    public let source:
        GraphNodeID?

    public init(
        logicalSignal: RuntimeSignalID,
        physicalNet: PhysicalNet,
        direction: PinDirection,
        source: GraphNodeID? = nil
    ) {
        self.logicalSignal =
            logicalSignal
        self.physicalNet =
            physicalNet
        self.direction =
            direction
        self.source =
            source
    }
}

// ============================================================================
// MARK: - Switchboard Provenance Map
// ============================================================================

public enum SwitchboardProvenanceMap {

    public static func build()
        -> [ProvenanceLink]
    {
        [
            ProvenanceLink(
                logicalSignal:
                    SwitchboardRuntimeSignal.a,
                physicalNet:
                    PhysicalNet("A0"),
                direction: .input
            ),
            ProvenanceLink(
                logicalSignal:
                    SwitchboardRuntimeSignal.b,
                physicalNet:
                    PhysicalNet("B0"),
                direction: .input
            ),
            ProvenanceLink(
                logicalSignal:
                    SwitchboardRuntimeSignal.outputSum,
                physicalNet:
                    PhysicalNet("S0"),
                direction: .output
            ),
            ProvenanceLink(
                logicalSignal:
                    SwitchboardRuntimeSignal.overflow,
                physicalNet:
                    PhysicalNet("C3"),
                direction: .output
            ),
            ProvenanceLink(
                logicalSignal:
                    SwitchboardRuntimeSignal.c0,
                physicalNet:
                    PhysicalNet("C0"),
                direction: .output
            ),
            ProvenanceLink(
                logicalSignal:
                    SwitchboardRuntimeSignal.c1,
                physicalNet:
                    PhysicalNet("C1"),
                direction: .output
            ),
            ProvenanceLink(
                logicalSignal:
                    SwitchboardRuntimeSignal.c2,
                physicalNet:
                    PhysicalNet("C2"),
                direction: .output
            ),
            ProvenanceLink(
                logicalSignal:
                    SwitchboardRuntimeSignal.c3,
                physicalNet:
                    PhysicalNet("C3"),
                direction: .output
            )
        ]
    }
}
