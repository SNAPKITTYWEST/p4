//
// SwitchboardPhaseV.swift
//
// Phase V — Canonical IR / Equivalence Closure
//
// Requires Phase I–IV.
//
// CanonicalSwitchboardIR
// │
// ├──────────────► Swift executable model
// ├──────────────► MetaShard graph
// ├──────────────► VHDL
// ├──────────────► SPICE
// ├──────────────► manifest
// └──────────────► equivalence witnesses
//
// No backend owns topology.
// The IR owns topology.
//
// ============================================================================

import Foundation

// ============================================================================
// MARK: - Canonical Identity
// ============================================================================

public struct CanonicalID:
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
        lhs: CanonicalID,
        rhs: CanonicalID
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        rawValue
    }
}

// ============================================================================
// MARK: - Canonical Source Location
// ============================================================================

public struct CanonicalSourceLocation:
    Sendable,
    Equatable
{
    public let unit: String
    public let symbol: String

    public init(
        unit: String,
        symbol: String
    ) {
        self.unit = unit
        self.symbol = symbol
    }
}

// ============================================================================
// MARK: - Canonical Direction
// ============================================================================

public enum CanonicalDirection:
    UInt8,
    Sendable
{
    case input
    case output
    case internalSignal
}

// ============================================================================
// MARK: - Canonical Signal Type
// ============================================================================

public enum CanonicalSignalType:
    Sendable,
    Equatable
{
    case logic
    case vector(width: Int)
    case state
}

// ============================================================================
// MARK: - Canonical Signal
// ============================================================================

public struct CanonicalSignal:
    Sendable,
    Equatable
{
    public let id: CanonicalID
    public let direction: CanonicalDirection
    public let type: CanonicalSignalType
    public let source: CanonicalSourceLocation?

    public init(
        id: CanonicalID,
        direction: CanonicalDirection,
        type: CanonicalSignalType,
        source: CanonicalSourceLocation? = nil
    ) {
        self.id = id
        self.direction = direction
        self.type = type
        self.source = source
    }
}

// ============================================================================
// MARK: - Canonical State
// ============================================================================

public struct CanonicalState:
    Sendable,
    Equatable
{
    public let id: CanonicalID
    public let encoding: UInt8

    public init(
        id: CanonicalID,
        encoding: UInt8
    ) {
        self.id = id
        self.encoding = encoding
    }
}

// ============================================================================
// MARK: - Canonical Port Reference
// ============================================================================

public struct CanonicalPortReference:
    Hashable,
    Sendable,
    Equatable
{
    public let component: CanonicalID
    public let port: String

    public init(
        component: CanonicalID,
        port: String
    ) {
        self.component = component
        self.port = port
    }
}

// ============================================================================
// MARK: - Canonical Endpoint
// ============================================================================

public enum CanonicalEndpoint:
    Hashable,
    Sendable
{
    case signal(CanonicalID)
    case port(CanonicalPortReference)
    case constant(StdLogic)
}

// ============================================================================
// MARK: - Canonical Connection
// ============================================================================

public struct CanonicalConnection:
    Hashable,
    Sendable
{
    public let source: CanonicalEndpoint
    public let target: CanonicalEndpoint

    public init(
        source: CanonicalEndpoint,
        target: CanonicalEndpoint
    ) {
        self.source = source
        self.target = target
    }
}

// ============================================================================
// MARK: - Canonical Primitive
// ============================================================================

public enum CanonicalPrimitiveKind:
    String,
    Sendable
{
    case fullAdder
    case triState
    case stateRegister
    case stateDecoder
    case overflowAlias
}

// ============================================================================
// MARK: - Canonical Component
// ============================================================================

public struct CanonicalComponent:
    Sendable
{
    public let id: CanonicalID
    public let kind: CanonicalPrimitiveKind

    public init(
        id: CanonicalID,
        kind: CanonicalPrimitiveKind
    ) {
        self.id = id
        self.kind = kind
    }
}

// ============================================================================
// MARK: - Canonical Invariant Kind
// ============================================================================

public enum CanonicalInvariantKind:
    String,
    Sendable
{
    case width
    case carryChain
    case overflowAlias
    case legalState
    case reset
    case transition
    case structuralCardinality
}

// ============================================================================
// MARK: - Canonical Invariant
// ============================================================================

public struct CanonicalInvariant:
    Sendable
{
    public let id: CanonicalID
    public let kind: CanonicalInvariantKind
    public let description: String

    public init(
        id: CanonicalID,
        kind: CanonicalInvariantKind,
        description: String
    ) {
        self.id = id
        self.kind = kind
        self.description = description
    }
}

