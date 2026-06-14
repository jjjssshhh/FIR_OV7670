`timescale 1ns / 1ps


interface my_vga_if(input logic clk);
    //VGA
    localparam [6:0] Tpw = 96;
    localparam [7:0] Tbp = 144;
    localparam [9:0] Tdisp = 784;
    localparam [9:0] Ts = 800;
    localparam [9:0] ROW = 525;
    localparam [16:0] ROWCOL = 17'd76799;

    logic rstn;
    logic Hsync,Vsync;
    logic [3:0] vgaRed,vgaBlue,vgaGreen;
    logic finish;
    //
    logic [11:0] in_dt;
    logic wt_valid;
    //
    logic c_wt_en,c_rd_en;
    logic c_en;
    assign c_en = c_wt_en | c_rd_en;
    //
    logic [17:0] addra,addrb;
    logic [11:0] doutb;
    //sccb
    logic SIO_C;
    logic SIO_D_in;
    logic sio_c_n_edge,sio_c_p_edge;
    logic sccb_write_en,sccb_read_en;
    logic sccb_write_rstn, sccb_read_rstn;
    logic [7:0] ID_address,Sub_address, COM7;
    logic [7:0] read_data;
    logic [7:0] image_data;
    logic sccb_write_done,sccb_read_done;
    logic Camera_Hs,Camera_Vs;
    logic sccb_master_done;
    // tristate
    logic sio_d_write_en,sio_d_read_en;
    logic sio_dout_write,sio_dout_read;
    //
    logic led_clk1, led_clk2,led_clk3,led_clk4;
    logic one_shot_top_in;
    logic pclk;
    logic clk_vga;
    //FIR Filter
    logic [11:0] fir_lpf_tdata,fir_hpf_tdata;
    logic m_lpf_ready, m_lpf_valid;
    logic s_lpf_ready, s_lpf_valid;
    logic m_hpf_ready, m_hpf_valid;
    logic s_hpf_ready,s_hpf_valid;
    logic [17:0] hpf_addra;
    logic [17:0] lpf_addra;
    logic [1:0] sw;
    assign m_hpf_ready = 1;
    assign s_lpf_valid = wt_valid;
    assign s_hpf_valid = sw[1] ? 1'b0 : m_lpf_valid;
    assign m_lpf_ready = sw[1] ? 1'b1 : s_hpf_ready;

    modport bot (input clk_vga,rstn,doutb,Vsync,finish,sw,
                 output Hsync,vgaRed,vgaBlue,vgaGreen,addrb,led_clk3);

    modport sccb_write (input clk,rstn,sccb_write_rstn,SIO_C,sio_c_n_edge,sio_c_p_edge,sccb_write_en,ID_address,Sub_address,COM7,
                        output c_wt_en,sio_d_write_en,sio_dout_write,sccb_write_done);

    modport sccb_read  (input clk,rstn,sccb_read_rstn,sccb_read_en,ID_address,SIO_D_in,sio_c_p_edge,sio_c_n_edge,
                        output c_rd_en,read_data,sccb_read_done,sio_d_read_en,sio_dout_read);

    modport sccb_master (input clk,pclk,rstn,sccb_write_done,sccb_read_done,one_shot_top_in,read_data,
                         output led_clk1,sccb_write_rstn,sccb_read_rstn,sccb_write_en,sccb_read_en,ID_address,Sub_address,COM7,sccb_master_done);

    modport image_cov (input pclk,rstn,image_data,Camera_Hs,Camera_Vs,sccb_master_done,
                       output in_dt,addra,wt_valid,finish,led_clk2);

    modport make_sioc (input clk,rstn,c_en, output SIO_C);

    modport edged (input clk,rstn,SIO_C,c_en, output sio_c_n_edge,sio_c_p_edge);

    modport fir_lpf (input pclk,rstn,s_lpf_valid,in_dt,m_lpf_ready,finish, output fir_lpf_tdata,s_lpf_ready,m_lpf_valid,lpf_addra);
    modport fir_hpf (input pclk,rstn,s_hpf_valid,fir_lpf_tdata,m_hpf_ready,finish, output fir_hpf_tdata,s_hpf_ready,m_hpf_valid,hpf_addra);

endinterface

module OV_VGA
(
    input wclk,
    input rstn,
    //OV7670
    output SIO_C,
    inout SIO_D,
    output MCLK,
    input PCLK,
    input Camera_Hs,Camera_Vs,
    input [7:0] image_data,
    //test_set
    input one_shot_top,
    input [1:0] sw,
    output led_clk1,led_clk2,led_clk3,led_clk4,
    //vga
    output Hsync,Vsync,
    output [3:0] vgaRed,vgaGreen,vgaBlue
);
    assign led_clk1 = main_bus.led_clk1;
    assign led_clk2 = main_bus.led_clk2;
    assign led_clk3 = main_bus.led_clk3;
    assign led_clk4 = main_bus.led_clk4;

    logic clk,clk_vga;
    clk_wiz_0 cw0
    (
        .clk_in1(wclk),
        .reset(!rstn),
        .clk_out1(clk),
        .clk_out2(clk_vga)
    );

    my_vga_if main_bus(clk);

    VGA_controller_b   b0   (.mi0(main_bus.bot));

    OV_write           wt   (.mi0(main_bus.sccb_write));
    OV_read            rd   (.mi0(main_bus.sccb_read));
    OV_MASTER          ov_m (.mi0(main_bus.sccb_master));

    make_sio_c         c0   (.mi0(main_bus.make_sioc));
    edge_detector_n    ed0  (.mi0(main_bus.edged));

    Image_conv         Icv0 (.m(main_bus.image_cov));

    FIR_LPF            lpf0 (.m(main_bus.fir_lpf));
    FIR_HPF            hpf0 (.m(main_bus.fir_hpf));

    assign main_bus.sw              = sw;
    assign main_bus.clk_vga        = clk_vga;
    assign main_bus.rstn           = rstn;
    assign SIO_C                   = main_bus.SIO_C;
    assign SIO_D = (main_bus.sio_d_write_en) ? main_bus.sio_dout_write :
                   (main_bus.sio_d_read_en)  ? main_bus.sio_dout_read : 1'bz;
    assign main_bus.SIO_D_in       = SIO_D;
    assign main_bus.image_data     = image_data;
    assign main_bus.one_shot_top_in = one_shot_top;
    assign MCLK                    = main_bus.clk;
    assign main_bus.pclk           = PCLK;
    assign main_bus.Camera_Hs      = Camera_Hs;
    assign main_bus.Camera_Vs      = Camera_Vs;
    assign Hsync                   = main_bus.Hsync;
    assign Vsync                   = main_bus.Vsync;
    assign vgaRed                  = main_bus.vgaRed;
    assign vgaBlue                 = main_bus.vgaBlue;
    assign vgaGreen                = main_bus.vgaGreen;

    blk_mem_gen_0 bram0(
        .addra(sw[0] ? main_bus.hpf_addra : sw[1] ? main_bus.lpf_addra : main_bus.addra),
        .clka(main_bus.pclk),
        .dina(sw[0] ? main_bus.fir_hpf_tdata : sw[1] ? main_bus.fir_lpf_tdata : main_bus.in_dt),
        .wea(sw[0] ? main_bus.m_hpf_valid : sw[1] ? main_bus.m_lpf_valid : main_bus.wt_valid),
        .addrb(main_bus.addrb),
        .clkb(main_bus.clk_vga),
        .doutb(main_bus.doutb)
    );

endmodule
