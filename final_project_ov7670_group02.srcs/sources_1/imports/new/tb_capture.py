import os
from pathlib import Path

import cocotb
from cocotb.triggers import Timer, FallingEdge
from cocotb.clock import Clock
from cocotb_tools.runner import get_runner

@cocotb.test()
async def test_camera_capture(dut):
    """Testbench สำหรับจำลองการรับค่าจากกล้อง OV7670 (RGB565 -> RGB444)"""
    
    cocotb.start_soon(Clock(dut.pclk, 40, units="ns").start())
    
    dut.vsync.value = 0
    dut.href.value = 0
    dut.d.value = 0
    
    dut._log.info("System Reset Complete. Waiting for VSYNC...")
    await Timer(100, units="ns")
    
    await FallingEdge(dut.pclk)
    dut.vsync.value = 1
    await Timer(120, units="ns")
    await FallingEdge(dut.pclk)
    dut.vsync.value = 0
    
    # 4. จำลองการรับพิกเซลต่อเนื่อง (Pipeline Data Stream)
    dut.href.value = 1 
    
    # --- เริ่มคล็อกที่ 1 ---
    dut._log.info(">>> Sending Pixel 1: RED (0xF800)")
    dut.d.value = 0xF8 # ส่ง High Byte 1
    await FallingEdge(dut.pclk)
    
    # --- เริ่มคล็อกที่ 2 ---
    dut.d.value = 0x00 # ส่ง Low Byte 1
    await FallingEdge(dut.pclk)
    
    # --- เริ่มคล็อกที่ 3 ---
    dut._log.info(">>> Sending Pixel 2: GREEN (0x07E0)")
    dut.d.value = 0x07 # ส่ง High Byte 2 (ส่งต่อเนื่องเลย)
    await FallingEdge(dut.pclk)
    
    # ณ จุดนี้ (คล็อกที่ 3) ลอจิกประมวลผล Pixel 1 เสร็จแล้ว! ตรวจคำตอบได้เลย
    dout_val = int(dut.dout.value)
    dut._log.info(f"[Check Pixel 1] DOUT: {hex(dout_val)}, WE: {dut.we.value}")
    assert dut.we.value == 1, "WE should be 1 for Pixel 1"
    assert dout_val == 0xf00, f"Expected 0xf00 but got {hex(dout_val)}"
    
    # --- เริ่มคล็อกที่ 4 ---
    dut.d.value = 0xE0 # ส่ง Low Byte 2
    await FallingEdge(dut.pclk)
    
    # --- เริ่มคล็อกที่ 5 ---
    dut.href.value = 0 # จบการส่งเฟรม เอา HREF ลง
    await FallingEdge(dut.pclk)
    
    # ณ จุดนี้ (คล็อกที่ 5) ลอจิกประมวลผล Pixel 2 เสร็จแล้ว!
    dout_val = int(dut.dout.value)
    dut._log.info(f"[Check Pixel 2] DOUT: {hex(dout_val)}, WE: {dut.we.value}")
    assert dut.we.value == 1, "WE should be 1 for Pixel 2"
    assert dout_val == 0x0f0, f"Expected 0x0f0 but got {hex(dout_val)}"
    
    await Timer(100, units="ns")
    dut._log.info("Camera Capture Simulation Complete! Check the Waveform.")

def runner():
    top_module = "ov7670_capture"
    test_module = "tb_capture" 
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "camera_capture.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=top_module,
        always=True,
        waves=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(
        hdl_toplevel=top_module,
        test_module=test_module,
        waves=True,
    )

if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    runner()