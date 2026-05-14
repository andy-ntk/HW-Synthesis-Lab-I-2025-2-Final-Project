//////////////////////////////////////////////////////////////////////////////////
// Module Name: ov7670_capture
// Description: Module for capturing parallel pixel data from the OV7670 camera.
//              It latches two bytes to form a 16-bit RGB565 pixel, converts it 
//              to RGB444 format, and generates memory addresses for a 320x240 buffer.
//////////////////////////////////////////////////////////////////////////////////

module ov7670_capture(
    // Clock and Synchronization Signals
    input pclk,              // Pixel Clock จากกล้อง ใช้เป็นสัญญาณนาฬิกาหลักของโมดูล
    input vsync,             // Vertical Sync ระบุการเริ่มต้นเฟรมใหม่  
    input href,              // Horizontal Reference ระบุช่วงที่มีข้อมูลพิกเซลที่ถูกต้องในแนวตั้ง  
    
    // Data Input
    input [7:0] d,           // ข้อมูลพิกเซลขนาน 8 บิตจากพอร์ตข้อมูลของกล้อง  
    
    // Output Signals
    output [16:0] addr,      // แอดเดรสสำหรับเขียนลง RAM (คำนวณจากตำแหน่ง X, Y)  
    output [11:0] dout,      // ข้อมูลพิกเซลในรูปแบบ RGB444 (12 บิต)  
    output reg we,           // สัญญาณ Write Enable สำหรับสั่งบันทึกลง RAM  
    
    // Position Debug/Status
    output [9:0] x,          // ตำแหน่งพิกเซลในแนวนอน (0-319)  
    output [9:0] y           // ตำแหน่งพิกเซลในแนวตั้ง (0-239)  
);

    // Internal Registers
    reg [15:0] d_latch = 0;  // รีจิสเตอร์สำหรับพักข้อมูล 2 ไบต์ที่รับเข้ามา  
    reg [11:0] dout1 = 0;    // รีจิสเตอร์เก็บค่าพิกเซล RGB444 ที่พร้อมส่งออก  
    reg [1:0] wr_hold = 0;   // สัญญาณหน่วงสำหรับการควบคุมจังหวะการเขียน (Write Control)  

    // Pixel Position Registers
    reg [9:0] x_reg = 0;     // ตัวนับตำแหน่งพิกเซลในแนวนอน  
    reg [9:0] y_reg = 0;     // ตัวนับตำแหน่งพิกเซลในแนวตั้ง  

    // ===== RGB565 Extraction =====
    // แยกส่วนประกอบสีจากข้อมูล 16 บิต (5 บิต แดง, 6 บิต เขียว, 5 บิต น้ำเงิน)  
    wire [4:0] r5 = d_latch[15:11];
    wire [5:0] g6 = d_latch[10:5];
    wire [4:0] b5 = d_latch[4:0];

    // ===== RGB444 Conversion =====
    // แปลงข้อมูลจาก 5/6 บิต ให้เหลือ 4 บิตต่อสีเพื่อลดขนาดการจัดเก็บ  
    wire [3:0] r4 = r5[4:1];
    wire [3:0] g4 = g6[5:2];
    wire [3:0] b4 = b5[4:1];

    // Output Assignments
    // คำนวณหา Linear Address สำหรับหน่วยความจำขนาด 320x240  
    assign addr = y_reg * 320 + x_reg;
    assign dout = dout1;

    // Main Capture Logic
    always @(posedge pclk) begin
        if (vsync) begin
            // เมื่อขึ้นเฟรมใหม่ ให้รีเซ็ตตำแหน่งและสถานะทั้งหมด  
            x_reg <= 0;
            y_reg <= 0;
            wr_hold <= 0;
            we <= 0;
        end else begin
            // ทำการ Latch ข้อมูลทีละไบต์ต่อกันจนครบ 2 ไบต์เพื่อให้ได้ 1 พิกเซล  
            d_latch <= {d_latch[7:0], d};

            // ตรวจสอบจังหวะข้อมูลพิกเซลที่ถูกต้อง (HREF) 
            // wr_hold[1] จะเป็น High ทุกๆ 2 รอบของ pclk เมื่อได้รับข้อมูลครบ 1 พิกเซล  
            wr_hold <= {wr_hold[0], (href && !wr_hold[0])};
            we <= wr_hold[1];

            if (wr_hold[1]) begin
                // บันทึกค่าสี RGB444 ลงในรีจิสเตอร์เตรียมส่งออก  
                dout1 <= {r4, g4, b4};

                // จัดการการเลื่อนตำแหน่งพิกัด X และ Y
                if (x_reg < 319) begin
                    x_reg <= x_reg + 1;
                end else begin
                    // เมื่อจบบรรทัด ให้กลับไปเริ่มต้น X ใหม่และเพิ่มค่า Y
                    x_reg <= 0;
                    if (y_reg < 239)
                        y_reg <= y_reg + 1;
                    else
                        y_reg <= 0;
                end
            end
        end
    end

    // มอบหมายค่าตำแหน่งปัจจุบันไปยังพอร์ตเอาต์พุต
    assign x = x_reg;
    assign y = y_reg;

endmodule