@ ENDEREÇOS DOS REGISTRADORES DO PIO (Parallel I/O)
.equ PIO_INSTRUCT,         0x00   @ Offset para registrador de instruções
.equ PIO_START,            0x30   @ Offset para sinal de START
.equ PIO_DONE,             0x20   @ Offset para ler flag DONE (operação concluída)
.equ PIO_DONE_WRITE,       0x40   @ Offset para escrever em DONE 

@tamanho da ram
.equ VRAM_MAX_ADDR,     19200     @ Tamanho máximo da RAM (160x120 pixels)

@opcodes - 2 BITS (compatível com SW[1:0] do Verilog)
.equ OPCODE_REPLICACAO, 0x00   @ 2'b00 
.equ OPCODE_DECIMACAO,  0x01   @ 2'b01
.equ OPCODE_NHI,        0x02   @ 2'b10
.equ OPCODE_MEDIA,      0x03   @ 2'b11

@timeouts dos algoritmos
.equ TIMEOUT_COUNT,     0x0

@ SEÇÃO .rodata - DADOS SOMENTE LEITURA (strings constantes)
.section .rodata 

.LC0:           .asciz "/dev/mem"     @ Caminho do dispositivo de memória

.LC1:           .asciz "ERROR: could not open '/dev/mem' ...\n"   @ Mensagem de erro ao abrir /dev/mem

.LC2:           .asciz "ERROR: mmap() failed ...\n"         @ Mensagem de erro no mapeamento

.LC3:           .asciz "ERROR: munmap() failed ...\n"       @ Mensagem de erro ao desmapear


@ Ponteiro para o endereço mapeado da FPGA
FPGA_ADRS:
    .space 4                      @ Reserva 4 bytes para armazenar o endereço base da FPGA

@ File descriptor do arquivo /dev/mem
FILE_DESCRIPTOR:
    .space 4                      @ Reserva 4 bytes para o descritor de arquivo

@ Tamanho da região a ser mapeada (4KB)
LW_SPAM:
    .word 0x1000                  @ 4096 bytes = 4KB

@ Endereço base do lightweight bridge (0xFF200000 no DE1-SoC)
LW_BASE:
    .word 0xff200                 @ Endereço físico base 

@ Máscara para isolar bits de endereço no empacotamento
MASK_ADDR:
    .word 0x000FFFE0              @ Máscara para bits [19:5] do endereço

@ Valor de timeout para operações (3 milhões de ciclos)
TIMEOUT_VAL:
    .word 3000000                 @ 3 milhões de iterações antes de timeout

@ SEÇÃO .text - CÓDIGO EXECUTÁVEL

.text
@ FUNÇÃO: iniciarAPI
@ DESCRIÇÃO: Abre /dev/mem e mapeia a região da FPGA na memória do processo
@ RETORNO: 0 se sucesso, -1 se erro

.global iniciarAPI
.type iniciarAPI, %function


iniciarAPI:
    @ Salva registradores na pilha (convenção ARM)
    PUSH    {r4-r7, lr}           @ r4-r7: registradores salvos, lr: endereço de retorno

    @ ========================================================================
    @ PASSO 1: Abrir o arquivo /dev/mem (syscall open)
    @ ========================================================================
    LDR      r0, =.LC0            @ r0 = "/dev/mem" (nome do arquivo)
    LDR      r1, =4098            @ r1 =  flags de abertura
    MOV      r2, #0               @ r2 = 0 (mode, não usado aqui)
    MOV      r7, #5               @ r7 = 5 (número da syscall open)

.L_MMAP_Call:
    SVC      0                    @ Chama o kernel (system call)
    MOV      r4, r0               @ r4 = file descriptor retornado

    @ Salva o file descriptor na memória
    LDR      r1, =FILE_DESCRIPTOR
    STR      r4, [r1]             @ Armazena FD para uso posterior

    @ Verifica se houve erro (-1 indica falha)
    CMP      r4, #-1
    BNE      .L_MMAP_Setup        @ Se FD válido, continua

    @ Tratamemto de erro: Não foi possível abrir /dev/mem
    LDR      r0, =.LC1            @ Carrega mensagem de erro
    BL       puts                 @ Imprime mensagem
    MOV      r0, #-1              @ Retorna -1 (erro)
    B        .L_Return_init       @ Sai da função

   
    @ Se não deu erro: Mapear região física da FPGA (syscall mmap)
   
