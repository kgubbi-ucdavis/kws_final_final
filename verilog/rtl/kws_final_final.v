// verilator lint_off BLKANDNBLK
/* verilator lint_off EOFNEWLINE */


module CNN_Accelerator_Top(
    input wire clk,
    input wire reset,
    input wire start,
    input wire [7:0] serial_weight_data,  // Serial weight data from off-chip memory
    input wire serial_weight_valid,       // Valid signal for serial weight data
    input wire [7:0] serial_line_data,    // Serial line data from off-chip memory
    input wire serial_line_valid,         // Valid signal for serial line data
    output reg [7:0] serial_result,       // Serial output for result data
    output reg serial_result_valid,       // Valid signal for serial result data
    output wire done
);

    // Registers to store the results
    reg [7:0] result [15:0];
    reg [3:0] result_index;

    // Control FSM signals
    wire weight_write_enable;
    wire line_write_enable;
    wire [7:0] weight_data;
    wire [3:0] weight_write_addr;
    wire [7:0] line_data;
    wire [3:0] line_write_addr;
    wire [3:0] line_read_addr;

    // Intermediate signals
    wire [127:0] weight_out;
    wire [127:0] line_out;
    wire [255:0] products;
    wire [127:0] sum;

    // Instantiate the Control FSM
    ControlFSM control_fsm (
        .clk(clk),
        .reset(reset),
        .start(start),
        .weight_write_enable(weight_write_enable),
        .line_write_enable(line_write_enable),
        .weight_data(weight_data),
        .weight_write_addr(weight_write_addr),
        .line_data(line_data),
        .line_write_addr(line_write_addr),
        .line_read_addr(line_read_addr),
        .done(done),
        .serial_weight_data(serial_weight_data),
        .serial_weight_valid(serial_weight_valid),
        .serial_line_data(serial_line_data),
        .serial_line_valid(serial_line_valid)
    );

    // Instantiate the Weight Buffer
    WeightBuffer weight_buffer (
        .clk(clk),
        .reset(reset),
        .weight_data(weight_data),
        .write_enable(weight_write_enable),
        .write_addr(weight_write_addr),
        .weight_out(weight_out)
    );

    // Instantiate the Line Buffer
    LineBuffer line_buffer (
        .clk(clk),
        .reset(reset),
        .data_in(line_data),
        .write_enable(line_write_enable),
        .write_addr(line_write_addr),
        .read_addr(line_read_addr),
        .data_out(line_out)
    );

    // Instantiate the MAC Array
    MACArray mac_array (
        .line_data(line_out),
        .weight_data(weight_out),
        .products(products)
    );

    // Instantiate the Configurable Adder Tree
    ConfigurableAdderTree adder_tree (
        .products(products),
        .final_sum(sum)
    );

    // Combined always block for state transitions and signal assignments
    localparam IDLE = 2'b00,
               SERIALIZE = 2'b01;

    reg [1:0] state, next_state;
    integer i;  // Declare the loop variable here

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            next_state <= IDLE;
            result_index <= 0;
            serial_result_valid <= 0;
            serial_result <= 8'b0;
            for (i = 0; i < 16; i = i + 1) begin
                result[i] <= 0;
            end
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    if (done) begin
                        next_state <= SERIALIZE;
                        for (i = 0; i < 16; i = i + 1) begin
                            result[i] <= sum[i*8 +: 8];
                        end
                        result_index <= 0;
                    end else begin
                        serial_result_valid <= 0;
                    end
                end
                SERIALIZE: begin
                    if (result_index < 16) begin
                        serial_result <= result[result_index];
                        serial_result_valid <= 1;
                        result_index <= result_index + 1;
                    end else begin
                        next_state <= IDLE;
                        serial_result_valid <= 0;
                    end
                end
                default: next_state <= IDLE;
            endcase
        end
    end

endmodule

