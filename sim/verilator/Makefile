cd ~/projects/axi_protocol_suite

cat > sim/verilator/Makefile << 'FILEEND'
###############################################################################
# Makefile for AXI4-Lite Slave simulation using Verilator
# Usage: make sim | make wave | make clean
###############################################################################

RTL_DIR   = ../../rtl
TB_DIR    = ../../tb
WAVE_DIR  = ../../waves

SRCS  = $(RTL_DIR)/pkg/axi_pkg.sv
SRCS += $(RTL_DIR)/interfaces/axi4_lite_if.sv
SRCS += $(RTL_DIR)/axi4_lite/axi4_lite_slave.sv
SRCS += $(TB_DIR)/axi4_lite/tb_axi4_lite_slave.sv

TOP = tb_axi4_lite_slave

VFLAGS  = --binary
VFLAGS += --timing
VFLAGS += --trace
VFLAGS += --trace-structs
VFLAGS += -Wall
VFLAGS += -Wno-WIDTHEXPAND
VFLAGS += -Wno-WIDTHTRUNC
VFLAGS += -Wno-UNUSEDSIGNAL
VFLAGS += -Wno-UNUSEDPARAM
VFLAGS += -Wno-TIMESCALEMOD
VFLAGS += -Wno-fatal
VFLAGS += --top-module $(TOP)
VFLAGS += --Mdir obj_dir

.PHONY: all sim wave clean lint

all: clean sim

sim:
	@echo ""
	@echo "============================================"
	@echo "  AXI4-Lite Slave - Verilator Simulation"
	@echo "============================================"
	@echo ""
	@echo "[1/3] Compiling..."
	verilator $(VFLAGS) $(SRCS)
	@echo "[2/3] Building..."
	@make -C obj_dir -f V$(TOP).mk -j$$(nproc) --quiet
	@echo "[3/3] Running..."
	@echo "--------------------------------------------"
	@mkdir -p $(WAVE_DIR)
	@cd $(WAVE_DIR) && ../sim/verilator/obj_dir/V$(TOP)
	@echo "--------------------------------------------"
	@echo ""
	@echo "Waveform: $(WAVE_DIR)/axi4_lite_slave.vcd"
	@echo ""

wave:
	gtkwave $(WAVE_DIR)/axi4_lite_slave.vcd &

lint:
	verilator --lint-only -Wall $(SRCS)

clean:
	rm -rf obj_dir
	rm -f $(WAVE_DIR)/axi4_lite_slave.vcd
FILEEND

echo "✅ Makefile updated"
