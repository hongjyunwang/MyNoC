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
    HEAD_TAIL = 2'b11
  } flit_type_t;

  parameter int HEAD_META_W = 2 + X_COORD_W + Y_COORD_W + X_COORD_W + Y_COORD_W + VC_ID_W + PACKET_ID_W;
  parameter int HEAD_PAYLOAD_W = FLIT_WIDTH - HEAD_META_W;
  parameter int DATA_META_W = 2 + VC_ID_W;
  parameter int DATA_PAYLOAD_W = FLIT_WIDTH - DATA_META_W;

  // Head flit structure
  typedef struct packed {
    flit_type_t flit_type; // [63:62]
    logic [X_COORD_W-1:0] dst_x; // dest x
    logic [Y_COORD_W-1:0] dst_y; // dest y
    logic [X_COORD_W-1:0] src_x; // src x
    logic [Y_COORD_W-1:0] src_y; //src y
    logic [VC_ID_W-1:0] vc_id; // virtual channel
    logic [PACKET_ID_W-1:0] pkt_id; // transaction ID
    logic [HEAD_PAYLOAD_W-1:0] payload; // remaining bits
  } head_flit_t;

  // Body/tail flit structure
  typedef struct packed {
    flit_type_t flit_type;
    logic [VC_ID_W-1:0] vc_id;
    logic [DATA_PAYLOAD_W-1:0] payload;
  } data_flit_t;

  // Generic flit
  typedef logic [FLIT_WIDTH-1:0] flit_t;

endpackage
