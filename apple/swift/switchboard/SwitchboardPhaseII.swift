//
// SwitchboardPhaseII.swift
//
// Phase II — CMOS / SPICE Lowering
//
// Requires Phase I types:
// Logic
// LogicBus
// FullAdder
// SPICENode
// SPICEElement
// SPICECircuit
// InvariantViolation
// InvariantID
//
// Objective:
//
// VHDL full_adder
// │
// ▼
// Swift structural primitive
// │
// ▼
// CMOS gate graph
// │
// ▼
// transistor netlist
// │
// ▼
// SPICE subcircuit
// │
// ▼
// topology + semantic firewall
//

import Foundation

// ============================================================================
// MARK: - Physical Identifiers
// ============================================================================

public struct DeviceID:
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

public struct PhysicalNet:
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
// MARK: - MOS Polarity
// ============================================================================

@frozen
public enum MOSKind:
    String,
    Sendable
{
    case nmos
    case pmos
}

// ============================================================================
// MARK: - Device Geometry
// ============================================================================

public struct MOSGeometry:
    Sendable,
    Equatable
{
    public let width: Double
    public let length: Double

    public init(
        width: Double,
        length: Double
    ) {
        precondition(width > 0)
        precondition(length > 0)

        self.width = width
        self.length = length
    }

    public static let minimumNMOS =
        MOSGeometry(
            width: 0.36e-6,
            length: 0.18e-6
        )

    public static let minimumPMOS =
        MOSGeometry(
            width: 0.72e-6,
            length: 0.18e-6
        )
}

// ============================================================================
// MARK: - MOS Device
// ============================================================================

public struct MOSDevice:
    Sendable
{
    public let id: DeviceID
    public let kind: MOSKind

    public let drain: PhysicalNet
    public let gate: PhysicalNet
    public let source: PhysicalNet
    public let body: PhysicalNet

    public let geometry: MOSGeometry

    public init(
        id: DeviceID,
        kind: MOSKind,
        drain: PhysicalNet,
        gate: PhysicalNet,
        source: PhysicalNet,
        body: PhysicalNet,
        geometry: MOSGeometry
    ) {
        self.id = id
        self.kind = kind
        self.drain = drain
        self.gate = gate
        self.source = source
        self.body = body
        self.geometry = geometry
    }
}

// ============================================================================
// MARK: - Physical Cell
// ============================================================================

public struct PhysicalCell:
    Sendable
{
    public let name: String

    public var ports: [PhysicalNet]
    public var internalNets: Set<PhysicalNet>
    public var devices: [MOSDevice]

    public init(
        name: String,
        ports: [PhysicalNet]
    ) {
        precondition(!name.isEmpty)

        self.name = name
        self.ports = ports
        self.internalNets = []
        self.devices = []
    }

    public mutating func declare(
        _ net: PhysicalNet
    ) {
        if !ports.contains(net) {
            internalNets.insert(net)
        }
    }

    public mutating func append(
        _ device: MOSDevice
    ) {
        devices.append(device)

        declare(device.drain)
        declare(device.gate)
        declare(device.source)
        declare(device.body)
    }
}

// ============================================================================
// MARK: - CMOS Rails
// ============================================================================

public enum CMOSRail {

    public static let vdd =
        PhysicalNet("VDD")

    public static let vss =
        PhysicalNet("VSS")
}

// ============================================================================
// MARK: - Deterministic Device Allocator
// ============================================================================

public struct DeviceAllocator {

    private var nextIndex: UInt64 = 0

    public init() {}

    public mutating func next(
        prefix: String
    ) -> DeviceID {

        defer {
            nextIndex &+= 1
        }

        return DeviceID(
            "\(prefix)_\(nextIndex)"
        )
    }
}

// ============================================================================
// MARK: - Net Allocator
// ============================================================================

public struct NetAllocator {

    private var nextIndex: UInt64 = 0

    public init() {}

    public mutating func next(
        prefix: String
    ) -> PhysicalNet {

        defer {
            nextIndex &+= 1
        }

        return PhysicalNet(
            "\(prefix)_\(nextIndex)"
        )
    }
}