// ============================================================================
// MARK: - Canonical FSM Transition
// ============================================================================

public enum CanonicalTransitionCondition:
    Sendable,
    Equatable
{
    case always
    case anyInputNonZero
    case resetAsserted
}

// ============================================================================
// MARK: - Canonical Transition
// ============================================================================

public struct CanonicalTransition:
    Sendable,
    Equatable
{
    public let from: CanonicalID
    public let to: CanonicalID
    public let condition: CanonicalTransitionCondition
    public let priority: Int

    public init(
        from: CanonicalID,
        to: CanonicalID,
        condition: CanonicalTransitionCondition,
        priority: Int
    ) {
        self.from = from
        self.to = to
        self.condition = condition
        self.priority = priority
    }
}

// ============================================================================
// MARK: - Canonical IR
// ============================================================================

public struct CanonicalSwitchboardIR:
    Sendable
{
    public let name: String

    public let signals: [CanonicalSignal]
    public let states: [CanonicalState]
    public let components: [CanonicalComponent]
    public let connections: [CanonicalConnection]
    public let transitions: [CanonicalTransition]
    public let invariants: [CanonicalInvariant]

    public init(
        name: String,
        signals: [CanonicalSignal],
        states: [CanonicalState],
        components: [CanonicalComponent],
        connections: [CanonicalConnection],
        transitions: [CanonicalTransition],
        invariants: [CanonicalInvariant]
    ) {
        self.name = name
        self.signals = signals
        self.states = states
        self.components = components
        self.connections = connections
        self.transitions = transitions
        self.invariants = invariants
    }
}

// ============================================================================
// MARK: - Canonical IDs
// ============================================================================

public enum SwitchboardCanonicalID {

    // External ports

    public static let clk =
        CanonicalID("signal.clk")

    public static let reset =
        CanonicalID("signal.reset")

    public static let a =
        CanonicalID("signal.a")

    public static let b =
        CanonicalID("signal.b")

    public static let sum =
        CanonicalID("signal.sum")

    public static let overflow =
        CanonicalID("signal.overflow")

    public static let stateOutput =
        CanonicalID("signal.state")

    // Internal datapath

    public static let sInt =
        CanonicalID("signal.s_int")

    public static let c0 =
        CanonicalID("signal.c0")

    public static let c1 =
        CanonicalID("signal.c1")

    public static let c2 =
        CanonicalID("signal.c2")

    public static let c3 =
        CanonicalID("signal.c3")

    public static let enable =
        CanonicalID("signal.en")

    public static let stateRegister =
        CanonicalID("signal.st")

    public static let nextState =
        CanonicalID("signal.st_next")

    // Components

    public static let fa0 =
        CanonicalID("cell.fa0")

    public static let fa1 =
        CanonicalID("cell.fa1")

    public static let fa2 =
        CanonicalID("cell.fa2")

    public static let fa3 =
        CanonicalID("cell.fa3")

    public static let triState =
        CanonicalID("cell.tristate")

    public static let overflowAlias =
        CanonicalID("cell.overflow_alias")

    public static let fsmDecoder =
        CanonicalID("cell.fsm_decoder")

    public static let fsmRegister =
        CanonicalID("cell.fsm_register")

    // States

    public static let idle =
        CanonicalID("state.idle")

    public static let read =
        CanonicalID("state.read")

    public static let write =
        CanonicalID("state.write")
}

// ============================================================================
// MARK: - Canonical IR Factory
// ============================================================================

public enum CanonicalSwitchboardFactory {