.L_MMAP_Setup:
    MOV      r0, #0               @ r0 = NULL (kernel escolhe o endereço virtual)

    LDR      r1, =LW_SPAM
    LDR      r1, [r1]             @ r1 = Tamanho da região a ser mapeada 

    MOV      r2, #3               @ r2 = permissões
    MOV      r3, #1               @ r3 = MAP_SHARED (compartilhado)

    LDR      r4, =FILE_DESCRIPTOR
    LDR      r4, [r4]             @ r4 = file descriptor

    LDR      r5, =LW_BASE
    LDR      r5, [r5]             @ r5 = 0xFF200 (endereço base físico)

    MOV      r7, #192             @ r7 = 192 (número da syscall mmap2)

    SVC      0                    @ Chama o kernel
    MOV      r4, r0               @ r4 = endereço virtual mapeado

    @ Salva o endereço virtual mapeado
    LDR      r1, =FPGA_ADRS
    STR      r4, [r1]             @ Armazena para uso nas outras funções

    @ Verifica se houve erro no mmap
    CMP      r4, #-1
    BNE      .L_Success_init      @ Se sucesso, pula para o fim

    
    @ Tratamento de erro: mmap() falhou
  
    LDR      r0, =.LC2            @ Mensagem de erro
    BL       puts                 @ Imprime

    @ Fecha o file descriptor antes de sair
    LDR      r0, =FILE_DESCRIPTOR
    LDR      r0, [r0]
    BL       close                @ Fecha /dev/mem
    MOV      r0, #-1              @ Retorna -1 (erro)
    B        .L_Return_init

   
    @ Se não deu erro: API inicializada corretamente
   
.L_Success_init:
    MOV      r0, #0               @ Retorna 0 (sucesso)

.L_Return_init:
    POP      {r4-r7, pc}          @ Restaura registradores e retorna

.size iniciarAPI, .-iniciarAPI


@ FUNÇÃO: encerrarAPI
@ DESCRIÇÃO: Desmapeia a memória da FPGA e fecha o file descriptor
@ RETORNO: 0 se sucesso, -1 se erro

global encerrarAPI
.type encerrarAPI, %function

encerrarAPI:
    PUSH    {r4-r7, lr}

   
    @ Desmapear a memória (syscall munmap)
   
    LDR      r0, =FPGA_ADRS
    LDR      r0, [r0]             @ r0 = endereço virtual mapeado

    LDR      r1, =LW_SPAM
    LDR      r1, [r1]             @ r1 = tamanho (4KB)

    MOV      r7, #91              @ r7 = 91 (syscall munmap)
    SVC      0                    @ Chama o kernel
    MOV      r4, r0               @ r4 = resultado (0 se sucesso)

    @ Verifica se houve erro
    CMP      r4, #0
    BEQ      .L_Close_Call        @ Se sucesso, fecha o FD

    
    @ Tratamento de erro: munmap() falhou
    LDR      r0, =.LC3
    BL       puts
    MOV      r0, #-1
    B        .L_Return_end

  
    @Fecha o file descriptor (syscall close)
   
.L_Close_Call:
    LDR      r0, =FILE_DESCRIPTOR
    LDR      r0, [r0]             @ r0 = file descriptor

    MOV      r7, #6               @ r7 = 6 (syscall close)
    SVC      0

    MOV      r0, #0               @ Retorna 0 (sucesso)

.L_Return_end:
    POP      {r4-r7, pc}

.size encerrarAPI, .-encerrarAPI

@ FUNÇÃO: write_pixel
@ DESCRIÇÃO: Escreve um pixel na RAM do FPGA
@ PARÂMETROS:
@   r0 = endereço do pixel (0-19199)
@   r1 = valor do pixel (0-255, grayscale)
@ RETORNO: 0 se sucesso, -1 se endereço inválido

.global write_pixel
.type write_pixel, %function

write_pixel:
    push    {r4-r6, lr}

    @ Carrega o endereço base da FPGA
    ldr     r4, =FPGA_ADRS
    ldr     r4, [r4]             @ r4 = ponteiro para a FPGA

   
    @Verifica se o endereço está dentro do limite
   
    cmp     r0, #19200           @ Compara com tamanho máximo da RAM
    bhs     .L_INVALID_ADDR      @ Se >= 19200, salta para erro

   
@ EMPACOTAMENTO DO DADO: Monta o pacote de 32 bits
@ Formato do pacote:
@   bits [19:5]  = endereço do pixel (15 bits)
@   bits [27:20] = valor do pixel (8 bits)
@   bit  [4]     = SolicitaEscrita (1 = escrever)
   
