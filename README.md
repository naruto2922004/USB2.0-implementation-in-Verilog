# USB 2.0 Implementation in Verilog

A ground-up, fully synthesizable Verilog implementation of the USB 2.0 protocol covering the complete stack from the differential-line PHY layer up through the protocol layer — verified in simulation for both HID keyboard and HID mouse devices.

---

## Overview

This project implements a single-host, single-device USB 2.0 system. Every layer of the stack is hand-written in synthesizable RTL: bit-level encoding/decoding, packet framing, CRC computation, link-layer sequencing, and the full host and device protocol state machines. The goal was a deep, concrete understanding of how USB works at every level — not just the software-visible part, but the actual bits on the wire.

The complete control transfer and interrupt transfer flow has been implemented and verified end-to-end in simulation, including enumeration, HID descriptor retrieval, and periodic HID report delivery.

---

## Architecture

The design is split into four layers, mirroring the USB specification's layered model.

```
┌─────────────────────────────────────────────┐
│             Protocol Layer                  │
│   host_protocol.v   │   mouse/keyboard      │
│   (host FSM)        │   _protocol.v (dev)   │
├─────────────────────────────────────────────┤
│              Link Layer                     │
│        tx_link.v  │  rx_link.v              │
│  (packet framing, CRC, data toggle, FIFO)   │
├─────────────────────────────────────────────┤
│               PHY Layer                     │
│  TX: serializer → bitstuffer → NRZI encoder │
│  RX: NRZI decoder → bitunstuffer →          │
│       sync_detect → deserializer            │
├─────────────────────────────────────────────┤
│          Differential Line Layer            │
│  diff_tx_driver.v  │  diff_rx_sampler.v     │
│           eop_detect.v  │  bus.v            │
└─────────────────────────────────────────────┘
```

### Directory Structure

```
├── phy/
│   ├── tx/
│   │   ├── serializer.v        # Parallel-to-serial, 8-bit to 1-bit
│   │   ├── bitstuffer.v        # Inserts zero after 6 consecutive ones
│   │   ├── nrzi_encoder.v      # NRZI encoding for the wire
│   │   └── tx.v                # TX PHY top — wires the TX pipeline
│   └── rx/
│       ├── nrzi_decoder.v      # NRZI decoding from line transitions
│       ├── bitunstuffer.v      # Removes stuffed zero bits
│       ├── sync_detect.v       # SYNC pattern detection, EOP detection
│       ├── deserializer.v      # Serial-to-parallel, 1-bit to 8-bit
│       ├── diff_rx_sampler.v   # Differential line → logic-level
│       ├── eop_detect.v        # SE0 EOP detection
│       └── rx.v                # RX PHY top — wires the RX pipeline
├── link/
│   ├── tx_link.v               # FIFO drain, PID prepend, CRC16 append
│   └── rx_link.v               # PID strip, CRC16 verify, FIFO fill
├── device/
│   ├── device_phy_link.v       # Device-side PHY+link integration
│   ├── device_diff.v           # Differential driver/enable control
│   ├── mouse_protocol.v        # HID mouse device state machine
│   └── keyboard_protocol.v    # HID keyboard device state machine
├── host/
│   ├── host_phy_link.v         # Host-side PHY+link integration
│   ├── host_diff.v             # Differential driver/enable control
│   └── host_protocol.v        # Full host protocol state machine
├── shared/
│   ├── crc5_engine.v           # CRC-5 for token packets
│   ├── crc16_engine.v          # CRC-16 for data packets (poly 0x8005)
│   ├── sync_fifo.v             # Synchronous FIFO (TX path)
│   ├── async_fifo.v            # Asynchronous FIFO (clock-domain crossing)
│   └── bus.v                   # Shared differential bus wire model
└── sim/
    ├── phy/                    # PHY-layer unit testbenches
    ├── link/                   # Link-layer unit testbench
    ├── phy_link/               # PHY+link integration testbench
    └── usb/
        ├── usb_mouse.v         # Full system top — mouse
        ├── usb_mouse_tb.v      # Mouse system testbench (10 checks)
        ├── usb_keyboard.v      # Full system top — keyboard
        └── udb_keyboard_tb.v   # Keyboard system testbench (10 checks)
```

---

## What Is Implemented

### PHY Layer — TX Path

