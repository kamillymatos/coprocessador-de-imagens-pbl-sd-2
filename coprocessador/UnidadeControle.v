module UnidadeControle(
    input  wire        clk_50,
    input  wire        reset,
    input  wire        start,
    input  wire [1:0]  SW,
    input  wire [1:0]  zoom_select,
	 input  wire [7:0]  dados_pixel_hps,
	 input              SolicitaEscrita,
	 input  wire [14:0] addr_in_hps,
    output wire [1:0]  opcao_Redmn,
    output reg         ready,

    // Saída VGA
    output wire        hsync,
    output wire        vsync,
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        sync,
    output wire        clk,
    output wire        blank,
	 output wire   done_redim,
	 output reg   done_write
);

    // ---------------------------------------------------------------------
    // Parâmetros
    // ---------------------------------------------------------------------
    localparam integer ALTURA_ORIGINAL  = 120;
    localparam integer LARGURA_ORIGINAL = 160;
    localparam integer MAX_LARGURA = 320;  // Limite para Zoom IN
    localparam integer MAX_ALTURA = 240;   // Limite para Zoom IN

    // ---------------------------------------------------------------------
    // Clock
    // ---------------------------------------------------------------------
    wire clock_25;
    divisor_clock divisor_inst (
        .clk_50(clk_50),
        .reset(!reset),
        .clk_25(clock_25)
    );
	 
	 wire clk_100;
		clk_100_0002 clk_100_inst (
		.refclk   (clk_50),   //  refclk.clk
		.rst      (!reset),      //   reset.reset
		.outclk_0 (clk_100), // outclk0.clk
		.locked   ()    //  locked.export
	);

    // ---------------------------------------------------------------------
    // Estados e seleção
    // ---------------------------------------------------------------------
    localparam INICIO  = 2'b00;
    localparam EXECUTE = 2'b01;
    localparam CHECK   = 2'b10;

    localparam REPLICACAO      = 2'b00;
    localparam DECIMACAO       = 2'b01;
    localparam VIZINHO_PROXIMO = 2'b10;
    localparam MEDIA_BLOCOS    = 2'b11;

    reg [1:0] estado, prox_estado;
    reg [1:0] Tipo_redmn;
    assign opcao_Redmn = Tipo_redmn;

    reg operacao_ativa;

    // ---------------------------------------------------------------------
    // Memórias
    // ---------------------------------------------------------------------
	 
    wire [14:0] rom_addr_top;
    wire [7:0] rom_pixel;

	 reg [1:0] count;

	   // ---------------------------------------------------------------------
		// Lógica de escrita na RAM da imagem original
		// ---------------------------------------------------------------------
				
		localparam IDLE_WRITE = 2'b00;
		localparam WRITE      = 2'b01;
		localparam WAIT_WRITE = 2'b10;

		reg [1:0] state_write, next_state_write;
		reg wren_ram1;
		reg [7:0] dados_RAM;
		reg [14:0] addr_hps;

		// Registrador de estado (síncrono)
		always @(posedge clk_100 or negedge reset) begin
			 if (!reset)
				  state_write <= IDLE_WRITE;
			 else
				  state_write <= next_state_write;
		end

		// Lógica combinacional para próximo estado
		always @(*) begin
			 next_state_write = state_write;
			 
			 case (state_write)
				  IDLE_WRITE: begin
						if (SolicitaEscrita)
							 next_state_write = WRITE;
				  end
				  
				  WRITE: begin
						next_state_write = WAIT_WRITE;
				  end
				  
				  WAIT_WRITE: begin
						next_state_write = IDLE_WRITE;
				  end
				  
				  default: next_state_write = IDLE_WRITE;
			 endcase
		end

		// Lógica de saída (síncrona)
		always @(posedge clk_100 or negedge reset) begin
			 if (!reset) begin
				  wren_ram1 <= 1'b0;
				  done_write <= 1'b0;
				  dados_RAM <= 8'b0;
				  addr_hps <= 15'b0;
			 end else begin
				  case (state_write)
						IDLE_WRITE: begin
							 wren_ram1 <= 1'b0;
							 done_write <= 1'b0;
						end
						
						WRITE: begin
							 dados_RAM <= dados_pixel_hps;
							 addr_hps <= addr_in_hps;
							 wren_ram1 <= 1'b1;
							 done_write <= 1'b0;
						end
						
						WAIT_WRITE: begin
							 wren_ram1 <= 1'b0;  // Desliga wren
							 done_write <= 1'b1;  // Sinaliza pronto
						end
						
						default: begin
							 wren_ram1 <= 1'b0;
							 done_write <= 1'b0;
						end
				  endcase
			 end
		end

								
	 mem1 memory1(
        .rdaddress(rom_addr_top), 
        .wraddress(addr_hps), 
        .clock(clk_100), 
        .data(dados_RAM), 
        .wren(wren_ram1), 
        .q(rom_pixel)
    );						
	
    wire [18:0] EnderecoRAM;
    wire [7:0] ram_data_in;
	 wire wren_ram;
    wire [7:0] saida_RAM;

    mem2  memory2 (
        .address (EnderecoRAM),
        .clock   (clk_100),
        .data    (ram_data_in),
        .wren    (wren_ram),
        .q       (saida_RAM)
    );

    // ---------------------------------------------------------------------
    // CONTROLADOR COM CORTE
    // ---------------------------------------------------------------------
    wire [14:0] rom_addr_redim;
    wire [18:0] ram_addr_redim;
    wire [7:0] pixel_out_redim;
    wire wren_redim;

    ControladorRedimensionamento #(
        .LARGURA_ORIG(LARGURA_ORIGINAL),
        .ALTURA_ORIG(ALTURA_ORIGINAL),
        .MAX_LARGURA(MAX_LARGURA),
        .MAX_ALTURA(MAX_ALTURA)
    ) controlador_redim (
        .clk(clock_25),
        .rst(!reset),
        .start(start),
        .algoritmo(SW),
        .zoom_select(zoom_select),
        .pixel_in(rom_pixel),
        .rom_addr(rom_addr_redim),
        .ram_addr(ram_addr_redim),
        .pixel_out(pixel_out_redim),
        .wren(wren_redim),
        .done(done_redim)
    );

    // ---------------------------------------------------------------------
    // Endereço ROM para imagem original (idle)
    // ---------------------------------------------------------------------
    wire [14:0] rom_addr_original;
    assign rom_addr_original = (next_y - y_offset) * LARGURA_ORIGINAL + (next_x - x_offset);

   // Multiplexação de endereços para RAM de uma porta
	assign rom_addr_top = (operacao_ativa)   ? rom_addr_redim :    // Prioridade 2: Redimensionamento
                                              rom_addr_original;   // Prioridade 3: Exibição original
    // ---------------------------------------------------------------------
    // Cálculo de Dimensões COM CORTE
    // ---------------------------------------------------------------------
    wire [3:0] BLOCK_SIZE_val = (zoom_select == 2'b00) ? 4'd1 :
                                (zoom_select == 2'b01) ? 4'd2 :
                                (zoom_select == 2'b10) ? 4'd4 :
                                (zoom_select == 2'b11) ? 4'd8 : 4'd1;

    reg [9:0] IMG_W, IMG_H;
    reg [9:0] x_offset, y_offset;
	 reg [10:0] largura_ampliada;
	 reg [10:0] altura_ampliada;

    always @(posedge clock_25 or negedge reset) begin
        if (!reset) begin
            IMG_W <= LARGURA_ORIGINAL;
            IMG_H <= ALTURA_ORIGINAL;
            x_offset <= 10'd0;
            y_offset <= 10'd0;
        end else begin
            // ========================================
            // ZOOM IN com limite de 320×240
            // ========================================
            if ((SW == REPLICACAO || SW == VIZINHO_PROXIMO) && start) begin
                // Calcula dimensões ampliadas
                largura_ampliada <= LARGURA_ORIGINAL * BLOCK_SIZE_val;
                altura_ampliada <= ALTURA_ORIGINAL * BLOCK_SIZE_val;
                
                // Aplica limite (corte em 320×240)
                if (largura_ampliada > MAX_LARGURA)
                    IMG_W <= MAX_LARGURA;
                else
                    IMG_W <= largura_ampliada[9:0];
                    
                if (altura_ampliada > MAX_ALTURA)
                    IMG_H <= MAX_ALTURA;
                else
                    IMG_H <= altura_ampliada[9:0];
            end 
            // ========================================
            // ZOOM OUT (sem limite, sempre cabe)
            // ========================================
            else if ((SW == DECIMACAO || SW == MEDIA_BLOCOS) && start) begin
                IMG_W <= LARGURA_ORIGINAL / BLOCK_SIZE_val;
                IMG_H <= ALTURA_ORIGINAL / BLOCK_SIZE_val;
            end
            
            // Centraliza na tela 640×480
            x_offset <= (640 - IMG_W) / 2;
            y_offset <= (480 - IMG_H) / 2;
        end
    end

    // ---------------------------------------------------------------------
    // Controle de exibição
    // ---------------------------------------------------------------------
    reg exibe_imagem;
    always @(posedge clock_25 or negedge reset) begin
        if (!reset) 
            exibe_imagem <= 1'b0;
        else if (start) 
            exibe_imagem <= 1'b0;
        else if (done_redim)
            exibe_imagem <= 1'b1;
    end

    // Para VGA
    wire [9:0] next_x, next_y;
    wire in_image_bounds = (next_x >= x_offset) && (next_x < (x_offset + IMG_W)) &&
                           (next_y >= y_offset) && (next_y < (y_offset + IMG_H));

    // Endereço RAM para VGA
    wire [18:0] ram_addr_vga;
    assign ram_addr_vga = (next_y - y_offset) * IMG_W + (next_x - x_offset);

    // Multiplexação RAM
    assign EnderecoRAM = (exibe_imagem) ? ram_addr_vga : ram_addr_redim;
    assign ram_data_in = (exibe_imagem) ? 8'd0 : pixel_out_redim;
    assign wren_ram = (exibe_imagem) ? 1'b0 : wren_redim;

    wire idle = (!operacao_ativa && !exibe_imagem);

    // ---------------------------------------------------------------------
    // Máquina de Estados
    // ---------------------------------------------------------------------
    always @(posedge clock_25 or negedge reset) begin
        if (!reset) begin
            estado <= INICIO;
            prox_estado <= INICIO;
            Tipo_redmn <= REPLICACAO;
            operacao_ativa <= 1'b0;
            ready <= 1'b0;
        end else begin
            estado <= prox_estado;
            
            case (estado)
                INICIO: begin
                    ready <= 1'b0;
                    prox_estado <= INICIO;
                    if (start && !operacao_ativa) begin
                        operacao_ativa <= 1'b1;
                        Tipo_redmn <= SW;
                        prox_estado <= EXECUTE;
                    end
                end
                
                EXECUTE: begin
                    prox_estado <= CHECK;
                end
                
                CHECK: begin
                    if (done_redim) begin
                        operacao_ativa <= 1'b0;
                        ready <= 1'b1;
                        prox_estado <= INICIO;
                    end else 
                        prox_estado <= CHECK;
                end
                
                default: prox_estado <= INICIO;
            endcase
        end
    end

    // ---------------------------------------------------------------------
    // Saída VGA
    // ---------------------------------------------------------------------
    wire [7:0] out_vga;
    
    assign out_vga = (idle && in_image_bounds) ? rom_pixel :
                     (exibe_imagem && in_image_bounds) ? saida_RAM : 8'h00;

    vga_driver draw (
        .clock(clock_25),
        .reset(!reset),
        .color_in(out_vga),
        .next_x(next_x),
        .next_y(next_y),
        .hsync(hsync),
        .vsync(vsync),
        .red(vga_r),
        .green(vga_g),
        .blue(vga_b),
        .sync(sync),
        .clk(clk),
        .blank(blank)
    );

endmodule