    public static func build()
        -> CanonicalSwitchboardIR
    {
        let signals: [CanonicalSignal] = [

            CanonicalSignal(
                id: SwitchboardCanonicalID.clk,
                direction: .input,
                type: .logic
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.reset,
                direction: .input,
                type: .logic
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.a,
                direction: .input,
                type: .vector(width: 4)
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.b,
                direction: .input,
                type: .vector(width: 4)
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.sum,
                direction: .output,
                type: .vector(width: 4)
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.overflow,
                direction: .output,
                type: .logic
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.stateOutput,
                direction: .output,
                type: .vector(width: 2)
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.sInt,
                direction: .internalSignal,
                type: .vector(width: 4)
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.c0,
                direction: .internalSignal,
                type: .logic
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.c1,
                direction: .internalSignal,
                type: .logic
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.c2,
                direction: .internalSignal,
                type: .logic
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.c3,
                direction: .internalSignal,
                type: .logic
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.enable,
                direction: .internalSignal,
                type: .logic
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.stateRegister,
                direction: .internalSignal,
                type: .state
            ),

            CanonicalSignal(
                id: SwitchboardCanonicalID.nextState,
                direction: .internalSignal,
                type: .state
            )
        ]

        let states = [

            CanonicalState(
                id: SwitchboardCanonicalID.idle,
                encoding: 0b00
            ),

            CanonicalState(
                id: SwitchboardCanonicalID.read,
                encoding: 0b01
            ),

            CanonicalState(
                id: SwitchboardCanonicalID.write,
                encoding: 0b10
            )
        ]

        let components = [

            CanonicalComponent(
                id: SwitchboardCanonicalID.fa0,
                kind: .fullAdder
            ),

            CanonicalComponent(
                id: SwitchboardCanonicalID.fa1,
                kind: .fullAdder
            ),

            CanonicalComponent(
                id: SwitchboardCanonicalID.fa2,
                kind: .fullAdder
            ),

            CanonicalComponent(
                id: SwitchboardCanonicalID.fa3,
                kind: .fullAdder
            ),

            CanonicalComponent(
                id: SwitchboardCanonicalID.triState,
                kind: .triState
            ),

            CanonicalComponent(
                id: SwitchboardCanonicalID.overflowAlias,
                kind: .overflowAlias
            ),

            CanonicalComponent(
                id: SwitchboardCanonicalID.fsmDecoder,
                kind: .stateDecoder
            ),

            CanonicalComponent(
                id: SwitchboardCanonicalID.fsmRegister,
                kind: .stateRegister
            )
        ]

        let connections =
            buildConnections()

        let transitions = [

            CanonicalTransition(
                from: SwitchboardCanonicalID.idle,
                to: SwitchboardCanonicalID.read,
                condition: .anyInputNonZero,
                priority: 10
            ),

            CanonicalTransition(
                from: SwitchboardCanonicalID.read,
                to: SwitchboardCanonicalID.write,
                condition: .always,
                priority: 10
            ),

            CanonicalTransition(
                from: SwitchboardCanonicalID.write,
                to: SwitchboardCanonicalID.idle,
                condition: .always,
                priority: 10
            ),

            CanonicalTransition(
                from: SwitchboardCanonicalID.idle,
                to: SwitchboardCanonicalID.idle,
                condition: .resetAsserted,
                priority: 100
            ),

            CanonicalTransition(
                from: SwitchboardCanonicalID.read,
                to: SwitchboardCanonicalID.idle,
                condition: .resetAsserted,
                priority: 100
            ),

            CanonicalTransition(
                from: SwitchboardCanonicalID.write,
                to: SwitchboardCanonicalID.idle,
                condition: .resetAsserted,
                priority: 100
            )
        ]

        let invariants = [

            CanonicalInvariant(
                id: CanonicalID("I2"),
                kind: .width,
                description:
                    "A, B and SUM are exactly four bits."
            ),

            CanonicalInvariant(
                id: CanonicalID("I3"),
                kind: .carryChain,
                description:
                    "FA0.COUT→FA1.CIN→FA2.CIN→FA3.CIN."
            ),

            CanonicalInvariant(
                id: CanonicalID("I4"),
                kind: .overflowAlias,
                description:
                    "OVERFLOW aliases the final carry C3."
            ),

            CanonicalInvariant(
                id: CanonicalID("I5"),
                kind: .legalState,
                description:
                    "FSM is exactly IDLE, READ or WRITE."
            ),

            CanonicalInvariant(
                id: CanonicalID("I6"),
                kind: .reset,
                description:
                    "Reset forces IDLE."
            ),

            CanonicalInvariant(
                id: CanonicalID("I6.TRANSITION"),
                kind: .transition,
                description:
                    "IDLE→READ→WRITE→IDLE transition structure."
            ),

            CanonicalInvariant(
                id: CanonicalID("STRUCTURE.FA"),
                kind: .structuralCardinality,
                description:
                    "Exactly four full-adder cells exist."
            )
        ]

        return CanonicalSwitchboardIR(
            name: "switchboard",
            signals: signals,
            states: states,
            components: components,
            connections: connections,
            transitions: transitions,
            invariants: invariants
        )
    }