// ============================================================================
// MARK: - CMOS Builder
// ============================================================================

public struct CMOSBuilder {

    public private(set) var cell: PhysicalCell

    private var devices:
        DeviceAllocator

    private var nets:
        NetAllocator

    public init(
        name: String,
        ports: [PhysicalNet]
    ) {
        self.cell =
            PhysicalCell(
                name: name,
                ports: ports
            )

        self.devices =
            DeviceAllocator()

        self.nets =
            NetAllocator()
    }

    // ------------------------------------------------------------------------
    // Internal net
    // ------------------------------------------------------------------------

    public mutating func internalNet(
        _ prefix: String
    ) -> PhysicalNet {

        let net =
            nets.next(prefix: prefix)

        cell.declare(net)

        return net
    }

    // ------------------------------------------------------------------------
    // NMOS
    // ------------------------------------------------------------------------

    public mutating func nmos(
        prefix: String,
        drain: PhysicalNet,
        gate: PhysicalNet,
        source: PhysicalNet
    ) {
        cell.append(
            MOSDevice(
                id: devices.next(
                    prefix: prefix
                ),
                kind: .nmos,
                drain: drain,
                gate: gate,
                source: source,
                body: CMOSRail.vss,
                geometry: .minimumNMOS
            )
        )
    }

    // ------------------------------------------------------------------------
    // PMOS
    // ------------------------------------------------------------------------

    public mutating func pmos(
        prefix: String,
        drain: PhysicalNet,
        gate: PhysicalNet,
        source: PhysicalNet
    ) {
        cell.append(
            MOSDevice(
                id: devices.next(
                    prefix: prefix
                ),
                kind: .pmos,
                drain: drain,
                gate: gate,
                source: source,
                body: CMOSRail.vdd,
                geometry: .minimumPMOS
            )
        )
    }
}

// ============================================================================
// MARK: - CMOS Inverter
// ============================================================================
//
// VDD
//  │
// PMOS
//  │
//  ├──── OUT
//  │
// NMOS
//  │
// VSS
//
// Both gates driven by IN.
//
// ============================================================================

extension CMOSBuilder {

    public mutating func inverter(
        input: PhysicalNet,
        output: PhysicalNet,
        label: String
    ) {
        pmos(
            prefix: "\(label)_P",
            drain: output,
            gate: input,
            source: CMOSRail.vdd
        )

        nmos(
            prefix: "\(label)_N",
            drain: output,
            gate: input,
            source: CMOSRail.vss
        )
    }
}

// ============================================================================
// MARK: - NAND2
// ============================================================================
//
// Pull-up:
//
// VDD  VDD
//  │    │
// P(A) P(B)
//  │    │
//  └──── Y ───┘
//
// Pull-down:
//
//  Y
//  │
// N(A)
//  │
// N(B)
//  │
// VSS
//
// ============================================================================

extension CMOSBuilder {

    public mutating func nand2(
        a: PhysicalNet,
        b: PhysicalNet,
        output: PhysicalNet,
        label: String
    ) {
        let series =
            internalNet(
                "\(label)_PD"
            )

        pmos(
            prefix: "\(label)_PA",
            drain: output,
            gate: a,
            source: CMOSRail.vdd
        )

        pmos(
            prefix: "\(label)_PB",
            drain: output,
            gate: b,
            source: CMOSRail.vdd
        )

        nmos(
            prefix: "\(label)_NA",
            drain: output,
            gate: a,
            source: series
        )

        nmos(
            prefix: "\(label)_NB",
            drain: series,
            gate: b,
            source: CMOSRail.vss
        )
    }
}

// ============================================================================
// MARK: - AND2
// ============================================================================

extension CMOSBuilder {

    public mutating func and2(
        a: PhysicalNet,
        b: PhysicalNet,
        output: PhysicalNet,
        label: String
    ) {
        let nand =
            internalNet(
                "\(label)_NAND"
            )

        nand2(
            a: a,
            b: b,
            output: nand,
            label: "\(label)_NAND"
        )

        inverter(
            input: nand,
            output: output,
            label: "\(label)_INV"
        )
    }
}

