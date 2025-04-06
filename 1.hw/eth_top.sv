// SPDX-FileCopyrightText: 2024 Chili.CHIPS*ba
//
// SPDX-License-Identifier: BSD-3-Clause

//======================================================================== 
// openeye-CamSI * NLnet-sponsored open-source core for Camera I/F with ISP
//------------------------------------------------------------------------
//                   Copyright (C) 2024 Chili.CHIPS*ba
// 
// Redistribution and use in source and binary forms, with or without 
// modification, are permitted provided that the following conditions 
// are met:
//
// 1. Redistributions of source code must retain the above copyright 
// notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright 
// notice, this list of conditions and the following disclaimer in the 
// documentation and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its 
// contributors may be used to endorse or promote products derived
// from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS 
// IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED 
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A 
// PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT 
// HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, 
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT 
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY 
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE 
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//              https://opensource.org/license/bsd-3-clause
//------------------------------------------------------------------------
// Description: This is the Chip top-level file for Puzhi Artix35 board. It includes:
//   - Main PLL with top-level clock and reset generation
//   - Xilinx-specific IDELAY controller
//   - I2C Master for loading configuration into camera
//   - CSI_RX camera front-end
//   - ISP blocks:
//        - raw2rgb
//   - Asynchronous FIFO
//   - HDMI monitor back-end
//   - Package RGB data to UDP
//   - UDP Ethernet Video Stream Out
//   - Misc and Debug utilities
//========================================================================

module eth_top 
   import top_pkg::*;
   import hdmi_pkg::*;
