# openeye-CamSI-ethernet
1Gbps Ethernet uplink of live camera video over UDP. This is a component of openeye-CamSI project that may be used independently. It comes with GUI app for rendering UDP video on PC.
For details about main project openeye-CamSI, please refer to the parent [openeye-CamSI](https://github.com/chili-chips-ba/openeye-CamSI) project.

## Introduction to openeye-CamSI-ethernet subproject

Initially, it was planned to use the same hardware for the Ethernet subproject as for the main project, i.e. the following configuration:
- Trenz Carrier Card (TEB0707-02)
- Trenz 4x5 SoM with Artix-7 FPGA (TE0711-01)
- VHDPlus HDMI + 2-lane CSI Camera adapter
- Raspberry Pi V2.1 camera (Sony IMX219)

However, due to the inability to achieve a transfer rate of 1Gbps, we had to adapt and change the FPGA board, for this purpose we used the 
[Puzhytech PA35T-StarLite](https://www.aliexpress.us/item/3256806434967523.html?gps-id=pcStoreJustForYou&scm=1007.23125.137358.0&scm_id=1007.23125.137358.0&scm-url=1007.23125.137358.0&pvid=c1d02f3c-8f66-4b76-a24a-a72144960d79&_t=gps-id%3ApcStoreJustForYou%2Cscm-url%3A1007.23125.137358.0%2Cpvid%3Ac1d02f3c-8f66-4b76-a24a-a72144960d79%2Ctpp_buckets%3A668%232846%238107%231934&pdp_npi=4%40dis%21USD%21128.44%21102.75%21%21%21901.32%21721.06%21%402101c67a17281960440137763ec377%2112000037845115402%21rec%21US%212013047485%21XZ&spm=a2g0o.store_pc_home.smartJustForYou_2010082555490.1005006621282275&gatewayAdapt=glo2usa) development board, which fit into our budget. 
This compact card brings everything we need for video projects off-the-bat, within basic package, including 2-lane MIPI CSI connector, HDMI output and 1Gbps Ethernet. 
No need for multiple add-on cards and connectors to put together a useable system that's 3x more expensive, more fragile, and not in stock.

Unfortunately, since we had no documentation for this board, we only discovered that the MIPI CSI-2 interface was not implemented once we had it in our hands. For this reason, our recommendation is to use the more powerful Puzhytech PA75T-StarLite board, which includes a built-in MIPI CSI-2 interface. Although the Puzhy PA35T board lacked CSI-2 support, we were still able to establish a connection and enable CMOS communication with the FPGA through the 40-pin connector by using an old IDE hard-drive ribbon cable as an adapter.

<p align="center" style="margin: 20px;">
    <div style="display: flex; justify-content: center; margin: 20px;">
        <img width="300" src="0.doc/Images/hard-drive-IDE.jpg" hspace="20">
        <img width="300" src="0.doc/Images/soldering-skill.jpg" hspace="20">
    </div>
</p>

<p align="center" style="margin: 20px;">
  <video src="0.doc/Video/Puzhi-2lane-improvized.mp4" controls width="600"></video>

  [Video Link](https://github.com/user-attachments/assets/f2797042-4659-47c1-8f70-43437a3e3c2f)
</p>


## Block Diagram Explanation

The block diagram illustrates the complete camera-to-HDMI and camera-to-UDP-stream data flow implemented on the FPGA module (eth_top) and how the video stream is finally displayed on a PC.

<p align="center" style="margin: 20px;">
  <img width="600" src="0.doc/Images/Block Diagram.png" >
<p>

The system has two parallel video outputs:
Local HDMI display directly from FPGA and UDP video stream sent over Ethernet to a PC, where the PC decodes and displays the video.
1.  CMOS Camera → FPGA (CSI-2 Interface)
    The CMOS camera outputs video using a MIPI CSI-2 interface.
    These signals enter the FPGA and are processed by the csi_rx_top module, which contains:
    - Clock and data PHY receivers
    - Clock detector
    - Byte aligners
    - Word aligner
    - Packet depacketizer
    This module converts the serialized MIPI CSI-2 data into parallel RAW pixel data plus timing signals (line/frame valid).

2.  FPGA Internal Processing (eth_top)
    The FPGA block contains several functional modules:

    a) clkrst_gen – Clock and Reset Generator
    This module creates all internal clock domains required for:
    - Camera interface
    - ISP processing
    - HDMI output
    - Ethernet MAC
    - I²C timing
    It also generates internal resets and the signal that enables the camera (cam_en).

    b) i2c_top – Camera I²C Master
    This block initializes the CMOS camera at startup over the I²C bus.
    It writes sensor configuration registers such as exposure, frame size, and CSI settings.

    c) RAW-to-RGB Conversion (RAW-to-RGB)
    After depacketization, raw pixel data flows into the ISP stage, which performs:
    - Bayer RAW decoding
    - Color interpolation
    - RGB pixel generation
    This produces a continuous stream of RGB pixel data.