| Module | Description |
|---|---|
| `serializer.v` | Converts 8-bit parallel data to a serial bit stream. Uses a 4-bit counter to precisely separate the last-bit emission from the byte-advance decision, avoiding corruption when the bitstuffer stalls on the final bit. |
| `bitstuffer.v` | Counts consecutive `1` bits and inserts a `0` after every six, per USB 2.0 spec §7.1.9. Drives `stall_upstream` combinationally to halt the serializer on the same cycle the stuffed bit is inserted. |
| `nrzi_encoder.v` | NRZI-encodes the serial bit stream: a `1` holds the line, a `0` toggles it. |
| `diff_tx_driver.v` | Drives the D+/D− differential pair from the encoded line state. |

### PHY Layer — RX Path

| Module | Description |
|---|---|
| `nrzi_decoder.v` | Recovers the original NRZ bit stream from differential line transitions. |
| `bitunstuffer.v` | Detects six consecutive `1` bits and discards the following `0` stuff bit, asserting `stall_downstream` for exactly one cycle. |
| `sync_detect.v` | FSM that recognises the USB SYNC pattern (KJKJKJKK for Full Speed), asserts `sync_detected` for the duration of the packet body, and asserts `packet_done` upon EOP. Holds `sync_detected` active through all EOP-transition states so the deserializer can capture any final byte arriving in the pipeline. |
| `deserializer.v` | Reassembles 8-bit bytes from the serial stream. Only operates while `sync_detected` is high and the current bit is not a stuffed zero. |
| `diff_rx_sampler.v` | Converts the D+/D− differential pair to a logic-level line state. |
| `eop_detect.v` | Detects the SE0 (both lines low) EOP condition. |

### Link Layer

| Module | Description |
|---|---|
| `tx_link.v` | Reads payload bytes from the TX FIFO, prepends the PID byte, then appends the two-byte CRC-16 (high byte then low byte). Drives the PHY with `next_packet`, `data_phy`, and `transfering` signals, and waits for `packet_done` before returning to idle. Handles the data toggle (DATA0/DATA1 alternation). |
| `rx_link.v` | Receives bytes from the deserializer, strips the PID, feeds the payload through the CRC-16 engine, and writes valid data to the RX FIFO. Uses a two-entry shift buffer to hold the last two received bytes so the CRC residual bytes are never written as data. Asserts `status` to indicate packet-valid, corrupt, or FIFO-empty. |

### Shared Components

| Module | Description |
|---|---|
| `crc5_engine.v` | CRC-5 computation for token packets (polynomial x⁵+x²+1). |
| `crc16_engine.v` | CRC-16 computation for data packets (polynomial 0x8005, bit-by-bit, with final inversion). Processes one byte per clock, shifting through all 8 bits in subsequent cycles. |
| `sync_fifo.v` | Parameterised synchronous FIFO used in the TX path. |
| `async_fifo.v` | Parameterised asynchronous FIFO with Gray-code pointer synchronisation for safe clock-domain crossing. |

### Host Protocol State Machine (`host_protocol.v`)

A large, hierarchical FSM that drives the full USB enumeration sequence and then services software-issued transfer requests:

1. **Reset** — asserts USB reset on the bus for the required duration
2. **GET_DESCRIPTOR (Device, 8 bytes)** — reads `bMaxPacketSize0`
3. **SET_ADDRESS** — assigns the device a non-zero address
4. **GET_DESCRIPTOR (Device, 18 bytes)** — reads the full device descriptor
5. **GET_DESCRIPTOR (Configuration, full)** — reads the configuration + interface + HID + endpoint descriptors
6. **SET_CONFIGURATION** — selects configuration 1
7. **Software-driven requests** — after enumeration, accepts `sw_request` commands from the testbench for HID class requests (SET_IDLE, SET_PROTOCOL) and interrupt IN transfers

The host generates SOF packets on the correct interval (`CLK_FREQ / 1000` for Full Speed, `CLK_FREQ / 8000` for High Speed), handles NAK retries, response timeouts (10 µs), and inter-packet gaps. All USB PID constants, standard request codes, and descriptor type codes are defined as named `localparam`s.

### Device Protocol State Machines

`mouse_protocol.v` and `keyboard_protocol.v` each implement the device-side responder:

- **ROM-based descriptors** — Device, Configuration, Interface, HID, Endpoint, and HID Report descriptors are stored in `always @(*)` case blocks, indexed by address counter, making them synthesisable ROM. The HID Report Descriptor encodes the full HID usage-page structure for each device class.
- **SETUP stage handling** — Decodes the 8-byte SETUP packet and dispatches to the appropriate response.
- **DATA stage** — Sends descriptor data in `bMaxPacketSize0`-sized chunks with correct DATA0/DATA1 toggle and ZLP (zero-length packet) termination.
- **Standard requests** — GET_DESCRIPTOR, SET_ADDRESS, SET_CONFIGURATION
- **HID class requests** — SET_IDLE, SET_PROTOCOL, GET_HID_REPORT_DESCRIPTOR
- **Interrupt IN** — Responds to IN tokens with the current HID report, alternating DATA0/DATA1, and handles the host's ACK.

---

## Simulation and Verification

### Testbench Structure

Each top-level testbench (`usb_mouse_tb.v`, `udb_keyboard_tb.v`) instantiates the complete host+device system including both PHY paths sharing a common differential bus model. The testbench acts as a software driver:

1. Asserts power-on reset and connects the device
2. Waits for enumeration to complete (host FSM reaches `PROTO_READY`)
3. Sends HID class setup requests via the `sw_request` interface
4. Starts an interrupt IN transfer and supplies HID reports via `ep1_in`/`ep1_valid`
5. Reads received data out of the host's RX FIFO and verifies it

A 10-point checklist covers every phase of the flow, and a watchdog timer fails the simulation if it does not complete within a bound.

### Verification Results

```
USB MOUSE TESTBENCH
=================================================================
|               USB MOUSE - VERIFICATION SUMMARY               |
=================================================================
| #  | Check                                | Result           |
-----------------------------------------------------------------
| 1  | Reset released                       | PASS             |
| 2  | Device connected                     | PASS             |
| 3  | Enumeration complete                 | PASS             |
| 4  | SET_CONFIGURATION                    | PASS             |
| 5  | GET_HID_REPORT_DESCRIPTOR            | PASS             |
| 6  | SET_IDLE                             | PASS             |
| 7  | SET_PROTOCOL                         | PASS             |
| 8  | Interrupt-IN transfer started        | PASS             |
| 9  | RX descriptor/data drained           | PASS             |
| 10 | Mouse report(s) sent                 | PASS             |
-----------------------------------------------------------------
 Reports sent : 16
=================================================================
 RESULT : 10 / 10 CHECKS PASSED
=================================================================
```

```
USB KEYBOARD TESTBENCH
=================================================================
|              USB KEYBOARD - VERIFICATION SUMMARY             |
=================================================================
| 10 checks — identical structure to mouse                     |
-----------------------------------------------------------------
 Reports sent : 16
=================================================================
 RESULT : 10 / 10 CHECKS PASSED
=================================================================
```

Both testbenches compile and simulate with **0 errors and 0 warnings**.

---


## How to Simulate

Tested with **ModelSim - Intel FPGA Edition 2020.1** (also referred to as ModelSim ASE).

### 1. Generate the file list

```powershell
((Get-ChildItem -Recurse -Filter *.v).FullName -replace '\\', '/') | Out-File -Encoding ascii files.f
```

### 2. Compile

```bash
vlog -f files.f
```

Expected output: `Errors: 0, Warnings: 0`

### 3. Run the mouse testbench

```bash
vsim -c -do "run -all; quit" usb_mouse_tb
```

### 4. Run the keyboard testbench

```bash
vsim -c -do "run -all; quit" usb_keyboard_tb
```

---

## Limitations and Future Scope

### Simulation Model Only

The current implementation represents one USB bit per clock cycle and shares the same clock across the protocol and PHY layers. This means it cannot be connected to a real USB differential line as-is. A real USB PHY requires:
- A dedicated bit-clock recovery circuit (typically a PLL or CDR)
- Oversampling of the differential line (e.g. 4× oversampling at 48 MHz for Full Speed)
- Separate protocol and PHY clock domains with proper CDC

### Not Implemented

- Bulk and isochronous transfers (the link layer is structured to support them; transfer type routing exists but the transfer logic is not filled in)
- USB hub and multi-device support
- Remaining special PIDs: PRE, SPLIT, PING, ERR
- Proper PHY clock recovery and line oversampling
- USB speed auto-detection on the bus
- FPGA-ready PHY interface (ULPI or equivalent)

### Possible Extensions

- Add bulk transfer support in `tx_link.v` / `rx_link.v` and the host/device FSMs
- Implement USB hub routing
- Replace the single-clock PHY model with a proper oversampling RX and a PLL-based TX
- Port to FPGA with a ULPI PHY companion chip