// ============================================================================
// MARK: - NOR2
// ============================================================================
//
// Pull-up series PMOS.
// Pull-down parallel NMOS.
//
// ============================================================================

extension CMOSBuilder {

    public mutating func nor2(
        a: PhysicalNet,
        b: PhysicalNet,
        output: PhysicalNet,
        label: String
    ) {
        let series =
            internalNet(
                "\(label)_PU"
            )

        pmos(
            prefix: "\(label)_PA",
            drain: output,
            gate: a,
            source: series
        )

        pmos(
            prefix: "\(label)_PB",
            drain: series,
            gate: b,
            source: CMOSRail.vdd
        )

        nmos(
            prefix: "\(label)_NA",
            drain: output,
            gate: a,
            source: CMOSRail.vss
        )

        nmos(
            prefix: "\(label)_NB",
            drain: output,
            gate: b,
            source: CMOSRail.vss
        )
    }
}

// ============================================================================
// MARK: - OR2
// ============================================================================

extension CMOSBuilder {

    public mutating func or2(
        a: PhysicalNet,
        b: PhysicalNet,
        output: PhysicalNet,
        label: String
    ) {
        let nor =
            internalNet(
                "\(label)_NOR"
            )

        nor2(
            a: a,
            b: b,
            output: nor,
            label: "\(label)_NOR"
        )

        inverter(
            input: nor,
            output: output,
            label: "\(label)_INV"
        )
    }
}

// ============================================================================
// MARK: - XOR2
// ============================================================================
//
// Static CMOS composition:
//
//   nA = !A
//   nB = !B
//
//   T0 = A & !B
//   T1 = !A & B
//
//   Y = T0 | T1
//
// This intentionally favors transparent structural semantics over transistor
// minimization. Phase V can replace this implementation with optimized cells
// while retaining the same logical proof boundary.
//
// ============================================================================

extension CMOSBuilder {

    public mutating func xor2(
        a: PhysicalNet,
        b: PhysicalNet,
        output: PhysicalNet,
        label: String
    ) {
        let notA =
            internalNet(
                "\(label)_NOT_A"
            )

        let notB =
            internalNet(
                "\(label)_NOT_B"
            )

        let term0 =
            internalNet(
                "\(label)_TERM0"
            )

        let term1 =
            internalNet(
                "\(label)_TERM1"
            )

        inverter(
            input: a,
            output: notA,
            label: "\(label)_IA"
        )

        inverter(
            input: b,
            output: notB,
            label: "\(label)_IB"
        )

        and2(
            a: a,
            b: notB,
            output: term0,
            label: "\(label)_T0"
        )

        and2(
            a: notA,
            b: b,
            output: term1,
            label: "\(label)_T1"
        )

        or2(
            a: term0,
            b: term1,
            output: output,
            label: "\(label)_OR"
        )
    }
}

// ============================================================================
// MARK: - Full Adder CMOS Construction
// ============================================================================
//
// VHDL:
//
//   s <= x xor y xor cin;
//   cout <= (x and y) or
//           (cin and (x xor y));
//
// Structural:
//
//   ┌──── XOR ──── P ───── XOR ─── S
// X ─────────┤
// Y ─────────┘
//
// X ─────────┐
//             AND ── XY ─────────┐
// Y ─────────┘                   │
//                                 OR ───── COUT
// CIN ───────┐                   │
//             AND ── CP ─────────┘
// P ─────────┘
//
// ============================================================================

public enum CMOSFullAdder {

    public static func build()
        -> PhysicalCell
    {
        let x =
            PhysicalNet("X")

        let y =
            PhysicalNet("Y")

        let cin =
            PhysicalNet("CIN")

        let sum =
            PhysicalNet("S")

        let cout =
            PhysicalNet("COUT")

        var builder =
            CMOSBuilder(
                name: "FULL_ADDER",
                ports: [
                    x,
                    y,
                    cin,
                    sum,
                    cout,
                    CMOSRail.vdd,
                    CMOSRail.vss
                ]
            )

        let propagate =
            builder.internalNet(
                "PROPAGATE"
            )

        let xy =
            builder.internalNet(
                "XY"
            )

        let cp =
            builder.internalNet(
                "CIN_PROP"
            )

        builder.xor2(
            a: x,
            b: y,
            output: propagate,
            label: "XOR_XY"
        )

        builder.xor2(
            a: propagate,
            b: cin,
            output: sum,
            label: "XOR_SUM"
        )

        builder.and2(
            a: x,
            b: y,
            output: xy,
            label: "AND_XY"
        )

        builder.and2(
            a: cin,
            b: propagate,
            output: cp,
            label: "AND_CP"
        )

        builder.or2(
            a: xy,
            b: cp,
            output: cout,
            label: "OR_CARRY"
        )

        return builder.cell
    }
}

