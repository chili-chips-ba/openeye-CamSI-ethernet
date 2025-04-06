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
// Description: RGB-to-UDP Top level
// 
// Features: This module implements the converting pixel data from rgb888 to rgb565 format
// 
// We created a UDP packet with 2 bytes of frame and line counters and 1280 bytes of pixels. This means that our UDP packet length is 1282 bytes.
// In the first two bytes, 15-th bit represent the frame counter and on the PC side we can detect even and odd frames, the next 15 bits [14:0] represent 
// the line counter in the frame, in our case it is lines from 0 to 719.
// The next 1280 bytes represent the line pixels that we get from the RGB module. However, since the RGB module sends us pixels in the form of 
// RGB888 (3 bytes per pixel) and sends us 1280 pixels in one line, our packet should be 3840 bytes in length.
// Since we do not have a buffer to store these incoming pixels, we have to reduce this packet, the first part is to convert 
// the RGB888 format to RGB565 format, in this way instead of 3840 bytes we need to send 2560. 
// In the second round we can send every other pixel, let's say that in even lines we send even pixels: 0, 2, 4, ... 1178 in RGB565 format, and in odd lines 
// we send odd pixels: 1, 3, 5, .... 1179 on this way we have reduced the amount of pixels that we need to send via Ethernet to 1280 bytes per one CMOS line.
//
//========================================================================
module rgb2udp_top
  import top_pkg::*;
   import hdmi_pkg::*;   