    private static func buildConnections()
        -> [CanonicalConnection]
    {
        var c: [CanonicalConnection] = []

        // FA0

        c.append(
            .init(
                source:
                    .signal(
                        SwitchboardCanonicalID.a
                    ),
                target:
                    .port(
                        .init(
                            component:
                                SwitchboardCanonicalID.fa0,
                            port: "X[0]"
                        )
                    )
            )
        )

        c.append(
            .init(
                source:
                    .signal(
                        SwitchboardCanonicalID.b
                    ),
                target:
                    .port(
                        .init(
                            component:
                                SwitchboardCanonicalID.fa0,
                            port: "Y[0]"
                        )
                    )
            )
        )

        c.append(
            .init(
                source: .constant(.zero),
                target:
                    .port(
                        .init(
                            component:
                                SwitchboardCanonicalID.fa0,
                            port: "CIN"
                        )
                    )
            )
        )

        c.append(
            .init(
                source:
                    .port(
                        .init(
                            component:
                                SwitchboardCanonicalID.fa0,
                            port: "COUT"
                        )
                    ),
                target:
                    .signal(
                        SwitchboardCanonicalID.c0
                    )
            )
        )

        // FA1

        c.append(
            .init(
                source:
                    .signal(
                        SwitchboardCanonicalID.c0
                    ),
                target:
                    .port(
                        .init(
                            component:
                                SwitchboardCanonicalID.fa1,
                            port: "CIN"
                        )
                    )
            )
        )

        c.append(
            .init(
                source:
                    .port(
                        .init(
                            component:
                                SwitchboardCanonicalID.fa1,
                            port: "COUT"
                        )
                    ),
                target:
                    .signal(
                        SwitchboardCanonicalID.c1
                    )
            )
        )

        // FA2

        c.append(
            .init(
                source:
                    .signal(
                        SwitchboardCanonicalID.c1
                    ),
                target:
                    .port(
                        .init(
                            component:
                                SwitchboardCanonicalID.fa2,
                            port: "CIN"
                        )
                    )
            )
        )

        c.append(
            .init(
                source:
                    .port(
                        .init(
                            component:
                                SwitchboardCanonicalID.fa2,
                            port: "COUT"
                        )
                    ),
                target:
                    .signal(
                        SwitchboardCanonicalID.c2
                    )
            )
        )

        // FA3

        c.append(
            .init(
                source:
                    .signal(
                        SwitchboardCanonicalID.c2
                    ),
                target:
                    .port(
                        .init(
                            component:
                                SwitchboardCanonicalID.fa3,
                            port: "CIN"
                        )
                    )
            )
        )

        c.append(
            .init(
                source:
                    .port(
                        .init(
                            component:
                                SwitchboardCanonicalID.fa3,
                            port: "COUT"
                        )
                    ),
                target:
                    .signal(
                        SwitchboardCanonicalID.c3
                    )
            )
        )

        // C3 -> OVERFLOW

        c.append(
            .init(
                source:
                    .signal(
                        SwitchboardCanonicalID.c3
                    ),
                target:
                    .signal(
                        SwitchboardCanonicalID.overflow
                    )
            )
        )

        return c
    }
}

// ============================================================================
// MARK: - IR Validation Error
// ============================================================================

public enum CanonicalIRError:
    Error,
    Sendable,
    CustomStringConvertible
{
    case duplicateSignal(CanonicalID)
    case duplicateComponent(CanonicalID)
    case duplicateState(CanonicalID)

    case missingSignal(CanonicalID)
    case missingComponent(CanonicalID)

    case invalidFullAdderCount(Int)
    case invalidWidth(CanonicalID)
    case missingCarryEdge(String)
    case overflowNotAliased
    case duplicateStateEncoding(UInt8)
    case missingResetTransition(CanonicalID)
    case invalidStateEncoding(CanonicalID)

    public var description: String {

        switch self {

        case let .duplicateSignal(id):
            return "duplicate signal \(id)"

        case let .duplicateComponent(id):
            return "duplicate component \(id)"

        case let .duplicateState(id):
            return "duplicate state \(id)"

        case let .missingSignal(id):
            return "missing signal \(id)"

        case let .missingComponent(id):
            return "missing component \(id)"

        case let .invalidFullAdderCount(count):
            return
                "expected four full adders, found \(count)"

        case let .invalidWidth(id):
            return "invalid width \(id)"

        case let .missingCarryEdge(edge):
            return
                "missing carry edge \(edge)"

        case .overflowNotAliased:
            return
                "OVERFLOW is not sourced by C3"

        case let .duplicateStateEncoding(code):
            return
                "duplicate state encoding \(code)"

        case let .missingResetTransition(state):
            return
                "state \(state) lacks reset transition"

        case let .invalidStateEncoding(state):
            return
                "invalid state encoding \(state)"
        }
    }
}

// ============================================================================
// MARK: - IR Firewall
// ============================================================================

public enum CanonicalIRFirewall {

    public static func verify(
        _ ir: CanonicalSwitchboardIR
    ) throws {

        try verifyIdentities(ir)
        try verifyWidths(ir)
        try verifyFullAdders(ir)
        try verifyCarryChain(ir)
        try verifyOverflow(ir)
        try verifyStates(ir)
        try verifyReset(ir)
    }