// ============================================================================
// MARK: - Physical Topology Index
// ============================================================================

public struct NetTopology:
    Sendable
{
    public var gates:
        [DeviceID]

    public var drains:
        [DeviceID]

    public var sources:
        [DeviceID]

    public var bodies:
        [DeviceID]

    public init() {
        gates = []
        drains = []
        sources = []
        bodies = []
    }
}

public struct PhysicalTopology:
    Sendable
{
    public let nets:
        [PhysicalNet: NetTopology]

    public init(
        cell: PhysicalCell
    ) {
        var map:
            [PhysicalNet: NetTopology] = [:]

        func ensure(
            _ net: PhysicalNet,
            in map:
                inout [PhysicalNet: NetTopology]
        ) {
            if map[net] == nil {
                map[net] =
                    NetTopology()
            }
        }

        for port in cell.ports {
            ensure(
                port,
                in: &map
            )
        }

        for net in cell.internalNets {
            ensure(
                net,
                in: &map
            )
        }

        for device in cell.devices {

            ensure(
                device.gate,
                in: &map
            )

            ensure(
                device.drain,
                in: &map
            )

            ensure(
                device.source,
                in: &map
            )

            ensure(
                device.body,
                in: &map
            )

            map[device.gate]!
                .gates
                .append(device.id)

            map[device.drain]!
                .drains
                .append(device.id)

            map[device.source]!
                .sources
                .append(device.id)

            map[device.body]!
                .bodies
                .append(device.id)
        }

        self.nets = map
    }
}

// ============================================================================
// MARK: - Physical Audit Failure
// ============================================================================

public enum PhysicalAuditFailure:
    Error,
    Sendable,
    CustomStringConvertible
{
    case duplicateDevice(DeviceID)

    case floatingInternalNet(
        PhysicalNet
    )

    case invalidBodyConnection(
        DeviceID
    )

    case missingRail(
        PhysicalNet
    )

    case emptyCell

    case portMissing(
        PhysicalNet
    )

    public var description: String {

        switch self {

        case let .duplicateDevice(id):
            return
                "duplicate MOS device \(id)"

        case let .floatingInternalNet(net):
            return
                "floating internal net \(net)"

        case let .invalidBodyConnection(id):
            return
                "invalid MOS body connection \(id)"

        case let .missingRail(net):
            return
                "required CMOS rail missing: \(net)"

        case .emptyCell:
            return
                "physical cell contains no devices"

        case let .portMissing(net):
            return
                "required cell port missing: \(net)"
        }
    }
}

// ============================================================================
// MARK: - Physical Firewall
// ============================================================================

public enum PhysicalFirewall {

    public static func validate(
        _ cell: PhysicalCell
    ) throws {

        guard !cell.devices.isEmpty else {
            throw PhysicalAuditFailure.emptyCell
        }

        try checkRequiredPorts(cell)
        try checkUniqueDevices(cell)
        try checkBodies(cell)
        try checkConnectivity(cell)
    }

    // ------------------------------------------------------------------------
    // Required ports
    // ------------------------------------------------------------------------

    private static func checkRequiredPorts(
        _ cell: PhysicalCell
    ) throws {

        let required = [
            PhysicalNet("X"),
            PhysicalNet("Y"),
            PhysicalNet("CIN"),
            PhysicalNet("S"),
            PhysicalNet("COUT"),
            CMOSRail.vdd,
            CMOSRail.vss
        ]

        for port in required {

            guard cell.ports.contains(port)
            else {
                throw PhysicalAuditFailure
                    .portMissing(port)
            }
        }
    }