(
   input  logic      clk,
   input  logic      rst,
   input  logic      enable,
   
   input  logic      in_frame,
   input  logic      in_line, 

   input  pix_t      data_in,
   input  logic      data_in_en,      
   
   input  logic      tx_ready,
   output bus16_t    tx_length,
   output bus8_t     tx_data,
   output logic      tx_valid,   
   output logic      tx_last,
   output logic      tx_reset,
   
   output bus8_t     debug
);

   parameter [3:0]   T_STATES_IDLE = 0,
                     T_STATES_INIT = 1,
                     T_STATES_WAIT_ROW = 2,
                     T_STATES_ROW_HI = 3,
                     T_STATES_ROW_LO = 4,
                     T_STATES_IMAGE_DATA = 5,
                     T_STATES_END_ROW = 6;

   parameter [15:0]  C_COL_START = 0;
   parameter [15:0]  C_COL_STOP = 1280;
   parameter [15:0]  C_ROW_START = 0;
   parameter [15:0]  C_ROW_STOP = 720;   
   parameter [15:0]  C_PACKET_LENGTH = 1282;
   
   bus2_t         I_FRAME_CNT;
   bus16_t        I_ROW_CNT;
   bus16_t        I_COL_CNT, I_COL_CNT_dl1, I_COL_CNT_dl2;
       
   bus4_t         I_CURRENT_STATE;
   bus4_t         I_NEXT_STATE;
   bus8_t         I_TX_FIFO_WRDAT_WORD;
   logic          I_TX_FIFO_WREN_WORD;   
   logic          in_frame_dl1;
   logic          in_line_dl1, in_line_dl2, in_line_dl3, in_line_dl4;
   pix_t          data_in_dl1, data_in_dl2, data_in_dl3, data_in_dl4;
   
   always_ff @(posedge clk)
   begin 
      if (rst) begin
         in_line_dl1 <= 1'b0;
         in_line_dl2 <= 1'b0;
         in_line_dl3 <= 1'b0;
         in_line_dl4 <= 1'b0;
         data_in_dl1 <= '0;
         data_in_dl2 <= '0;
         data_in_dl3 <= '0;
         data_in_dl4 <= '0;
      end else begin
         in_line_dl1 <= in_line;
         in_line_dl2 <= in_line_dl1;
         in_line_dl3 <= in_line_dl2;
         in_line_dl4 <= in_line_dl3;   
         data_in_dl1 <= data_in;
         data_in_dl2 <= data_in_dl1;
         data_in_dl3 <= data_in_dl2;
         data_in_dl4 <= data_in_dl3;
      end
   end
      
   always_ff @(posedge clk)
   begin
      if (rst) begin
         I_CURRENT_STATE <= T_STATES_IDLE;
      end else begin
         case (I_CURRENT_STATE)
            T_STATES_IDLE :
               if (tx_ready && enable && in_frame)
                  I_CURRENT_STATE <= T_STATES_INIT;
               else
                  I_CURRENT_STATE <= T_STATES_IDLE;

            T_STATES_INIT :
               I_CURRENT_STATE <= T_STATES_WAIT_ROW;
                  
            T_STATES_WAIT_ROW :
               if((enable == 1'b1) & (in_frame == 1'b1)) begin           
                  if((in_line_dl1 == 1'b0) && (in_line == 1'b1))            
                     I_CURRENT_STATE <= T_STATES_ROW_HI;
               end else 
                  I_CURRENT_STATE <= T_STATES_IDLE;
                                                 
            T_STATES_ROW_HI :    
               I_CURRENT_STATE <= T_STATES_ROW_LO;
                        
            T_STATES_ROW_LO :
               I_CURRENT_STATE <= T_STATES_IMAGE_DATA;
                                                                                                                                                                               
            T_STATES_IMAGE_DATA :
               if((enable == 1'b1) & (in_frame == 1'b1)) begin
                  if((in_line_dl3 == 1'b1) && (in_line_dl2 == 1'b0))
                     I_CURRENT_STATE <= T_STATES_END_ROW;
                  else
                     I_CURRENT_STATE <= T_STATES_IMAGE_DATA;
               end else
                  I_CURRENT_STATE <= T_STATES_IDLE;
  
            T_STATES_END_ROW :
               I_CURRENT_STATE <= T_STATES_WAIT_ROW;
                     
         endcase
      end
   end
    
   always_ff @(posedge clk)
   begin
      if (rst) begin
         I_FRAME_CNT <= 2'd0;
         in_frame_dl1 <= 1'b0;
      end else begin
         in_frame_dl1 <= in_frame;
         if(in_frame_dl1 == 1'b1 && in_frame == 1'b0) begin
            I_FRAME_CNT <= I_FRAME_CNT + 2'd1;    
         end            
      end
   end   
   
   //------------------------------------------------------------------------------
   // column counter
   //------------------------------------------------------------------------------     
   always_ff @(posedge clk)
   begin: COL_CNT_EVAL
      if (rst == 1'b1) begin
         I_COL_CNT <= {16{1'b0}};
         I_COL_CNT_dl1 <= {16{1'b0}};
         I_COL_CNT_dl2 <= {16{1'b0}};
      end else begin
         if (enable == 1'b1 && in_frame == 1'b1) begin
            I_COL_CNT_dl1 <= I_COL_CNT;
            I_COL_CNT_dl2 <= I_COL_CNT_dl1;
            if(I_CURRENT_STATE == T_STATES_IMAGE_DATA)
               I_COL_CNT <= I_COL_CNT + 16'd1;                
            else
               I_COL_CNT <= {16{1'b0}};
         end else
            I_COL_CNT <= {16{1'b0}};
      end
   end
         
   //------------------------------------------------------------------------------
   // row counter
   //------------------------------------------------------------------------------       
   always_ff @(posedge clk)
   begin
      if (rst == 1'b1) begin
         I_ROW_CNT <= {16{1'b0}};
      end else begin        
         if (enable == 1'b1) begin               
            if (in_frame == 1'b1) begin                 
               if (in_line_dl4 == 1'b1 && in_line_dl3 == 1'b0)
                  I_ROW_CNT <= I_ROW_CNT + 1'b1;
            end else
               I_ROW_CNT <= {16{1'b0}};
         end else
            I_ROW_CNT <= {16{1'b0}};                
      end
   end
    
   always_ff @(posedge clk)
   begin
      if (rst) begin
         I_TX_FIFO_WREN_WORD <= 1'b0;
      end else begin 
         case (I_CURRENT_STATE)
            T_STATES_IDLE :
               I_TX_FIFO_WREN_WORD <= 1'b0;
               
            T_STATES_INIT :
               I_TX_FIFO_WREN_WORD <= 1'b0;    
           
            T_STATES_WAIT_ROW :
               I_TX_FIFO_WREN_WORD <= 1'b0;  
                          
            T_STATES_ROW_HI :
               if(tx_enable && (I_ROW_CNT >= C_ROW_START) && (I_ROW_CNT < C_ROW_STOP))
                  I_TX_FIFO_WREN_WORD <= 1'b1;
               else 
                  I_TX_FIFO_WREN_WORD <= 1'b0;   
                                 
            T_STATES_ROW_LO :
               if(tx_enable && (I_ROW_CNT >= C_ROW_START) && (I_ROW_CNT < C_ROW_STOP))
                  I_TX_FIFO_WREN_WORD <= 1'b1;
               else 
                  I_TX_FIFO_WREN_WORD <= 1'b0;               
                                                                                                          
            T_STATES_IMAGE_DATA : begin
                  if(tx_enable && in_line_dl3 == 1'b1) begin
                     if((I_ROW_CNT >= C_ROW_START) && (I_ROW_CNT < C_ROW_STOP)) begin                        
                        if((C_COL_START <= I_COL_CNT) && (I_COL_CNT < C_COL_STOP)) begin
                           I_TX_FIFO_WREN_WORD <= 1'b1;
                        end else
                           I_TX_FIFO_WREN_WORD <= 1'b0;                                                
                     end else
                        I_TX_FIFO_WREN_WORD <= 1'b0;                        
                  end else
                     I_TX_FIFO_WREN_WORD <= 1'b0;
               end
                                                                
            T_STATES_END_ROW : 
               I_TX_FIFO_WREN_WORD <= 1'b0;                 
         endcase
      end
   end
       
   always_ff @(posedge clk)
   begin
      if (rst)
         I_TX_FIFO_WRDAT_WORD <= {8{1'b0}};
      else begin
         case (I_CURRENT_STATE)
            T_STATES_IDLE :
               I_TX_FIFO_WRDAT_WORD <= {8{1'b0}};
            T_STATES_INIT :
               I_TX_FIFO_WRDAT_WORD <= 8'h00;
            T_STATES_WAIT_ROW :
               I_TX_FIFO_WRDAT_WORD <= 8'h00;
            T_STATES_ROW_HI :
               I_TX_FIFO_WRDAT_WORD <= {I_FRAME_CNT[0], I_ROW_CNT[14:8]};
            T_STATES_ROW_LO :
               I_TX_FIFO_WRDAT_WORD <= I_ROW_CNT[7:0];  
            T_STATES_IMAGE_DATA : 
            begin
               if((I_ROW_CNT[0] == 1'b0) && (I_COL_CNT[0] == 0)) begin //even row, even column: 0, 2, 4, ..., 1278
                  I_TX_FIFO_WRDAT_WORD <= {data_in_dl3[23:19], data_in_dl3[15:9], data_in_dl3[7:3]}[15:8];   // Pixel_0 RGB565[15:8], Pixel_2 RGB565[15:8], ...
               end else if((I_ROW_CNT[0] == 1'b0) && (I_COL_CNT[0] == 1)) begin //even row, odd column: 1, 3, 5, ..., 1279                  
                  I_TX_FIFO_WRDAT_WORD <= {data_in_dl4[23:19], data_in_dl4[15:9], data_in_dl4[7:3]}[7:0];    // Pixel_0 RGB565[7:0], Pixel_2 RGB565[7:0], ...
               end else if((I_ROW_CNT[0] == 1'b1) && (I_COL_CNT[0] == 0)) begin //odd row, even column: 0, 2, 4, ..., 1278                  
                  I_TX_FIFO_WRDAT_WORD <= {data_in_dl2[23:19], data_in_dl2[15:9], data_in_dl2[7:3]}[15:8];  // Pixel_1 RGB565[15:8], Pixel_3 RGB565[15:8], ...
               end else if((I_ROW_CNT[0] == 1'b1) && (I_COL_CNT[0] == 1)) begin //odd row, odd column: 1, 3, 5, ..., 1279              
                  I_TX_FIFO_WRDAT_WORD <= {data_in_dl3[23:19], data_in_dl3[15:9], data_in_dl3[7:3]}[7:0];   // Pixel_1 RGB565[7:0], Pixel_3 RGB565[7:0], ...
               end  
            end
                                           
            T_STATES_END_ROW :
               I_TX_FIFO_WRDAT_WORD <= 8'hEE;                                
         endcase
      end
   end

   //Enable transmit over Ethernet for every received CMOS line
   assign tx_enable = 1'b1;
   
   //Enable transmit over Ethernet for every odd frame send odd line and for even frame send even line, we use this case if we have issue with ethernet bandwidth
//   assign tx_enable = ((I_FRAME_CNT[0] == 0) && (I_ROW_CNT[0] == 0)) || ((I_FRAME_CNT[0] == 1) && (I_ROW_CNT[0] == 1));
   
   assign tx_length = C_PACKET_LENGTH; 
   assign tx_reset = (in_frame_dl1 == 1'b0 && in_frame == 1'b1) ? 1'b1 : 1'b0;
   
   assign tx_data =  I_TX_FIFO_WRDAT_WORD;
   assign tx_valid =  I_TX_FIFO_WREN_WORD;
   assign tx_last = tx_enable && (I_ROW_CNT < C_ROW_STOP) && (I_CURRENT_STATE == T_STATES_END_ROW);

   assign debug = { 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, (I_CURRENT_STATE == T_STATES_INIT), (I_CURRENT_STATE == T_STATES_IMAGE_DATA),  tx_last};

endmodule: rgb2udp_top

/*
------------------------------------------------------------------------------
Version History:
------------------------------------------------------------------------------
 2024/12/10 Anel H: Initial creation 
*/
