// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Self-checking testbench for the SwAccessRC + MuBi configuration of prim_subreg_arb.
//
// For read-to-clear registers the `we` input is a read pulse. When it is asserted the register must
// be forced to its cleared (MuBi*False) value whatever `wd` carries. This is checked for every MuBi
// width that prim_subreg_arb supports.
//
// Run with Verilator (from the repository root):
//
//   $ verilator --binary --timing -Wno-fatal -Ihw/ip/prim/rtl \
//     hw/ip/prim/rtl/prim_mubi_pkg.sv hw/ip/prim/rtl/prim_subreg_pkg.sv \
//     hw/ip/prim/rtl/prim_subreg_arb.sv \
//     hw/ip/prim/dv/prim_subreg_arb/tb/prim_subreg_arb_rc_mubi_tb.sv \
//     --top-module prim_subreg_arb_rc_mubi_tb && obj_dir/Vprim_subreg_arb_rc_mubi_tb

module prim_subreg_arb_rc_mubi_tb;
  import prim_mubi_pkg::*;
  import prim_subreg_pkg::*;

  int unsigned num_errors = 0;

  // One instance of the DUT per MuBi width. `False` and `True` are the legal encodings. wd is also
  // driven with values that are not legal encodings, because an RC register must ignore it.
  for (genvar i = 0; i < 4; i++) begin : gen_dut
    localparam int Width = (i == 0) ? 4 : (i == 1) ? 8 : (i == 2) ? 12 : 16;
    localparam logic [Width-1:0] False =
        (Width == 4)  ? Width'(MuBi4False)  :
        (Width == 8)  ? Width'(MuBi8False)  :
        (Width == 12) ? Width'(MuBi12False) : Width'(MuBi16False);
    localparam logic [Width-1:0] True = ~False;

    logic             we, de;
    logic [Width-1:0] wd, d, q, wr_data;
    logic             wr_en;

    prim_subreg_arb #(
      .DW       (Width),
      .SwAccess (SwAccessRC),
      .Mubi     (1'b1)
    ) u_dut (.we, .wd, .de, .d, .q, .wr_en, .wr_data);

    task automatic check(string what, logic [Width-1:0] exp_data, logic exp_en);
      #1;
      if (wr_data !== exp_data || wr_en !== exp_en) begin
        $display("ERROR: DW=%0d %s: we=%b de=%b wd=%h d=%h q=%h",
                 Width, what, we, de, wd, d, q);
        $display("       got wr_en=%b wr_data=%h, expected wr_en=%b wr_data=%h",
                 wr_en, wr_data, exp_en, exp_data);
        num_errors++;
      end
    endtask

    initial begin
      logic [Width-1:0] wd_vals [4];
      logic [Width-1:0] q_vals  [2];
      wd_vals = '{False, True, {Width{1'b0}}, {Width{1'b1}}};
      q_vals  = '{False, True};
      de = 1'b0;
      d  = '0;
      #1;
      foreach (q_vals[qi]) begin
        foreach (wd_vals[wi]) begin
          q = q_vals[qi];
          wd = wd_vals[wi];
          // A read (we) with no HW update clears the register, regardless of wd.
          we = 1'b1; de = 1'b0; d = '0;
          check("read clears", False, 1'b1);
          // A read with a simultaneous HW update of True still clears (SW read wins over the
          // value that is being written in the same cycle, as for the non-MuBi case).
          de = 1'b1; d = True;
          check("read clears HW-set value", False, 1'b1);
          // No read, no HW update: the register is unchanged (and not written).
          we = 1'b0; de = 1'b0; d = '0;
          check("idle keeps value", q, 1'b0);
          // No read, HW update: the HW value is written.
          de = 1'b1; d = True;
          check("HW update", True, 1'b1);
          d = False;
          check("HW update False", False, 1'b1);
        end
      end
    end
  end

  initial begin
    #100;
    if (num_errors == 0) $display("PASSED: prim_subreg_arb RC MuBi tests");
    else                 $display("FAILED: %0d errors", num_errors);
    $finish(num_errors == 0 ? 0 : 1);
  end
endmodule