    private static func verifyIdentities(
        _ ir: CanonicalSwitchboardIR
    ) throws {

        var signals =
            Set<CanonicalID>()

        for signal in ir.signals {

            guard signals.insert(
                signal.id
            ).inserted
            else {
                throw CanonicalIRError
                    .duplicateSignal(
                        signal.id
                    )
            }
        }

        var components =
            Set<CanonicalID>()

        for component in ir.components {

            guard components.insert(
                component.id
            ).inserted
            else {
                throw CanonicalIRError
                    .duplicateComponent(
                        component.id
                    )
            }
        }

        var states =
            Set<CanonicalID>()

        for state in ir.states {

            guard states.insert(
                state.id
            ).inserted
            else {
                throw CanonicalIRError
                    .duplicateState(
                        state.id
                    )
            }
        }
    }

    private static func verifyWidths(
        _ ir: CanonicalSwitchboardIR
    ) throws {

        for id in [
            SwitchboardCanonicalID.a,
            SwitchboardCanonicalID.b,
            SwitchboardCanonicalID.sum,
            SwitchboardCanonicalID.sInt
        ] {

            guard let signal =
                ir.signals.first(
                    where: {
                        $0.id == id
                    }
                )
            else {
                throw CanonicalIRError
                    .missingSignal(id)
            }

            guard signal.type
                == .vector(width: 4)
            else {
                throw CanonicalIRError
                    .invalidWidth(id)
            }
        }

        guard let state =
            ir.signals.first(
                where: {
                    $0.id
                        == SwitchboardCanonicalID
                        .stateOutput
                }
            )
        else {
            throw CanonicalIRError
                .missingSignal(
                    SwitchboardCanonicalID
                        .stateOutput
                )
        }

        guard state.type
            == .vector(width: 2)
        else {
            throw CanonicalIRError
                .invalidWidth(
                    state.id
                )
        }
    }

    private static func verifyFullAdders(
        _ ir: CanonicalSwitchboardIR
    ) throws {

        let adders =
            ir.components.filter {
                $0.kind == .fullAdder
            }

        guard adders.count == 4
        else {
            throw CanonicalIRError
                .invalidFullAdderCount(
                    adders.count
                )
        }

        for id in [
            SwitchboardCanonicalID.fa0,
            SwitchboardCanonicalID.fa1,
            SwitchboardCanonicalID.fa2,
            SwitchboardCanonicalID.fa3
        ] {

            guard adders.contains(
                where: {
                    $0.id == id
                }
            )
            else {
                throw CanonicalIRError
                    .missingComponent(id)
            }
        }
    }

    private static func verifyCarryChain(
        _ ir: CanonicalSwitchboardIR
    ) throws {

        try requireSignalToPort(
            ir,
            signal:
                SwitchboardCanonicalID.c0,
            component:
                SwitchboardCanonicalID.fa1,
            port: "CIN"
        )

        try requireSignalToPort(
            ir,
            signal:
                SwitchboardCanonicalID.c1,
            component:
                SwitchboardCanonicalID.fa2,
            port: "CIN"
        )

        try requireSignalToPort(
            ir,
            signal:
                SwitchboardCanonicalID.c2,
            component:
                SwitchboardCanonicalID.fa3,
            port: "CIN"
        )
    }

    private static func requireSignalToPort(
        _ ir: CanonicalSwitchboardIR,
        signal: CanonicalID,
        component: CanonicalID,
        port: String
    ) throws {

        let expected =
            CanonicalConnection(
                source:
                    .signal(signal),
                target:
                    .port(
                        CanonicalPortReference(
                            component:
                                component,
                            port:
                                port
                        )
                    )
            )

        guard ir.connections
            .contains(expected)
        else {
            throw CanonicalIRError
                .missingCarryEdge(
                    "\(signal) -> \(component).\(port)"
                )
        }
    }

    private static func verifyOverflow(
        _ ir: CanonicalSwitchboardIR
    ) throws {

        let expected =
            CanonicalConnection(
                source:
                    .signal(
                        SwitchboardCanonicalID.c3
                    ),
                target:
                    .signal(
                        SwitchboardCanonicalID.overflow
                    )
            )

        guard ir.connections
            .contains(expected)
        else {
            throw CanonicalIRError
                .overflowNotAliased
        }
    }

