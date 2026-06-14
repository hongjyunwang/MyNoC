package noc_pkg;
  // Top-level parameters
  parameter int FLIT_WIDTH = 64; // 64 bits
  parameter int MESH_DIM_X = 4; // mesh X dimension
  parameter int MESH_DIM_Y = 4; // mesh Y dimension
  parameter int NUM_VC = 2;
  parameter int PACKET_ID_W = 4; // 16 outstanding packets max

  // Derived parameters
  // bits needed to represent quantities
  parameter int X_COORD_W = $clog2(MESH_DIM_X);
  parameter int Y_COORD_W = $clog2(MESH_DIM_Y);
  parameter int VC_ID_W = $clog2(NUM_VC);

  // Flit type encoding
  typedef enum logic [1:0] {
    HEAD = 2'b00,
    BODY = 2'b01,
    TAIL = 2'b10,
    HEDA_TAIL = 2'b11,
  } flit_type_t;

  // Head flit structure
  typedef struct packed {
    flit_type_t flit_type; // [63:62]
    logic [X_COORD_W-1:0] dst_x; // dest x
    logic [Y_COORD_W-1:0] dst_y; // dest y
    logic [X_COORD_W-1:0] src_x; // src x
    logic [Y_COORD_W-1:0] src_y; //src y
    logic [VC_ID_W-1:0] vc_id; // virtual channel
    logic [PACKET_ID_W-1:0] pkt_id; // transaction ID
    logic [...] payload; // remaining bits
  } head_flit_t;

  // Body/tail flit structure
  typedef struct packed {
    flit_type_t flit_type;
    logic [VC_ID_W-1:0] vc_id;
    logic [...] payload;
  } data_flit_t;

  // Generic flit
  typedef logic [FLIT_WIDTH-1:0] flit_t;

endpackage