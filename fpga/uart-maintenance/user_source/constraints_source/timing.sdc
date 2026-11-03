# Direct 50MHz board oscillator. No PLL or generated internal clock.
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
# UART is asynchronous and is synchronized by serial/rx_meta -> rx_sync.
# All internal functional register-to-register paths remain timed.