module ControlFSM(
    input wire clk,
    input wire reset,
    input wire start,
    output reg weight_write_enable,
    output reg line_write_enable,
    output reg [7:0] weight_data,
    output reg [3:0] weight_write_addr,
    output reg [7:0] line_data,
    output reg [3:0] line_write_addr,
    output reg [3:0] line_read_addr,
    output reg done,
    input wire [7:0] serial_weight_data,  // Serial weight data from top module
    input wire serial_weight_valid,       // Valid signal for serial weight data
    input wire [7:0] serial_line_data,    // Serial line data from top module
    input wire serial_line_valid          // Valid signal for serial line data
);
    reg [3:0] state, next_state;
    reg [3:0] read_addr_counter; // Read address counter

    localparam IDLE = 4'b0000,
               LOAD_WEIGHTS = 4'b0001,
               LOAD_LINE = 4'b0010,
               COMPUTE = 4'b0011,
               RELU = 4'b0101,
               POOL = 4'b0110,
               DONE = 4'b0111;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            read_addr_counter <= 0; // Initialize read address counter
        end else begin
            state <= next_state;
            if (state == COMPUTE) begin
                read_addr_counter <= read_addr_counter + 1;
            end else begin
                read_addr_counter <= 0;
            end
        end
    end

    always @(*) begin
        next_state = state;
        weight_write_enable = 0;
        line_write_enable = 0;
        weight_data = 0;
        weight_write_addr = 0;
        line_data = 0;
        line_write_addr = 0;
        line_read_addr = read_addr_counter; // Dynamic read address
        done = 0;

        case (state)
            IDLE: begin
                if (start)
                    next_state = LOAD_WEIGHTS;
            end
            LOAD_WEIGHTS: begin
                if (serial_weight_valid) begin
                    weight_write_enable = 1;
                    weight_data = serial_weight_data;
                    weight_write_addr = weight_write_addr + 1;
                    if (weight_write_addr == 4'b1111)
                        next_state = LOAD_LINE;
                end
            end
            LOAD_LINE: begin
                if (serial_line_valid) begin
                    line_write_enable = 1;
                    line_data = serial_line_data;
                    line_write_addr = line_write_addr + 1;
                    if (line_write_addr == 4'b1111)
                        next_state = COMPUTE;
                end
            end
            COMPUTE: begin
                next_state = RELU;
            end
            RELU: begin
                next_state = POOL;
            end
            POOL: begin
                next_state = DONE;
            end
            DONE: begin
                done = 1;
                next_state = IDLE;
            end
            default: next_state = IDLE; // Ensure default case is handled
        endcase
    end
endmodule

module ReLU(
    input wire [127:0] data_in,
    output wire [127:0] data_out
);
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : relu_loop
            assign data_out[i*8 +: 8] = (data_in[i*8 + 7] == 1'b1) ? 8'b0 : data_in[i*8 +: 8]; // Check if the MSB (sign bit) is 1
        end
    endgenerate
endmodule

module Pooling(
    input wire [7:0] data_in0,
    input wire [7:0] data_in1,
    input wire [7:0] data_in2,
    input wire [7:0] data_in3,
    output wire [7:0] data_out
);
    assign data_out = (data_in0 + data_in1 + data_in2 + data_in3) >> 2; // Average pooling
endmodule

module AdderTree(
    input wire [7:0] in0,
    input wire [7:0] in1,
    input wire [7:0] in2,
    input wire [7:0] in3,
    input wire [7:0] in4,
    input wire [7:0] in5,
    input wire [7:0] in6,
    input wire [7:0] in7,
    output wire [7:0] sum
);
    wire [7:0] sum1, sum2, sum3, sum4;
    assign sum1 = in0 + in1;
    assign sum2 = in2 + in3;
    assign sum3 = in4 + in5;
    assign sum4 = in6 + in7;
    assign sum = sum1 + sum2 + sum3 + sum4;
endmodule

module ConfigurableAdderTree(
    input wire [255:0] products, // Flattened array for products (16 x 16-bit)
    output wire [127:0] final_sum // Flattened array for final sums (16 x 8-bit)
);

    // Unflattened products for easier readability
    wire [15:0] products_array [15:0];
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : products_loop
            assign products_array[i] = products[i*16 +: 16]; // Fixed range
        end
    endgenerate

    // Pointwise summation
    AdderTree adder_tree_0 (
        .in0(products_array[0][7:0]),
        .in1(products_array[1][7:0]),
        .in2(products_array[2][7:0]),
        .in3(products_array[3][7:0]),
        .in4(products_array[4][7:0]),
        .in5(products_array[5][7:0]),
        .in6(products_array[6][7:0]),
        .in7(products_array[7][7:0]),
        .sum(final_sum[7:0])
    );

    AdderTree adder_tree_1 (
        .in0(products_array[8][7:0]),
        .in1(products_array[9][7:0]),
        .in2(products_array[10][7:0]),
        .in3(products_array[11][7:0]),
        .in4(products_array[12][7:0]),
        .in5(products_array[13][7:0]),
        .in6(products_array[14][7:0]),
        .in7(products_array[15][7:0]),
        .sum(final_sum[15:8])
    );

    AdderTree adder_tree_2 (
        .in0(products_array[0][15:8]),
        .in1(products_array[1][15:8]),
        .in2(products_array[2][15:8]),
        .in3(products_array[3][15:8]),
        .in4(products_array[4][15:8]),
        .in5(products_array[5][15:8]),
        .in6(products_array[6][15:8]),
        .in7(products_array[7][15:8]),
        .sum(final_sum[23:16])
    );

    AdderTree adder_tree_3 (
        .in0(products_array[8][15:8]),
        .in1(products_array[9][15:8]),
        .in2(products_array[10][15:8]),
        .in3(products_array[11][15:8]),
        .in4(products_array[12][15:8]),
        .in5(products_array[13][15:8]),
        .in6(products_array[14][15:8]),
        .in7(products_array[15][15:8]),
        .sum(final_sum[31:24])
    );

    AdderTree adder_tree_4 (
        .in0(products_array[0][7:0]),
        .in1(products_array[1][7:0]),
        .in2(products_array[2][7:0]),
        .in3(products_array[3][7:0]),
        .in4(products_array[4][7:0]),
        .in5(products_array[5][7:0]),
        .in6(products_array[6][7:0]),
        .in7(products_array[7][7:0]),
        .sum(final_sum[39:32])
    );

    AdderTree adder_tree_5 (
        .in0(products_array[8][7:0]),
        .in1(products_array[9][7:0]),
        .in2(products_array[10][7:0]),
        .in3(products_array[11][7:0]),
        .in4(products_array[12][7:0]),
        .in5(products_array[13][7:0]),
        .in6(products_array[14][7:0]),
        .in7(products_array[15][7:0]),
        .sum(final_sum[47:40])
    );

    AdderTree adder_tree_6 (
        .in0(products_array[0][15:8]),
        .in1(products_array[1][15:8]),
        .in2(products_array[2][15:8]),
        .in3(products_array[3][15:8]),
        .in4(products_array[4][15:8]),
        .in5(products_array[5][15:8]),
        .in6(products_array[6][15:8]),
        .in7(products_array[7][15:8]),
        .sum(final_sum[55:48])
    );

    AdderTree adder_tree_7 (
        .in0(products_array[8][15:8]),
        .in1(products_array[9][15:8]),
        .in2(products_array[10][15:8]),
        .in3(products_array[11][15:8]),
        .in4(products_array[12][15:8]),
        .in5(products_array[13][15:8]),
        .in6(products_array[14][15:8]),
        .in7(products_array[15][15:8]),
        .sum(final_sum[63:56])
    );

    AdderTree adder_tree_8 (
        .in0(products_array[0][7:0]),
        .in1(products_array[1][7:0]),
        .in2(products_array[2][7:0]),
        .in3(products_array[3][7:0]),
        .in4(products_array[4][7:0]),
        .in5(products_array[5][7:0]),
        .in6(products_array[6][7:0]),
        .in7(products_array[7][7:0]),
        .sum(final_sum[71:64])
    );

    AdderTree adder_tree_9 (
        .in0(products_array[8][7:0]),
        .in1(products_array[9][7:0]),
        .in2(products_array[10][7:0]),
        .in3(products_array[11][7:0]),
        .in4(products_array[12][7:0]),
        .in5(products_array[13][7:0]),
        .in6(products_array[14][7:0]),
        .in7(products_array[15][7:0]),
        .sum(final_sum[79:72])
    );

    AdderTree adder_tree_10 (
        .in0(products_array[0][15:8]),
        .in1(products_array[1][15:8]),
        .in2(products_array[2][15:8]),
        .in3(products_array[3][15:8]),
        .in4(products_array[4][15:8]),
        .in5(products_array[5][15:8]),
        .in6(products_array[6][15:8]),
        .in7(products_array[7][15:8]),
        .sum(final_sum[87:80])
    );

    AdderTree adder_tree_11 (
        .in0(products_array[8][15:8]),
        .in1(products_array[9][15:8]),
        .in2(products_array[10][15:8]),
        .in3(products_array[11][15:8]),
        .in4(products_array[12][15:8]),
        .in5(products_array[13][15:8]),
        .in6(products_array[14][15:8]),
        .in7(products_array[15][15:8]),
        .sum(final_sum[95:88])
    );

    AdderTree adder_tree_12 (
        .in0(products_array[0][7:0]),
        .in1(products_array[1][7:0]),
        .in2(products_array[2][7:0]),
        .in3(products_array[3][7:0]),
        .in4(products_array[4][7:0]),
        .in5(products_array[5][7:0]),
        .in6(products_array[6][7:0]),
        .in7(products_array[7][7:0]),
        .sum(final_sum[103:96])
    );

    AdderTree adder_tree_13 (
        .in0(products_array[8][7:0]),
        .in1(products_array[9][7:0]),
        .in2(products_array[10][7:0]),
        .in3(products_array[11][7:0]),
        .in4(products_array[12][7:0]),
        .in5(products_array[13][7:0]),
        .in6(products_array[14][7:0]),
        .in7(products_array[15][7:0]),
        .sum(final_sum[111:104])
    );

    AdderTree adder_tree_14 (
        .in0(products_array[0][15:8]),
        .in1(products_array[1][15:8]),
        .in2(products_array[2][15:8]),
        .in3(products_array[3][15:8]),
        .in4(products_array[4][15:8]),
        .in5(products_array[5][15:8]),
        .in6(products_array[6][15:8]),
        .in7(products_array[7][15:8]),
        .sum(final_sum[119:112])
    );

    AdderTree adder_tree_15 (
        .in0(products_array[8][15:8]),
        .in1(products_array[9][15:8]),
        .in2(products_array[10][15:8]),
        .in3(products_array[11][15:8]),
        .in4(products_array[12][15:8]),
        .in5(products_array[13][15:8]),
        .in6(products_array[14][15:8]),
        .in7(products_array[15][15:8]),
        .sum(final_sum[127:120])
    );

endmodule

module WeightBuffer(
    input wire clk,
    input wire reset,
    input wire [7:0] weight_data,
    input wire write_enable,
    input wire [3:0] write_addr,
    output wire [127:0] weight_out  // Flattened array for weight data (16 x 8-bit)
);
    reg [7:0] weights [15:0];
    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 16; i = i + 1) begin
                weights[i] <= 8'b0;
            end
        end else if (write_enable) begin
            weights[write_addr] <= weight_data;
        end
    end

    // Flatten the output array
    assign weight_out = {weights[0], weights[1], weights[2], weights[3],
                         weights[4], weights[5], weights[6], weights[7],
                         weights[8], weights[9], weights[10], weights[11],
                         weights[12], weights[13], weights[14], weights[15]};
endmodule

module LineBuffer(
    input wire clk,
    input wire reset,
    input wire [7:0] data_in,
    input wire write_enable,
    input wire [3:0] write_addr,
    input wire [3:0] read_addr,
    output wire [127:0] data_out  // Flattened array for line data (16 x 8-bit)
);
    reg [7:0] line_data [15:0];
    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 16; i = i + 1) begin
                line_data[i] <= 8'b0;
            end
        end else if (write_enable) begin
            line_data[write_addr] <= data_in;
        end
    end
    
    // Flatten the output array
    assign data_out = {line_data[0], line_data[1], line_data[2], line_data[3],
                       line_data[4], line_data[5], line_data[6], line_data[7],
                       line_data[8], line_data[9], line_data[10], line_data[11],
                       line_data[12], line_data[13], line_data[14], line_data[15]};
endmodule

module MAC(
    input wire [7:0] a,
    input wire [7:0] b,
    output wire [15:0] product
);
    assign product = a * b;
endmodule

module MACArray(
    input wire [127:0] line_data,  // Flattened array for line data (16 x 8-bit)
    input wire [127:0] weight_data,  // Flattened array for weight data (16 x 8-bit)
    output wire [255:0] products  // Flattened array for products (16 x 16-bit)
);
    wire [7:0] line_data_array [15:0];
    wire [7:0] weight_data_array [15:0];
    wire [15:0] products_array [15:0];

    // Unflatten the input arrays
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : input_unflatten
            assign line_data_array[i] = line_data[i*8 +: 8];
            assign weight_data_array[i] = weight_data[i*8 +: 8];
        end
    endgenerate

    // Instantiate the MAC units
    generate
        for (i = 0; i < 16; i = i + 1) begin : mac
            MAC mac_unit (
                .a(line_data_array[i]),
                .b(weight_data_array[i]),
                .product(products_array[i])
            );
        end
    endgenerate

    // Flatten the output array
    generate
        for (i = 0; i < 16; i = i + 1) begin : output_flatten
            assign products[i*16 +: 16] = products_array[i];
        end
    endgenerate
endmodule