    private static func verifyStates(
        _ ir: CanonicalSwitchboardIR
    ) throws {

        guard ir.states.count == 3
        else {
            throw CanonicalIRError
                .invalidStateEncoding(
                    CanonicalID(
                        "state.count"
                    )
                )
        }

        var encodings =
            Set<UInt8>()

        for state in ir.states {

            guard state.encoding
                <= 0b10
            else {
                throw CanonicalIRError
                    .invalidStateEncoding(
                        state.id
                    )
            }

            guard encodings.insert(
                state.encoding
            ).inserted
            else {
                throw CanonicalIRError
                    .duplicateStateEncoding(
                        state.encoding
                    )
            }
        }
    }

    private static func verifyReset(
        _ ir: CanonicalSwitchboardIR
    ) throws {

        for state in ir.states {

            let reset =
                ir.transitions.first {
                    $0.from == state.id
                    &&
                    $0.to
                        == SwitchboardCanonicalID.idle
                    &&
                    $0.condition
                        == .resetAsserted
                }

            guard reset != nil
            else {
                throw CanonicalIRError
                    .missingResetTransition(
                        state.id
                    )
            }
        }
    }
}

// ============================================================================
// MARK: - Canonical State Conversion
// ============================================================================

public enum CanonicalStateConversion {

    public static func runtime(
        _ id: CanonicalID
    ) -> SwitchboardState {

        switch id {

        case SwitchboardCanonicalID.idle:
            return .idle

        case SwitchboardCanonicalID.read:
            return .read

        case SwitchboardCanonicalID.write:
            return .write

        default:
            preconditionFailure(
                "unknown canonical state \(id)"
            )
        }
    }

    public static func canonical(
        _ state: SwitchboardState
    ) -> CanonicalID {

        switch state {

        case .idle:
            return
                SwitchboardCanonicalID.idle

        case .read:
            return
                SwitchboardCanonicalID.read

        case .write:
            return
                SwitchboardCanonicalID.write
        }
    }
}

// ============================================================================
// MARK: - Canonical Transition Engine
// ============================================================================

public enum CanonicalTransitionEngine {

    public static func next(
        ir: CanonicalSwitchboardIR,
        state: SwitchboardState,
        a: LogicBus,
        b: LogicBus,
        reset: Logic
    ) -> SwitchboardState {

        let current =
            CanonicalStateConversion
            .canonical(state)

        let candidates =
            ir.transitions
            .filter {
                $0.from == current
            }
            .sorted {
                $0.priority > $1.priority
            }

        for transition in candidates {

            if matches(
                transition.condition,
                a: a,
                b: b,
                reset: reset
            ) {
                return
                    CanonicalStateConversion
                    .runtime(
                        transition.to
                    )
            }
        }

        return state
    }

    private static func matches(
        _ condition:
            CanonicalTransitionCondition,
        a: LogicBus,
        b: LogicBus,
        reset: Logic
    ) -> Bool {

        switch condition {

        case .always:
            return true

        case .resetAsserted:
            return reset == .one

        case .anyInputNonZero:

            for index in 0..<4 {

                if a[index] == .one ||
                    b[index] == .one {
                    return true
                }
            }

            return false
        }
    }
}

// ============================================================================
// MARK: - Canonical Datapath Evaluation
// ============================================================================

public struct CanonicalDatapathResult:
    Sendable,
    Equatable
{
    public let sum: LogicBus
    public let c0: Logic
    public let c1: Logic
    public let c2: Logic
    public let c3: Logic
    public let overflow: Logic

    public init(
        sum: LogicBus,
        c0: Logic,
        c1: Logic,
        c2: Logic,
        c3: Logic,
        overflow: Logic
    ) {
        self.sum = sum
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
        self.overflow = overflow
    }
}

// ============================================================================
// MARK: - IR Datapath Executor
// ============================================================================

public enum CanonicalDatapathExecutor {

    public static func evaluate(
        ir: CanonicalSwitchboardIR,
        a: LogicBus,
        b: LogicBus
    ) -> CanonicalDatapathResult {

        precondition(a.width == 4)
        precondition(b.width == 4)

        let fa0 =
            FullAdder.evaluate(
                .init(
                    x: a[0],
                    y: b[0],
                    cin: .zero
                )
            )

        let fa1 =
            FullAdder.evaluate(
                .init(
                    x: a[1],
                    y: b[1],
                    cin: fa0.carry
                )
            )

        let fa2 =
            FullAdder.evaluate(
                .init(
                    x: a[2],
                    y: b[2],
                    cin: fa1.carry
                )
            )

        let fa3 =
            FullAdder.evaluate(
                .init(
                    x: a[3],
                    y: b[3],
                    cin: fa2.carry
                )
            )

        let sum =
            LogicBus(
                [
                    fa0.sum,
                    fa1.sum,
                    fa2.sum,
                    fa3.sum
                ]
            )

        return CanonicalDatapathResult(
            sum: sum,
            c0: fa0.carry,
            c1: fa1.carry,
            c2: fa2.carry,
            c3: fa3.carry,
            overflow: fa3.carry
        )
    }
}

