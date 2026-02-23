[200~# 🚀 AXI Protocol Suite - Complete From-Scratch Implementation

Complete, professional-quality implementation of AMBA AXI bus protocols 
and common digital peripherals. Built entirely from scratch using 
SystemVerilog with full testbenches and synthesis support.

## 📋 Project Overview

| Module | Protocol | Status |
|--------|----------|--------|
| AXI4-Lite Slave | AMBA AXI4-Lite | 🔄 In Progress |
| AXI4-Lite Master | AMBA AXI4-Lite | ⬜ Planned |
| AXI4-Full Slave | AMBA AXI4 | ⬜ Planned |
| AXI4-Full Master | AMBA AXI4 | ⬜ Planned |
| SPI Master/Slave | SPI | ⬜ Planned |
| I2C Master | I2C | ⬜ Planned |
| UART Controller | UART | ⬜ Planned |
| Simple SoC | Integration | ⬜ Planned |

## 🛠️ Tools Used

- **Language**: SystemVerilog (IEEE 1800-2017)
- **Simulator**: Verilator 5.x (Open Source)
- **Waveform**: GTKWave (Open Source)
- **Synthesis**: Xilinx Vivado 2023.x WebPACK (Free)
- **FPGA Target**: Xilinx Artix-7 (xc7a35tcpg236-1)

## 📁 Project Structure~
rtl/ → Synthesizable RTL modules (SystemVerilog)
tb/ → Testbenches (directed + constrained-random)
sim/ → Simulation scripts (Verilator Makefile, Vivado TCL)
synth/ → Synthesis scripts, constraints, utilization reports
assertions/ → SVA protocol compliance checkers
docs/ → Theory notes, block diagrams, waveform screenshots
## 🚀 Quick Start

```bash
# Clone
git clone git@github.com:Abhishek-Dhakad1/axi_protocol_suite.git
cd axi_protocol_suite

# Simulate (Verilator)
cd sim/verilator
make sim

# View Waveforms
make wave
👨‍💻 Author
Abhishek Dhakad - MTech VLSI Design

GitHub: @Abhishek-Dhakad1
Email: abhidhakad1289@gmail.com
📄 License
MIT License - See LICENSE file