3.  FPGA Video Output 
    * Path #1: HDMI Display, the RGB stream is sent into the hdmi_top module, which converts RGB pixel data into TMDS signals for HDMI. Output:
        - HDMI clock (TMDS)
        - Three HDMI data channels (RGB encoded)
    These signals go directly to Display 1, providing a real-time hardware preview of the camera image.

    * Path #2: UDP Ethernet Streaming, parallel to the HDMI output, the RGB pixel stream is passed to the rgb2udp_top module, which:
        - Converts RGB pixels into byte packets
        - Packs pixels into UDP-sized payloads
        - Provides packet framing signals (valid, last, length, etc.)

        The UDP payload stream is then fed into the udp_stream module, which contains:
        - eth_mac (Ethernet MAC controller)
        - AXI-Stream interfaces (eth_axis_rx, eth_axis_tx)
        - UDP protocol handler
        - Final UDP packet transmitter (udp_rx_tx)

        This module bundles the packetized RGB data into fully valid Ethernet/IPv4/UDP frames,  which are transmitted over the Ethernet PHY.
        The output leaves the FPGA through an Ethernet cable, delivering the video stream to the PC.

4.  PC-Side Video Display
    On the PC side, the UDP packets are decoded and displayed in software.
    Two example implementations are shown:

    a) Python receiver [Source](5.sw/python)

    udp_receiver.py uses NumPy + OpenCV (cv2)
    Reconstructs the frames from UDP packets and displays them on Display 2

    b) QtUDP - C++ receiver [Source](5.sw/qt)

    Written using Qt + OpenCV
    Performs the same function: receives UDP video packets, reconstructs the image, and displays it.

    Both implementations can optionally output to an HDMI display connected to the PC.

## Explanation of RGB-to-UDP Conversion Logic
The purpose of the RGB-to-UDP module is to convert full-resolution RGB888 pixel data coming from the ISP into a compact UDP payload that can be streamed over Ethernet in real time, without requiring large frame buffers inside the FPGA.

The module performs:
- Pixel format reduction (RGB888 → RGB565)
- Pixel subsampling (sending every second pixel)
- Packetization into UDP frames

This ensures that each UDP packet fits within the size constraints of the Ethernet streaming design.

1.  Original Input Format (From ISP / RGB Module)
    
    The ISP sends pixels in the format:
    
        RGB888 → 3 bytes per pixel
        1280 pixels per line

        Therefore:
        1280 pixels × 3 bytes = 3840 bytes per line

    A full line in RGB888 would require 3840 bytes of UDP payload.

    However, this is too large for the intended UDP packet structure and cannot be buffered efficiently in the FPGA.

2.  UDP Packet Structure

    Each UDP packet is designed to be 1282 bytes:

        Bytes	Description
        0 – 1	Frame/line counters (combined into 16 bits)
        2 – 1281	Pixel data for that line (1280 bytes)

    Frame/Line counter encoding (2 bytes)

    A 16-bit header is used:

        Bit 15 → frame counter (toggles between even/odd frames)
        Bits 14:0 → line number (0–719)

    This allows the PC receiver to:

        - Detect frame boundaries
        - Reconstruct the image line order
        - Distinguish even/odd frame parity

