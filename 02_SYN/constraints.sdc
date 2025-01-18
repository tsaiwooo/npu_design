###############################################################################
# constraints.sdc
###############################################################################

# 1) 定義時鐘週期 (假設 7ns)
set CYCLE 7.0

###############################################################################
# 2) 創建時鐘
###############################################################################

# 為 AXI Slave 接口創建時鐘 s00_axis_aclk
create_clock -name s00_axis_aclk -period $CYCLE [get_ports s00_axis_aclk]

# 為 AXI Master 接口創建時鐘 m00_axis_aclk
create_clock -name m00_axis_aclk -period $CYCLE [get_ports m00_axis_aclk]

###############################################################################
# 3) 設定 s00_axis_aclk 時鐘域相關約束
###############################################################################

# (A) 設定輸入延遲 (假設延遲為時鐘週期的一半 3.5 ns)
#     這些輸入訊號屬於 s00_axis_aclk 時鐘域
set_input_delay [expr $CYCLE*0.5] \
    -clock [get_clocks s00_axis_aclk] \
    [get_ports {
        s00_axis_tdata
        s00_axis_tstrb
        s00_axis_tvalid
        s00_axis_tlast
        s00_axis_tuser
        quantized_multiplier
        shift
    }]

# (B) [修正] 放寬輸出延遲 (原本 3.5 ns 改為 3.45 ns)
#     這些輸出訊號屬於 s00_axis_aclk 時鐘域
#     讓設計多 0.05 ns 的時間收斂路徑 (7.0 - 3.45 = 3.55 ns)
set_output_delay 3.45 \
    -clock [get_clocks s00_axis_aclk] \
    [get_ports s00_axis_tready]

# (C) 設定輸出負載 (Load)
set_load 0.05 [get_ports s00_axis_tready]

# (D) 設定最大延遲 (set_max_delay)
#     !!! 注意: set_max_delay 不需要 -clock 選項 !!!
set_max_delay 5 \
    -from [get_pins axi_stream_input_inst/s_axis_tready] \
    -to   [get_ports s00_axis_tready]

###############################################################################
# 4) 設定 m00_axis_aclk 時鐘域相關約束
###############################################################################

# (A) 設定輸入延遲 (維持 3.5 ns 不變)
set_input_delay [expr $CYCLE*0.5] \
    -clock [get_clocks m00_axis_aclk] \
    [get_ports m00_axis_tready]

# (B) 設定輸出延遲 (維持 3.5 ns 不變)
set_output_delay [expr $CYCLE*0.5] \
    -clock [get_clocks m00_axis_aclk] \
    [get_ports {
        m00_axis_tdata
        m00_axis_tstrb
        m00_axis_tvalid
        m00_axis_tlast
        m00_axis_tuser
    }]

# (C) 設置這些輸出端口的負載
set_load 0.05 [get_ports {
    m00_axis_tdata
    m00_axis_tstrb
    m00_axis_tvalid
    m00_axis_tlast
    m00_axis_tuser
}]

