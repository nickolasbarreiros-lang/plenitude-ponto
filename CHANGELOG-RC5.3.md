# Plenitude Ponto RC5.3 — Diagnóstico completo da contingência

## Diagnóstico ampliado

A página Dispositivos agora verifica separadamente:

- sessão offline;
- login offline;
- verificador criptográfico do PIN;
- perfil do funcionário;
- vínculo com o token do dispositivo;
- quantidade de funcionários completamente preparados.

## Funcionários preparados

Nova listagem mostra:

- nome;
- matrícula;
- data da preparação;
- presença do PIN protegido;
- perfil local;
- sessão offline;
- vínculo com o computador autorizado.

## Testar contingência agora

Novo teste controlado verifica:

- estrutura do login offline;
- Service Worker;
- cache dos arquivos;
- gravação fictícia no IndexedDB;
- leitura e integridade do registro;
- remoção completa do registro de teste;
- disponibilidade do módulo de sincronização.

O teste não desliga a internet, não cria marcação oficial e não envia registro para aprovação.
