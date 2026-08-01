# RC5.26B

O erro `column sf.token does not exist` vinha da função de consulta das
pendências do funcionário. Ela foi corrigida para reutilizar
`funcionario_por_token()`, a validação oficial já usada pelo sistema.
