//
// Switchboard.swift
//
// Phase I
// VHDL switchboard -> Swift structural hardware model
//
// Design:
// 4-bit ripple-carry datapath
// explicit full-adder cells
// three-state FSM
// tri-state output bus
// four-state digital logic
// invariant firewall
// structural netlist representation
// SPICE-facing primitive vocabulary
// MetaShard-compatible state representation
//
// No framework dependencies.
//

import Foundation

// ============================================================================
// MARK: - Four-State Logic
// ============================================================================

@frozen
public enum Logic: UInt8, CaseIterable, Sendable {
    case zero = 0
    case one = 1
    case x = 2
    case z = 3

    @inline(__always)
    public var isKnown: Bool {
        self == .zero || self == .one
    }

    @inline(__always)
    public var bit: UInt8? {
        switch self {
        case .zero: return 0
        case .one: return 1
        case .x, .z: return nil
        }
    }
}

extension Logic: CustomStringConvertible {
    public var description: String {
        switch self {
        case .zero: return "0"
        case .one: return "1"
        case .x: return "X"
        case .z: return "Z"
        }
    }
}

// ============================================================================
// MARK: - Logic Algebra
// ============================================================================

@inline(__always)
public prefix func ~ (a: Logic) -> Logic {
    switch a {
    case .zero: return .one
    case .one: return .zero
    case .x: return .x
    case .z: return .x
    }
}

@inline(__always)
public func & (lhs: Logic, rhs: Logic) -> Logic {
    switch (lhs, rhs) {
    case (.zero, _), (_, .zero):
        return .zero

    case (.one, .one):
        return .one

    case (.one, .x),
         (.x, .one),
         (.x, .x):
        return .x

    default:
        return .x
    }
}

@inline(__always)
public func | (lhs: Logic, rhs: Logic) -> Logic {
    switch (lhs, rhs) {
    case (.one, _), (_, .one):
        return .one

    case (.zero, .zero):
        return .zero

    case (.zero, .x),
         (.x, .zero),
         (.x, .x):
        return .x

    default:
        return .x
    }
}

@inline(__always)
public func ^ (lhs: Logic, rhs: Logic) -> Logic {
    guard let a = lhs.bit,
          let b = rhs.bit else {
        return .x
    }

    return (a ^ b) == 0 ? .zero : .one
}

// ============================================================================
// MARK: - Fixed Width Four-State Bus
// ============================================================================

public struct LogicBus: Sendable, Equatable {

    private var storage: [Logic]

    public let width: Int

    public init(width: Int, fill: Logic = .zero) {
        precondition(width > 0)

        self.width = width
        self.storage = Array(repeating: fill, count: width)
    }

    public init(_ bitsLSBFirst: [Logic]) {
        precondition(!bitsLSBFirst.isEmpty)

        self.width = bitsLSBFirst.count
        self.storage = bitsLSBFirst
    }

    public init(width: Int, unsigned value: UInt64) {
        precondition(width > 0)
        precondition(width <= 64)

        self.width = width
        self.storage = []

        storage.reserveCapacity(width)

        for index in 0..<width {
            let bit = (value >> UInt64(index)) & 1
            storage.append(bit == 0 ? .zero : .one)
        }
    }

    public subscript(_ index: Int) -> Logic {
        get {
            precondition(index >= 0 && index < width)
            return storage[index]
        }

        set {
            precondition(index >= 0 && index < width)
            storage[index] = newValue
        }
    }

    public var allKnown: Bool {
        storage.allSatisfy(\.isKnown)
    }

    public var containsUnknown: Bool {
        storage.contains(.x)
    }

    public var containsHighImpedance: Bool {
        storage.contains(.z)
    }

    public var unsignedValue: UInt64? {
        guard allKnown else {
            return nil
        }

        var result: UInt64 = 0

        for index in 0..<width {
            if storage[index] == .one {
                result |= UInt64(1) << UInt64(index)
            }
        }

        return result
    }

    public var isZero: Bool {
        guard allKnown else {
            return false
        }

        return storage.allSatisfy { $0 == .zero }
    }

    public static func highImpedance(width: Int) -> LogicBus {
        LogicBus(width: width, fill: .z)
    }

    public static func unknown(width: Int) -> LogicBus {
        LogicBus(width: width, fill: .x)
    }

