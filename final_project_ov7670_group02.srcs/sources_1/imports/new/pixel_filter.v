`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: pixel_filter
// Description: Real-time image processing module. 
//              It performs color correction (RGB Boost/Reduction), 
//              Gamma Correction, and implements four selectable filters: 
//              Normal, Grayscale, Color Splash (Blue), and Edge Detection.
//////////////////////////////////////////////////////////////////////////////////

module pixel_filter(
    input clk,                  // สัญญาณนาฬิกา (ใช้คล็อกเดียวกับระบบแสดงผล)
    input [1:0] sw,             // สวิตช์เลือกรูปแบบฟิลเตอร์ (2'b00 ถึง 2'b11)
    input [11:0] pixel_in,      // ข้อมูลพิกเซลขาเข้า RGB444 (12 บิต)
    output reg [11:0] pixel_out // ข้อมูลพิกเซลขาออกที่ผ่านการประมวลผลแล้ว
);

    // ==========================================
    // 0. แยกสีดั้งเดิมจากกล้อง (Raw RGB Extraction)
    // แยกข้อมูล 12 บิตออกเป็นส่วนประกอบ แดง (R), เขียว (G), และน้ำเงิน (B) อย่างละ 4 บิต
    // ==========================================
    wire [3:0] r_raw = pixel_in[11:8];
    wire [3:0] g_raw = pixel_in[7:4];
    wire [3:0] b_raw = pixel_in[3:0];

    // ==========================================
    // 1. นำสีดั้งเดิมมาผ่าน Color LUT (Color Correction)
    // ปรับจูนค่าสีเพื่อชดเชยข้อบกพร่องของเซนเซอร์กล้อง OV7670
    // ==========================================
    reg [3:0] r_clut;
    wire [3:0] g_clut;
    wire [3:0] b_clut;

    // แก้ไขสีแดง: เพิ่มความสว่าง (Boost) เล็กน้อยในช่วงสีกลาง
    always @(*) begin
        case (r_raw)
            4'h7: r_clut = 4'h8;
            4'h8: r_clut = 4'h9;
            4'h9: r_clut = 4'hA;
            default: r_clut = r_raw;
        endcase
    end

    // แก้ไขสีเขียว: ลดความอมเขียว (Green Tint) ซึ่งเป็นลักษณะเฉพาะของกล้องรุ่นนี้
    assign g_clut = (g_raw > 4'h8) ? (g_raw - 1) : g_raw;
    
    // แก้ไขสีน้ำเงิน: ปรับลดความเข้มและป้องกันค่าติดลบ (Underflow)
    assign b_clut = (b_raw > 4'h0 && b_raw < 4'h6) ? (b_raw - 1) : b_raw;

    // ==========================================
    // 2. สร้างฟังก์ชันสำหรับ Gamma LUT (Gamma Correction)
    // ปรับปรุง Contrast และความสว่างของภาพให้เหมาะสมกับการแสดงผลบนจอภาพ
    // ==========================================
    function [3:0] gamma_corr;
        input [3:0] in_val;
        begin
            case(in_val)
                4'h4: gamma_corr = 4'h5;
                4'h5: gamma_corr = 4'h6;
                4'h6: gamma_corr = 4'h7;
                4'h7: gamma_corr = 4'h9;
                4'h8: gamma_corr = 4'hA;
                4'h9: gamma_corr = 4'hB;
                4'hA: gamma_corr = 4'hC;
                4'hB: gamma_corr = 4'hD;
                4'hC: gamma_corr = 4'hE;
                4'hD: gamma_corr = 4'hF;
                4'hE: gamma_corr = 4'hF;
                4'hF: gamma_corr = 4'hF;
                default: gamma_corr = in_val; // สำหรับค่าความสว่างต่ำ (0-3) ให้คงค่าเดิม
            endcase
        end
    endfunction

    // นำค่าสีที่ผ่าน Color Correction แล้วมาเข้าสู่กระบวนการ Gamma Correction
    wire [3:0] r = gamma_corr(r_clut);
    wire [3:0] g = gamma_corr(g_clut);
    wire [3:0] b = gamma_corr(b_clut);

    // รวมสัญญาณ R, G, B เป็นพิกเซลที่ปรับปรุงสีสันเรียบร้อยแล้ว
    wire [11:0] pixel_corrected = {r, g, b};

    // ==========================================
    // 3. คำนวณฟิลเตอร์ต่างๆ (Image Processing Filters)
    // ==========================================
    
    // 3.1 ฟิลเตอร์ภาพขาวดำ (Grayscale)
    // ใช้สูตรน้ำหนักสีเพื่อให้ได้ความสว่างที่สมจริง (Y = 0.3R + 0.6G + 0.1B)
    wire [7:0] gray8 = (r * 3) + (g * 6) + (b * 1);
    wire [3:0] gray = gray8[7:4]; // นำบิตบนมาใช้งานเป็นค่าสีเทา 4 บิต

    // 3.2 ฟิลเตอร์ตรวจจับขอบ (Edge Detection)
    // เปรียบเทียบความแตกต่างของความสว่างพิกเซลปัจจุบันกับพิกเซลก่อนหน้า
    reg [3:0] prev_gray = 0;
    always @(posedge clk) begin
        prev_gray <= gray;
    end
    wire [4:0] diff = (gray > prev_gray) ? (gray - prev_gray) : (prev_gray - gray);
    // หากความต่างมากกว่า Threshold (ค่า 3) ให้แสดงเป็นสีขาว (ขอบ) มิฉะนั้นเป็นสีดำ
    wire [3:0] edge_val = (diff >= 3) ? 4'hF : 4'h0;

    // 3.3 ระบบดูดสี (Color Splash - Blue focus)
    // ตรวจสอบเงื่อนไขว่าพิกเซลนี้เป็น "สีน้ำเงิน" หรือไม่ โดยเปรียบเทียบสัดส่วนสี B กับ R และ G
    wire [4:0] r5 = {1'b0, r};
    wire [4:0] g5 = {1'b0, g};
    wire [4:0] b5 = {1'b0, b};
    wire is_blue = (b5 > r5 + 2) && (b5 > g5 + 1) && (b5 > 2);

    // ==========================================
    // 4. MUX: ตัวเลือกฟิลเตอร์เพื่อแสดงผลออกจอ (Output Multiplexer)
    // เลือกแสดงภาพตามสถานะของสวิตช์ควบคุม
    // ==========================================
    always @(*) begin
        case(sw)
            2'b00: pixel_out = pixel_corrected;                     // 00: ภาพสีปกติที่ปรับปรุงสีแล้ว
            2'b01: pixel_out = {gray, gray, gray};                  // 01: ภาพขาวดำสมบูรณ์
            2'b10: pixel_out = is_blue ? pixel_corrected : {gray, gray, gray}; // 10: เฉพาะสีน้ำเงินที่เป็นสี ส่วนอื่นเป็นขาวดำ
            2'b11: pixel_out = {edge_val, edge_val, edge_val};      // 11: แสดงเฉพาะเส้นขอบของวัตถุ
            default: pixel_out = pixel_corrected;
        endcase
    end

endmodule