`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: I2C_AV_Config
// Description: Module for configuring the OV7670 camera registers via SCCB (I2C-like) protocol.
//              It iterates through a Look-Up Table (LUT) containing register addresses 
//              and configuration data to initialize the camera settings.
//////////////////////////////////////////////////////////////////////////////////

module I2C_AV_Config 
(
	// Global Signals
	input				iCLK,		// สัญญาณนาฬิกาหลัก (25MHz)
	input				iRST_N,		// สัญญาณรีเซ็ตแบบ Active Low
	
	// I2C/SCCB Interface Side
	output				I2C_SCLK,	// สัญญาณนาฬิกา SCCB (I2C Clock)
	inout				I2C_SDAT,	// สายสัญญาณข้อมูล SCCB (I2C Data) แบบ Bi-directional
	
	// Status and Monitoring Signals
	output	reg			Config_Done,// สถานะระบุว่าการตั้งค่ารีจิสเตอร์ทั้งหมดเสร็จสิ้นแล้ว
	output	reg	[7:0]	LUT_INDEX,	// ดัชนีระบุตำแหน่งปัจจุบันใน Look-Up Table (LUT)
	output		[7:0]	I2C_RDATA	// ข้อมูลที่อ่านได้จาก I2C (สำหรับกรณีตรวจสอบ ID)

);

	// Parameter Definitions
	parameter	LUT_SIZE	=	193;	// จำนวนรายการรีจิสเตอร์ทั้งหมดที่ต้องตั้งค่า

	///////////////////// I2C Control Clock Generation ////////////////////////
	// ทำการหารสัญญาณนาฬิกาจาก 25MHz เพื่อสร้างสัญญาณนาฬิกาสำหรับควบคุม I2C (10 KHz)
	parameter	CLK_Freq	=	25_000000;	// ความถี่คล็อกขาเข้า 25 MHz
	parameter	I2C_Freq	=	10_000;		// ความถี่ I2C ที่ต้องการ 10 KHz
	reg	[15:0]	mI2C_CLK_DIV;				// ตัวนับสำหรับหารความถี่ (Clock Divider)
	reg			mI2C_CTRL_CLK;				// สัญญาณนาฬิกาควบคุมภายในสำหรับ I2C

	always @(posedge iCLK or negedge iRST_N)
	begin
		if(!iRST_N)
			begin
			mI2C_CLK_DIV	<=	0;
			mI2C_CTRL_CLK	<=	0;
			end
		else
			begin
			 // นับจำนวนรอบตามอัตราส่วนความถี่
			 if( mI2C_CLK_DIV < (CLK_Freq/I2C_Freq)/2)
				 mI2C_CLK_DIV <= mI2C_CLK_DIV + 1'd1;
			 else
				 begin
				 mI2C_CLK_DIV <= 0;
				 mI2C_CTRL_CLK <= ~mI2C_CTRL_CLK; // ทำการ Toggle สัญญาณนาฬิกา
				 end
			end
	end

	// Edge Detection for I2C Clock
	// ตรวจสอบขอบขาลงของ mI2C_CTRL_CLK เพื่อใช้เป็นจังหวะในการเปลี่ยนข้อมูล
	reg	i2c_en_r0, i2c_en_r1;
	always @(posedge iCLK or negedge iRST_N)
	begin
		if(!iRST_N)
			begin
			i2c_en_r0 <= 0;
			i2c_en_r1 <= 0;
			end
		else
			begin
			i2c_en_r0 <= mI2C_CTRL_CLK;
			i2c_en_r1 <= i2c_en_r0;
			end
	end
	wire	i2c_negclk = (i2c_en_r1 & ~i2c_en_r0) ? 1'b1 : 1'b0; // สร้าง Pulse เมื่อเกิดขอบขาลง

	////////////////////// Configuration Control State Machine ////////////////////////////
	wire		mI2C_END;		// สัญญาณแจ้งว่าการรับ-ส่งข้อมูล 1 รายการเสร็จสิ้น
	wire		mI2C_ACK;		// สัญญาณตอบรับ (Acknowledge) จากอุปกรณ์ปลายทาง
	reg	[1:0]	mSetup_ST;		// สถานะปัจจุบันของ State Machine (0: IDLE, 1: TRANSFER, 2: NEXT)
	reg			mI2C_GO;		// สัญญาณเริ่มต้นการทำงานของตัวส่ง I2C
	reg			mI2C_WR;		// ระบุประเภทการทำงาน (0: อ่านข้อมูล, 1: เขียนข้อมูล)

	always @(posedge iCLK or negedge iRST_N)
	begin
		if(!iRST_N)
			begin
			Config_Done <= 0;
			LUT_INDEX	<=	0;
			mSetup_ST	<=	0;
			mI2C_GO		<=	0;
			mI2C_WR     <=	0;
			end
		else if(i2c_negclk) // ทำงานตามจังหวะสัญญาณนาฬิกา I2C
			begin
			if(LUT_INDEX < LUT_SIZE)
				begin
				Config_Done <= 0;
				case(mSetup_ST)
				0:	begin						// IDLE State: เตรียมการเริ่มต้น
					if(~mI2C_END)				// ตรวจสอบว่าตัวส่งว่างพร้อมทำงาน
						mSetup_ST	<=	1;		
					else
						mSetup_ST	<=	0;				
					mI2C_GO		<=	1;			// สั่งเริ่มการส่งข้อมูล
					
					// 2 รายการแรกของ LUT มักเป็นการอ่านค่าตรวจสอบ (Read) รายการที่เหลือเป็นการตั้งค่า (Write)
					if(LUT_INDEX < 8'd2)	
						mI2C_WR <= 0;			// โหมดอ่านข้อมูล
					else
						mI2C_WR <= 1;			// โหมดเขียนข้อมูล
					end
				1:	
					begin						// Transfer State: รอการส่งข้อมูลเสร็จสิ้น
					if(mI2C_END)
						begin
						mI2C_WR     <=	0;
						mI2C_GO		<=	0;
						if(~mI2C_ACK)			// หากได้รับสัญญาณ ACK (Active Low) แสดงว่าส่งสำเร็จ
							mSetup_ST <= 2;		// ไปยังขั้นตอนถัดไป
						else
							mSetup_ST <= 0;		// หากไม่ได้รับ ACK ให้ทำการส่งซ้ำ (Repeat Transfer)
						end
					end
				2:	begin						// Next Index State: เพิ่มตำแหน่งดัชนี LUT
					LUT_INDEX	<=	LUT_INDEX + 8'd1;
					mSetup_ST	<=	0;
					mI2C_GO		<=	0;
					mI2C_WR     <=	0;
					end
				endcase
				end
			else
				begin
				// เมื่อส่งครบทุกรายการใน LUT แล้ว ให้คงสถานะเสร็จสิ้นไว้
				Config_Done <= 1'b1;
				LUT_INDEX 	<= LUT_INDEX;
				mSetup_ST	<=	0;
				mI2C_GO		<=	0;
				mI2C_WR     <=	0;
				end
		end
	end

	////////////////////////////////////////////////////////////////////
	// Instance ของโมดูล Look-Up Table (LUT)
	// ทำหน้าที่จัดเก็บและจ่ายข้อมูล Register Address และ Data ตามดัชนี (LUT_INDEX)
	wire	[15:0]	LUT_DATA;
	I2C_OV7670_RGB565_Config	OV7670_RGB565_Config
	(
		.LUT_INDEX		(LUT_INDEX),
		.LUT_DATA		(LUT_DATA)
	);

	////////////////////////////////////////////////////////////////////
	// Instance ของโมดูล SCCB/I2C Controller
	// ทำหน้าที่ส่งสัญญาณตามมาตรฐานโปรโตคอล I2C ไปยังขากล้องโดยตรง
	I2C_Controller 	sccb_sender	
	(	
		.iCLK			(iCLK),
		.iRST_N			(iRST_N),
								
		.I2C_CLK		(mI2C_CTRL_CLK),	// สัญญาณนาฬิกาควบคุม
		.I2C_EN			(i2c_negclk),		// สัญญาณ Enable ข้อมูล
		.I2C_WDATA		({8'h42, LUT_DATA}),// ข้อมูลที่จะเขียน: [Address ของกล้อง 0x42, ข้อมูลจาก LUT]
		.I2C_SCLK		(I2C_SCLK),			// ขาเอาต์พุตนาฬิกาจริง
		.I2C_SDAT		(I2C_SDAT),			// ขาข้อมูลจริง
		
		.GO				(mI2C_GO),			// สัญญาณสั่งทำงาน
		.WR				(mI2C_WR),      	// ประเภทการทำงาน Write/Read
		.ACK			(mI2C_ACK),			// สัญญาณตอบรับจากปลายทาง
		.END			(mI2C_END),			// สถานะจบการส่ง 1 ชุดข้อมูล
		.I2C_RDATA		(I2C_RDATA)			// ข้อมูลที่อ่านได้
	);		
	////////////////////////////////////////////////////////////////////

endmodule