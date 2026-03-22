## Generated SDC file "fir_basic.out.sdc"

## Copyright (C) 2025  Altera Corporation. All rights reserved.
## Your use of Altera Corporation's design tools, logic functions 
## and other software and tools, and any partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Altera Program License 
## Subscription Agreement, the Altera Quartus Prime License Agreement,
## the Altera IP License Agreement, or other applicable license
## agreement, including, without limitation, that your use is for
## the sole purpose of programming logic devices manufactured by
## Altera and sold by Altera or its authorized distributors.  Please
## refer to the Altera Software License Subscription Agreements 
## on the Quartus Prime software download page.


## VENDOR  "Altera"
## PROGRAM "Quartus Prime"
## VERSION "Version 25.1std.0 Build 1129 10/21/2025 SC Lite Edition"

## DATE    "Sun Mar 22 12:15:41 2026"

##
## DEVICE  "5CGXFC7C7F23C8"
##


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {clk} -period 10.000 -waveform { 0.000 5.000 } [get_ports {clk}]


#**************************************************************
# Create Generated Clock
#**************************************************************



#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************

set_clock_uncertainty -rise_from [get_clocks {clk}] -rise_to [get_clocks {clk}] -setup 0.100  
set_clock_uncertainty -rise_from [get_clocks {clk}] -rise_to [get_clocks {clk}] -hold 0.070  
set_clock_uncertainty -rise_from [get_clocks {clk}] -fall_to [get_clocks {clk}] -setup 0.100  
set_clock_uncertainty -rise_from [get_clocks {clk}] -fall_to [get_clocks {clk}] -hold 0.070  
set_clock_uncertainty -fall_from [get_clocks {clk}] -rise_to [get_clocks {clk}] -setup 0.100  
set_clock_uncertainty -fall_from [get_clocks {clk}] -rise_to [get_clocks {clk}] -hold 0.070  
set_clock_uncertainty -fall_from [get_clocks {clk}] -fall_to [get_clocks {clk}] -setup 0.100  
set_clock_uncertainty -fall_from [get_clocks {clk}] -fall_to [get_clocks {clk}] -hold 0.070  


#**************************************************************
# Set Input Delay
#**************************************************************

set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[0]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[0]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[1]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[1]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[2]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[2]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[3]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[3]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[4]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[4]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[5]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[5]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[6]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[6]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[7]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[7]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[8]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[8]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[9]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[9]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[10]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[10]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[11]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[11]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[12]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[12]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[13]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[13]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[14]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[14]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din[15]}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din[15]}]
set_input_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {din_valid}]
set_input_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {din_valid}]


#**************************************************************
# Set Output Delay
#**************************************************************

set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[0]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[0]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[1]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[1]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[2]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[2]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[3]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[3]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[4]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[4]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[5]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[5]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[6]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[6]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[7]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[7]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[8]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[8]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[9]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[9]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[10]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[10]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[11]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[11]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[12]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[12]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[13]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[13]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[14]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[14]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[15]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[15]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[16]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[16]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[17]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[17]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[18]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[18]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[19]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[19]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[20]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[20]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[21]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[21]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[22]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[22]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[23]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[23]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[24]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[24]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[25]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[25]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[26]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[26]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[27]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[27]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[28]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[28]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[29]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[29]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[30]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[30]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[31]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[31]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[32]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[32]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[33]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[33]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[34]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[34]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[35]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[35]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[36]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[36]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout[37]}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout[37]}]
set_output_delay -add_delay -max -clock [get_clocks {clk}]  5.000 [get_ports {dout_valid}]
set_output_delay -add_delay -min -clock [get_clocks {clk}]  0.000 [get_ports {dout_valid}]


#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************

set_false_path -from [get_ports {rst_n}] 


#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

