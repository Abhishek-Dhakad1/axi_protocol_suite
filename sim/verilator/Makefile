cd ~/projects/axi_protocol_suite/sim/verilator

# Pehle purana delete karo
rm -f Makefile

# Naya Makefile create karo using printf (tab-safe method)
printf '%s\n' \
'###############################################################################' \
'# Makefile for AXI4-Lite Slave simulation using Verilator' \
'###############################################################################' \
'' \
'RTL_DIR   = ../../rtl' \
'TB_DIR    = ../../tb' \
'WAVE_DIR  = ../../waves' \
'' \
'SRCS  = $(RTL_DIR)/pkg/axi_pkg.sv' \
'SRCS += $(RTL_DIR)/interfaces/axi4_lite_if.sv' \
'SRCS += $(RTL_DIR)/axi4_lite/axi4_lite_slave.sv' \
'SRCS += $(TB_DIR)/axi4_lite/tb_axi4_lite_slave.sv' \
'' \
'TOP = tb_axi4_lite_slave' \
'' \
'VFLAGS  = --binary --timing --trace --trace-structs' \
'VFLAGS += -Wall -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC' \
'VFLAGS += -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-TIMESCALEMOD' \
'VFLAGS += -Wno-fatal' \
'VFLAGS += --top-module $(TOP) --Mdir obj_dir' \
'' \
'.PHONY: all sim wave clean' \
'' \
'all: clean sim' \
'' > Makefile

# Ab tab-indented rules add karo (yahan TAB zaroori hai)
cat >> Makefile << 'MAKEEOF'
sim:
	@echo ""
	@echo "============================================"
	@echo "  AXI4-Lite Slave - Verilator Simulation"
	@echo "============================================"
	@echo "[1/3] Compiling..."
	verilator $(VFLAGS) $(SRCS)
	@echo "[2/3] Building..."
	@make -C obj_dir -f V$(TOP).mk -j$$(nproc) --quiet
	@echo "[3/3] Running..."
	@echo "--------------------------------------------"
	@mkdir -p $(WAVE_DIR)
	@cd $(WAVE_DIR) && ../sim/verilator/obj_dir/V$(TOP)
	@echo "--------------------------------------------"
	@echo "Waveform: $(WAVE_DIR)/axi4_lite_slave.vcd"

wave:
	gtkwave $(WAVE_DIR)/axi4_lite_slave.vcd &

clean:
	rm -rf obj_dir
	rm -f $(WAVE_DIR)/axi4_lite_slave.vcd
MAKEEOF

echo ""
echo "✅ Makefile created"
echo ""
# Verify tab characters are present (should show ^I for tabs)
echo "Verifying tabs in Makefile:"
cat -A Makefile | grep "verilator" | head -1
echo ""
