module Adder_16bit (
    input  wire [15:0] a, b,
    input  wire        cin,
    output wire [15:0] sum,
    output wire        cout
);
    wire [15:0] g, p;
    wire [16:0] c;  // c[0] = cin, c[16] = cout
    
    assign c[0] = cin;
    
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : cla_gen
            assign g[i] = a[i] & b[i];      // Generate
            assign p[i] = a[i] ^ b[i];      // Propagate
            assign c[i+1] = g[i] | (p[i] & c[i]);
            assign sum[i] = p[i] ^ c[i];
        end
    endgenerate
    
    assign cout = c[16];
endmodule