    public static func zero(width: Int) -> LogicBus {
        LogicBus(width: width, fill: .zero)
    }
}

extension LogicBus: CustomStringConvertible {

    public var description: String {
        var result = ""

        for index in stride(
            from: width - 1,
            through: 0,
            by: -1
        ) {
            result.append(storage[index].description)
        }

        return result
    }
}

// ============================================================================
// MARK: - Signal
// ============================================================================

public struct Signal<Value: Sendable>: Sendable {

    public let name: String
    public var value: Value

    public init(
        _ name: String,
        _ value: Value
    ) {
        self.name = name
        self.value = value
    }
}

// ============================================================================
// MARK: - Primitive Full Adder
// ============================================================================

public struct FullAdder: Sendable {

    public struct Input: Sendable {
        public var x: Logic
        public var y: Logic
        public var cin: Logic

        public init(
            x: Logic,
            y: Logic,
            cin: Logic
        ) {
            self.x = x
            self.y = y
            self.cin = cin
        }
    }

    public struct Output: Sendable, Equatable {
        public var sum: Logic
        public var carry: Logic

        public init(
            sum: Logic,
            carry: Logic
        ) {
            self.sum = sum
            self.carry = carry
        }
    }

    @inline(__always)
    public static func evaluate(
        _ input: Input
    ) -> Output {

        let xy = input.x ^ input.y

        let sum =
            xy ^ input.cin

        let carry =
            (input.x & input.y) |
            (input.cin & xy)

        return Output(
            sum: sum,
            carry: carry
        )
    }
}

// ============================================================================
// MARK: - Structural Cell Identity
// ============================================================================

