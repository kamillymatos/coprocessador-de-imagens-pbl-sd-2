# Coprocessador de Imagens com Interface HPS–FPGA (Problema 2 – Sistemas Digitais 2025.2)

Este projeto foi desenvolvido como parte do Problema 2 da disciplina **Sistemas Digitais (TEC499)** da **Universidade Estadual de Feira de Santana (UEFS)**. O objetivo central foi compreender e aplicar os conceitos de **programação em Assembly e integração software–hardware**, por meio da **implementação de uma biblioteca de controle (API)** e de uma **aplicação em linguagem C** destinada ao gerenciamento de um **coprocessador gráfico** em uma plataforma **DE1-SoC**.

O trabalho dá continuidade ao **coprocessador de processamento de imagens** desenvolvido no Problema 1, originalmente publicado no GitHub por uma colega de equipe, e mantido como base estrutural deste projeto. Entretanto, foram realizadas **adaptações e aprimoramentos** no código e na arquitetura para atender aos novos requisitos das etapas 2 e 3, incluindo:
- Construção de uma **API em Assembly** responsável por gerenciar o repertório de instruções da ISA do coprocessador;
- Integração entre **HPS (Hard Processor System)** e **FPGA** para comunicação e transferência de dados;
- Implementação de uma aplicação em **linguagem C**, capaz de carregar imagens no formato **BITMAP**, executar operações de **zoom in/out** e enviar comandos de controle ao hardware.

O projeto explora de forma prática os princípios de **mapeamento de memória ARM**, **link-edição entre módulos Assembly e C**, e **interação entre software e hardware reconfigurável**, resultando em um sistema embarcado funcional de **redimensionamento de imagens em escala de cinza**.

Este repositório contém os códigos-fonte comentados, a documentação técnica e os scripts de compilação utilizados para a execução e validação do sistema.

---

## Modificações no Coprocessador Verilog (Evolução do Problema 1)

O **coprocessador original (Problema 1)** apresentava uma estrutura **monolítica**, na qual cada algoritmo de redimensionamento realizava **todas as etapas do fluxo de processamento** — leitura da imagem, cálculo e escrita — de forma **autônoma**.  
Essa abordagem funcionava corretamente para um sistema totalmente em FPGA, mas dificultava a **análise modular** e inviabilizava a **integração com o HPS**, já que as memórias eram fixas e não havia controle externo sobre a escrita.

O **coprocessador revisado (Problema 2)** foi reestruturado com foco em **clareza, modularização e interoperabilidade**.  
As principais diferenças estão resumidas a seguir:

| Aspecto | Coprocessador do Problema 1 | Coprocessador do Problema 2 |
|----------|------------------------------|------------------------------|
| **Organização dos algoritmos** | Cada algoritmo (Replicação, Decimação, etc.) realizava leitura, processamento e escrita internamente. | Algoritmos transformados em módulos puramente funcionais — apenas processam pixels — para facilitar análise e depuração. |
| **Controle de fluxo** | A Unidade de Controle coordenava todo o processo, mas sem distinguir leitura, processamento e escrita. | Introdução de um módulo **`ControladorRedimensionamento`** para coordenar operações e monitorar o progresso dos algoritmos. |
| **Controle de escrita** | Escrita direta e fixa em memória, embutida na lógica dos algoritmos. | Criação de uma **FSM exclusiva para controle de escrita**, isolada da FSM principal, permitindo gravação controlada pelo HPS. |
| **Memória de imagem** | ROM de 1 porta (somente leitura) com imagem sintetizada. | **RAM dual-port de 76 800 pixels**, permitindo leitura e escrita simultâneas e recebimento de imagens externas. |
| **Integração com HPS** | Inexistente — operação autônoma em FPGA. | Preparada para integração HPS–FPGA, com **comunicação via PIOs** e utilização da ponte do projeto **`my_first_fpga-hps_base`**. |
| **Flexibilidade e expansão** | Estrutura fixa, sem interface de controle externo. | Arquitetura modular, escalável e apta a receber comandos e dados do processador ARM. |

Em síntese, o novo coprocessador manteve o **núcleo funcional original** (FSM principal e algoritmos), mas incorporou **módulos auxiliares de controle e memória** que possibilitam sua integração ao sistema híbrido **HPS–FPGA**, tornando o projeto mais **organizado, flexível e interoperável**.

As principais alterações estruturais se concentraram em dois pontos:
- **Criação de um módulo `ControladorRedimensionamento`**, responsável por coordenar a leitura, o processamento e a escrita, tarefa anteriormente atribuida aos próprios algoritmos de redimensionamento;
- **Implementação de uma FSM de controle de escrita** e **substituição da ROM por uma RAM dual-port**, etapas fundamentais para preparar o sistema para comunicação com o HPS. 