// ============================================================================
// MARK: - Canonical Snapshot
// ============================================================================

public struct CanonicalMachineSnapshot:
    Sendable,
    Equatable
{
    public let a: LogicBus
    public let b: LogicBus

    public let state:
        SwitchboardState

    public let nextState:
        SwitchboardState

    public let internalSum:
        LogicBus

    public let outputSum:
        LogicBus

    public let c0: Logic
    public let c1: Logic
    public let c2: Logic
    public let c3: Logic

    public let overflow:
        Logic

    public let enable:
        Logic
}

// ============================================================================
// MARK: - Canonical Machine
// ============================================================================

public struct CanonicalSwitchboardMachine:
    Sendable
{
    public let ir:
        CanonicalSwitchboardIR

    public private(set) var state:
        SwitchboardState

    public init(
        ir: CanonicalSwitchboardIR
    ) throws {

        try CanonicalIRFirewall
            .verify(ir)

        self.ir = ir
        self.state = .idle
    }

    public func evaluate(
        a: LogicBus,
        b: LogicBus,
        reset: Logic
    ) -> CanonicalMachineSnapshot {

        let datapath =
            CanonicalDatapathExecutor
            .evaluate(
                ir: ir,
                a: a,
                b: b
            )

        let next =
            CanonicalTransitionEngine
            .next(
                ir: ir,
                state: state,
                a: a,
                b: b,
                reset: reset
            )

        let enable: Logic =
            state == .read
            ? .one
            : .zero

        let output: LogicBus

        if enable == .one {

            output =
                datapath.sum

        } else {

            output =
                .highImpedance(
                    width: 4
                )
        }

        return CanonicalMachineSnapshot(
            a: a,
            b: b,
            state: state,
            nextState: next,
            internalSum:
                datapath.sum,
            outputSum:
                output,
            c0: datapath.c0,
            c1: datapath.c1,
            c2: datapath.c2,
            c3: datapath.c3,
            overflow:
                datapath.overflow,
            enable:
                enable
        )
    }

    public mutating func clock(
        a: LogicBus,
        b: LogicBus,
        reset: Logic
    ) -> CanonicalMachineSnapshot {

        let before =
            evaluate(
                a: a,
                b: b,
                reset: reset
            )

        state =
            before.nextState

        return evaluate(
            a: a,
            b: b,
            reset: reset
        )
    }
}

// ============================================================================
// MARK: - IR Canonical Encoding
// ============================================================================

public enum CanonicalIREncoder {

    public static func encode(
        _ ir: CanonicalSwitchboardIR
    ) -> ByteBuffer {

        var buffer =
            ByteBuffer()

        buffer.append(
            string: ir.name
        )

        encodeSignals(
            ir.signals,
            into: &buffer
        )

        encodeStates(
            ir.states,
            into: &buffer
        )

        encodeComponents(
            ir.components,
            into: &buffer
        )

        encodeConnections(
            ir.connections,
            into: &buffer
        )

        encodeTransitions(
            ir.transitions,
            into: &buffer
        )

        encodeInvariants(
            ir.invariants,
            into: &buffer
        )

        return buffer
    }

    public static func digest(
        _ ir: CanonicalSwitchboardIR
    ) -> Digest256 {

        DigestEngine.hash(
            encode(ir)
        )
    }

    private static func encodeSignals(
        _ signals: [CanonicalSignal],
        into buffer: inout ByteBuffer
    ) {

        let ordered =
            signals.sorted {
                $0.id < $1.id
            }

        buffer.append(
            UInt64(ordered.count)
        )

        for signal in ordered {

            buffer.append(
                string:
                    signal.id.rawValue
            )

            buffer.append(
                signal.direction.rawValue
            )

            switch signal.type {

            case .logic:

                buffer.append(0)

            case let .vector(width):

                buffer.append(1)

                buffer.append(
                    UInt64(width)
                )

            case .state:

                buffer.append(2)
            }
        }
    }

    private static func encodeStates(
        _ states: [CanonicalState],
        into buffer: inout ByteBuffer
    ) {

        let ordered =
            states.sorted {
                $0.id < $1.id
            }

        buffer.append(
            UInt64(ordered.count)
        )

        for state in ordered {

            buffer.append(
                string:
                    state.id.rawValue
            )

            buffer.append(
                state.encoding
            )
        }
    }