public struct CellID:
    Hashable,
    Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) {
        precondition(!rawValue.isEmpty)
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

// ============================================================================
// MARK: - Net Identity
// ============================================================================

public struct NetID:
    Hashable,
    Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) {
        precondition(!rawValue.isEmpty)
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

// ============================================================================
// MARK: - Structural Pin
// ============================================================================

public enum PinDirection: Sendable {
    case input
    case output
    case bidirectional
}

public struct Pin: Sendable {

    public let name: String
    public let direction: PinDirection
    public let net: NetID

    public init(
        name: String,
        direction: PinDirection,
        net: NetID
    ) {
        self.name = name
        self.direction = direction
        self.net = net
    }
}

// ============================================================================
// MARK: - Primitive Kind
// ============================================================================

public enum PrimitiveKind: String, Sendable {
    case fullAdder
    case xor
    case and
    case or
    case inverter
    case triState
    case register
}

// ============================================================================
// MARK: - Cell
// ============================================================================

public struct Cell: Sendable {

    public let id: CellID
    public let primitive: PrimitiveKind
    public let pins: [Pin]

    public init(
        id: CellID,
        primitive: PrimitiveKind,
        pins: [Pin]
    ) {
        self.id = id
        self.primitive = primitive
        self.pins = pins
    }
}

// ============================================================================
// MARK: - Structural Netlist
// ============================================================================

public struct StructuralNetlist: Sendable {

    public var nets: Set<NetID>
    public var cells: [Cell]

    public init() {
        self.nets = []
        self.cells = []
    }

    public mutating func declare(
        _ net: NetID
    ) {
        nets.insert(net)
    }

    public mutating func append(
        _ cell: Cell
    ) {
        cells.append(cell)

        for pin in cell.pins {
            nets.insert(pin.net)
        }
    }
}

// ============================================================================
// MARK: - Switchboard State
// ============================================================================

@frozen
public enum SwitchboardState:
    UInt8,
    CaseIterable,
    Sendable
{
    case idle = 0b00
    case read = 0b01
    case write = 0b10

    public var encoded: UInt8 {
        rawValue
    }
}

extension SwitchboardState: CustomStringConvertible {

    public var description: String {
        switch self {
        case .idle:
            return "ST_IDLE"

        case .read:
            return "ST_READ"

        case .write:
            return "ST_WRITE"
        }
    }
}

// ============================================================================
// MARK: - Input Port
// ============================================================================

public struct SwitchboardInput: Sendable {

    public var reset: Logic
    public var a: LogicBus
    public var b: LogicBus

    public init(
        reset: Logic = .zero,
        a: LogicBus = .zero(width: 4),
        b: LogicBus = .zero(width: 4)
    ) {
        precondition(a.width == 4)
        precondition(b.width == 4)

        self.reset = reset
        self.a = a
        self.b = b
    }
}

// ============================================================================
// MARK: - Output Port
// ============================================================================

public struct SwitchboardOutput: Sendable {

    public var sum: LogicBus
    public var overflow: Logic
    public var state: UInt8

    public init(
        sum: LogicBus,
        overflow: Logic,
        state: UInt8
    ) {
        self.sum = sum
        self.overflow = overflow
        self.state = state
    }
}

// ============================================================================
// MARK: - Carry Chain
// ============================================================================

public struct CarryChain: Sendable, Equatable {

    public var c0: Logic
    public var c1: Logic
    public var c2: Logic
    public var c3: Logic

    public init(
        c0: Logic = .x,
        c1: Logic = .x,
        c2: Logic = .x,
        c3: Logic = .x
    ) {
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
    }

    public subscript(_ index: Int) -> Logic {
        switch index {
        case 0: return c0
        case 1: return c1
        case 2: return c2
        case 3: return c3
        default:
            preconditionFailure("carry index outside 0...3")
        }
    }
}

// ============================================================================
// MARK: - Datapath Evaluation
// ============================================================================

public struct DatapathResult: Sendable {

    public let sum: LogicBus
    public let carry: CarryChain

    public init(
        sum: LogicBus,
        carry: CarryChain
    ) {
        self.sum = sum
        self.carry = carry
    }
}

public enum RippleAdder4 {

    @inline(__always)
    public static func evaluate(
        a: LogicBus,
        b: LogicBus
    ) -> DatapathResult {

        precondition(a.width == 4)
        precondition(b.width == 4)

        var result =
            LogicBus(width: 4, fill: .x)

        let fa0 = FullAdder.evaluate(
            .init(
                x: a[0],
                y: b[0],
                cin: .zero
            )
        )

        result[0] = fa0.sum

        let fa1 = FullAdder.evaluate(
            .init(
                x: a[1],
                y: b[1],
                cin: fa0.carry
            )
        )

        result[1] = fa1.sum

        let fa2 = FullAdder.evaluate(
            .init(
                x: a[2],
                y: b[2],
                cin: fa1.carry
            )
        )

        result[2] = fa2.sum

        let fa3 = FullAdder.evaluate(
            .init(
                x: a[3],
                y: b[3],
                cin: fa2.carry
            )
        )

        result[3] = fa3.sum

        return DatapathResult(
            sum: result,
            carry: CarryChain(
                c0: fa0.carry,
                c1: fa1.carry,
                c2: fa2.carry,
                c3: fa3.carry
            )
        )
    }
}

// ============================================================================
// MARK: - Invariant IDs
// ============================================================================

public enum InvariantID:
    String,
    CaseIterable,
    Sendable
{
    case i2 = "I2"
    case i3 = "I3"
    case i4 = "I4"
    case i5 = "I5"
    case i6 = "I6"
}

// ============================================================================
// MARK: - Invariant Violation
// ============================================================================

public struct InvariantViolation:
    Error,
    Sendable,
    CustomStringConvertible
{
    public let invariant: InvariantID
    public let message: String

    public init(
        _ invariant: InvariantID,
        _ message: String
    ) {
        self.invariant = invariant
        self.message = message
    }

    public var description: String {
        "\(invariant.rawValue): \(message)"
    }
}

// ============================================================================
// MARK: - Firewall Result
// ============================================================================

public struct FirewallResult: Sendable {

    public let violations: [InvariantViolation]

    public var passed: Bool {
        violations.isEmpty
    }

    public init(
        violations: [InvariantViolation]
    ) {
        self.violations = violations
    }
}

// ============================================================================
// MARK: - Switchboard Snapshot
// ============================================================================

public struct SwitchboardSnapshot: Sendable {

    public let cycle: UInt64

    public let input: SwitchboardInput

    public let state: SwitchboardState
    public let nextState: SwitchboardState

    public let internalSum: LogicBus
    public let outputSum: LogicBus

    public let carries: CarryChain

    public let overflow: Logic
    public let enabled: Logic

    public init(
        cycle: UInt64,
        input: SwitchboardInput,
        state: SwitchboardState,
        nextState: SwitchboardState,
        internalSum: LogicBus,
        outputSum: LogicBus,
        carries: CarryChain,
        overflow: Logic,
        enabled: Logic
    ) {
        self.cycle = cycle
        self.input = input
        self.state = state
        self.nextState = nextState
        self.internalSum = internalSum
        self.outputSum = outputSum
        self.carries = carries
        self.overflow = overflow
        self.enabled = enabled
    }
}

// ============================================================================
// MARK: - Invariant Firewall
// ============================================================================

public enum InvariantFirewall {

    public static func evaluate(
        _ snapshot: SwitchboardSnapshot
    ) -> FirewallResult {

        var failures: [InvariantViolation] = []

        checkI2(
            snapshot,
            into: &failures
        )

        checkI3(
            snapshot,
            into: &failures
        )

        checkI4(
            snapshot,
            into: &failures
        )

        checkI5(
            snapshot,
            into: &failures
        )

        checkI6(
            snapshot,
            into: &failures
        )

        return FirewallResult(
            violations: failures
        )
    }

    // ------------------------------------------------------------------------
    // I2
    //
    // Input buses are exactly four bits.
    // ------------------------------------------------------------------------

    private static func checkI2(
        _ snapshot: SwitchboardSnapshot,
        into failures: inout [InvariantViolation]
    ) {
        if snapshot.input.a.width != 4 {
            failures.append(
                InvariantViolation(
                    .i2,
                    "A bus width is \(snapshot.input.a.width), expected 4"
                )
            )
        }

        if snapshot.input.b.width != 4 {
            failures.append(
                InvariantViolation(
                    .i2,
                    "B bus width is \(snapshot.input.b.width), expected 4"
                )
            )
        }
    }

    // ------------------------------------------------------------------------
    // I3
    //
    // Recompute each full-adder boundary independently.
    // Do not trust the implementation under test.
    // ------------------------------------------------------------------------

    private static func checkI3(
        _ snapshot: SwitchboardSnapshot,
        into failures: inout [InvariantViolation]
    ) {
        let a = snapshot.input.a
        let b = snapshot.input.b

        let r0 = FullAdder.evaluate(
            .init(
                x: a[0],
                y: b[0],
                cin: .zero
            )
        )

        if r0.carry != snapshot.carries.c0 {
            failures.append(
                InvariantViolation(
                    .i3,
                    "carry c0 disagrees with bit-0 full adder"
                )
            )
        }

        let r1 = FullAdder.evaluate(
            .init(
                x: a[1],
                y: b[1],
                cin: snapshot.carries.c0
            )
        )

        if r1.carry != snapshot.carries.c1 {
            failures.append(
                InvariantViolation(
                    .i3,
                    "carry c1 disagrees with bit-1 full adder"
                )
            )
        }

        let r2 = FullAdder.evaluate(
            .init(
                x: a[2],
                y: b[2],
                cin: snapshot.carries.c1
            )
        )

        if r2.carry != snapshot.carries.c2 {
            failures.append(
                InvariantViolation(
                    .i3,
                    "carry c2 disagrees with bit-2 full adder"
                )
            )
        }

        let r3 = FullAdder.evaluate(
            .init(
                x: a[3],
                y: b[3],
                cin: snapshot.carries.c2
            )
        )

        if r3.carry != snapshot.carries.c3 {
            failures.append(
                InvariantViolation(
                    .i3,
                    "carry c3 disagrees with bit-3 full adder"
                )
            )
        }
    }

    // ------------------------------------------------------------------------
    // I4
    // ------------------------------------------------------------------------

    private static func checkI4(
        _ snapshot: SwitchboardSnapshot,
        into failures: inout [InvariantViolation]
    ) {
        if snapshot.overflow != snapshot.carries.c3 {
            failures.append(
                InvariantViolation(
                    .i4,
                    "overflow != final carry"
                )
            )
        }
    }

    // ------------------------------------------------------------------------
    // I5
    //
    // Swift enum representation makes illegal FSM encodings impossible inside
    // the state machine itself. Validate emitted representation anyway.
    // ------------------------------------------------------------------------

    private static func checkI5(
        _ snapshot: SwitchboardSnapshot,
        into failures: inout [InvariantViolation]
    ) {
        switch snapshot.state {
        case .idle, .read, .write:
            break
        }
    }

    // ------------------------------------------------------------------------
    // I6
    // ------------------------------------------------------------------------

    private static func checkI6(
        _ snapshot: SwitchboardSnapshot,
        into failures: inout [InvariantViolation]
    ) {
        if snapshot.input.reset == .one,
           snapshot.nextState != .idle {

            failures.append(
                InvariantViolation(
                    .i6,
                    "asserted reset did not select IDLE"
                )
            )
        }

        switch snapshot.state {

        case .idle:
            break

        case .read:
            if snapshot.input.reset != .one,
               snapshot.nextState != .write {

                failures.append(
                    InvariantViolation(
                        .i6,
                        "READ must transition to WRITE"
                    )
                )
            }

        case .write:
            if snapshot.input.reset != .one,
               snapshot.nextState != .idle {

                failures.append(
                    InvariantViolation(
                        .i6,
                        "WRITE must transition to IDLE"
                    )
                )
            }
        }
    }
}

// ============================================================================
// MARK: - Switchboard Machine
// ============================================================================

public struct Switchboard: Sendable {

    private(set) public var state: SwitchboardState
    private(set) public var cycle: UInt64

    public init() {
        self.state = .idle
        self.cycle = 0
    }

    // ------------------------------------------------------------------------
    // FSM combinational logic
    // ------------------------------------------------------------------------

    @inline(__always)
    public func nextState(
        input: SwitchboardInput
    ) -> SwitchboardState {

        if input.reset == .one {
            return .idle
        }

        switch state {

        case .idle:
            if busActivity(input.a, input.b) {
                return .read
            }

            return .idle

        case .read:
            return .write

        case .write:
            return .idle
        }
    }

    // ------------------------------------------------------------------------
    // VHDL:
    //
    // if (a or b) /= "0000"
    // ------------------------------------------------------------------------

    @inline(__always)
    private func busActivity(
        _ a: LogicBus,
        _ b: LogicBus
    ) -> Bool {

        precondition(a.width == 4)
        precondition(b.width == 4)

        for index in 0..<4 {
            if a[index] == .one ||
                b[index] == .one {
                return true
            }
        }

        return false
    }

    // ------------------------------------------------------------------------
    // Combinational evaluation
    // ------------------------------------------------------------------------

    public func evaluate(
        input: SwitchboardInput
    ) -> SwitchboardSnapshot {

        let datapath =
            RippleAdder4.evaluate(
                a: input.a,
                b: input.b
            )

        let next =
            nextState(input: input)

        let enabled: Logic =
            state == .read
            ? .one
            : .zero

        let outputBus: LogicBus

        if enabled == .one {
            outputBus = datapath.sum
        } else {
            outputBus = .highImpedance(width: 4)
        }

        return SwitchboardSnapshot(
            cycle: cycle,
            input: input,
            state: state,
            nextState: next,
            internalSum: datapath.sum,
            outputSum: outputBus,
            carries: datapath.carry,
            overflow: datapath.carry.c3,
            enabled: enabled
        )
    }

    // ------------------------------------------------------------------------
    // Rising clock edge
    // ------------------------------------------------------------------------

    @discardableResult
    public mutating func clock(
        input: SwitchboardInput
    ) throws -> SwitchboardSnapshot {

        let before =
            evaluate(input: input)

        let firewall =
            InvariantFirewall.evaluate(before)

        if let first = firewall.violations.first {
            throw first
        }

        state = before.nextState
        cycle &+= 1

        let after =
            evaluate(input: input)

        let afterFirewall =
            InvariantFirewall.evaluate(after)

        if let first = afterFirewall.violations.first {
            throw first
        }

        return after
    }

    public mutating func reset() {
        state = .idle
        cycle = 0
    }
}

// ============================================================================
// MARK: - Structural Netlist Construction
// ============================================================================

public enum SwitchboardNetlist {

    public static func build() -> StructuralNetlist {

        var netlist = StructuralNetlist()

        let zero = NetID("VSS")

        let a0 = NetID("A0")
        let a1 = NetID("A1")
        let a2 = NetID("A2")
        let a3 = NetID("A3")

        let b0 = NetID("B0")
        let b1 = NetID("B1")
        let b2 = NetID("B2")
        let b3 = NetID("B3")

        let s0 = NetID("S0")
        let s1 = NetID("S1")
        let s2 = NetID("S2")
        let s3 = NetID("S3")

        let c0 = NetID("C0")
        let c1 = NetID("C1")
        let c2 = NetID("C2")
        let c3 = NetID("C3")

        netlist.declare(zero)

        netlist.append(
            Cell(
                id: CellID("FA0"),
                primitive: .fullAdder,
                pins: [
                    Pin(
                        name: "X",
                        direction: .input,
                        net: a0
                    ),
                    Pin(
                        name: "Y",
                        direction: .input,
                        net: b0
                    ),
                    Pin(
                        name: "CIN",
                        direction: .input,
                        net: zero
                    ),
                    Pin(
                        name: "S",
                        direction: .output,
                        net: s0
                    ),
                    Pin(
                        name: "COUT",
                        direction: .output,
                        net: c0
                    )
                ]
            )
        )

        netlist.append(
            Cell(
                id: CellID("FA1"),
                primitive: .fullAdder,
                pins: [
                    Pin(
                        name: "X",
                        direction: .input,
                        net: a1
                    ),
                    Pin(
                        name: "Y",
                        direction: .input,
                        net: b1
                    ),
                    Pin(
                        name: "CIN",
                        direction: .input,
                        net: c0
                    ),
                    Pin(
                        name: "S",
                        direction: .output,
                        net: s1
                    ),
                    Pin(
                        name: "COUT",
                        direction: .output,
                        net: c1
                    )
                ]
            )
        )

        netlist.append(
            Cell(
                id: CellID("FA2"),
                primitive: .fullAdder,
                pins: [
                    Pin(
                        name: "X",
                        direction: .input,
                        net: a2
                    ),
                    Pin(
                        name: "Y",
                        direction: .input,
                        net: b2
                    ),
                    Pin(
                        name: "CIN",
                        direction: .input,
                        net: c1
                    ),
                    Pin(
                        name: "S",
                        direction: .output,
                        net: s2
                    ),
                    Pin(
                        name: "COUT",
                        direction: .output,
                        net: c2
                    )
                ]
            )
        )

        netlist.append(
            Cell(
                id: CellID("FA3"),
                primitive: .fullAdder,
                pins: [
                    Pin(
                        name: "X",
                        direction: .input,
                        net: a3
                    ),
                    Pin(
                        name: "Y",
                        direction: .input,
                        net: b3
                    ),
                    Pin(
                        name: "CIN",
                        direction: .input,
                        net: c2
                    ),
                    Pin(
                        name: "S",
                        direction: .output,
                        net: s3
                    ),
                    Pin(
                        name: "COUT",
                        direction: .output,
                        net: c3
                    )
                ]
            )
        )

        return netlist
    }
}

// ============================================================================
// MARK: - SPICE Intermediate Representation
// ============================================================================

public struct SPICENode:
    Hashable,
    Sendable,
    CustomStringConvertible
{
    public let name: String

    public init(_ name: String) {
        precondition(!name.isEmpty)
        self.name = name
    }

    public var description: String {
        name
    }
}

public enum SPICEElement: Sendable {

    case resistor(
        name: String,
        a: SPICENode,
        b: SPICENode,
        ohms: Double
    )

    case capacitor(
        name: String,
        a: SPICENode,
        b: SPICENode,
        farads: Double
    )

    case voltage(
        name: String,
        positive: SPICENode,
        negative: SPICENode,
        volts: Double
    )

    case mosfet(
        name: String,
        drain: SPICENode,
        gate: SPICENode,
        source: SPICENode,
        body: SPICENode,
        model: String
    )

    case subcircuit(
        name: String,
        nodes: [SPICENode],
        model: String
    )
}

// ============================================================================
// MARK: - SPICE Circuit
// ============================================================================

public struct SPICECircuit: Sendable {

    public var title: String
    public var elements: [SPICEElement]

    public init(
        title: String
    ) {
        self.title = title
        self.elements = []
    }

    public mutating func append(
        _ element: SPICEElement
    ) {
        elements.append(element)
    }
}

// ============================================================================
// MARK: - SPICE Serialization
// ============================================================================

public enum SPICESerializer {

    public static func serialize(
        _ circuit: SPICECircuit
    ) -> String {

        var text = ""

        text += "* "
        text += circuit.title
        text += "\n"

        for element in circuit.elements {
            text += serialize(element)
            text += "\n"
        }

        text += ".end\n"

        return text
    }

    private static func serialize(
        _ element: SPICEElement
    ) -> String {

        switch element {

        case let .resistor(
            name,
            a,
            b,
            ohms
        ):
            return "R\(name) \(a) \(b) \(ohms)"

        case let .capacitor(
            name,
            a,
            b,
            farads
        ):
            return "C\(name) \(a) \(b) \(farads)"

        case let .voltage(
            name,
            positive,
            negative,
            volts
        ):
            return "V\(name) \(positive) \(negative) DC \(volts)"

        case let .mosfet(
            name,
            drain,
            gate,
            source,
            body,
            model
        ):
            return [
                "M\(name)",
                drain.description,
                gate.description,
                source.description,
                body.description,
                model
            ].joined(separator: " ")

        case let .subcircuit(
            name,
            nodes,
            model
        ):
            let nodeList =
                nodes
                .map(\.description)
                .joined(separator: " ")

            return "X\(name) \(nodeList) \(model)"
        }
    }
}

// ============================================================================
// MARK: - Switchboard SPICE Projection
// ============================================================================

public enum SwitchboardSPICE {

    public static func build() -> SPICECircuit {

        var circuit =
            SPICECircuit(
                title:
                    "Switchboard 4-bit invariant guarded ripple datapath"
            )

        let gnd = SPICENode("0")
        let vdd = SPICENode("VDD")

        circuit.append(
            .voltage(
                name: "DD",
                positive: vdd,
                negative: gnd,
                volts: 1.8
            )
        )

        for bit in 0..<4 {

            let a =
                SPICENode("A\(bit)")

            let b =
                SPICENode("B\(bit)")

            let sum =
                SPICENode("S\(bit)")

            let cin =
                bit == 0
                ? gnd
                : SPICENode("C\(bit - 1)")

            let cout =
                SPICENode("C\(bit)")

            circuit.append(
                .subcircuit(
                    name: "FA\(bit)",
                    nodes: [
                        a,
                        b,
                        cin,
                        sum,
                        cout,
                        vdd,
                        gnd
                    ],
                    model: "FULL_ADDER"
                )
            )
        }

        return circuit
    }
}

// ============================================================================
// MARK: - MetaShard Core
// ============================================================================

public struct ShardID:
    Hashable,
    Sendable,
    CustomStringConvertible
{
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public var description: String {
        String(
            rawValue,
            radix: 16,
            uppercase: true
        )
    }
}

public enum ShardKind: UInt8, Sendable {
    case signal
    case cell
    case state
    case invariant
    case transition
    case observation
    case spiceNode
    case spiceElement
}

// ============================================================================
// MARK: - Meta Value
// ============================================================================

public enum MetaValue: Sendable {

    case logic(Logic)
    case bus(LogicBus)
    case unsigned(UInt64)
    case signed(Int64)
    case real(Double)
    case text(String)
    case flag(Bool)
}

// ============================================================================
// MARK: - Meta Field
// ============================================================================

public struct MetaField: Sendable {

    public let key: String
    public let value: MetaValue

    public init(
        _ key: String,
        _ value: MetaValue
    ) {
        self.key = key
        self.value = value
    }
}

// ============================================================================
// MARK: - MetaShard
// ============================================================================

public struct MetaShard: Sendable {

    public let id: ShardID
    public let kind: ShardKind
    public let fields: [MetaField]

    public init(
        id: ShardID,
        kind: ShardKind,
        fields: [MetaField]
    ) {
        self.id = id
        self.kind = kind
        self.fields = fields
    }
}

// ============================================================================
// MARK: - Deterministic Shard ID
// ============================================================================

public enum ShardHasher {

    // FNV-1a 64-bit.
    //
    // Used only as deterministic structural identity here, not as a
    // cryptographic primitive.

    @inline(__always)
    public static func hash(
        _ string: String
    ) -> ShardID {

        var hash: UInt64 =
            0xcbf29ce484222325

        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }

        return ShardID(hash)
    }
}