    // ------------------------------------------------------------------------
    // Device identity uniqueness
    // ------------------------------------------------------------------------

    private static func checkUniqueDevices(
        _ cell: PhysicalCell
    ) throws {

        var observed =
            Set<DeviceID>()

        for device in cell.devices {

            guard observed.insert(
                device.id
            ).inserted
            else {
                throw PhysicalAuditFailure
                    .duplicateDevice(
                        device.id
                    )
            }
        }
    }

    // ------------------------------------------------------------------------
    // Bulk/body connections
    // ------------------------------------------------------------------------

    private static func checkBodies(
        _ cell: PhysicalCell
    ) throws {

        for device in cell.devices {

            switch device.kind {

            case .nmos:
                guard device.body
                    == CMOSRail.vss
                else {
                    throw PhysicalAuditFailure
                        .invalidBodyConnection(
                            device.id
                        )
                }

            case .pmos:
                guard device.body
                    == CMOSRail.vdd
                else {
                    throw PhysicalAuditFailure
                        .invalidBodyConnection(
                            device.id
                        )
                }
            }
        }
    }

    // ------------------------------------------------------------------------
    // Internal connectivity
    // ------------------------------------------------------------------------

    private static func checkConnectivity(
        _ cell: PhysicalCell
    ) throws {

        let topology =
            PhysicalTopology(
                cell: cell
            )

        guard topology.nets[
            CMOSRail.vdd
        ] != nil else {
            throw PhysicalAuditFailure
                .missingRail(
                    CMOSRail.vdd
                )
        }

        guard topology.nets[
            CMOSRail.vss
        ] != nil else {
            throw PhysicalAuditFailure
                .missingRail(
                    CMOSRail.vss
                )
        }

        for net in cell.internalNets {

            guard let connection =
                topology.nets[net]
            else {
                throw PhysicalAuditFailure
                    .floatingInternalNet(net)
            }

            let conduction =
                connection.drains.count
                + connection.sources.count

            let observation =
                connection.gates.count

            if conduction == 0 &&
                observation == 0 {

                throw PhysicalAuditFailure
                    .floatingInternalNet(net)
            }
        }
    }
}

// ============================================================================
// MARK: - SPICE Model Definition
// ============================================================================

public struct SPICEModel:
    Sendable
{
    public let name: String
    public let type: MOSKind
    public let parameters:
        [String: Double]

    public init(
        name: String,
        type: MOSKind,
        parameters: [String: Double]
    ) {
        self.name = name
        self.type = type
        self.parameters = parameters
    }
}

// ============================================================================
// MARK: - SPICE Subcircuit
// ============================================================================

public struct SPICESubcircuit:
    Sendable
{
    public let name: String
    public let ports: [SPICENode]
    public let body: [String]

    public init(
        name: String,
        ports: [SPICENode],
        body: [String]
    ) {
        self.name = name
        self.ports = ports
        self.body = body
    }
}

// ============================================================================
// MARK: - SPICE Number Formatting
// ============================================================================

public enum SPICENumber {

    public static func meters(
        _ value: Double
    ) -> String {

        let microns =
            value * 1_000_000

        return compact(microns)
            + "u"
    }

    public static func compact(
        _ value: Double
    ) -> String {

        if value.rounded() == value {
            return String(
                Int(value)
            )
        }

        return String(
            format: "%.6g",
            value
        )
    }
}

// ============================================================================
// MARK: - Physical Cell -> SPICE
// ============================================================================

public enum PhysicalSPICELowering {

    public static func lower(
        _ cell: PhysicalCell,
        nmosModel: String = "NMOS_CORE",
        pmosModel: String = "PMOS_CORE"
    ) throws -> SPICESubcircuit {

        try PhysicalFirewall.validate(
            cell
        )

        let ports =
            cell.ports.map {
                SPICENode(
                    spiceName($0)
                )
            }

        var body:
            [String] = []

        body.reserveCapacity(
            cell.devices.count
        )

        for device in cell.devices {

            let model: String

            switch device.kind {
            case .nmos:
                model = nmosModel

            case .pmos:
                model = pmosModel
            }

            let line = [
                "M\(device.id.rawValue)",
                spiceName(device.drain),
                spiceName(device.gate),
                spiceName(device.source),
                spiceName(device.body),
                model,
                "W=\(SPICENumber.meters(device.geometry.width))",
                "L=\(SPICENumber.meters(device.geometry.length))"
            ]
            .joined(separator: " ")

            body.append(line)
        }

        return SPICESubcircuit(
            name: cell.name,
            ports: ports,
            body: body
        )
    }

