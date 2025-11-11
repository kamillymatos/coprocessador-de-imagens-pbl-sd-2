#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include "header.h"
#include <unistd.h>
#include "hps_0.h"
#include <sys/mman.h>
#include <stdlib.h>
#include <stdint.h>


extern int iniciarAPI();
extern int encerrarAPI();
extern int NHI(int zoom);
extern int replicacao(int zoom);
extern int decimacao(int zoom);
extern int media_blocos(int zoom);
extern int Flag_Done();
extern void write_pixel(int address, unsigned char pixel_data);


// Estrutura do cabeçalho BMP
#pragma pack(push, 1)
typedef struct {
    uint16_t type;
    uint32_t size;
    uint16_t reserved1;
    uint16_t reserved2;
    uint32_t offset;
} BMPHeader;

typedef struct {
    uint32_t size;
    int32_t width;
    int32_t height;
    uint16_t planes;
    uint16_t bits_per_pixel;
    uint32_t compression;
    uint32_t image_size;
    int32_t x_pixels_per_meter;
    int32_t y_pixels_per_meter;
    uint32_t colors_used;
    uint32_t colors_important;
} BMPInfoHeader;
#pragma pack(pop)


// Função para carregar e enviar imagem BMP
int enviar_imagem_bmp(const char *filename) {
    FILE *file = fopen(filename, "rb");
    if (!file) {
        printf("ERRO: Não foi possível abrir o arquivo '%s'\n", filename);
        return -1;
    }

    // Ler cabeçalhos
    BMPHeader header;
    BMPInfoHeader info;
    
    fread(&header, sizeof(BMPHeader), 1, file);
    fread(&info, sizeof(BMPInfoHeader), 1, file);

    // Verificar se é BMP válido
    if (header.type != 0x4D42) {
        printf("ERRO: Arquivo não é um BMP válido!\n");
        fclose(file);
        return -1;
    }

    printf("Dimensões: %dx%d pixels\n", info.width, info.height);
    printf("Bits por pixel: %d\n", info.bits_per_pixel);

    // Verificar dimensões esperadas (160x120 = 19200 pixels)
    if (info.width != 160 || info.height != 120) {
        printf("AVISO: Imagem com dimensões diferentes de 160x120!\n");
    }

    // Mover para início dos dados de pixel
    fseek(file, header.offset, SEEK_SET);

    // Calcular padding (linhas BMP são alinhadas a 4 bytes)
    int bytes_per_pixel = info.bits_per_pixel / 8;
    int row_size = info.width * bytes_per_pixel;
    int padding = (4 - (row_size % 4)) % 4;

    printf("\nEnviando imagem...\n");

    // Buffer para uma linha
    unsigned char *row_buffer = (unsigned char*)malloc(row_size);
    if (!row_buffer) {
        printf("ERRO: Falha ao alocar memória!\n");
        fclose(file);
        return -1;
    }

    int total_pixels = info.width * info.height;
    int pixel_count = 0;

    // BMP armazena de baixo para cima, então invertemos
    for(int y = info.height - 1; y >= 0; y--) {
        // Ler linha
        fseek(file, header.offset + y * (row_size + padding), SEEK_SET);
        fread(row_buffer, 1, row_size, file);

        // Enviar pixels da linha
        for(int x = 0; x < info.width; x++) {
            unsigned char pixel_data;
            
            if (info.bits_per_pixel == 8) {
                // Grayscale 8 bits
                pixel_data = row_buffer[x];
            } 
            else if (info.bits_per_pixel == 24) {
                // BGR para grayscale (média simples)
                int idx = x * 3;
                unsigned char b = row_buffer[idx];
                unsigned char g = row_buffer[idx + 1];
                unsigned char r = row_buffer[idx + 2];
                pixel_data = (r + g + b) / 3;
            }
            else {
                printf("ERRO: Formato de pixel não suportado (%d bits)\n", info.bits_per_pixel);
                free(row_buffer);
                fclose(file);
                return -1;
            }

            // Endereço linear do pixel
            int address = (info.height - 1 - y) * info.width + x;
            
            // ✅ Chama write_pixel assembly (r0=address, r1=pixel_data)
            write_pixel(address, pixel_data);

            pixel_count++;
            
            // Atualizar progresso
            if(pixel_count % 500 == 0) {
                float progresso = (pixel_count * 100.0) / total_pixels;
                printf("\rProgresso: %d/%d pixels (%.1f%%)    ", 
                       pixel_count, total_pixels, progresso);
                fflush(stdout);
            }
        }
    }

    printf("\rProgresso: %d/%d pixels (100.0%%)    \n", total_pixels, total_pixels);
    printf("Imagem enviada com sucesso!\n");

    free(row_buffer);
    fclose(file);
    return 0;
}