Os próximos tópicos abordarão com mais detalhamento as principais mudanças feitas no circuito.

### 🔹 1. Algoritmos

O coprocessador desenvolvido no **Problema 1** possuía uma estrutura na qual **cada algoritmo de redimensionamento** — *Replicação*, *Decimação*, *Vizinho Mais Próximo* e *Média de Blocos* — era responsável por **todo o fluxo de execução**, incluindo **leitura da imagem**, **processamento** e **escrita dos pixels de saída**.  
Essa abordagem funcionava corretamente, mas dificultava a depuração e a análise visual do comportamento interno do sistema, já que a lógica de controle estava embutida em cada módulo.

No **Problema 2**, essa arquitetura foi **reorganizada** com foco em **clareza e modularidade**, permitindo observar e testar separadamente cada parte do fluxo de processamento.  
Os algoritmos foram **separados em módulos individuais**, não para alterar seu funcionamento, mas para **facilitar o entendimento e o acompanhamento das operações internas** no Verilog.  

---

### 🔹 2. Controlador de Redimensionamento

O módulo **`ControladorRedimensionamento`** foi introduzido para centralizar o controle das operações internas do coprocessador, coordenando a leitura de pixels, o processamento em cada algoritmo e a escrita dos resultados na memória.  

A lógica de funcionamento segue a sequência abaixo:

1. **Inicialização**  
   O controlador é ativado através do sinal `start`. Nesse instante, ele reinicia contadores internos de coordenadas (`x_orig`, `y_orig`, `x_dest`, `y_dest`) e seleciona o algoritmo ativo de acordo com o comando recebido.

2. **Leitura e Processamento**  
   Em cada ciclo de clock, o controlador solicita um pixel da memória de origem (`mem1_addr`) e o envia para o módulo do algoritmo correspondente (`pixel_in`).  
   Quando o algoritmo sinaliza que o processamento foi concluído (`ready = 1`), o controlador armazena o valor resultante (`pixel_out`).

3. **Escrita do Resultado**  
   O controlador habilita o sinal `we = 1` e grava o resultado no endereço de destino (`mem2_addr`), incrementando os contadores até o fim do processamento da imagem.

4. **Finalização**  
   Após o processamento completo, o sinal `done_redim` é ativado, informando à FSM principal que a operação foi concluída e que os dados podem ser exibidos via VGA.

> 💡 **Importante:**  
> O `ControladorRedimensionamento` **não substitui a FSM principal da Unidade de Controle**.  
> Ele funciona como uma **camada intermediária**, permitindo que o controle global (inicialização, operação e exibição) continue sob responsabilidade da FSM original, preservando a estrutura base do Problema 1.

---

### 🔹 3. FSM de Controle de Escrita

Para permitir o recebimento de dados externos e armazenamento dinâmico da imagem na memória, foi criada uma **FSM dedicada à escrita**.  
Essa FSM é **independente da FSM original**, atuando como um componente auxiliar que apenas gerencia a gravação dos pixels enviados pelo processador.

| Estado | Descrição |
|---------|------------|
| **IDLE_WRITE** | Estado inicial. Aguarda o sinal `SolicitaEscrita = 1` indicando o início da transferência. |
| **WRITE** | Ativa o sinal de escrita (`we = 1`) e grava o valor de `dados_pixel_hps` no endereço corrente (`addr_in_hps`). Incrementa o contador de endereços a cada ciclo. |
| **WAIT_WRITE** | Após todos os pixels serem recebidos, desativa a escrita (`we = 0`), gera o sinal `done_write` e retorna ao estado inicial. |

Essa FSM foi criada separadamente para **minimizar alterações na Unidade de Controle original**.  
Ela prepara o sistema para lidar com imagens externas, mas sem alterar a estrutura principal do coprocessador.

---

### 🔹 4. Substituição da Memória ROM por RAM Dual-Port

No projeto anterior, a imagem era armazenada em uma **ROM de 1 porta** com 19 200 palavras, utilizada apenas para leitura.  
Para permitir operações de escrita e leitura simultâneas, essa memória foi substituída por uma **RAM dual-port** com **76 800 posições de 8 bits**.

| Característica | ROM (Problema 1) | RAM Dual-Port (Problema 2) |
|----------------|------------------|-----------------------------|
| Tipo de acesso | Somente leitura | Leitura e escrita |
| Portas de acesso | 1 | 2 (independentes) |
| Capacidade | 19 200 pixels | 76 800 pixels |
| Fonte dos dados | Imagem fixa sintetizada | Dados enviados pelo HPS |
| Controle de endereços | Interno aos algoritmos | Externo, via FSM de escrita e controlador |

