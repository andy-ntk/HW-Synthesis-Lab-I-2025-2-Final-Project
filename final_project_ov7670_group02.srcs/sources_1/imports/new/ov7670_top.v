`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Project: Real-Time Video Capture and Processing System
// Module Name: ov7670_top
// Description: Top-level module for interfacing OV7670 camera with VGA display.
//              Handles clock generation, camera configuration, image capture,
//              buffering in BRAM, image filtering, and VGA output.
//////////////////////////////////////////////////////////////////////////////////

module ov7670_top(
    // System Clock Input
    input  clk100,          // มาสเตอร์คล็อก 100MHz จากบอร์ด FPGA
    
    // OV7670 Camera Interface Signals
    input  OV7670_VSYNC,    // สัญญาณ Vertical Sync จากกล้อง
    input  OV7670_HREF,     // สัญญาณ Horizontal Reference จากกล้อง
    input  OV7670_PCLK,     // Pixel Clock จากกล้อง สำหรับซิงโครไนซ์ข้อมูลพิกเซล
    output OV7670_XCLK,     // System Clock ที่ส่งไปเลี้ยงตัวกล้อง (ทำงานที่ 24MHz)
    output OV7670_SIOC,     // SCCB Clock (I2C interface) สำหรับตั้งค่ากล้อง
    inout  OV7670_SIOD,     // SCCB Data (I2C interface) สำหรับตั้งค่ากล้อง
    input [7:0] OV7670_D,   // ข้อมูลพิกเซลขนาน 8 บิตจากกล้อง

    // Output Signals
    output[3:0] LED,        // ไฟ LED แสดงสถานะ (LED[0] ติดเมื่อตั้งค่ากล้องเสร็จ)
    output[3:0] vga_red,    // สัญญาณสีแดง VGA 4 บิต
    output[3:0] vga_green,  // สัญญาณสีเขียว VGA 4 บิต
    output[3:0] vga_blue,   // สัญญาณสีน้ำเงิน VGA 4 บิต
    output vga_hsync,       // สัญญาณซิงค์แนวนอนสำหรับจอภาพ VGA
    output vga_vsync,       // สัญญาณซิงค์แนวตั้งสำหรับจอภาพ VGA
    
    // Control Inputs
    input btn,              // ปุ่มกดสำหรับสั่ง Resend การตั้งค่ากล้อง
    output pwdn,            // สัญญาณ Power Down ของกล้อง (Set เป็น 0 สำหรับการทำงานปกติ)
    output reset,           // สัญญาณ Reset ของกล้อง (Set เป็น 1)
    input [11:0] sw,        // สวิตช์ควบคุมฟิลเตอร์และการแสดงผล
    output [1:0] Tled       // ไฟสถานะเพิ่มเติม (ปัจจุบันไม่ได้ใช้งาน)
);

    // Internal Wires and Signals
    wire [16:0] frame_addr;      // แอดเดรสสำหรับอ่านข้อมูลจาก Buffer ไปแสดงผล VGA
    wire [16:0] capture_addr;    // แอดเดรสสำหรับเขียนข้อมูลจากกล้องลง Buffer
    wire  capture_we;            // สัญญาณ Write Enable สำหรับเขียนข้อมูลลง RAM
    wire  config_finished;       // สถานะระบุว่าตั้งค่ารีจิสเตอร์กล้องเสร็จสิ้น
    wire  clk25;                 // คล็อก 25MHz สำหรับระบบ VGA
    wire  clk50;                 // คล็อก 50MHz สำหรับระบบ Debounce
    wire  clk;                   // คล็อกระบบทั่วไป
    wire  clk24;                 // คล็อก 24MHz สำหรับ XCLK ของกล้อง
    wire  resend;                // สัญญาณสั่งเริ่มตั้งค่ากล้องใหม่หลังจาก Debounce
    wire [11:0] frame_pixel;     // ข้อมูลพิกเซลที่อ่านออกมาจาก RAM
    wire [11:0] data_16;         // ข้อมูลพิกเซล 12 บิตที่ได้จากการรวมข้อมูลจากกล้อง
    wire [9:0] capture_x;        // ตำแหน่งพิกัด X ที่กำลังบันทึก
    wire [9:0] capture_y;        // ตำแหน่งพิกัด Y ที่กำลังบันทึก

    // Hardware Control Assignments
    assign pwdn = 0;             // 0: Normal mode, 1: Power down mode
    assign reset = 1;            // Active High Reset (ปกติเป็น 1)
    assign LED = {3'b0, config_finished}; // แสดงสถานะการตั้งค่าผ่าน LED
    assign OV7670_XCLK = clk24;  // จ่ายสัญญาณนาฬิกาให้กล้อง

    // Button Debounce Module
    // ป้องกันการสั่นของสัญญาณปุ่มกดเมื่อสั่ง Resend Configuration
    debounce btn_debounce(
        .clk(clk50),
        .i(btn),
        .o(resend)
    );

    // Image Filtering Module
    // รับพิกเซลดิบจาก RAM และประมวลผลตามค่า Switch
    wire [11:0] filtered_pixel;
    pixel_filter pf(
        .pixel_in(frame_pixel),
        .sw(sw),
        .pixel_out(filtered_pixel)
    );

    // VGA Controller Module
    // สร้างสัญญาณ Sync และดึงข้อมูลภาพจาก Buffer ไปแสดงผลบนจอ
    vga vga_display (
        .clk25       (clk25),
        .sw          (sw),
        .vga_red     (vga_red),
        .vga_green   (vga_green),
        .vga_blue    (vga_blue),
        .vga_hsync   (vga_hsync),
        .vga_vsync   (vga_vsync),
        .HCnt        (),
        .VCnt        (),
        .frame_addr  (frame_addr),
        .frame_pixel (filtered_pixel)
    );

    // Block RAM Frame Buffer (Simple Dual-Port)
    // เก็บข้อมูลภาพขนาด 320x240 พิกเซล
    blk_mem_gen_0 u_frame_buffer(
        // Write Port (Camera Side)
        .clka  (OV7670_PCLK),    // ใช้ PCLK ในการเขียน
        .wea   (capture_we),
        .addra (capture_addr),
        .dina  (data_16),

        // Read Port (VGA Side)
        .clkb  (clk25),          // ใช้ 25MHz ในการอ่าน
        .addrb (frame_addr),
        .doutb (frame_pixel)
    );

    // Camera Capture Module
    // แปลงสัญญาณข้อมูลจากกล้องเป็นพิกเซล 12 บิต และระบุแอดเดรสสำหรับจัดเก็บ
    ov7670_capture capture(
        .pclk  (OV7670_PCLK),   
        .vsync (OV7670_VSYNC),  
        .href  (OV7670_HREF),   
        .d     (OV7670_D),      
        .addr  (capture_addr),  
        .dout  (data_16),         
        .we    (capture_we),
        .x     (capture_x),     
        .y     (capture_y)
    );

    // Camera Configuration Module (SCCB)
    // ส่งข้อมูลตั้งค่ารีจิสเตอร์เริ่มต้นให้กล้อง OV7670
    I2C_AV_Config IIC(                 
        .iCLK        (clk25),          
        .iRST_N      (!resend),        
        .Config_Done (config_finished),    
        .I2C_SDAT    (OV7670_SIOD),    
        .I2C_SCLK    (OV7670_SIOC),  
        .LUT_INDEX   (),
        .I2C_RDATA   ()
    );

    // Clock Wizard
    // สร้างสัญญาณนาฬิกาความถี่ต่างๆ จากคล็อก 100MHz ของบอร์ด
    clk_wiz_0 clk_div(
        .clk_in1  (clk100),
        .clk_out1 (clk50),    // 50MHz
        .clk_out2 (clk25),    // 25MHz
        .clk_out3 (clk),      // 100MHz
        .clk_out4 (clk24)     // 24MHz
    );

    // Default status for unused signals
    assign Tled[0] = 1'b0;   
    assign Tled[1] = 1'b0;        

endmodule