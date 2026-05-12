module cocotb_iverilog_dump();
initial begin
    string dumpfile_path;    if ($value$plusargs("dumpfile_path=%s", dumpfile_path)) begin
        $dumpfile(dumpfile_path);
    end else begin
        $dumpfile("/Users/andy_ntk/vivado-mac/final_project_ov7670_group02/final_project_ov7670_group02.srcs/sources_1/imports/new/sim_build/ov7670_capture.fst");
    end
    $dumpvars(0, ov7670_capture);
end
endmodule