A **porta A** é utilizada para escrita (entrada de dados externos) e a **porta B** para leitura (acesso da lógica de processamento).  
Essa alteração foi um **passo essencial para permitir a futura comunicação bidirecional com o HPS**, sem bloqueios entre leitura e escrita.

---

## Integração HPS–FPGA

Após a reorganização da arquitetura do coprocessador, foram iniciadas as **etapas de integração entre o HPS e a FPGA**.  
Essas etapas envolvem a criação de uma ponte de comunicação e o mapeamento de sinais no *Platform Designer* do Quartus.

---

### 🔹 1. Projeto Base: *my_first_fpga-hps_base*

A integração foi desenvolvida a partir do projeto de referência **`my_first_fpga-hps_base`**, disponibilizado pela Intel.  
Esse projeto serve como **base oficial para comunicação HPS–FPGA**, fornecendo automaticamente toda a estrutura de interconexão entre o **ARM Cortex-A9** e a **lógica programável da FPGA**, incluindo:

- **Controlador DDR3** totalmente configurado e sincronizado;  
- **Barramentos AXI e Avalon-MM** já instanciados e mapeados;  
- **Ponte Lightweight HPS–FPGA** para troca de dados em nível de registradores;  
- **Gerenciamento de clock e reset compartilhado** entre HPS e FPGA;  
- **Interfaces Ethernet, USB, UART, SPI, SDIO e GPIO** prontas para uso.

Esses componentes são extremamente complexos de implementar manualmente, exigindo múltiplos níveis de sincronização de barramentos, domínio de clock e protocolos de reset — tarefas que o *my_first_fpga-hps_base* já resolve automaticamente.  

Nosso coprocessador foi **instanciado dentro desse projeto**, aproveitando sua infraestrutura e permitindo que os sinais necessários à comunicação fossem facilmente conectados ao HPS.

---

### 🔹 2. Conexão via PIOs no Platform Designer

A comunicação entre o **HPS** e o **coprocessador** foi realizada utilizando **PIOs (Parallel Input/Output)** configurados no **Platform Designer** do Quartus.  
Os PIOs foram usados para criar **registradores mapeados em memória**, acessíveis tanto pelo software (HPS) quanto pela lógica Verilog.

Principais PIOs criados:
- `pio_instruction` – para envio de instruções e dados de controle do HPS;  
- `pio_start` – sinal de ativação do processamento;  
- `pio_done` e `pio_donewrite` – sinais de status de conclusão de escrita e redimensionamento.

Esses sinais foram mapeados no barramento Lightweight do HPS e conectados à nossa **Unidade de Controle** dentro do módulo `ghrd_top.v`.

---

### 🔹 3. Adaptação do Arquivo `ghrd_top.v`

O arquivo **`ghrd_top.v`** (Gerador de Hardware de Referência da Intel) foi adaptado para **instanciar o nosso coprocessador** dentro da estrutura do projeto de referência.  
Além das conexões padrão do HPS (memória DDR3, interfaces de I/O e clock), adicionamos a instância da **`UnidadeControle`** e os **PIOs criados no Platform Designer**, conectando-os diretamente aos sinais internos da FPGA.

Essas modificações permitiram:
- Controlar o coprocessador diretamente a partir do HPS via registradores mapeados;  
- Sincronizar os sinais `start`, `done` e `done_write` entre software e hardware;  
- Executar instruções enviadas pelo HPS em tempo real, através da ponte Lightweight.

---

### 🔹 4. Resultado da Integração

A partir dessa estrutura, o HPS passou a ser capaz de:
- Enviar comandos e parâmetros para o coprocessador (via `pio_instruction` e `pio_start`);  
- Monitorar o progresso das operações (`done` e `done_write`);  
- Carregar imagens na memória RAM dual-port através da FSM de escrita;  
- Receber o resultado processado exibido na saída VGA da FPGA.

Essa integração utiliza a infraestrutura Intel existente para comunicação híbrida, garantindo **compatibilidade, estabilidade e redução de complexidade de implementação**, além de manter a **modularidade e escalabilidade** do sistema.

---

**Resumo:**  
As modificações internas (FSM, RAM dual-port e controlador) foram **etapas preparatórias**, enquanto a integração via *my_first_fpga-hps_base* e os PIOs do Quartus **estabelecem a ponte real entre o HPS e a FPGA**, consolidando o sistema como uma solução híbrida e funcional de processamento de imagens.
