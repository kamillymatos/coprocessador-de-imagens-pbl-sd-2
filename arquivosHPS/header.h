#ifndef HEADER_H
#define HEADER_H

// Offsets dos registradores PIO
#define PIO_INSTRUCTION 0x00
#define PIO_DONE        0x20
#define PIO_START       0x30
#define PIO_DONE_WRITE  0x40


// Constantes de Controle e Status
#define VRAM_MAX_ADDR   19200       // Endereço máximo da VRAM (0x4B00)
#define FLAG_DONE_MASK  0x01        // Máscara para o bit 'DONE'
#define TIMEOUT_NHI     60000000    // Timeout para operações

// Opcodes (2 bits)
#define OPCODE_REPLICACAO 0x00      // 2'b00
#define OPCODE_DECIMACAO  0x01      // 2'b01
#define OPCODE_NHI        0x02      // 2'b10
#define OPCODE_MEDIA      0x03      // 2'b11


/**
 * @brief Inicializa a API, abrindo /dev/mem e mapeando o endereço base do FPGA na memória.
 * @return 0 em caso de sucesso, -1 em caso de erro.
 */
int iniciarAPI();

/**
 * @brief Finaliza a API, desmapeando a memória e fechando o descritor de arquivo.
 * @return 0 em caso de sucesso, -1 em caso de erro de munmap.
 */
int encerrarAPI();


void write_pixel(int address, unsigned char pixel_data);


/**
 * @brief Executa interpolação por Vizinho Mais Próximo (Nearest Neighbor).
 * @param zoom Fator de zoom: 0=1x, 1=2x, 2=4x, 3=8x
 * @return 0 em sucesso, -2 em caso de timeout
 */
int NHI(int zoom);

/**
 * @brief Executa replicação de pixels.
 * @param zoom Fator de zoom: 0=1x, 1=2x, 2=4x, 3=8x
 * @return 0 em sucesso, -2 em caso de timeout
 */
int replicacao(int zoom);

/**
 * @brief Executa decimação de pixels.
 * @param zoom Fator de zoom: 0=1x, 1=2x, 2=4x, 3=8x
 * @return 0 em sucesso, -2 em caso de timeout
 */
int decimacao(int zoom);

/**
 * @brief Executa média de blocos.
 * @param zoom Fator de zoom: 0=1x, 1=2x, 2=4x, 3=8x
 * @return 0 em sucesso, -2 em caso de timeout
 */
int media_blocos(int zoom);

/**
 * @brief Verifica o status do flag DONE do hardware.
 * @return 1 se DONE está ativo (hardware pronto), 0 caso contrário
 */
int Flag_Done();



#endif