    private static func encodeComponents(
        _ components:
            [CanonicalComponent],
        into buffer:
            inout ByteBuffer
    ) {

        let ordered =
            components.sorted {
                $0.id < $1.id
            }

        buffer.append(
            UInt64(ordered.count)
        )

        for component in ordered {

            buffer.append(
                string:
                    component.id.rawValue
            )

            buffer.append(
                string:
                    component.kind.rawValue
            )
        }
    }

    private static func encodeConnections(
        _ connections:
            [CanonicalConnection],
        into buffer:
            inout ByteBuffer
    ) {

        let encoded =
            connections
            .map {
                connectionString($0)
            }
            .sorted()

        buffer.append(
            UInt64(encoded.count)
        )

        for item in encoded {
            buffer.append(
                string: item
            )
        }
    }

    private static func connectionString(
        _ connection: CanonicalConnection
    ) -> String {

        "\(endpointString(connection.source))->\(endpointString(connection.target))"
    }

    private static func endpointString(
        _ endpoint: CanonicalEndpoint
    ) -> String {

        switch endpoint {

        case let .signal(id):
            return "sig:\(id.rawValue)"

        case let .port(ref):
            return "port:\(ref.component.rawValue).\(ref.port)"

        case let .constant(value):
            return "const:\(value)"
        }
    }

    private static func encodeTransitions(
        _ transitions:
            [CanonicalTransition],
        into buffer:
            inout ByteBuffer
    ) {

        let ordered =
            transitions.sorted {

                if $0.from != $1.from {
                    return
                        $0.from < $1.from
                }

                if $0.priority
                    != $1.priority
                {
                    return
                        $0.priority
                        > $1.priority
                }

                return
                    $0.to < $1.to
            }

        buffer.append(
            UInt64(ordered.count)
        )

        for transition in ordered {

            buffer.append(
                string:
                    transition.from.rawValue
            )

            buffer.append(
                string:
                    transition.to.rawValue
            )

            buffer.append(
                UInt64(transition.priority)
            )

            switch transition.condition {

            case .always:
                buffer.append(0)

            case .resetAsserted:
                buffer.append(1)

            case .anyInputNonZero:
                buffer.append(2)
            }
        }
    }

    private static func encodeInvariants(
        _ invariants:
            [CanonicalInvariant],
        into buffer:
            inout ByteBuffer
    ) {

        let ordered =
            invariants.sorted {
                $0.id < $1.id
            }

        buffer.append(
            UInt64(ordered.count)
        )

        for invariant in ordered {

            buffer.append(
                string:
                    invariant.id.rawValue
            )

            buffer.append(
                string:
                    invariant.kind.rawValue
            )

            buffer.append(
                string:
                    invariant.description
            )
        }
    }
}

// ============================================================================
// MARK: - Equivalence Witness
// ============================================================================

public struct EquivalenceWitness:
    Sendable
{
    public let canonicalDigest:
        Digest256

    public let swiftDigest:
        Digest256

    public let spiceDigest:
        Digest256

    public var agreed: Bool {
        canonicalDigest == swiftDigest
            && swiftDigest == spiceDigest
    }
}

// ============================================================================
// MARK: - Equivalence Report
// ============================================================================

public struct EquivalenceReport:
    Sendable
{
    public let ir: CanonicalSwitchboardIR

    public let witness: EquivalenceWitness

    public let canonicalVsSwiftAgreed: Bool
    public let swiftVsSpiceAgreed: Bool

    public var fullyClosed: Bool {
        canonicalVsSwiftAgreed
            && swiftVsSpiceAgreed
    }
}

// ============================================================================
// MARK: - Canonical Manifest
// ============================================================================

public struct CanonicalManifest:
    Sendable
{
    public let irDigest: Digest256
    public let equivalenceReport: EquivalenceReport
    public let irName: String
    public let componentCount: Int
    public let signalCount: Int
    public let invariantCount: Int
    public let transitionCount: Int

    public init(
        ir: CanonicalSwitchboardIR,
        report: EquivalenceReport
    ) {
        self.irDigest =
            CanonicalIREncoder.digest(ir)

        self.equivalenceReport = report
        self.irName = ir.name
        self.componentCount =
            ir.components.count
        self.signalCount =
            ir.signals.count
        self.invariantCount =
            ir.invariants.count
        self.transitionCount =
            ir.transitions.count
    }

    public var description: String {

        """
        CanonicalManifest {
          name:        \(irName)
          digest:      \(irDigest)
          components:  \(componentCount)
          signals:     \(signalCount)
          invariants:  \(invariantCount)
          transitions: \(transitionCount)
          closed:      \(equivalenceReport.fullyClosed)
        }
        """
    }
}
