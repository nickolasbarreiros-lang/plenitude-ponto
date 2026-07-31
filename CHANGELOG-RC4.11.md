# Plenitude Ponto 1.0.0 RC4.11

## Eliminação definitiva da consulta direta no Backup

- Removida a função genérica `queryAll` do módulo de backup.
- O arquivo `backup.js` foi substituído por `backup-rc4-11.js`.
- O novo nome impede o navegador de reutilizar o JavaScript antigo.
- A página Backup utiliza exclusivamente a RPC `exportar_backup_admin`.
- Incluído marcador de versão visível no cabeçalho e no Console.