    private static func spiceName(
        _ net: PhysicalNet
    ) -> String {

        if net == CMOSRail.vss {
            return "0"
        }

        return net.rawValue
    }
}

// ============================================================================
// MARK: - Subcircuit Serialization
// ============================================================================

public enum SPICESubcircuitSerializer {

    public static func serialize(
        _ subcircuit: SPICESubcircuit
    ) -> String {

        var output =
            ".subckt "

        output += subcircuit.name
        output += " "

        output += subcircuit
            .ports
            .map(\.description)
            .joined(separator: " ")

        output += "\n"

        for line in subcircuit.body {
            output += line
            output += "\n"
        }

        output += ".ends "
        output += subcircuit.name
        output += "\n"

        return output
    }
}

// ============================================================================
// MARK: - MOS Model Serialization
// ============================================================================

public enum SPICEModelSerializer {

    public static func serialize(
        _ model: SPICEModel
    ) -> String {

        let type: String

        switch model.type {
        case .nmos:
            type = "NMOS"

        case .pmos:
            type = "PMOS"
        }

        let parameters =
            model.parameters
            .sorted {
                $0.key < $1.key
            }
            .map {
                "\($0.key)=\(SPICENumber.compact($0.value))"
            }
            .joined(separator: " ")

        return
            ".model \(model.name) \(type) (\(parameters))"
    }
}

// ============================================================================
// MARK: - Generic Educational MOS Models
// ============================================================================
//
// These are intentionally generic Level-1 models.
//
// They establish the SPICE machinery without pretending to represent a
// particular fabrication process. A real PDK/model card replaces these later.
//
// ============================================================================

public enum GenericMOSModels {

    public static let nmos =
        SPICEModel(
            name: "NMOS_CORE",
            type: .nmos,
            parameters: [
                "LEVEL": 1,
                "VTO": 0.45,
                "KP": 120e-6,
                "LAMBDA": 0.04
            ]
        )

    public static let pmos =
        SPICEModel(
            name: "PMOS_CORE",
            type: .pmos,
            parameters: [
                "LEVEL": 1,
                "VTO": -0.45,
                "KP": 50e-6,
                "LAMBDA": 0.05
            ]
        )
}

// ============================================================================
// MARK: - FULL_ADDER SPICE Library
// ============================================================================

public enum FullAdderSPICELibrary {

    public static func generate()
        throws -> String
    {
        let cell =
            CMOSFullAdder.build()

        let subcircuit =
            try PhysicalSPICELowering
            .lower(cell)

        var text = ""

        text += """
        * ================================================================
        * SWITCHBOARD FULL ADDER
        * Generated from invariant-guarded structural CMOS representation
        * ================================================================

        """

        text +=
            SPICEModelSerializer.serialize(
                GenericMOSModels.nmos
            )

        text += "\n"

        text +=
            SPICEModelSerializer.serialize(
                GenericMOSModels.pmos
            )

        text += "\n\n"

        text +=
            SPICESubcircuitSerializer.serialize(
                subcircuit
            )

        return text
    }
}

// ============================================================================
// MARK: - Four-Bit Physical Switchboard
// ============================================================================

public struct SPICEInstance:
    Sendable
{
    public let name: String
    public let nodes: [String]
    public let subcircuit: String

    public init(
        name: String,
        nodes: [String],
        subcircuit: String
    ) {
        self.name = name
        self.nodes = nodes
        self.subcircuit = subcircuit
    }

    public var spice: String {

        let joined =
            nodes.joined(separator: " ")

        return
            "X\(name) \(joined) \(subcircuit)"
    }
}

// ============================================================================
// MARK: - Switchboard Physical Top
// ============================================================================