int main() {
    int opcao, zoom_escolha, zoom_real, resultado;
    
    printf("\n=== INICIANDO API ===\n");
    printf("DEBUG: Tentando abrir /dev/mem...\n");
    
    int init_result = iniciarAPI();
    printf("DEBUG: iniciarAPI() retornou: %d\n", init_result);
    
    if (init_result != 0) {
        printf("ERRO ao iniciar API!\n");
        printf("DICA: Execute como root (sudo ./programa)\n");
        return 1;
    }
    
    printf("API OK!\n");
    
    // Verificação inicial do DONE
    int done_inicial = Flag_Done();
    printf("DEBUG: Status inicial DONE = %d\n", done_inicial);
    
    if (done_inicial == 0) {
        printf("AVISO: Hardware inicia com DONE=0.\n");
        printf("       Isso pode indicar problema no Verilog.\n");
        printf("       Continuando mesmo assim...\n");
    }
    
    printf("\n");
    
    do {
        printf("\n--- MENU DE TESTES ---\n");
        printf("1. Vizinho Proximo (NHI)\n");
        printf("2. Replicacao\n");
        printf("3. Decimacao\n");
        printf("4. Media Blocos\n");
        printf("5. Verificar Status (Flag Done)\n");
        printf("6. Enviar imagem BMP\n");
        printf("7. Sair\n");
        printf("Opcao: ");
        
        if (scanf("%d", &opcao) != 1) {
            printf("Entrada invalida!\n");
            while(getchar() != '\n'); // Limpa buffer
            continue;
        }
        
        switch (opcao) {
            case 1:
            case 2:
            case 3:
            case 4:
                printf("\nEscolha o zoom:\n");
                printf("(1) 1x  - Sem zoom\n");
                printf("(2) 2x  - Zoom 2x\n");
                printf("(3) 4x  - Zoom 4x\n");
                printf("(4) 8x  - Zoom 8x\n");
                printf("Opcao: ");
                
                if (scanf("%d", &zoom_escolha) != 1) {
                    printf("Entrada invalida!\n");
                    while(getchar() != '\n');
                    break;
                }
                
                // Converter escolha do usuário (1-4) para valor assembly (0-3)
                zoom_real = zoom_escolha - 1;
                
                if (zoom_real < 0 || zoom_real > 3) {
                    printf("ERRO: Zoom invalido! Use valores de 1 a 4.\n");
                    break;
                }
                
                // Verifica status do hardware (rápido)
                int done_status = Flag_Done();
                printf("DEBUG: Flag_Done = %d\n", done_status);
                
                // Se DONE=0, só avisa mas NÃO ESPERA
                if (done_status == 0) {
                    printf("AVISO: Hardware inicia com DONE=0 (problema no Verilog).\n");
                    printf("Executando mesmo assim...\n");
                }
                
                // Executar operação e capturar resultado
                switch (opcao) {
                    case 1:
                        printf("Executando Vizinho Proximo (zoom=%dx)...\n", 1 << zoom_real);
                        resultado = NHI(zoom_real);
                        break;
                    case 2:
                        printf("Executando Replicacao (zoom=%dx)...\n", 1 << zoom_real);
                        resultado = replicacao(0);
                        resultado = replicacao(zoom_real);
                        break;
                    case 3:
                        printf("Executando Decimacao (zoom=%dx)...\n", 1 << zoom_real);
                        resultado = decimacao(zoom_real);
                        break;
                    case 4:
                        printf("Executando Media de Blocos (zoom=%dx)...\n", 1 << zoom_real);
                        resultado = media_blocos(zoom_real);
                        break;
                    default:
                        resultado = -1;
                }
                
                // Verificar resultado
                if (resultado == 0) {
                    printf("Operacao concluida com sucesso!\n");
                } else if (resultado == -2) {
                    printf("ERRO: Timeout! Hardware nao respondeu.\n");
                } else {
                    printf("ERRO: Codigo de retorno = %d\n", resultado);
                }
                break;
                
            case 5:
                if (Flag_Done()) {
                    printf("\nStatus: Hardware PRONTO (Done=1)\n");
                } else {
                    printf("\nStatus: Hardware OCUPADO (Done=0)\n");
                }
                break;

            case 6:
                printf("Digite o caminho da imagem BMP (160x120): ");
                char filename[]= "./ImgGalinha.bmp";
            
                
                if (enviar_imagem_bmp(filename) == 0) {
                    printf("Imagem carregada na RAM1!\n");
                } else {
                    printf("ERRO ao carregar imagem!\n");
                }
                break;

            case 7:
                printf("\nSaindo...\n");
                break;
                
            default:
                printf("\nOpcao invalida!\n");

        }
    } while (opcao != 7);
    
    printf("\nEncerrando API...");
    if (encerrarAPI() == 0) {
        printf(" OK!\n");
    } else {
        printf(" ERRO!\n");
    }
    
    return 0;
}