3.  Reducing Pixel Data (3840 → 2560 bytes)
    
    Step A — Convert RGB888 → RGB565

        RGB888 (24 bits) is reduced to RGB565 (16 bits):
        Red: 8 → 5 bits
        Green: 8 → 6 bits
        Blue: 8 → 5 bits

    This reduces pixel size from 3 bytes to 2 bytes.
    So:

        1280 pixels × 2 bytes = 2560 bytes

    Still too large to transmit directly.

4. Subsampling to Fit Into UDP Packet (2560 → 1280 bytes)

    To reduce data further, only half of the pixels are sent for each line:

        On even lines → send even pixels: 0, 2, 4, ..., 1178
        On odd lines → send odd pixels: 1, 3, 5, ..., 1179

    This produces exactly 640 RGB565 pixels per line:

        640 pixels × 2 bytes = 1280 bytes


    So the UDP payload becomes:

        Header (2 bytes) + Pixel Data (1280 bytes) = 1282 bytes


    Which matches the target packet size.

5.  Why This Works

    This approach allows:

    - Zero-buffer processing — the FPGA never needs to store a full line or frame
    - Reduced bandwidth — only half the pixels are sent, halving data rate
    - Consistent packet size — every CMOS line becomes exactly one UDP packet
    - Deterministic timing — simple, streaming-friendly design
    - Easily reconstructible video on PC — the receiver knows which pixels belong to which line and which frame

    Given a 1280×720 resolution, the PC receives:
    - 720 UDP packets per frame
    - Each containing a single subsampled line
    - With the necessary line and frame numbers included

### Summary

<table>
    <thead>
        <tr>
        <th>Stage</th>
        <th>Operation</th>
        <th>Size</th>
        </tr>
    </thead>
    <tbody>
        <tr>
        <td>RAW camera data &rarr; ISP</td>
        <td>RGB888 (3 bytes/pixel)</td>
        <td>3840 bytes/line</td>
        </tr>
        <tr>
        <td>Convert to RGB565</td>
        <td>3&rarr;2 bytes/pixel</td>
        <td>2560 bytes/line</td>
        </tr>
        <tr>
        <td>Subsample (every other pixel)</td>
        <td>1280&rarr;640 pixels</td>
        <td>1280 bytes/line</td>
        </tr>
        <tr>
        <td>Add header</td>
        <td>+2 bytes</td>
        <td><strong>1282-byte UDP packet</strong></td>
        </tr>
    </tbody>
</table>

Thus, each CMOS sensor line becomes a compact UDP packet carrying:

    * Frame ID (1 bit)
    * Line number (15 bits)
    * 1280 bytes of pixel data

This strategy fits the Ethernet bandwidth constraints while maintaining real-time streaming.    

## Sample Videos

    Video sample for openeye-CamSI UDP stream coded in C++ using QT 5.11.1 and OpenCV library.

<p align="center" style="margin: 20px;">
    <video src="0.doc/Video/qt_udp.mp4" controls type="video/mp4" width="600" ></video>
</p>

[Qt_UDP Video Link](https://github.com/user-attachments/assets/84bee7db-d9ba-4833-be93-3879f710f8cc)

    Video sample for openeye-CamSI UDP stream coded in Python using OpenCV and NumPy library.

<p align="center" style="margin: 20px;">
    <video src="0.doc/Video/python_udp.mp4" controls type="video/mp4" width="600" ></video>
</p>

[Python_UDP Video Link](https://github.com/user-attachments/assets/ce939bf7-7cab-45de-8ab9-35c15ed11f1c)



## *Acknowledgements*
We are grateful to:
 - NLnet Foundation's sponsorship for giving us an opportunity to work on this fresh new take at FPGA video processing.
 - Special thanks also go to [Alex Forencich](https://github.com/alexforencich), whose Ethernet core served as the basis for the implementation of UDP streaming.

<p align="center">
    <img src="https://github.com/chili-chips-ba/openeye/assets/67533663/18e7db5c-8c52-406b-a58e-8860caa327c2">
    <img width="115" alt="NGI-Entrust-Logo" src="https://github.com/chili-chips-ba/openeye-CamSI/assets/67533663/013684f5-d530-42ab-807d-b4afd34c1522">
</p>

#### End of Document
