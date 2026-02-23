###############################################################################
# File:    sim/verilator/Makefile
# Author:  Abhishek Dhakad
# Purpose: Compile and simulate AXI4-Lite Slave using Verilator
#
# Usage:
#   make sim    → Compile + Run simulation
#   make wave   → Open waveform in GTKWave
#   make clean  → Remove build files
#   make all    → clean + sim
###############################################################################

# ─── Project Paths ───
RTL_DIR   = ../../rtl
TB_DIR    = ../../tb
WAVE_DIR  = ../../waves

# ─── Source Files (ORDER MATTERS! Package first, then interface, then modules) ───
SRCS  = $(RTL_DIR)/pkg/axi_pkg.sv
SRCS += $(RTL_DIR)/interfaces/axi4_lite_if.sv
SRCS += $(RTL_DIR)/axi4_lite/axi4_lite_slave.sv
SRCS += $(TB_DIR)/axi4_lite/tb_axi4_lite_slave.sv

# ─── Top Module ───
TOP = tb_axi4_lite_slave

# ─── Verilator Flags ───
VFLAGS  = --binary           # Generate standalone executable
VFLAGS += --timing           # Support #delays, @(posedge), etc.
VFLAGS += --trace            # Enable VCD waveform generation
VFLAGS += --trace-structs    # Better signal names in VCD
VFLAGS += -Wall              # All warnings ON
VFLAGS += -Wno-WIDTHEXPAND   # Suppress width expansion warnings
VFLAGS += -Wno-WIDTHTRUNC    # Suppress width truncation warnings
VFLAGS += -Wno-UNUSEDSIGNAL  # Suppress unused signal warnings
VFLAGS += --top-module $(TOP)
VFLAGS += --Mdir obj_dir     # Build directory

# ─── Targets ───
.PHONY: all sim wave clean lint

# Default: clean + sim
all: clean sim

# Compile and run simulation
sim:
	@echo ""
	@echo "══════════════════════════════════════════════"
	@echo "  Phase 1: AXI4-Lite Slave Simulation"
	@echo "  Tool: Verilator"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo "Step 1: Compiling..."
	verilator $(VFLAGS) $(SRCS)
	@echo ""
	@echo "Step 2: Building..."
	@make -C obj_dir -f V$(TOP).mk -j$$(nproc) --quiet
	@echo ""
	@echo "Step 3: Running simulation..."
	@echo "──────────────────────────────────────────────"
	@mkdir -p $(WAVE_DIR)
	@cd $(WAVE_DIR) && ../sim/verilator/obj_dir/V$(TOP)
	@echo "──────────────────────────────────────────────"
	@echo ""
	@echo "Waveform: $(WAVE_DIR)/axi4_lite_slave.vcd"
	@echo ""

# Open waveform viewer
wave:
	@echo "Opening GTKWave..."
	gtkwave $(WAVE_DIR)/axi4_lite_slave.vcd &

# Lint check only (no simulation)
lint:
	verilator --lint-only -Wall $(SRCS)

# Clean build files
clean:
	rm -rf obj_dir
	rm -f $(WAVE_DIR)/axi4_lite_slave.vcd
	@echo "Clean done."
