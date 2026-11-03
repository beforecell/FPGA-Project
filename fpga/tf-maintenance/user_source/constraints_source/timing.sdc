create_clock -name sys_clk -period 20 [get_ports {clk}]
create_clock -name phy_rx -period 8 [get_ports {phy1_rgmii_rx_clk}]
derive_pll_clocks -instance [get_cells {u_tx_pll/pll_inst}]
derive_pll_clocks -instance [get_cells {u_rx_pll/pll_inst}]
# TX/RX vendor frame FIFOs are deliberately asynchronous;their pointers are
# synchronized in the supplied IP,regardless of the nominal PLL ratio.
set_clock_groups -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks {u_tx_pll*}] -group [get_clocks {phy_rx u_rx_pll*}]
# Startup assertion distribution only;functional Q->D paths remain timed.
set_false_path -through [get_nets {reset}]
