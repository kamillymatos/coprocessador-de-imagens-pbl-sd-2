# Coprocessador de Imagens com Interface HPS–FPGA (Problema 2 – Sistemas Digitais 2025.2)

Este projeto foi desenvolvido como parte do Problema 2 da disciplina **Sistemas Digitais (TEC499)** da **Universidade Estadual de Feira de Santana (UEFS)**. O objetivo central foi compreender e aplicar os conceitos de **programação em Assembly e integração software–hardware**, por meio da **implementação de uma biblioteca de controle (API)** e de uma **aplicação em linguagem C** destinada ao gerenciamento de um **coprocessador gráfico** em uma plataforma **DE1-SoC**.

O trabalho dá continuidade ao **coprocessador de processamento de imagens** desenvolvido no Problema 1, originalmente publicado no GitHub por uma colega de equipe, e mantido como base estrutural deste projeto. Entretanto, foram realizadas **adaptações e aprimoramentos** no código e na arquitetura para atender aos novos requisitos das etapas 2 e 3, incluindo:
- Construção de uma **API em Assembly** responsável por gerenciar o repertório de instruções da ISA do coprocessador;
- Integração entre **HPS (Hard Processor System)** e **FPGA** para comunicação e transferência de dados;
- Implementação de uma aplicação em **linguagem C**, capaz de carregar imagens no formato **BITMAP**, executar operações de **zoom in/out** e enviar comandos de controle ao hardware.

O projeto explora de forma prática os princípios de **mapeamento de memória ARM**, **link-edição entre módulos Assembly e C**, e **interação entre software e hardware reconfigurável**, resultando em um sistema embarcado funcional de **redimensionamento de imagens em escala de cinza**.

Este repositório contém os códigos-fonte comentados, a documentação técnica e os scripts de compilação utilizados para a execução e validação do sistema.
