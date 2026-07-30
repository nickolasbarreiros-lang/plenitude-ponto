(async function(){
 const auth=window.PlenitudeAuth, client=auth?.client; const ctx=await auth.requireAccess({roles:['administrador']}); if(!ctx||!client)return;
 const status=document.getElementById('status'); document.getElementById('sair').onclick=()=>auth.signOut();
 async function run(fn,confirmText){if(confirmText&&!confirm(confirmText))return; status.textContent='Processando...'; try{const {data,error}=await client.rpc(fn);if(error)throw error;status.textContent=fn.startsWith('criar')?'Funcionário teste pronto. Matrícula 999, PIN 9999.':`Reset concluído. ${data?.registros_removidos||0} registro(s) removido(s).`;}catch(e){alert(e.message);status.textContent='Erro: '+e.message;}}
 document.getElementById('criar').onclick=()=>run('criar_funcionario_homologacao_admin');
 document.getElementById('resetar').onclick=()=>run('resetar_funcionario_homologacao_admin','Apagar todos os registros de teste da matrícula 999? Os dados da Roseli não serão alterados.');
})();
