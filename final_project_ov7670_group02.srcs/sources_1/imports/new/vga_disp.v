`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: vga
// Description: VGA Controller module for 640x480 @ 60Hz display.
//              Includes digital zooming, image scaling (15/16 ratio), 
//              alignment adjustment to avoid visual noise, and pipeline 
//              synchronization with BRAM and Pixel Filter.
//////////////////////////////////////////////////////////////////////////////////

module vga(
    input clk25,              // สัญญาณนาฬิกา 25MHz สำหรับ VGA Timing
    input [1:0] sw,           // สวิตช์เลือกโหมดฟิลเตอร์ (ส่งต่อไปยัง pixel_filter)
    output reg [3:0] vga_red,  // สัญญาณสีแดง VGA 4 บิต
    output reg [3:0] vga_green,// สัญญาณสีเขียว VGA 4 บิต
    output reg [3:0] vga_blue, // สัญญาณสีน้ำเงิน VGA 4 บิต
    output vga_hsync,         // สัญญาณ Horizontal Sync
    output vga_vsync,         // สัญญาณ Vertical Sync
    output [9:0] HCnt,        // ตำแหน่งพิกเซลแนวนอนปัจจุบัน (Horizontal Counter)
    output [9:0] VCnt,        // ตำแหน่งพิกเซลแนวตั้งปัจจุบัน (Vertical Counter)
    output [16:0] frame_addr, // แอดเดรสสำหรับอ่านข้อมูลพิกเซลจาก RAM
    input [11:0] frame_pixel  // ข้อมูลพิกเซลจาก RAM (12-bit RGB444)
);

    // =========================================================
    // 1. VGA Timing Parameters (640x480 @ 60Hz)
    // นิยามค่าพารามิเตอร์มาตรฐานสำหรับการสร้างสัญญาณซิงค์
    // =========================================================
    localparam H_DISPLAY  = 640; // ส่วนแสดงผลแนวนอน
    localparam H_L_BORDER = 48;  // ขอบซ้าย (Back Porch)
    localparam H_R_BORDER = 16;  // ขอบขวา (Front Porch)
    localparam H_RETRACE  = 96;  // ช่วงสัญญาณ Sync แนวนอน
    localparam H_MAX      = H_DISPLAY + H_L_BORDER + H_R_BORDER + H_RETRACE - 1;
    localparam START_H_RETRACE = H_DISPLAY + H_R_BORDER;
    localparam END_H_RETRACE   = H_DISPLAY + H_R_BORDER + H_RETRACE - 1;

    localparam V_DISPLAY  = 480; // ส่วนแสดงผลแนวตั้ง
    localparam V_T_BORDER = 10;  // ขอบบน (Front Porch)
    localparam V_B_BORDER = 33;  // ขอบล่าง (Back Porch)
    localparam V_RETRACE  = 2;   // ช่วงสัญญาณ Sync แนวตั้ง
    localparam V_MAX      = V_DISPLAY + V_T_BORDER + V_B_BORDER + V_RETRACE - 1;
    localparam START_V_RETRACE = V_DISPLAY + V_B_BORDER;
    localparam END_V_RETRACE   = V_DISPLAY + V_B_BORDER + V_RETRACE - 1;

    // Registers สำหรับตัวนับและสัญญาณ Sync
    reg [9:0] h_count_reg = 0, h_count_next;
    reg [9:0] v_count_reg = 0, v_count_next;
    reg vsync_reg = 0, hsync_reg = 0;

    // กระบวนการอัปเดตตัวนับและสร้างสัญญาณ Sync (Active Low)
    always @(posedge clk25) begin
        v_count_reg <= v_count_next;
        h_count_reg <= h_count_next;
        vsync_reg <= ~(v_count_reg >= START_V_RETRACE && v_count_reg <= END_V_RETRACE);
        hsync_reg <= ~(h_count_reg >= START_H_RETRACE && h_count_reg <= END_H_RETRACE);
    end

    // ตรรกะการนับตำแหน่งพิกเซล (Next State Logic)
    always @* begin
        h_count_next = (h_count_reg == H_MAX) ? 0 : h_count_reg + 1;
        v_count_next = (h_count_reg == H_MAX) ? 
                       ((v_count_reg == V_MAX) ? 0 : v_count_reg + 1) : v_count_reg;
    end

    assign HCnt = h_count_reg;
    assign VCnt = v_count_reg;

    // ตรวจสอบว่าพิกัดปัจจุบันอยู่ในพื้นที่แสดงผลหรือไม่
    wire video_on = (h_count_reg < H_DISPLAY) && (v_count_reg < V_DISPLAY);

    // =========================================================
    // 2. UNIFORM DIGITAL ZOOM & Scaling
    // ปรับสัดส่วนภาพจาก 320x240 ให้แสดงผลบน 640x480
    // =========================================================
    
    // Pixel Doubling: หารด้วย 2 (Shift Right 1) เพื่อขยายพิกเซลจาก 320 เป็น 640
    wire [8:0] cam_x = h_count_reg >> 1; // ช่วง 0-319
    wire [8:0] cam_y = v_count_reg >> 1; // ช่วง 0-239

    // Scaling Logic (อัตราส่วน 15/16):
    // เพื่อบีบสเกลภาพให้เล็กลงเล็กน้อยสำหรับพื้นที่ขอบเพื่อลดสัญญาณรบกวน (Garbage pixels)
    wire [13:0] temp_x = cam_x * 15;
    wire [13:0] temp_y = cam_y * 15;

    // Image Alignment & Offset:
    // safe_cam_x: ขยับแกน X ไปทางขวา 15 พิกเซล เพื่อหลบขยะสีจากขอบซ้ายของกล้อง
    wire [8:0] safe_cam_x = 15 + (temp_x >> 4);
    // safe_cam_y: ขยับแกน Y ลงมา 7 พิกเซล เพื่อให้ภาพอยู่กึ่งกลางจอพอดี
    wire [8:0] safe_cam_y = 7 + (temp_y >> 4);

    // ดึงข้อมูล Address สำหรับ RAM ด้วยพิกัดที่ปรับแต่งแล้ว
    assign frame_addr = video_on ? ((safe_cam_y * 320) + safe_cam_x) : 0;

    // =========================================================
    // 3. Pipeline Delay Management
    // การหน่วงสัญญาณเพื่อให้ Sync กับข้อมูลที่อ่านมาจาก BRAM (ใช้เวลา 2 รอบคล็อก)
    // =========================================================
    reg video_on_d1 = 0, video_on_d2 = 0;
    reg hsync_d1 = 0, hsync_d2 = 0;
    reg vsync_d1 = 0, vsync_d2 = 0;

    always @(posedge clk25) begin
        video_on_d1 <= video_on;
        video_on_d2 <= video_on_d1;
        hsync_d1 <= hsync_reg;
        hsync_d2 <= hsync_d1;
        vsync_d1 <= vsync_reg;
        vsync_d2 <= vsync_d1;
    end

    // เอาต์พุตสัญญาณ Sync ที่ถูกหน่วงเวลาแล้ว
    assign vga_hsync = hsync_d2;
    assign vga_vsync = vsync_d2;

    // =========================================================
    // 4. Pixel Filtering & Final Output
    // ประมวลผลพิกเซลผ่าน Filter และส่งออกไปยังขา VGA
    // =========================================================
    wire [11:0] filtered_pixel;

    // เชื่อมต่อโมดูลตัวกรองภาพ (pixel_filter)
    pixel_filter my_filter (
        .clk(clk25),
        .sw(sw),
        .pixel_in(frame_pixel),
        .pixel_out(filtered_pixel)
    );

    // กำหนดค่าสีให้กับ Output Registers (4 บิตต่อสี)
    always @(posedge clk25) begin
        if (video_on_d2) begin
            vga_red   <= filtered_pixel[11:8];
            vga_green <= filtered_pixel[7:4];
            vga_blue  <= filtered_pixel[3:0];
        end else begin
            // แสดงสีดำเมื่ออยู่นอกพื้นที่การแสดงผล (Blanking period)
            vga_red   <= 4'b0;
            vga_green <= 4'b0;
            vga_blue  <= 4'b0;
        end
    end

endmodule