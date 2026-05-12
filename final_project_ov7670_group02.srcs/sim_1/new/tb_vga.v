`timescale 1ns / 1ps

module tb_vga();

    // ประกาศตัวแปรสัญญาณจำลอง
    reg clk25;
    reg [1:0] sw;
    reg [11:0] frame_pixel;
    
    // ประกาศสายสัญญาณสำหรับรับค่า Output จากโมดูล
    wire [3:0] vga_red, vga_green, vga_blue;
    wire vga_hsync, vga_vsync;
    wire [9:0] HCnt, VCnt;
    wire [16:0] frame_addr;

    // เรียกใช้งานโมดูล vga_disp ของจริงมาทดสอบ
    vga uut (
        .clk25(clk25),
        .sw(sw),
        .vga_red(vga_red),
        .vga_green(vga_green),
        .vga_blue(vga_blue),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .HCnt(HCnt),
        .VCnt(VCnt),
        .frame_addr(frame_addr),
        .frame_pixel(frame_pixel)
    );

    // สร้างสัญญาณนาฬิกา 25 MHz (คาบเวลา = 40 ns -> สลับค่าทุกๆ 20 ns)
    always #20 clk25 = ~clk25;

    // กำหนดพฤติกรรมจำลอง
    initial begin
        // กำหนดค่าเริ่มต้น
        clk25 = 0;
        sw = 2'b00;
        frame_pixel = 12'hF00; // สมมติว่าอ่านค่าสีแดง (Red) มาจาก RAM ตลอดเวลา
        
        // รอเวลาให้ระบบรันไปประมาณ 2 มิลลิวินาที (เพื่อให้เห็นสัญญาณ HSYNC สลับค่าหลายๆ รอบ)
        #2000000; 
        
        // จบการจำลอง
        $finish;
    end

endmodule