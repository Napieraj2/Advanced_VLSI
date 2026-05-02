# ===========================================================================
# viterbi.sdc — Synopsys Design Constraints for Viterbi decoder designs
# ===========================================================================
# Target: 100 MHz (10 ns period) on Cyclone V
# Shared by viterbi_soft and viterbi_hard revisions.
# ===========================================================================

# Primary clock
create_clock -name clk -period 10.000 [get_ports {clk}]

# Cut timing on asynchronous reset
set_false_path -from [get_ports {rst_n}]

# I/O delays (assuming half-period for unconstrained board-level I/O)
set_input_delay  -clock clk -max 5.0 [remove_from_collection [all_inputs] {clk rst_n}]
set_input_delay  -clock clk -min 0.0 [remove_from_collection [all_inputs] {clk rst_n}]
set_output_delay -clock clk -max 5.0 [all_outputs]
set_output_delay -clock clk -min 0.0 [all_outputs]
