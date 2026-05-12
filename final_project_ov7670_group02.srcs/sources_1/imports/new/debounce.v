//////////////////////////////////////////////////////////////////////////////////
// Module Name: debounce
// Description: Module for filtering mechanical switch bounce.
//              It ensures that the output signal 'o' becomes high only after 
//              the input signal 'i' has been stable at logic high for a 
//              continuous duration defined by a 24-bit counter.
//////////////////////////////////////////////////////////////////////////////////

module debounce(
    input clk,          // สัญญาณนาฬิกาหลัก (ในโปรเจกต์นี้ใช้ 50MHz จาก Clock Wizard)
    input i,            // สัญญาณอินพุตจากปุ่มกด (ปุ่มที่อาจมีการสั่นของหน้าสัมผัส)
    output reg o        // สัญญาณเอาต์พุตที่สะอาดและเสถียรแล้ว
);

    // Register Definitions
    reg [23:0] c;       // รีจิสเตอร์ตัวนับขนาด 24 บิต เพื่อสร้างช่วงเวลาหน่วง (Delay)
    
    // Initial State Configuration
    initial c = 24'b0;  // กำหนดค่าเริ่มต้นของตัวนับเป็น 0

    // Debounce Logic
    always @(posedge clk) begin   
        if (i == 1) begin
            // หากตรวจพบว่ามีการกดปุ่ม (In=1) ให้เริ่มทำการนับ
            if (c == 24'hFFFFFF)
                // เมื่อตัวนับทำงานจนถึงค่าสูงสุด (Terminal Count) 
                // แสดงว่าสัญญาณอินพุตเสถียรที่สถานะ High นานพอแล้ว
                o <= 1;
            else
                // หากยังนับไม่ถึงเป้าหมาย ให้สถานะเอาต์พุตเป็น Low ต่อไป
                o <= 0;
            
            // เพิ่มค่าตัวนับในทุกรอบสัญญาณนาฬิกา
            c <= c + 1;
        end 
        else begin
            // หากปุ่มถูกปล่อย (In=0) หรือเกิดการสั่นจนสัญญาณหลุดเป็น 0
            // ให้รีเซ็ตตัวนับและเอาต์พุตกลับไปเป็นค่าเริ่มต้นทันที
            c <= 24'b0;
            o <= 0;
        end
    end  

endmodule