public enum PhysicalSwitchboard {

    public static func instances()
        -> [SPICEInstance]
    {
        [
            SPICEInstance(
                name: "FA0",
                nodes: [
                    "A0",
                    "B0",
                    "0",
                    "S0",
                    "C0",
                    "VDD",
                    "0"
                ],
                subcircuit: "FULL_ADDER"
            ),

            SPICEInstance(
                name: "FA1",
                nodes: [
                    "A1",
                    "B1",
                    "C0",
                    "S1",
                    "C1",
                    "VDD",
                    "0"
                ],
                subcircuit: "FULL_ADDER"
            ),

            SPICEInstance(
                name: "FA2",
                nodes: [
                    "A2",
                    "B2",
                    "C1",
                    "S2",
                    "C2",
                    "VDD",
                    "0"
                ],
                subcircuit: "FULL_ADDER"
            ),

            SPICEInstance(
                name: "FA3",
                nodes: [
                    "A3",
                    "B3",
                    "C2",
                    "S3",
                    "C3",
                    "VDD",
                    "0"
                ],
                subcircuit: "FULL_ADDER"
            )
        ]
    }
}

// ============================================================================
// MARK: - Structural Carry Audit
// ============================================================================

public enum CarryChainPhysicalAudit {

    public static func validate(
        _ instances: [SPICEInstance]
    ) throws {

        guard instances.count == 4 else {
            throw InvariantViolation(
                .i3,
                "physical ripple chain requires exactly four cells"
            )
        }

        let expectedNames = [
            "FA0",
            "FA1",
            "FA2",
            "FA3"
        ]

        for index in 0..<4 {

            guard instances[index].name
                == expectedNames[index]
            else {
                throw InvariantViolation(
                    .i3,
                    """
                    physical cell order changed at index \(index)
                    """
                )
            }

            guard instances[index].nodes.count
                == 7
            else {
                throw InvariantViolation(
                    .i3,
                    """
                    malformed FULL_ADDER instance \(index)
                    """
                )
            }
        }

        // FULL_ADDER node ordering:
        //
        // 0  X
        // 1  Y
        // 2  CIN
        // 3  S
        // 4  COUT
        // 5  VDD
        // 6  VSS

        guard instances[0].nodes[2]
            == "0"
        else {
            throw InvariantViolation(
                .i3,
                "FA0 CIN must be tied low"
            )
        }

        for index in 1..<4 {

            let previousCarry =
                instances[index - 1]
                .nodes[4]

            let currentCarryInput =
                instances[index]
                .nodes[2]

            guard previousCarry
                == currentCarryInput
            else {
                throw InvariantViolation(
                    .i3,
                    """
                    broken physical carry chain \
                    FA\(index - 1) -> FA\(index)
                    """
                )
            }
        }

        guard instances[3].nodes[4]
            == "C3"
        else {
            throw InvariantViolation(
                .i4,
                "physical overflow node must terminate at C3"
            )
        }
    }
}

// ============================================================================
// MARK: - Complete SPICE Deck
// ============================================================================

public enum SwitchboardSPICEDeck {

    public static func generate()
        throws -> String
    {
        let instances =
            PhysicalSwitchboard.instances()

        try CarryChainPhysicalAudit
            .validate(instances)

        var text = ""

        text += """
        * =================================================================
        * SWITCHBOARD
        * 4-bit ripple-carry datapath
        * transistor-lowered FULL_ADDER
        * invariant guarded
        * =================================================================

        """

        text +=
            try FullAdderSPICELibrary
            .generate()

        text += "\n"

        text += """
        * -----------------------------------------------------------------
        * Supply
        * -----------------------------------------------------------------

        VDD_SRC VDD 0 DC 1.8

        * -----------------------------------------------------------------
        * Four-cell extracted topology
        * -----------------------------------------------------------------

        """

        for instance in instances {
            text += instance.spice
            text += "\n"
        }

        text += """

        * I4 physical projection:
        * OVERFLOW == C3

        .end
        """

        return text
    }
}