.L_PACK_DATA:
    @Desloca endereço para bits [19:5]
    lsl     r2, r0, #5           @ r2 = endereço << 5

    @ Carrega máscara para isolar bits de endereço
    ldr     r6, =MASK_ADDR
    ldr     r6, [r6]             @ r6 = 0x000FFFE0

    and     r2, r2, r6           @ r2 = endereço isolado em [19:5]
    
    @Desloca valor do pixel para bits [27:20]
    lsl     r3, r1, #20          @ r3 = pixel_data << 20
    and     r3, r3, #0x0FF00000  @ Máscara para garantir 8 bits
    orr     r2, r2, r3           @ r2 |= pixel_data
    
    @Liga o bit SolicitaEscrita (bit 4)
    mov     r3, #1
    lsl     r3, r3, #4           @ r3 = 1 << 4 = 0x10
    orr     r2, r2, r3           @ r2 |= SolicitaEscrita
    
   
    @Envia pacote COM SolicitaEscrita = 1
    str     r2, [r4, #PIO_INSTRUCT]  @ Escreve no registrador de instrução
    dmb     sy                       @ Data Memory Barrier (sincronização)
    
   
    @Desliga SolicitaEscrita (borda de descida)
    mov     r3, #1
    lsl     r3, r3, #4           @ r3 = 0x10
    bic     r2, r2, r3           @ r2 &= (1<<4) - limpa bit 4
    
    str     r2, [r4, #PIO_INSTRUCT]  @ Envia novamente (borda de descida)
    dmb     sy

   
    b       .L_EXIT              @ Salta para saída

    
@ Tratamento de erro: Endereço fora da faixa válida
.L_INVALID_ADDR:
    mov     r0, #-1              @ Retorna -1 (erro)
    b       .L_EXIT

   
@ SAÍDA: Restaura registradores e retorna   
.L_EXIT:
    mov     r0, #0               @ Retorna 0 (sucesso)
    pop     {r4-r6, pc}

.size write_pixel, .-write_pixel

@ FUNÇÃO: replicacao
@ DESCRIÇÃO: Aplica algoritmo de interpolação por replicação
@ PARÂMETROS:
@   r0 = zoom (0=1x, 1=2x, 2=4x)
@ RETORNO: 0 se sucesso, -2 se timeout

.global replicacao
.type replicacao, %function

replicacao:
    PUSH {r4-r6, lr}

    @ Carrega endereço base da FPGA
    LDR r4, =FPGA_ADRS
    LDR r4, [r4]                 @ r4 = ponteiro FPGA

   
@ EMPACOTAMENTO DA INSTRUÇÃO
@ Formato: bits[1:0] = opcode, bits[3:2] = zoom
empacotamento_instrucao_replic:
    MOV r2, #OPCODE_REPLICACAO   @ r2 = 0x00 (opcode replicação)
    
    AND r0, r0, #0x02            @ Garante que zoom é 2 bits (0-2)
    LSL r3, r0, #2               @ r3 = zoom << 2 (desloca para bits[3:2])
    ORR r2, r2, r3               @ r2 = opcode | zoom

    @ Envia instrução para o hardware
    STR r2, [r4, #PIO_INSTRUCT]
    DMB                          @ Sincronização

   
    @ PULSO DE START: Gera borda de subida e descida
    MOV r2, #1
    STR r2, [r4, #PIO_START]     @ START = 1
    DMB
    MOV r2, #0
    STR r2, [r4, #PIO_START]     @ START = 0 (borda de descida inicia operação)
    DMB

 
    @ POLLING: Aguarda flag DONE com timeout
    LDR r5, =TIMEOUT_VAL         @ Carrega endereço da constante
    LDR r5, [r5]                 @ r5 = 3000000 (valor de timeout)

.LOOP_LE_DONE_REPLIC:
    LDR r2, [r4, #PIO_DONE]      @ Lê registrador DONE
    TST r2, #1                   @ Testa bit 0 (DONE)
    BNE .L_SUCCESS_REPLIC        @ Se DONE=1, operação concluída

    SUBS r5, r5, #1              @ Decrementa contador
    BNE .LOOP_LE_DONE_REPLIC     @ Se r5 != 0, continua esperando

   
    @ TIMEOUT: Hardware não respondeu a tempo
    MOV r0, #-2                  @ Retorna -2 (timeout)
    B .EXIT_REPLIC

  
@ Operação concluída
.L_SUCCESS_REPLIC:
    MOV r0, #0                   @ Retorna 0 (sucesso)

.EXIT_REPLIC:
    POP {r4-r6, pc}

.size replicacao, .-replicacao

@ FUNÇÃO: decimacao
@ DESCRIÇÃO: Aplica algoritmo de redução por decimação (pega 1 pixel a cada N)
@ PARÂMETROS:
@   r0 = zoom (0=1x, 1=2x, 2=4x)
@ RETORNO: 0 se sucesso, -2 se timeout

.global decimacao
.type decimacao, %function

decimacao:
    PUSH {r4-r6, lr}

    @ Carrega endereço base da FPGA
    LDR r4, =FPGA_ADRS
    LDR r4, [r4]                 @ r4 = ponteiro FPGA

   
@ EMPACOTAMENTO DA INSTRUÇÃO
@ Formato: bits[1:0] = opcode, bits[3:2] = zoom
empacotamento_instrucao_dec:
    MOV r2, #OPCODE_DECIMACAO    @ r2 = 0x01 (opcode decimação)
    
    AND r0, r0, #0x02            @ Garante que zoom é 2 bits (0-2)
    LSL r3, r0, #2               @ r3 = zoom << 2 (desloca para bits[3:2])
    ORR r2, r2, r3               @ r2 = opcode | zoom

    @ Envia instrução para o hardware
    STR r2, [r4, #PIO_INSTRUCT]
    DMB                          @ Sincronização

   
    @ PULSO DE START: Gera borda de subida e descida
    MOV r2, #1
    STR r2, [r4, #PIO_START]     @ START = 1
    DMB
    MOV r2, #0
    STR r2, [r4, #PIO_START]     @ START = 0 (borda de descida inicia operação)
    DMB

 
    @ POLLING: Aguarda flag DONE com timeout
    LDR r5, =TIMEOUT_VAL         @ Carrega endereço da constante
    LDR r5, [r5]                 @ r5 = 3000000 (valor de timeout)

.LOOP_LE_DONE_DEC:
    LDR r2, [r4, #PIO_DONE]      @ Lê registrador DONE
    TST r2, #1                   @ Testa bit 0 (DONE)
    BNE .L_SUCCESS_DEC           @ Se DONE=1, operação concluída

    SUBS r5, r5, #1              @ Decrementa contador
    BNE .LOOP_LE_DONE_DEC        @ Se r5 != 0, continua esperando

   
    @ TIMEOUT: Hardware não respondeu a tempo
    MOV r0, #-2                  @ Retorna -2 (timeout)
    B .EXIT_DEC

  
@ Operação concluída
.L_SUCCESS_DEC:
    MOV r0, #0                   @ Retorna 0 (sucesso)

.EXIT_DEC:
    POP {r4-r6, pc}

.size decimacao, .-decimacao

@ FUNÇÃO: Vizinho Mais Proximo
@ DESCRIÇÃO: Aplica algoritmo de vizinho mais proximo 
@ PARÂMETROS:
@   r0 = zoom (0=1x, 1=2x, 2=4x)
@ RETORNO: 0 se sucesso, -2 se timeout

.global NHI
.type NHI, %function

NHI:
    PUSH {r4-r6, lr}

    @ Carrega endereço base da FPGA
    LDR r4, =FPGA_ADRS
    LDR r4, [r4]                 @ r4 = ponteiro FPGA

   
@ EMPACOTAMENTO DA INSTRUÇÃO
@ Formato: bits[1:0] = opcode, bits[3:2] = zoom
empacotamento_instrucao_nhi:
    MOV r2, #OPCODE_NHI          @ r2 = 0x02 (opcode NHI)
    
    AND r0, r0, #0x03            @ Garante que zoom é 2 bits (0-2)
    LSL r3, r0, #2               @ r3 = zoom << 2 (desloca para bits[3:2])
    ORR r2, r2, r3               @ r2 = opcode | zoom

    @ Envia instrução para o hardware
    STR r2, [r4, #PIO_INSTRUCT]
    DMB                          @ Sincronização

   
    @ PULSO DE START: Gera borda de subida e descida
    MOV r2, #1
    STR r2, [r4, #PIO_START]     @ START = 1
    DMB
    MOV r2, #0
    STR r2, [r4, #PIO_START]     @ START = 0 (borda de descida inicia operação)
    DMB

 
    @ POLLING: Aguarda flag DONE com timeout
    LDR r5, =TIMEOUT_VAL         @ Carrega endereço da constante
    LDR r5, [r5]                 @ r5 = 3000000 (valor de timeout)

.LOOP_LE_DONE_NHI:
    LDR r2, [r4, #PIO_DONE]      @ Lê registrador DONE
    TST r2, #1                   @ Testa bit 0 (DONE)
    BNE .L_SUCCESS_NHI           @ Se DONE=1, operação concluída

    SUBS r5, r5, #1              @ Decrementa contador
    BNE .LOOP_LE_DONE_NHI        @ Se r5 != 0, continua esperando

   
    @ TIMEOUT: Hardware não respondeu a tempo
    MOV r0, #-2                  @ Retorna -2 (timeout)
    B .EXIT_NHI

  
@ Operação concluída
.L_SUCCESS_NHI:
    MOV r0, #0                   @ Retorna 0 (sucesso)

.EXIT_NHI:
    POP {r4-r6, pc}

.size NHI, .-NHI

@ FUNÇÃO: Media de Blocos 
@ DESCRIÇÃO: Aplica algoritmo de média de blocos (anti-aliasing)
@ PARÂMETROS:
@   r0 = zoom (0=1x, 1=2x, 2=4x)
@ RETORNO: 0 se sucesso, -2 se timeout

.global media_blocos
.type media_blocos, %function

media_blocos:
    PUSH {r4-r6, lr}

    @ Carrega endereço base da FPGA
    LDR r4, =FPGA_ADRS
    LDR r4, [r4]                 @ r4 = ponteiro FPGA

   
@ EMPACOTAMENTO DA INSTRUÇÃO
@ Formato: bits[1:0] = opcode, bits[3:2] = zoom
empacotamento_instrucao_med:
    MOV r2, #OPCODE_MEDIA        @ r2 = 0x03 (opcode média de blocos)
    
    AND r0, r0, #0x03            @ Garante que zoom é 2 bits (0-2)
    LSL r3, r0, #2               @ r3 = zoom << 2 (desloca para bits[3:2])
    ORR r2, r2, r3               @ r2 = opcode | zoom

    @ Envia instrução para o hardware
    STR r2, [r4, #PIO_INSTRUCT]
    DMB                          @ Sincronização

   
    @ PULSO DE START: Gera borda de subida e descida
    MOV r2, #1
    STR r2, [r4, #PIO_START]     @ START = 1
    DMB
    MOV r2, #0
    STR r2, [r4, #PIO_START]     @ START = 0 (borda de descida inicia operação)
    DMB

 
    @ POLLING: Aguarda flag DONE com timeout
    LDR r5, =TIMEOUT_VAL         @ Carrega endereço da constante
    LDR r5, [r5]                 @ r5 = 3000000 (valor de timeout)

.LOOP_LE_DONE_MED:
    LDR r2, [r4, #PIO_DONE]      @ Lê registrador DONE
    TST r2, #1                   @ Testa bit 0 (DONE)
    BNE .L_SUCCESS_MED           @ Se DONE=1, operação concluída

    SUBS r5, r5, #1              @ Decrementa contador
    BNE .LOOP_LE_DONE_MED        @ Se r5 != 0, continua esperando

   
    @ TIMEOUT: Hardware não respondeu a tempo
    MOV r0, #-2                  @ Retorna -2 (timeout)
    B .EXIT_MED

  
@ Operação concluída
.L_SUCCESS_MED:
    MOV r0, #0                   @ Retorna 0 (sucesso)

.EXIT_MED:
    POP {r4-r6, pc}

.size media_blocos, .-media_blocos


@ FUNÇÃO: Flag_Done
@ DESCRIÇÃO: Lê o estado atual da flag DONE do hardware
@ RETORNO: Valor do registrador DONE (bit 0 indica conclusão)

.global Flag_Done
.type Flag_Done, %function

Flag_Done: 
    push    {r7, lr}
    
    @ Carrega endereço da FPGA
    ldr     r3, =FPGA_ADRS
    ldr     r3, [r3]
    
    @ Lê registrador DONE e retorna o valor
    ldr     r0, [r3, #PIO_DONE]  @ r0 = valor do registrador DONE
    
    pop     {r7, pc}             @ Retorna (r0 já contém o resultado)

.size Flag_Done, .-Flag_Done


.section .note.GNU-stack,"",%progbits