(
   input logic sys_clk_p,
   input logic sys_clk_n,
   input logic sys_rst_n,   

  //I2C_Master to Camera
`ifdef COCOTB_SIM
   inout  tri1   i2c_sda,
   inout  tri1   i2c_scl,
`else
   inout  wire   i2c_sda,
   inout  wire   i2c_scl,
`endif //COCOTB_SIM

  //MIPI DPHY from/to Camera
   input  diff_t      cam_dphy_clk,
   input  lane_diff_t cam_dphy_dat,

   output logic       cam_en,
      
  //HDMI output, goes directly to connector
   output logic  hdmi_clk_p,
   output logic  hdmi_clk_n,
   output bus3_t hdmi_dat_p,
   output bus3_t hdmi_dat_n,
   
   /*
   * Ethernet: 1000BASE-T RGMII
   */
   input logic    phy_rgmii_rx_clk,
   input bus4_t   phy_rgmii_rxd,
   input logic    phy_rgmii_rx_ctl,
        
   output logic   phy_rgmii_tx_clk,
   output bus4_t  phy_rgmii_txd,
   output logic   phy_rgmii_tx_ctl,
   output logic   phy_rgmii_reset_n,
    
   output logic   phy_mdio_mdc,
   inout logic    phy_mdio_io,

  //Misc/Debug
   output bus2_t led,
   output bus8_t debug_pins
);

`ifdef COCOTB_SIM
glbl glbl();
`endif
//--------------------------------
// Clock and reset gen
//--------------------------------
   logic reset, i2c_areset_n;   
   logic clk_100, clk_125, clk_125_90, clk_180, clk_200, clk_1hz, strobe_400kHz;

   IBUFDS #(
      .DIFF_TERM("FALSE"),       
      .IBUF_LOW_PWR("TRUE"),     
      .IOSTANDARD("DEFAULT")     
   ) IBUFDS_inst (
      .O(clk_ext), 
      .I(sys_clk_p),  
      .IB(sys_clk_n) 
   );
   
   assign phy_rgmii_int_n = 1'b1;
   assign areset = ~sys_rst_n;

   clkrst_gen u_clkrst_gen (
      .reset_ext     (areset),        //i
      .clk_ext       (clk_ext),       //i: 200MHz Puzhi
                                       
      .clk_100       (clk_100),       //o: 100MHz 
      .clk_200       (clk_200),       //o: 200MHz 
      .clk_125       (clk_125),       //o: 125MHz 
      .clk_125_90    (clk_125_90),    //o: 125MHz, PHASE 90
      .clk_1hz       (clk_1hz),       //o: 1Hz
      .strobe_400kHz (strobe_400kHz), //o: pulse1 at 400kHz

      .reset         (reset),         //o
      .cam_en        (cam_en),        //o
      .i2c_areset_n  (i2c_areset_n)   //o
   );
  
//--------------------------------
// I2C Master
//--------------------------------
   bus8_t      debug_i2c;
   i2c_top  #(
      .I2C_SLAVE_ADDR (top_pkg::I2C_SLAVE_ADDR),
      .NUM_REGISTERS  (top_pkg::NUM_REGISTERS)
   ) u_i2c  (
     //clocks and resets
      .clk           (clk_100),       //i
      .strobe_400kHz (strobe_400kHz), //i
      .areset_n      (i2c_areset_n),  //i

     //I2C_Master to Camera
      .i2c_scl       (i2c_scl),       //io 
      .i2c_sda       (i2c_sda),       //io

     //Misc/Debug
      .debug_pins    (debug_i2c)      //o[7:0]
   );

//--------------------------------
// CSI_RX
//--------------------------------
   logic             csi_byte_clk;
   lane_raw_data_t   csi_word_data;
   logic             csi_word_valid;
   logic             csi_in_line, csi_in_frame;   
   bus8_t            debug_csi;
    
   csi_rx_top u_csi_rx_top (
      .ref_clock              (clk_200),        //i 
      .reset                  (reset),          //i 
                          
     //MIPI DPHY from/to Camera
      .cam_dphy_clk           (cam_dphy_clk),   //i'diff_t
      .cam_dphy_dat           (cam_dphy_dat),   //i'lane_diff_t
      .cam_en                 (cam_en),         //i 

     //CSI to internal video pipeline  
      .csi_byte_clk           (csi_byte_clk),   //o      
      .csi_unpack_raw_dat     (csi_word_data),  //o'lane_raw_data_t
      .csi_unpack_raw_dat_vld (csi_word_valid), //o

      .csi_in_line            (csi_in_line),    //o    
      .csi_in_frame           (csi_in_frame),   //o

     //Misc/Debug
      .debug_pins             (debug_csi)       //o[7:0]
   );
      
//--------------------------------
// ISP Functions
//--------------------------------
   logic  rgb_valid;
   pix_t  rgb_pix;
   logic  rgb_reading;

   isp_top #(
      .LINE_LENGTH (HSCREEN/NUM_LANE),  // number of data entries per line
      .RGB_WIDTH   ($bits(pix_t))       // width of RGB data (24-bit)
   )
   u_isp (
      .clk        (csi_byte_clk),   //i           
      .rst        (reset),          //i

      .data_in    (csi_word_data),  //i'lane_raw_data_t
      .data_valid (csi_word_valid), //i  
      .rgb_valid  (rgb_valid),      //i

      .reading    (rgb_reading),    //o
      .rgb_out    (rgb_pix)         //o[RGB_WIDTH-1:0]
   );
      
//--------------------------------
// AsyncFIFO with Synchronization
//--------------------------------
   logic hdmi_clk;
   logic hdmi_frame;
   logic hdmi_blank;
   logic hdmi_reset_n;
   pix_t hdmi_pix;
   bus4_t debug_fifo;

   rgb2hdmi u_rgb2hdmi (
     //from/to CSI and RGB block
      .csi_clk      (csi_byte_clk),   //i           
      .reset        (reset),          //i

      .csi_in_line  (csi_in_line),    //i  
      .csi_in_frame (csi_in_frame),   //i  

      .rgb_pix      (rgb_pix),        //i'pix_t
      .rgb_reading  (rgb_reading),    //i 
      .rgb_valid    (rgb_valid),      //o

     //from/to HDMI block
      .hdmi_clk     (hdmi_clk),       //i

      .hdmi_frame   (hdmi_frame),     //i
      .hdmi_blank   (hdmi_blank),     //i
      .hdmi_reset_n (hdmi_reset_n),   //o
      .hdmi_pix     (hdmi_pix),       //o'pix_t 

      .debug_fifo   (debug_fifo)      //o'bus4_t
   );

//--------------------------------
// HDMI backend
//--------------------------------
   logic hdmi_hsync, hdmi_vsync;
   bus12_t x;
   bus11_t y;

   hdmi_top u_hdmi_top(
      .clk_ext      (clk_100),      //i 
      .clk_pix      (hdmi_clk),     //o
                     
      .pix          (hdmi_pix),     //i'pix_t  
     
     //synchronization
      .hdmi_reset_n (hdmi_reset_n), //i
  
      .hdmi_frame   (hdmi_frame),   //o

      .blank        (hdmi_blank),   //o
      .vsync        (hdmi_vsync),   //o 
      .hsync        (hdmi_hsync),   //o 
                     
     //HDMI output, goes directly to connector
      .hdmi_clk_p   (hdmi_clk_p),   //o
      .hdmi_clk_n   (hdmi_clk_n),   //o
      .hdmi_dat_p   (hdmi_dat_p),   //o'bus3_t
      .hdmi_dat_n   (hdmi_dat_n),   //o'bus3_t

      .x            (x),            //o'bus12_t
      .y            (y)             //o'bus11_t
   );

   logic       tx_clk;
   logic       tx_reset;
   logic       tx_valid;
   logic       tx_ready;
   logic       tx_last;    
   bus16_t     tx_length;
   bus8_t      tx_data;  
   bus8_t      debug_udp;
          
   rgb2udp_top u_rgb2udp (
      .clk        (csi_byte_clk),
      .rst        (reset),
      .enable     (cam_en),
      
      .in_frame   (csi_in_frame),
      .in_line    (rgb_reading),
             
      .data_in    (rgb_pix),
      .data_in_en (rgb_reading),
      
      .tx_length  (tx_length),
      .tx_data    (tx_data),
      .tx_valid   (tx_valid),
      .tx_ready   (tx_ready),
      .tx_last    (tx_last),
      .tx_reset   (tx_reset),
      
      .debug      (debug_udp)            
   );      
   
//--------------------------------
// Ethernet
//--------------------------------

   // IODELAY elements for RGMII interface to PHY
   bus4_t   phy_rgmii_rxd_delay;
   logic    phy_rgmii_rx_ctl_delay;
  
   phy_rx_idelay u_phy_rx_idelay (
      .phy_rxd          (phy_rgmii_rxd),
      .phy_rxd_delay    (phy_rgmii_rxd_delay),
      .phy_rx_ctl       (phy_rgmii_rx_ctl),
      .phy_rx_ctl_delay (phy_rgmii_rx_ctl_delay)      
   );
   
   // buffer TX clock
   BUFG tx_clk_bufg (
      .I(csi_byte_clk),
      .O(tx_clk)
   );
           
   udp_stream #(
      .TARGET("XILINX")
   ) u_udp_stream (
      /*
       * Clock: 125MHz
       * Synchronous reset
       */
      .clk(clk_125),
      .clk90(clk_125_90),
      .rst(reset),
      
      /*
       * Ethernet: 1000BASE-T RGMII
       */
      .phy_rx_clk (phy_rgmii_rx_clk       ),
      .phy_rxd    (phy_rgmii_rxd_delay    ),
      .phy_rx_ctl (phy_rgmii_rx_ctl_delay ),
      .phy_tx_clk (phy_rgmii_tx_clk       ),
      .phy_txd    (phy_rgmii_txd          ),
      .phy_tx_ctl (phy_rgmii_tx_ctl       ),
      .phy_reset_n(phy_rgmii_reset_n      ),
      .phy_int_n  (phy_rgmii_int_n        ),
       
      .tx_clk     (tx_clk        ),
      .tx_length  (tx_length     ),
      .tx_data    (tx_data       ),
      .tx_valid   (tx_valid      ),
      .tx_ready   (tx_ready      ),
      .tx_last    (tx_last       ),
      .tx_reset   (tx_reset      )
   );

   assign led[0] = cam_en;
   assign led[1] = clk_1hz; 

assign debug_pins = { tx_reset, tx_last, tx_valid, tx_ready, /*hdmi_reset_n, hdmi_hsync, hdmi_vsync, hdmi_frame,*/ rgb_reading,  hdmi_blank, csi_in_line, csi_in_frame};

endmodule: eth_top

/*
------------------------------------------------------------------------------
Version History:
------------------------------------------------------------------------------
 2024/2/30  AnelH: Initial creation
 2024/3/14  Armin Zunic: updated based on sim results
 2024/11/12 Armin Zunic: updated for code readability
 2025/03/02 AnelH: updated for code Puzhi board and UDP Ethernet logic
*/
