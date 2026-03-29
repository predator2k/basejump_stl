  // -------------------------------------------------------
  // SRAM Test Core (included into each testbench)
  // Expects: DEPTH, WIDTH, ADDR_W, HAS_BW parameters
  //          clk, cen, rdwen, a, d, bw, q signals
  // -------------------------------------------------------

  localparam NUM_TEST_ENTRIES = (DEPTH > 512) ? 256 : DEPTH;
  localparam LFSR_SEED = 64'hA5A5_DEAD_BEEF_CAFE;

  // Clock generation
  initial clk = 0;
  always #5 clk = ~clk;

  // LFSR for random data
  logic [63:0] lfsr;
  wire lfsr_fb = lfsr[63] ^ lfsr[62] ^ lfsr[60] ^ lfsr[59];

  task automatic lfsr_next();
    lfsr = {lfsr[62:0], lfsr_fb};
  endtask

  // Generate WIDTH-bit data from current LFSR state
  function automatic [WIDTH-1:0] gen_data(input [63:0] seed);
    logic [WIDTH-1:0] result;
    logic [63:0] s;
    s = seed;
    for (int i = 0; i < WIDTH; i++) begin
      result[i] = s[i % 64];
      if ((i % 64) == 63)
        s = {s[62:0], s[63] ^ s[62] ^ s[60] ^ s[59]};
    end
    return result;
  endfunction

  // Shadow memory
  logic [WIDTH-1:0] shadow [NUM_TEST_ENTRIES];

  // Counters
  integer error_cnt;
  integer test_num;

  // Write one word
  task automatic sram_write(input [ADDR_W-1:0] addr, input [WIDTH-1:0] data, input [WIDTH-1:0] mask);
    @(posedge clk);
    cen   <= 1'b0;
    rdwen <= 1'b0;
    a     <= addr;
    d     <= data;
    if (HAS_BW) bw <= mask;
    @(posedge clk);
    cen   <= 1'b1;
    rdwen <= 1'b1;
  endtask

  // Read one word (1-cycle latency: present addr at posedge N, data valid after posedge N+1)
  task automatic sram_read(input [ADDR_W-1:0] addr, output [WIDTH-1:0] data);
    @(posedge clk);
    cen   <= 1'b0;
    rdwen <= 1'b1;
    a     <= addr;
    d     <= '0;
    if (HAS_BW) bw <= '0;
    @(posedge clk);
    cen   <= 1'b1;
    #1;  // wait past NBA region for Q to update
    data = q;
  endtask

  // Address generation: scatter across address space
  function automatic [ADDR_W-1:0] test_addr(input integer idx);
    if (DEPTH <= 512)
      return idx[ADDR_W-1:0];
    else begin
      // Spread across address space using golden ratio hash
      logic [31:0] h;
      h = idx * 32'h9E3779B9;
      return h[ADDR_W-1:0] % DEPTH;
    end
  endfunction

  // -------------------------------------------------------
  // Main test sequence
  // -------------------------------------------------------
  initial begin
    error_cnt = 0;
    test_num  = 0;
    lfsr      = LFSR_SEED;
    cen       = 1'b1;
    rdwen     = 1'b1;
    a         = '0;
    d         = '0;
    if (HAS_BW) bw = '0;

    // Wait for reset
    repeat (10) @(posedge clk);

    // =============================================
    // Test 1: Full-word write then read-back
    // =============================================
    test_num = 1;
    $display("[TEST 1] Full-word write/read: %0d entries", NUM_TEST_ENTRIES);

    lfsr = LFSR_SEED;
    for (int i = 0; i < NUM_TEST_ENTRIES; i++) begin
      logic [WIDTH-1:0] wdata;
      wdata = gen_data(lfsr);
      shadow[i] = wdata;
      sram_write(test_addr(i), wdata, {WIDTH{1'b1}});
      lfsr_next();
    end

    // Idle gap
    repeat (5) @(posedge clk);

    // Read back and compare
    for (int i = 0; i < NUM_TEST_ENTRIES; i++) begin
      logic [WIDTH-1:0] rdata;
      sram_read(test_addr(i), rdata);
      if (rdata !== shadow[i]) begin
        $error("[FAIL] Test1 addr=%0h: got=%0h exp=%0h", test_addr(i), rdata, shadow[i]);
        error_cnt++;
        if (error_cnt > 20) begin
          $display("[ABORT] Too many errors, stopping");
          $finish;
        end
      end
    end

    $display("[TEST 1] %s (%0d errors)",
      (error_cnt == 0) ? "PASS" : "FAIL", error_cnt);

    // =============================================
    // Test 2: Masked write (bit-write) -- only for HAS_BW
    // =============================================
    if (HAS_BW) begin
      integer mask_errors;
      mask_errors = 0;
      test_num = 2;
      $display("[TEST 2] Masked write: %0d entries", (NUM_TEST_ENTRIES > 64) ? 64 : NUM_TEST_ENTRIES);

      // First write known pattern (all 1s)
      for (int i = 0; i < ((NUM_TEST_ENTRIES > 64) ? 64 : NUM_TEST_ENTRIES); i++) begin
        sram_write(test_addr(i), {WIDTH{1'b1}}, {WIDTH{1'b1}});
        shadow[i] = {WIDTH{1'b1}};
      end

      repeat (5) @(posedge clk);

      // Now write with partial mask (alternating bits)
      lfsr = 64'hCAFE_BABE_1234_5678;
      for (int i = 0; i < ((NUM_TEST_ENTRIES > 64) ? 64 : NUM_TEST_ENTRIES); i++) begin
        logic [WIDTH-1:0] wdata, mask;
        wdata = gen_data(lfsr);
        // Alternate mask patterns
        if (i % 4 == 0) mask = {{(WIDTH/2){1'b1}}, {(WIDTH/2){1'b0}}};  // upper half
        else if (i % 4 == 1) mask = {{(WIDTH/2){1'b0}}, {(WIDTH/2){1'b1}}};  // lower half
        else if (i % 4 == 2) mask = {WIDTH{1'b0}};  // no write
        else mask = {WIDTH{1'b1}};  // full write

        // Apply mask to shadow: new = (mask & wdata) | (~mask & old)
        shadow[i] = (mask & wdata) | (~mask & shadow[i]);
        sram_write(test_addr(i), wdata, mask);
        lfsr_next();
      end

      repeat (5) @(posedge clk);

      // Verify
      for (int i = 0; i < ((NUM_TEST_ENTRIES > 64) ? 64 : NUM_TEST_ENTRIES); i++) begin
        logic [WIDTH-1:0] rdata;
        sram_read(test_addr(i), rdata);
        if (rdata !== shadow[i]) begin
          $error("[FAIL] Test2 addr=%0h: got=%0h exp=%0h", test_addr(i), rdata, shadow[i]);
          mask_errors++;
          error_cnt++;
        end
      end

      $display("[TEST 2] %s (%0d errors)",
        (mask_errors == 0) ? "PASS" : "FAIL", mask_errors);
    end

    // =============================================
    // Test 3: Back-to-back write then immediate read
    // =============================================
    begin
      integer bb_errors;
      bb_errors = 0;
      test_num = 3;
      $display("[TEST 3] Back-to-back write-read: 32 entries");

      lfsr = 64'hDEAD_FACE_0000_0001;
      for (int i = 0; i < 32; i++) begin
        logic [WIDTH-1:0] wdata, rdata;
        logic [ADDR_W-1:0] addr;
        wdata = gen_data(lfsr);
        addr = test_addr(i);
        sram_write(addr, wdata, {WIDTH{1'b1}});
        sram_read(addr, rdata);
        if (rdata !== wdata) begin
          $error("[FAIL] Test3 addr=%0h: got=%0h exp=%0h", addr, rdata, wdata);
          bb_errors++;
          error_cnt++;
        end
        lfsr_next();
      end

      $display("[TEST 3] %s (%0d errors)",
        (bb_errors == 0) ? "PASS" : "FAIL", bb_errors);
    end

    // =============================================
    // Summary
    // =============================================
    repeat (5) @(posedge clk);
    if (error_cnt == 0)
      $display("[RESULT] ALL TESTS PASSED");
    else
      $display("[RESULT] FAILED: %0d total errors", error_cnt);
    $finish;
  end

  // Timeout watchdog
  initial begin
    #(NUM_TEST_ENTRIES * 200 + 100000);
    $display("[TIMEOUT] Test did not complete in time");
    $finish;
  end
