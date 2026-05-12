`timescale 1ns / 1ps

module tb_camera_capture();

    // ประกาศตัวแปรสัญญาณจำลองฝั่ง Input
    reg pclk;
    reg vsync;
    reg href;
    reg [7:0] d;

    // ประกาศสายสัญญาณรับ Output
    wire [16:0] addr;
    wire [11:0] dout;
    wire we;
    wire [9:0] x;
    wire [9:0] y;

    // เรียกใช้งานโมดูล ov7670_capture
    ov7670_capture uut (
        .pclk(pclk),
        .vsync(vsync),
        .href(href),
        .d(d),
        .addr(addr),
        .dout(dout),
        .we(we),
        .x(x),
        .y(y)
    );

    // สร้างสัญญาณนาฬิกาจำลอง 24-25 MHz (คาบเวลา = 40 ns)
    always #20 pclk = ~pclk;

    initial begin
        // 1. กำหนดค่าเริ่มต้น
        pclk = 0;
        vsync = 0;
        href = 0;
        d = 0;

        // 2. จำลองสัญญาณ VSYNC เพื่อรีเซ็ตเฟรม (บอกว่ากำลังจะเริ่มภาพใหม่)
        #100;
        vsync = 1; #80; 
        vsync = 0; #80;

        // 3. เริ่มส่งข้อมูลพิกเซลบรรทัดแรก (HREF = 1)
        href = 1;
        
        // --- พิกเซลที่ 1: สีแดง (RGB565 = 16'hF800) ---
        d = 8'hF8; #40; // ส่งไบต์แรก (MSB)
        d = 8'h00; #40; // ส่งไบต์ที่สอง (LSB) -> คาดหวัง dout = 12'hF00, we = 1, x = 1

        // --- พิกเซลที่ 2: สีเขียว (RGB565 = 16'h07E0) ---
        d = 8'h07; #40; 
        d = 8'hE0; #40; // คาดหวัง dout = 12'h0F0, we = 1, x = 2

        // --- พิกเซลที่ 3: สีน้ำเงิน (RGB565 = 16'h001F) ---
        d = 8'h00; #40; 
        d = 8'h1F; #40; // คาดหวัง dout = 12'h00F, we = 1, x = 3

        // --- พิกเซลที่ 4: สีขาว (RGB565 = 16'hFFFF) ---
        d = 8'hFF; #40; 
        d = 8'hFF; #40; // คาดหวัง dout = 12'hFFF, we = 1, x = 4

        // 4. จบบรรทัด (HREF = 0)
        href = 0;
        d = 8'h00; #100;

        $finish;
    end

endmodule