// ============================================================================
// MARK: - Gate-Level Reference Evaluator
// ============================================================================
//
// Independent from FullAdder.evaluate.
//
// The point is deliberate redundancy:
//
//   implementation A:
//     FullAdder.evaluate()
//
//   implementation B:
//     primitive boolean decomposition below
//
// Agreement across all 8 binary vectors establishes the Phase-II semantic
// boundary before an external analog SPICE engine is introduced.
//
// ============================================================================

public enum CMOSReferenceLogic {

    @inline(__always)
    private static func not(
        _ x: Logic
    ) -> Logic {
        ~x
    }

    @inline(__always)
    private static func and(
        _ a: Logic,
        _ b: Logic
    ) -> Logic {
        a & b
    }

    @inline(__always)
    private static func or(
        _ a: Logic,
        _ b: Logic
    ) -> Logic {
        a | b
    }

    @inline(__always)
    private static func xor(
        _ a: Logic,
        _ b: Logic
    ) -> Logic {

        let notA =
            not(a)

        let notB =
            not(b)

        let term0 =
            and(
                a,
                notB
            )

        let term1 =
            and(
                notA,
                b
            )

        return or(
            term0,
            term1
        )
    }

    public static func fullAdder(
        x: Logic,
        y: Logic,
        cin: Logic
    ) -> FullAdder.Output {

        let propagate =
            xor(x, y)

        let sum =
            xor(
                propagate,
                cin
            )

        let xy =
            and(x, y)

        let cp =
            and(
                cin,
                propagate
            )

        let carry =
            or(
                xy,
                cp
            )

        return FullAdder.Output(
            sum: sum,
            carry: carry
        )
    }
}

// ============================================================================
// MARK: - Binary Vector
// ============================================================================

public struct FullAdderVector:
    Sendable
{
    public let x: Logic
    public let y: Logic
    public let cin: Logic

    public init(
        _ x: Logic,
        _ y: Logic,
        _ cin: Logic
    ) {
        self.x = x
        self.y = y
        self.cin = cin
    }
}

// ============================================================================
// MARK: - Full Adder Truth Space
// ============================================================================

public enum FullAdderTruthSpace {

    public static let binary:
        [FullAdderVector] =
        [
            FullAdderVector(
                .zero,
                .zero,
                .zero
            ),

            FullAdderVector(
                .zero,
                .zero,
                .one
            ),

            FullAdderVector(
                .zero,
                .one,
                .zero
            ),

            FullAdderVector(
                .zero,
                .one,
                .one
            ),

            FullAdderVector(
                .one,
                .zero,
                .zero
            ),

            FullAdderVector(
                .one,
                .zero,
                .one
            ),

            FullAdderVector(
                .one,
                .one,
                .zero
            ),

            FullAdderVector(
                .one,
                .one,
                .one
            )
        ]
}

// ============================================================================
// MARK: - Phase-II Equivalence Report
// ============================================================================

public struct PhaseIIEquivalenceReport:
    Sendable
{
    public let checked:
        Int

    public let failures:
        [String]

    public var passed: Bool {
        failures.isEmpty
    }
}

// ============================================================================
// MARK: - Logical / CMOS Equivalence
// ============================================================================

public enum CMOSLogicalEquivalence {

    public static func verify()
        -> PhaseIIEquivalenceReport
    {
        var checked = 0

        var failures:
            [String] = []

        for vector
            in FullAdderTruthSpace.binary
        {
            checked += 1

            let swift =
                FullAdder.evaluate(
                    .init(
                        x: vector.x,
                        y: vector.y,
                        cin: vector.cin
                    )
                )

            let physicalReference =
                CMOSReferenceLogic.fullAdder(
                    x: vector.x,
                    y: vector.y,
                    cin: vector.cin
                )

            if swift != physicalReference {

                failures.append(
                    """
                    semantic mismatch \
                    X=\(vector.x) \
                    Y=\(vector.y) \
                    CIN=\(vector.cin) \
                    swift=(\(swift.sum),\(swift.carry)) \
                    cmos=(\(physicalReference.sum),\(physicalReference.carry))
                    """
                )
            }
        }

        return PhaseIIEquivalenceReport(
            checked: checked,
            failures: failures
        )
    }
}