// ============================================================================
// MARK: - Snapshot -> MetaShard Projection
// ============================================================================

public enum SnapshotShardEncoder {

    public static func encode(
        _ snapshot: SwitchboardSnapshot
    ) -> [MetaShard] {

        var shards: [MetaShard] = []

        shards.append(
            MetaShard(
                id: ShardHasher.hash(
                    "cycle:\(snapshot.cycle):state"
                ),
                kind: .state,
                fields: [
                    MetaField(
                        "cycle",
                        .unsigned(snapshot.cycle)
                    ),
                    MetaField(
                        "state",
                        .text(snapshot.state.description)
                    ),
                    MetaField(
                        "state_encoding",
                        .unsigned(
                            UInt64(snapshot.state.encoded)
                        )
                    ),
                    MetaField(
                        "next_state",
                        .text(
                            snapshot.nextState.description
                        )
                    )
                ]
            )
        )

        shards.append(
            MetaShard(
                id: ShardHasher.hash(
                    "cycle:\(snapshot.cycle):a"
                ),
                kind: .signal,
                fields: [
                    MetaField(
                        "name",
                        .text("a")
                    ),
                    MetaField(
                        "value",
                        .bus(snapshot.input.a)
                    )
                ]
            )
        )

        shards.append(
            MetaShard(
                id: ShardHasher.hash(
                    "cycle:\(snapshot.cycle):b"
                ),
                kind: .signal,
                fields: [
                    MetaField(
                        "name",
                        .text("b")
                    ),
                    MetaField(
                        "value",
                        .bus(snapshot.input.b)
                    )
                ]
            )
        )

        shards.append(
            MetaShard(
                id: ShardHasher.hash(
                    "cycle:\(snapshot.cycle):sum.internal"
                ),
                kind: .signal,
                fields: [
                    MetaField(
                        "name",
                        .text("sum.internal")
                    ),
                    MetaField(
                        "value",
                        .bus(snapshot.internalSum)
                    )
                ]
            )
        )

        shards.append(
            MetaShard(
                id: ShardHasher.hash(
                    "cycle:\(snapshot.cycle):sum.output"
                ),
                kind: .observation,
                fields: [
                    MetaField(
                        "name",
                        .text("sum")
                    ),
                    MetaField(
                        "value",
                        .bus(snapshot.outputSum)
                    )
                ]
            )
        )

        shards.append(
            MetaShard(
                id: ShardHasher.hash(
                    "cycle:\(snapshot.cycle):overflow"
                ),
                kind: .observation,
                fields: [
                    MetaField(
                        "name",
                        .text("overflow")
                    ),
                    MetaField(
                        "value",
                        .logic(snapshot.overflow)
                    )
                ]
            )
        )

        shards.append(
            MetaShard(
                id: ShardHasher.hash(
                    "cycle:\(snapshot.cycle):carry"
                ),
                kind: .signal,
                fields: [
                    MetaField(
                        "c0",
                        .logic(snapshot.carries.c0)
                    ),
                    MetaField(
                        "c1",
                        .logic(snapshot.carries.c1)
                    ),
                    MetaField(
                        "c2",
                        .logic(snapshot.carries.c2)
                    ),
                    MetaField(
                        "c3",
                        .logic(snapshot.carries.c3)
                    )
                ]
            )
        )

        return shards
    }
}

