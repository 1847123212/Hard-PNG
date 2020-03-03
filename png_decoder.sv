`timescale 1 ns/1 ns

module huffman_inflate(
    input  wire        rst,
    input  wire        clk,
    input  wire        ivalid,
    output wire        iready,
    input  wire        ibit,
    output wire        ovalid,
    output wire  [7:0] obyte,
    output reg         raw_format,
    output reg         end_stream
);

initial  {raw_format, end_stream} = '0;

wire [ 4:0] CLCL [19] = {
    5'd16,5'd17,5'd18,5'd0,5'd8,5'd7,5'd9,5'd6,5'd10,5'd5,
    5'd11,5'd4,5'd12,5'd3,5'd13,5'd2,5'd14,5'd1,5'd15
};

wire [ 8:0] LENGTH_BASE[30] = {
    9'd0 , 9'd3 , 9'd4 , 9'd5 , 9'd6  ,9'd7  , 9'd8  , 9'd9  , 9'd10 , 9'd11,
    9'd13, 9'd15, 9'd17, 9'd19, 9'd23 , 9'd27 , 9'd31 , 9'd35 , 9'd43, 9'd51, 9'd59,
    9'd67, 9'd83, 9'd99, 9'd115,9'd131, 9'd163, 9'd195, 9'd227, 9'd258
};

wire [ 2:0] LENGTH_EXTRA[30] = {	//the extra bits used by codes 257-285 (added to base length)
    3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd1, 3'd1, 3'd1,
    3'd1, 3'd2, 3'd2, 3'd2, 3'd2, 3'd3, 3'd3, 3'd3, 3'd3, 3'd4, 3'd4,
    3'd4, 3'd4, 3'd5, 3'd5, 3'd5, 3'd5, 3'd0
};

wire [14:0] DISTANCE_BASE[30] = {	//the base backwards distances (the bits of distance codes appear after length codes and use their own huffman tree)
    15'd1, 15'd2, 15'd3, 15'd4, 15'd5, 15'd7, 15'd9, 15'd13, 
    15'd17, 15'd25, 15'd33, 15'd49, 15'd65, 15'd97, 15'd129, 15'd193, 15'd257, 15'd385, 15'd513,
    15'd769, 15'd1025, 15'd1537, 15'd2049, 15'd3073, 15'd4097, 15'd6145, 15'd8193, 15'd12289, 15'd16385, 15'd24577
};

wire [ 3:0] DISTANCE_EXTRA[30] = {	//the extra bits of backwards distances (added to base)
    4'd0, 4'd0, 4'd0, 4'd0, 4'd1, 4'd1, 4'd2, 4'd2, 4'd3, 4'd3, 4'd4,
    4'd4, 4'd5, 4'd5, 4'd6, 4'd6, 4'd7, 4'd7, 4'd8, 4'd8, 4'd9, 4'd9,
    4'd10,4'd10,4'd11,4'd11,4'd12,4'd12,4'd13,4'd13
};

reg        irepeat = 1'b0;
reg        srepeat = 1'b0;

reg symbol_valid = 1'b0;
reg [7:0] symbol  = '0;

reg  decoder_nreset = 1'b0;

reg  [ 1:0] iword = '0;
reg  [ 1:0] ibcnt = '0;
reg  [ 4:0] precode_wpt = '0;

reg         bfin  = 1'b0;
reg         bfix  = 1'b0;
reg         fixed_tree = 1'b0;
reg         precode_trash = 1'b0;
reg  [13:0] precode_reg  = '0;
wire [ 4:0] hclen = 5'd4   + {1'b0, precode_reg[13:10]};
wire [ 8:0] hlit  = 9'd257 +        precode_reg[ 4: 0]; 
wire [ 8:0] hdist = 9'd1   + {4'h0, precode_reg[ 9: 5]};
wire [ 8:0] hmax  = hlit + hdist;
wire [ 8:0] hend  = (hlit+32>288) ? hlit+32 : 288;

reg  [ 4:0] lentree_wpt  = '0;
reg  [ 8:0] tree_wpt = '0;

wire        lentree_codeen;   
wire [ 5:0] lentree_code;
wire        codetree_codeen;
wire [ 9:0] codetree_code;
wire        distree_codeen;
wire [ 9:0] distree_code;

reg  [ 2:0] repeat_code_pt  = '0;
enum {REPEAT_NONE, REPEAT_PREVIOUS, REPEAT_ZERO_FEW, REPEAT_ZERO_MANY} repeat_mode = REPEAT_NONE;
reg  [ 6:0] repeat_code='0;
reg  [ 7:0] repeat_len ='0;
reg  [ 5:0] repeat_val = '0;

reg         lentree_run = 1'b0;
wire        lentree_done;
reg         tree_run = 1'b0;
wire        codetree_done;
wire        distree_done;
wire        tree_done = (codetree_done & distree_done) | fixed_tree;

reg  [ 2:0] tcnt =3'h0, tmax =3'h0;
reg  [ 3:0] dscnt=4'h0, dsmax=4'h0;

enum {T, D, R, S} status = T;

wire   lentree_ien  = ~end_stream & ~raw_format & ivalid & lentree_done &  ~lentree_codeen & (repeat_mode==REPEAT_NONE && repeat_len==8'd0) & (tree_wpt<hmax);
wire   codetree_ien = ~end_stream & ~raw_format & ivalid & tree_done    & ~codetree_codeen & (tcnt==3'd0) & (dscnt==4'd0) & (status==T);
wire   distree_ien  = ~end_stream & ~raw_format & ivalid & tree_done    &  ~distree_codeen & (tcnt==3'd0) & (dscnt==4'd0) & (status==D);

assign iready = ~end_stream & ~raw_format & (
    ( precode_wpt<17 || lentree_wpt<hclen ) |
    ( lentree_done & ~lentree_codeen & ((repeat_mode==REPEAT_NONE && repeat_len==8'd0) | repeat_code_pt>3'd0) & (tree_wpt<hmax) ) |
    ( tree_done & ~codetree_codeen & ~distree_codeen & (status==T || status==D || (status==R && dscnt>4'd0)) ) );

reg  [ 8:0] lengthb= '0;
reg  [ 5:0] lengthe= '0;
wire [ 8:0] length = lengthb + lengthe;
reg  [ 8:0] len_last = '0;

reg  [15:0] distanceb='0;
reg  [15:0] distancee='0;
wire [15:0] distance = distanceb + distancee;

reg         lentree_wen = 1'b0;
reg  [ 4:0] lentree_waddr = '0;
reg  [ 2:0] lentree_wdata = '0;
reg         codetree_wen = 1'b0;
reg  [ 8:0] codetree_waddr = '0;
reg  [ 5:0] codetree_wdata = '0;
reg         distree_wen = 1'b0;
reg  [ 4:0] distree_waddr = '0;
reg  [ 5:0] distree_wdata = '0;

wire [ 5:0] lentree_raddr;
wire [ 5:0] lentree_rdata;
wire [ 9:0] codetree_raddr;
wire [ 9:0] codetree_rdata, codetree_rdata_fixed;
wire [ 5:0] distree_raddr;
wire [ 9:0] distree_rdata, distree_rdata_fixed;

task automatic lentree_write(input wen=1'b0, input [4:0] waddr='0, input [2:0] wdata='0);
    lentree_wen   <= wen;
    lentree_waddr <= waddr;
    lentree_wdata <= wdata;
endtask

task automatic codetree_write(input wen=1'b0, input [8:0] waddr='0, input [5:0] wdata='0);
    codetree_wen   <= wen;
    codetree_waddr <= waddr;
    codetree_wdata <= wdata;
endtask

task automatic distree_write(input wen=1'b0, input [4:0] waddr='0, input [5:0] wdata='0);
    distree_wen   <= wen;
    distree_waddr <= waddr;
    distree_wdata <= wdata;
endtask

task automatic reset_all_regs();
    decoder_nreset <= 1'b0;
    {bfin, bfix, fixed_tree} <= '0;
    iword <= '0;
    ibcnt <= '0;
    precode_wpt <= '0;
    precode_reg <= '0;
    lentree_wpt <= '0;
    lentree_run <= 1'b0;
    tree_run    <= 1'b0;
    lentree_write();
    codetree_write();
    distree_write();
    repeat_code_pt <= '0;
    repeat_mode <= REPEAT_NONE;
    repeat_code <= '0;
    repeat_len <= '0;
    repeat_val <= '0;
    tree_wpt   <= '0;
    tcnt     <= '0;
    tmax     <= '0;
    lengthb  <= '0;
    lengthe  <= '0;
    distanceb<= '0;
    distancee<= '0;
    dscnt    <= '0;
    dsmax    <= '0;
    status   <= T;
    symbol_valid <= 1'b0;
    symbol       <= '0;
    irepeat  <= 1'b0;
    srepeat  <= 1'b0;
    len_last <= '0;
endtask

always @ (posedge clk or posedge rst)
    if(rst) begin
        {raw_format, end_stream} <= '0;
        reset_all_regs();
    end else begin
        symbol_valid <= 1'b0;
        symbol       <= '0;
        irepeat  <= 1'b0;
        srepeat  <= 1'b0;
        decoder_nreset <= 1'b1;
        lentree_write();
        codetree_write();
        distree_write();
        if(precode_wpt<=2) begin
            lentree_run <= 1'b0;
            tree_run    <= 1'b0;
            if(ivalid) begin
                precode_wpt <= precode_wpt + 1;
                if(precode_wpt==0) begin
                    bfin <= ibit;
                end else if(precode_wpt==1) begin
                    bfix <= ibit;
                end else begin
                    case({ibit,bfix})
                    2'b00 :
                        raw_format <= 1'b1;
                    2'b01 : begin
                        precode_wpt <= '1;
                        lentree_wpt <= '1;
                        tree_wpt <= '1;
                        fixed_tree <= 1'b1;
                    end
                    endcase
                end
            end
        end else if(precode_wpt<17) begin
            lentree_run <= 1'b0;
            tree_run    <= 1'b0;
            if(ivalid) begin
                {precode_reg,precode_trash} <= {ibit,precode_reg};
                precode_wpt <= precode_wpt + 1;
            end
        end else if(lentree_wpt<hclen) begin
            lentree_run <= 1'b0;
            tree_run    <= 1'b0;
            if(ivalid) begin
                if(ibcnt<2'd2) begin
                    iword[ibcnt[0]] <= ibit;
                    ibcnt <= ibcnt + 2'd1;
                end else begin
                    lentree_write(1'b1, CLCL[lentree_wpt], {ibit, iword});
                    ibcnt <= 2'd0;
                    lentree_wpt <= lentree_wpt + 1;
                end
            end
        end else if(lentree_wpt<19) begin
            lentree_run <= 1'b0;
            tree_run    <= 1'b0;
            lentree_write(1'b1, CLCL[lentree_wpt], '0);
            lentree_wpt <= lentree_wpt + 1;
        end else if(~ (lentree_done | fixed_tree)) begin
            lentree_run <= ~fixed_tree;
            tree_run    <= 1'b0;
        end else if(tree_wpt<hmax) begin
            lentree_run <= ~fixed_tree;
            tree_run    <= 1'b0;
            if(repeat_code_pt>3'd0) begin
                if(ivalid) begin
                    repeat_code_pt <= repeat_code_pt - 3'd1;
                    repeat_code[3'd7-repeat_code_pt] <= ibit;
                end
            end else if(repeat_mode>0) begin
                case(repeat_mode)
                REPEAT_PREVIOUS: begin
                    repeat_len <= repeat_code[6:5] + 8'd3;
                end
                REPEAT_ZERO_FEW: begin
                    repeat_len <= repeat_code[6:4] + 8'd3;
                end
                REPEAT_ZERO_MANY: begin
                    repeat_len <= repeat_code[6:0] + 8'd11;
                end
                default: begin
                    repeat_len <= 0;
                end
                endcase
                repeat_mode <= REPEAT_NONE;
            end else if(repeat_len>8'd0) begin
                repeat_len <= repeat_len - 8'd1;
                tree_wpt   <= tree_wpt + 9'd1;
                if(tree_wpt<288)
                    codetree_write(1'b1, tree_wpt, (tree_wpt<hlit) ? repeat_val : '0);
                if(tree_wpt>=hlit && tree_wpt<(hlit+9'd32))
                    distree_write(1'b1, tree_wpt - hlit, (tree_wpt<hmax) ? repeat_val : '0);
            end else if(lentree_codeen) begin
                case(lentree_code)
                16: begin       // repeat previous
                    repeat_mode <= REPEAT_PREVIOUS;
                    repeat_code_pt <= 3'd2;
                end
                17: begin       // repeat 0 for 3-10 times
                    repeat_mode <= REPEAT_ZERO_FEW;
                    repeat_val  <= 0;
                    repeat_code_pt <= 3'd3;
                end
                18: begin       // repeat 0 for 11-138 times
                    repeat_mode <= REPEAT_ZERO_MANY;
                    repeat_val  <= 0;
                    repeat_code_pt <= 3'd7;
                end
                default: begin  // normal value
                    repeat_mode <= REPEAT_NONE;
                    repeat_val  <= lentree_code;  // save previous code for repeat
                    repeat_code_pt <= 3'd0;
                    tree_wpt <= tree_wpt + 9'd1;
                    if(tree_wpt<288)
                        codetree_write(1'b1, tree_wpt, (tree_wpt<hlit) ? lentree_code : '0);
                    if(tree_wpt>=hlit && tree_wpt<(hlit+9'd32))
                        distree_write(1'b1, tree_wpt - hlit, (tree_wpt<hmax) ? lentree_code : '0);
                end
                endcase
                repeat_code <= '0;
            end
        end else if(tree_wpt<hend) begin
            lentree_run <= ~fixed_tree;
            tree_run    <= 1'b0;
            if(tree_wpt<288)
                codetree_write(1'b1, tree_wpt, '0);
            if(tree_wpt>=hlit && tree_wpt<(hlit+9'd32))
                distree_write(1'b1, tree_wpt - hlit, '0);
            tree_wpt <= tree_wpt + 9'd1;
        end else if(tree_wpt<hend+2) begin
            lentree_run <= ~fixed_tree;
            tree_run    <= 1'b0;
            tree_wpt <= tree_wpt + 9'd1;
        end else if(~tree_done) begin
            lentree_run <= ~fixed_tree;
            tree_run    <= 1'b1;
        end else begin
            lentree_run <= ~fixed_tree;
            tree_run    <= ~fixed_tree;
            if(dscnt>4'd0) begin
                if(ivalid) begin
                    dscnt <= dscnt - 4'd1;
                    distancee[dsmax-dscnt] <= ibit;
                end
            end else if(tcnt>3'd0) begin
                if(ivalid) begin
                    tcnt <= tcnt - 3'd1;
                    lengthe[tmax-tcnt] <= ibit;
                end
            end else if(status==R) begin
                status <= S;
                len_last <= length;
                srepeat  <= 1'b1;
            end else if(status==S) begin
                if(len_last>0) begin
                    irepeat <= 1'b1;
                    len_last <= len_last - 1;
                end else
                    status <= T;
            end else if(codetree_codeen) begin
                if(codetree_code<10'd256) begin             // normal symbol
                    symbol_valid <= 1'b1;
                    symbol       <= codetree_code;
                end else if(codetree_code==10'd256) begin   // end symbol
                    end_stream <= bfin;
                    reset_all_regs();
                end else begin                              // special symbol
                    lengthb<= LENGTH_BASE[codetree_code-10'd256];
                    lengthe<= '0;
                    tcnt   <= LENGTH_EXTRA[codetree_code-10'd256];
                    tmax   <= LENGTH_EXTRA[codetree_code-10'd256];
                    status <= D;
                end
            end else if(distree_codeen) begin
                distanceb<= DISTANCE_BASE[distree_code];
                distancee<= '0;
                dscnt    <= DISTANCE_EXTRA[distree_code];
                dsmax    <= DISTANCE_EXTRA[distree_code];
                status <= R;
            end
        end
    end

huffman_build #(
    .NUMCODES  ( 19             ),
    .CODEBITS  ( 3              ),
    .BITLENGTH ( 7              ),
    .OUTWIDTH  ( 6              )
) lentree_builder (
    .clk       ( clk            ),
    .wren      ( lentree_wen    ),
    .wraddr    ( lentree_waddr  ),
    .wrdata    ( lentree_wdata  ),
    .run       ( lentree_run    ),
    .done      ( lentree_done   ),
    .rdaddr    ( lentree_raddr  ),
    .rddata    ( lentree_rdata  )
);

huffman_decode_symbol #(
    .NUMCODES  ( 19             ),
    .OUTWIDTH  ( 6              )
) lentree_decoder (
    .rst       ( ~decoder_nreset),
    .clk       ( clk            ),
    .ien       ( lentree_ien    ),
    .ibit      ( ibit           ),
    .oen       ( lentree_codeen ),
    .ocode     ( lentree_code   ),
    .rdaddr    ( lentree_raddr  ),
    .rddata    ( lentree_rdata  )
);

huffman_build #(
    .NUMCODES  ( 288            ),
    .CODEBITS  ( 5              ),
    .BITLENGTH ( 15             ),
    .OUTWIDTH  ( 10             )
) codetree_builder (
    .clk       ( clk            ),
    .wren      ( codetree_wen   ),
    .wraddr    ( codetree_waddr ),
    .wrdata    ( codetree_wdata ),
    .run       ( tree_run       ),
    .done      ( codetree_done  ),
    .rdaddr    ( codetree_raddr ),
    .rddata    ( codetree_rdata )
);

fixed_codetree codetree_fixed(
    .clk       ( clk            ),
    .rdaddr    ( codetree_raddr ),
    .rddata    ( codetree_rdata_fixed )
);

huffman_decode_symbol #(
    .NUMCODES  ( 288            ),
    .OUTWIDTH  ( 10             )
) codetree_decoder (
    .rst       ( ~decoder_nreset),
    .clk       ( clk            ),
    .ien       ( codetree_ien   ),
    .ibit      ( ibit           ),
    .oen       ( codetree_codeen),
    .ocode     ( codetree_code  ),
    .rdaddr    ( codetree_raddr ),
    .rddata    ( fixed_tree ? codetree_rdata_fixed : codetree_rdata )
);

huffman_build #(
    .NUMCODES  ( 32             ),
    .CODEBITS  ( 5              ),
    .BITLENGTH ( 15             ),
    .OUTWIDTH  ( 10             )
) distree_builder (
    .clk       ( clk            ),
    .wren      ( distree_wen    ),
    .wraddr    ( distree_waddr  ),
    .wrdata    ( distree_wdata  ),
    .run       ( tree_run       ),
    .done      ( distree_done   ),
    .rdaddr    ( distree_raddr  ),
    .rddata    ( distree_rdata  )
);

fixed_distree distree_fixed(
    .clk       ( clk            ),
    .rdaddr    ( distree_raddr  ),
    .rddata    ( distree_rdata_fixed )
);

huffman_decode_symbol #(
    .NUMCODES  ( 32             ),
    .OUTWIDTH  ( 10             )
) distree_decoder (
    .rst       ( ~decoder_nreset),
    .clk       ( clk            ),
    .ien       ( distree_ien    ),
    .ibit      ( ibit           ),
    .oen       ( distree_codeen ),
    .ocode     ( distree_code   ),
    .rdaddr    ( distree_raddr  ),
    .rddata    ( fixed_tree ? distree_rdata_fixed : distree_rdata  )
);

repeat_buffer repeat_buffer_i(
    .clk          ( clk            ),
    
    .ivalid       ( symbol_valid   ),
    .idata        ( symbol         ),
    
    .repeat_en    ( irepeat        ),
    .repeat_start ( srepeat        ),
    .repeat_dist  ( distance       ),
    
    .ovalid       ( ovalid         ),
    .odata        ( obyte          )
);
/*
always @ (posedge clk) begin
    if(symbol_valid)
        $write("%1d ", symbol);
    if(srepeat)
        $write("%1dd%1d ", length, distance);
end
*/
endmodule























module huffman_decode_symbol #(
    parameter    NUMCODES = 288,
    parameter    OUTWIDTH = 10
)(
    rst, clk,
    ien, ibit,
    oen, ocode,
    rdaddr, rddata
);

input  rst, clk;
input  ien, ibit;
output oen, ocode;
output rdaddr;
input  rddata;

function automatic integer clogb2(input integer val);
    for(clogb2=0; val>0; clogb2=clogb2+1) val = val>>1;
endfunction

wire                              rst, clk;
wire                              ien, ibit;
reg                               oen = 1'b0;
reg  [            OUTWIDTH-1:0]   ocode = '0;
wire [clogb2(2*NUMCODES-1)-1:0]   rdaddr;
wire [            OUTWIDTH-1:0]   rddata;

reg  [clogb2(2*NUMCODES-1)-2:0]   tpos = '0;
wire [clogb2(2*NUMCODES-1)-2:0]   ntpos;
reg                               ienl = 1'b0;

assign rdaddr = {ntpos, ibit};

assign ntpos = ienl ? (rddata<NUMCODES ? '0 : rddata-NUMCODES) : tpos;

always @ (posedge clk or posedge rst)
    if(rst)
        ienl <= 1'b0;
    else
        ienl <= ien;

always @ (posedge clk or posedge rst)
    if(rst)
        tpos <= '0;
    else
        tpos <= ntpos;

always_comb
    if(ienl && rddata<NUMCODES) begin
        oen   <= 1'b1;
        ocode <= rddata;
    end else begin
        oen   <= 1'b0;
        ocode <= '0;
    end

endmodule





















module fixed_codetree (
  input  logic       clk,
  input  logic [9:0] rdaddr,
  output logic [9:0] rddata
);

wire [9:0] rom [1024] = {10'd289, 10'd370, 10'd290, 10'd307, 10'd546, 10'd291, 10'd561, 10'd292, 10'd293, 10'd300, 10'd294, 10'd297, 10'd295, 10'd296, 10'd0, 10'd1, 10'd2, 10'd3, 10'd298, 10'd299, 10'd4, 10'd5, 10'd6, 10'd7, 10'd301, 10'd304, 10'd302, 10'd303, 10'd8, 10'd9, 10'd10, 10'd11, 10'd305, 10'd306, 10'd12, 10'd13, 10'd14, 10'd15, 10'd308, 10'd339, 10'd309, 10'd324, 10'd310, 10'd317, 10'd311, 10'd314, 10'd312, 10'd313, 10'd16, 10'd17, 10'd18, 10'd19, 10'd315, 10'd316, 10'd20, 10'd21, 10'd22, 10'd23, 10'd318, 10'd321, 10'd319, 10'd320, 10'd24, 10'd25, 10'd26, 10'd27, 10'd322, 10'd323, 10'd28, 10'd29, 10'd30, 10'd31, 10'd325, 10'd332, 10'd326, 10'd329, 10'd327, 10'd328, 10'd32, 10'd33, 10'd34, 10'd35, 10'd330, 10'd331, 10'd36, 10'd37, 10'd38, 10'd39, 10'd333, 10'd336, 10'd334, 10'd335, 10'd40, 10'd41, 10'd42, 10'd43, 10'd337, 10'd338, 10'd44, 10'd45, 10'd46, 10'd47, 10'd340, 10'd355, 10'd341, 10'd348, 10'd342, 10'd345, 10'd343, 10'd344, 10'd48, 10'd49, 10'd50, 10'd51, 10'd346, 10'd347, 10'd52, 10'd53, 10'd54, 10'd55, 10'd349, 10'd352, 10'd350, 10'd351, 10'd56, 10'd57, 10'd58, 10'd59, 10'd353, 10'd354, 10'd60, 10'd61, 10'd62, 10'd63, 10'd356, 10'd363, 10'd357, 10'd360, 10'd358, 10'd359, 10'd64, 10'd65, 10'd66, 10'd67, 10'd361, 10'd362, 10'd68, 10'd69, 10'd70, 10'd71, 10'd364, 10'd367, 10'd365, 10'd366, 10'd72, 10'd73, 10'd74, 10'd75, 10'd368, 10'd369, 10'd76, 10'd77, 10'd78, 10'd79, 10'd371, 10'd434, 10'd372, 10'd403, 10'd373, 10'd388, 10'd374, 10'd381, 10'd375, 10'd378, 10'd376, 10'd377, 10'd80, 10'd81, 10'd82, 10'd83, 10'd379, 10'd380, 10'd84, 10'd85, 10'd86, 10'd87, 10'd382, 10'd385, 10'd383, 10'd384, 10'd88, 10'd89, 10'd90, 10'd91, 10'd386, 10'd387, 10'd92, 10'd93, 10'd94, 10'd95, 10'd389, 10'd396, 10'd390, 10'd393, 10'd391, 10'd392, 10'd96, 10'd97, 10'd98, 10'd99, 10'd394, 10'd395, 10'd100, 10'd101, 10'd102, 10'd103, 10'd397, 10'd400, 10'd398, 10'd399, 10'd104, 10'd105, 10'd106, 10'd107, 10'd401, 10'd402, 10'd108, 10'd109, 10'd110, 10'd111, 10'd404, 10'd419, 10'd405, 10'd412, 10'd406, 10'd409, 10'd407, 10'd408, 10'd112, 10'd113, 10'd114, 10'd115, 10'd410, 10'd411, 10'd116, 10'd117, 10'd118, 10'd119, 10'd413, 10'd416, 10'd414, 10'd415, 10'd120, 10'd121, 10'd122, 10'd123, 10'd417, 10'd418, 10'd124, 10'd125, 10'd126, 10'd127, 10'd420, 10'd427, 10'd421, 10'd424, 10'd422, 10'd423, 10'd128, 10'd129, 10'd130, 10'd131, 10'd425, 10'd426, 10'd132, 10'd133, 10'd134, 10'd135, 10'd428, 10'd431, 10'd429, 10'd430, 10'd136, 10'd137, 10'd138, 10'd139, 10'd432, 10'd433, 10'd140, 10'd141, 10'd142, 10'd143, 10'd435, 10'd483, 10'd436, 10'd452, 10'd568, 10'd437, 10'd438, 10'd445, 10'd439, 10'd442, 10'd440, 10'd441, 10'd144, 10'd145, 10'd146, 10'd147, 10'd443, 10'd444, 10'd148, 10'd149, 10'd150, 10'd151, 10'd446, 10'd449, 10'd447, 10'd448, 10'd152, 10'd153, 10'd154, 10'd155, 10'd450, 10'd451, 10'd156, 10'd157, 10'd158, 10'd159, 10'd453, 10'd468, 10'd454, 10'd461, 10'd455, 10'd458, 10'd456, 10'd457, 10'd160, 10'd161, 10'd162, 10'd163, 10'd459, 10'd460, 10'd164, 10'd165, 10'd166, 10'd167, 10'd462, 10'd465, 10'd463, 10'd464, 10'd168, 10'd169, 10'd170, 10'd171, 10'd466, 10'd467, 10'd172, 10'd173, 10'd174, 10'd175, 10'd469, 10'd476, 10'd470, 10'd473, 10'd471, 10'd472, 10'd176, 10'd177, 10'd178, 10'd179, 10'd474, 10'd475, 10'd180, 10'd181, 10'd182, 10'd183, 10'd477, 10'd480, 10'd478, 10'd479, 10'd184, 10'd185, 10'd186, 10'd187, 10'd481, 10'd482, 10'd188, 10'd189, 10'd190, 10'd191, 10'd484, 10'd515, 10'd485, 10'd500, 10'd486, 10'd493, 10'd487, 10'd490, 10'd488, 10'd489, 10'd192, 10'd193, 10'd194, 10'd195, 10'd491, 10'd492, 10'd196, 10'd197, 10'd198, 10'd199, 10'd494, 10'd497, 10'd495, 10'd496, 10'd200, 10'd201, 10'd202, 10'd203, 10'd498, 10'd499, 10'd204, 10'd205, 10'd206, 10'd207, 10'd501, 10'd508, 10'd502, 10'd505, 10'd503, 10'd504, 10'd208, 10'd209, 10'd210, 10'd211, 10'd506, 10'd507, 10'd212, 10'd213, 10'd214, 10'd215, 10'd509, 10'd512, 10'd510, 10'd511, 10'd216, 10'd217, 10'd218, 10'd219, 10'd513, 10'd514, 10'd220, 10'd221, 10'd222, 10'd223, 10'd516, 10'd531, 10'd517, 10'd524, 10'd518, 10'd521, 10'd519, 10'd520, 10'd224, 10'd225, 10'd226, 10'd227, 10'd522, 10'd523, 10'd228, 10'd229, 10'd230, 10'd231, 10'd525, 10'd528, 10'd526, 10'd527, 10'd232, 10'd233, 10'd234, 10'd235, 10'd529, 10'd530, 10'd236, 10'd237, 10'd238, 10'd239, 10'd532, 10'd539, 10'd533, 10'd536, 10'd534, 10'd535, 10'd240, 10'd241, 10'd242, 10'd243, 10'd537, 10'd538, 10'd244, 10'd245, 10'd246, 10'd247, 10'd540, 10'd543, 10'd541, 10'd542, 10'd248, 10'd249, 10'd250, 10'd251, 10'd544, 10'd545, 10'd252, 10'd253, 10'd254, 10'd255, 10'd547, 10'd554, 10'd548, 10'd551, 10'd549, 10'd550, 10'd256, 10'd257, 10'd258, 10'd259, 10'd552, 10'd553, 10'd260, 10'd261, 10'd262, 10'd263, 10'd555, 10'd558, 10'd556, 10'd557, 10'd264, 10'd265, 10'd266, 10'd267, 10'd559, 10'd560, 10'd268, 10'd269, 10'd270, 10'd271, 10'd562, 10'd565, 10'd563, 10'd564, 10'd272, 10'd273, 10'd274, 10'd275, 10'd566, 10'd567, 10'd276, 10'd277, 10'd278, 10'd279, 10'd569, 10'd572, 10'd570, 10'd571, 10'd280, 10'd281, 10'd282, 10'd283, 10'd573, 10'd574, 10'd284, 10'd285, 10'd286, 10'd287, 10'd0, 10'd0,  10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0, 10'd0};

always @ (posedge clk)
    rddata <= rom[rdaddr];

endmodule







module fixed_distree (
  input  logic       clk,
  input  logic [5:0] rdaddr,
  output logic [9:0] rddata
);

wire [9:0] rom [64] = {10'd33, 10'd48, 10'd34, 10'd41, 10'd35, 10'd38, 10'd36, 10'd37, 10'd0, 10'd1, 10'd2, 10'd3, 10'd39, 10'd40, 10'd4, 10'd5, 10'd6, 10'd7, 10'd42, 10'd45, 10'd43, 10'd44, 10'd8, 10'd9, 10'd10, 10'd11, 10'd46, 10'd47, 10'd12, 10'd13, 10'd14, 10'd15, 10'd49, 10'd56, 10'd50, 10'd53, 10'd51, 10'd52, 10'd16, 10'd17, 10'd18, 10'd19, 10'd54, 10'd55, 10'd20, 10'd21, 10'd22, 10'd23, 10'd57, 10'd60, 10'd58, 10'd59, 10'd24, 10'd25, 10'd26, 10'd27, 10'd61, 10'd62, 10'd28, 10'd29, 10'd30, 10'd31, 10'd0, 10'd0};

always @ (posedge clk)
    rddata <= rom[rdaddr];

endmodule







module huffman_build #(
    parameter NUMCODES = 288,
    parameter CODEBITS = 5,
    parameter BITLENGTH= 15,
    parameter OUTWIDTH = 10
) (
    clk,
    wren, wraddr, wrdata,
    run , done,
    rdaddr, rddata
);

input  clk;
input  wren, wraddr, wrdata;
input  run;
output done;
input  rdaddr;
output rddata;

function automatic integer clogb2(input integer val);
    for(clogb2=0; val>0; clogb2=clogb2+1) val = val>>1;
endfunction

wire                              clk;
wire                              wren;
wire [  clogb2(NUMCODES-1)-1:0]   wraddr;
wire [           CODEBITS -1:0]   wrdata;
wire                              run;
wire                              done;
wire [clogb2(2*NUMCODES-1)-1:0]   rdaddr;
wire [            OUTWIDTH-1:0]   rddata;

reg  [clogb2(NUMCODES)-1:0] blcount  [BITLENGTH];
reg  [                31:0] nextcode [BITLENGTH+1];

reg  build_tree2d = 1'b0;
reg  [clogb2(BITLENGTH)-1:0] idx = '0;
reg  [ clogb2(NUMCODES)-1:0] nn='0, nnn, lnn='0;
reg  [CODEBITS-1:0] ii='0, lii='0;
reg  [CODEBITS-1:0] blenn, blen = '0;
wire [31:0] tree1d = nextcode[blen];
wire        islast = (blen==0 || ii==0);
reg  [clogb2(2*NUMCODES-1)-1:0] nodefilled=0;
reg  [clogb2(2*NUMCODES-1)-1:0] ntreepos, treepos='0;
wire [clogb2(2*NUMCODES-1)  :0] ntpos= {ntreepos, tree1d[ii]};
reg  [clogb2(2*NUMCODES-1)  :0] tpos = 0;
wire        rdfilled;
reg         valid = 1'b0;
wire [OUTWIDTH-1:0] rdtree2d;
wire [OUTWIDTH-1:0] wrtree2d = (lii==0) ? lnn : nodefilled + NUMCODES;
reg  alldone = 1'b0;

assign done = alldone & run;

initial for(int i=0; i< BITLENGTH; i++) blcount[i] = '0;
initial for(int i=0; i<=BITLENGTH; i++) nextcode[i] = '0;

always @ (posedge clk) begin
    valid <= build_tree2d & nn<NUMCODES & blen>0;
    treepos <= ntreepos;
    tpos <= {ntreepos, tree1d[ii]};
    lii <= ii;
    lnn <= nn;
end

always @ (posedge clk)
    if(islast)
        blen <= blenn;

always @ (posedge clk)
    if(done) begin
        for(int i=0; i<BITLENGTH; i++)
            blcount[i] <= '0;
    end else begin
        if(wren && wrdata<BITLENGTH)
            blcount[wrdata] <= blcount[wrdata] + 1;
    end

always_comb
    if(build_tree2d)
        nnn <= (nn<NUMCODES && islast) ? nn+1 : nn;
    else
        nnn <= (idx<BITLENGTH) ? '1 : '0;
        
always @ (posedge clk)
    nn <= nnn;

always @ (posedge clk) begin
    nextcode[0] = 0;
    alldone <= 1'b0;
    if(run) begin
        if(build_tree2d) begin
            if(nn<NUMCODES) begin
                if(islast) begin
                    ii <= blenn - 1;
                    if(blen>0)
                        nextcode[blen] <= tree1d + 1;
                end else
                    ii <= ii - 1;
            end else
                alldone <= 1'b1;
        end else begin
            if(idx<BITLENGTH) begin
                idx <= idx + 1;
                nextcode[idx+1] <= ( (nextcode[idx] + blcount[idx]) << 1 );
            end else begin
                ii <= blen - 1;
                build_tree2d <= 1'b1;
            end
        end
    end else begin
        ii <= '0;
        idx <= '0;
        build_tree2d <= 1'b0;
    end
end

always_comb
    if(~run)
        ntreepos <= 0;
    else if(valid) begin
        if(~rdfilled)
            ntreepos <= rdtree2d - NUMCODES;
        else
            ntreepos <= (lii==0) ? 0 : nodefilled;
    end else
        ntreepos <= treepos;
    
always @ (posedge clk)
    if(~run)
        nodefilled <= 1;
    else if(valid & rdfilled & lii>0)
        nodefilled <= nodefilled + 1;

RamSinglePort #(
    .SIZE     ( NUMCODES    ),
    .WIDTH    ( CODEBITS    )
) ram_for_bitlens (
    .clk      ( clk         ),
    .wen      ( wren        ),
    .waddr    ( wraddr      ),
    .wdata    ( wrdata      ),
    .raddr    ( nnn+1       ),
    .rdata    ( blenn       )
);

RamDualPort #(
    .SIZE     ( NUMCODES*2  ),
    .WIDTH    ( OUTWIDTH+1  )
) ram_for_tree2d (
    .clk      ( clk                         ),
    .wen      ( wren || (valid && rdfilled) ),
    .waddr    ( wren ? wraddr : tpos        ),
    .wdata    ( wren ? {1'b1,{OUTWIDTH{1'b0}}} : {1'b0, wrtree2d}       ),
    .wen2     ( wren                        ),
    .waddr2   ( wraddr + NUMCODES           ),
    .wdata2   ( {1'b1,{OUTWIDTH{1'b0}}}     ),
    .raddr    ( ntpos                       ),
    .rdata    ( {rdfilled,rdtree2d}         ),
    .raddr2   ( rdaddr                      ),
    .rdata2   ( rddata                      )
);

endmodule














module repeat_buffer #(
    parameter            MAXLEN = 32768+1024,
    parameter            DWIDTH = 8
) (
    input                    clk,
    
    input                    ivalid,
    input      [DWIDTH-1:0]  idata,
    
    input                    repeat_en,
    input                    repeat_start,
    input      [      15:0]  repeat_dist,
    
    output                   ovalid,
    output     [DWIDTH-1:0]  odata
);

reg  [15:0]  wptr = '0;
reg  [15:0]  rptr = '0;
reg  [15:0]  sptr = '0;
reg  [15:0]  eptr = '0;
wire [15:0]  sptrw = (wptr<repeat_dist) ? wptr + MAXLEN - repeat_dist : wptr - repeat_dist;
wire [15:0]  eptrw = (wptr<1) ? wptr + MAXLEN - 1 : wptr - 1;

reg                repeat_valid = 1'b0;
wire [DWIDTH-1:0]  repeat_data;

assign  ovalid = ivalid | repeat_valid;
assign  odata  = repeat_valid ? repeat_data : idata;

always @ (posedge clk)
    if(ovalid)
        wptr <= (wptr<(MAXLEN-1)) ? wptr+16'd1 : '0;

always @ (posedge clk) begin
    if(repeat_start) begin
        rptr <= sptrw;
        sptr <= sptrw;
        eptr <= eptrw;
    end else if(repeat_en) begin
        if(rptr!=eptr)
            rptr <= (rptr<(MAXLEN-1)) ? rptr+16'd1 : '0;
        else
            rptr <= sptr;
    end
end

always @ (posedge clk)
    repeat_valid <= repeat_en;

RamSinglePort #(
    .SIZE     ( MAXLEN      ),
    .WIDTH    ( DWIDTH      )
) ram_for_bitlens (
    .clk      ( clk         ),
    .wen      ( ovalid      ),
    .waddr    ( wptr        ),
    .wdata    ( odata       ),
    .raddr    ( rptr        ),
    .rdata    ( repeat_data )
);

endmodule



























module RamSinglePort #(
    parameter  SIZE     = 1024,
    parameter  WIDTH    = 32
)(
    clk,
    wen,
    waddr,
    wdata,
    raddr,
    rdata
);

input  clk, wen, waddr, wdata, raddr;
output rdata;

function automatic integer clogb2(input integer val);
    for(clogb2=0; val>0; clogb2=clogb2+1) val = val>>1;
endfunction

wire  clk;
wire  wen;
wire  [clogb2(SIZE-1)-1:0] waddr;
wire  [WIDTH-1:0] wdata;
wire  [clogb2(SIZE-1)-1:0] raddr;
reg   [WIDTH-1:0] rdata;

reg [WIDTH-1:0] mem [SIZE];

always @ (posedge clk)
    if(wen)
        mem[waddr] <= wdata;

initial rdata = '0;
always @ (posedge clk)
    rdata <= mem[raddr];

endmodule





















module RamDualPort #(
    parameter  SIZE     = 1024,
    parameter  WIDTH    = 32
)(
    clk,
    wen,
    waddr,
    wdata,
    wen2,
    waddr2,
    wdata2,
    raddr,
    rdata,
    raddr2,
    rdata2
);

input  clk;
input  wen , waddr , wdata;
input  wen2, waddr2, wdata2;
input  raddr;
output rdata;
input  raddr2;
output rdata2;

function automatic integer clogb2(input integer val);
    for(clogb2=0; val>0; clogb2=clogb2+1) val = val>>1;
endfunction

wire  clk;
wire  wen;
wire  [clogb2(SIZE-1)-1:0] waddr;
wire  [WIDTH-1:0] wdata;
wire  wen2;
wire  [clogb2(SIZE-1)-1:0] waddr2;
wire  [WIDTH-1:0] wdata2;
wire  [clogb2(SIZE-1)-1:0] raddr;
reg   [WIDTH-1:0] rdata;
wire  [clogb2(SIZE-1)-1:0] raddr2;
reg   [WIDTH-1:0] rdata2;

reg [WIDTH-1:0] mem [SIZE];

always @ (posedge clk)
    if(wen)
        mem[waddr] <= wdata;
        
always @ (posedge clk)
    if(wen2)
        mem[waddr2] <= wdata2;

initial rdata = '0;
always @ (posedge clk)
    rdata <= mem[raddr];
    
initial rdata2 = '0;
always @ (posedge clk)
    rdata2 <= mem[raddr2];

endmodule