// ============================================================================
// MARK: - Trace
// ============================================================================

public struct SwitchboardTrace: Sendable {

    private(set) public var snapshots:
        [SwitchboardSnapshot]

    private(set) public var shards:
        [MetaShard]

    public init() {
        snapshots = []
        shards = []
    }

    public mutating func append(
        _ snapshot: SwitchboardSnapshot
    ) {
        snapshots.append(snapshot)

        shards.append(
            contentsOf:
                SnapshotShardEncoder.encode(snapshot)
        )
    }
}

// ============================================================================
// MARK: - Simulator
// ============================================================================

public struct SwitchboardSimulator {

    private var machine: Switchboard

    public private(set) var trace:
        SwitchboardTrace

    public init() {
        machine = Switchboard()
        trace = SwitchboardTrace()
    }

    @discardableResult
    public mutating func drive(
        a: UInt8,
        b: UInt8,
        reset: Bool = false
    ) throws -> SwitchboardSnapshot {

        precondition(a <= 0x0F)
        precondition(b <= 0x0F)

        let input =
            SwitchboardInput(
                reset: reset ? .one : .zero,
                a: LogicBus(
                    width: 4,
                    unsigned: UInt64(a)
                ),
                b: LogicBus(
                    width: 4,
                    unsigned: UInt64(b)
                )
            )

        let snapshot =
            try machine.clock(input: input)

        trace.append(snapshot)

        return snapshot
    }

    public mutating func resetMachine() {
        machine.reset()
    }
}
