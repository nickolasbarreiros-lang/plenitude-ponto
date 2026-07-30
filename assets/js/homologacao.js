(async function(){
  'use strict';

  const auth = window.PlenitudeAuth;
  const client = auth?.client;
  const ctx = await auth.requireAccess({roles:['administrador']});
  if (!ctx || !client) return;

  const status = document.getElementById('status');
  const notesKey = 'plenitude-homologacao-notas-rc2-2';
  const checklistKey = 'plenitude-homologacao-checklist-rc2-2';

  document.getElementById('sair').onclick = () => auth.signOut();

  async function runRpc(fn, confirmText) {
    if (confirmText && !confirm(confirmText)) return;
    status.textContent = 'Processando...';
    try {
      const {data, error} = await client.rpc(fn);
      if (error) throw error;
      status.textContent = fn.startsWith('criar')
        ? 'Funcionário teste pronto. Matrícula 999, PIN 9999.'
        : `Reset concluído. ${data?.registros_removidos || 0} registro(s) removido(s).`;
    } catch (error) {
      status.textContent = `Erro: ${error.message}`;
      alert(error.message);
    }
  }

  document.getElementById('criar').onclick = () =>
    runRpc('criar_funcionario_homologacao_admin');

  document.getElementById('resetar').onclick = () =>
    runRpc(
      'resetar_funcionario_homologacao_admin',
      'Apagar todos os registros de teste da matrícula 999? Os dados reais não serão alterados.'
    );

  const scenarios = [
    {grupo:'1. Preparação', teste:'Diagnóstico técnico com todas as verificações aprovadas'},
    {grupo:'1. Preparação', teste:'Funcionário 999 criado ou reparado'},
    {grupo:'1. Preparação', teste:'Dados de homologação resetados'},
    {grupo:'1. Preparação', teste:'Computador de testes autorizado'},

    {grupo:'2. Jornada', teste:'Login com matrícula 999 e PIN 9999'},
    {grupo:'2. Jornada', teste:'Registrar entrada'},
    {grupo:'2. Jornada', teste:'Confirmar horário e próxima ação'},
    {grupo:'2. Jornada', teste:'Registrar saída para almoço'},
    {grupo:'2. Jornada', teste:'Registrar retorno do almoço'},
    {grupo:'2. Jornada', teste:'Registrar saída final'},
    {grupo:'2. Jornada', teste:'Confirmar jornada encerrada e resumo'},

    {grupo:'3. Movimentação temporária', teste:'Registrar saída temporária com motivo'},
    {grupo:'3. Movimentação temporária', teste:'Confirmar status Fora da loja'},
    {grupo:'3. Movimentação temporária', teste:'Registrar retorno temporário'},
    {grupo:'3. Movimentação temporária', teste:'Classificar movimentação no painel'},

    {grupo:'4. Ajustes', teste:'Solicitar entrada esquecida'},
    {grupo:'4. Ajustes', teste:'Solicitar saída esquecida'},
    {grupo:'4. Ajustes', teste:'Aprovar uma solicitação'},
    {grupo:'4. Ajustes', teste:'Rejeitar uma solicitação'},
    {grupo:'4. Ajustes', teste:'Confirmar reflexo no relatório e auditoria'},

    {grupo:'5. Banco de horas', teste:'Conferir tolerância de entrada'},
    {grupo:'5. Banco de horas', teste:'Conferir saldo diário'},
    {grupo:'5. Banco de horas', teste:'Conferir saldo semanal'},
    {grupo:'5. Banco de horas', teste:'Conferir saldo mensal'},
    {grupo:'5. Banco de horas', teste:'Conferir hora extra e saída antecipada'},

    {grupo:'6. Administração', teste:'Criar e editar funcionário'},
    {grupo:'6. Administração', teste:'Definir ou alterar PIN'},
    {grupo:'6. Administração', teste:'Bloquear e reativar acesso ao ponto'},
    {grupo:'6. Administração', teste:'Autorizar e revogar dispositivo'},
    {grupo:'6. Administração', teste:'Consultar auditoria'},
    {grupo:'6. Administração', teste:'Gerar backup e exportações'},

    {grupo:'7. Fechamento', teste:'Fechar competência'},
    {grupo:'7. Fechamento', teste:'Confirmar bloqueio de alterações'},
    {grupo:'7. Fechamento', teste:'Reabrir com motivo e PIN Mestre'},

    {grupo:'8. Relatórios', teste:'Gerar espelho mensal'},
    {grupo:'8. Relatórios', teste:'Imprimir ou salvar PDF'},
    {grupo:'8. Relatórios', teste:'Exportar CSV'},

    {grupo:'9. Segurança', teste:'Testar PIN incorreto'},
    {grupo:'9. Segurança', teste:'Confirmar bloqueio após tentativas inválidas'},
    {grupo:'9. Segurança', teste:'Testar computador não autorizado'},
    {grupo:'9. Segurança', teste:'Testar logout e sessão expirada'},

    {grupo:'10. Robustez operacional', teste:'Proteção contra múltiplos cliques', detalhe:'Vários cliques rápidos devem registrar apenas uma marcação.'},
    {grupo:'10. Robustez operacional', teste:'Persistência após atualizar a página (F5)', detalhe:'A marcação e a próxima etapa devem permanecer corretas.'},
    {grupo:'10. Robustez operacional', teste:'Proteção com duas abas abertas', detalhe:'Chamadas concorrentes não podem pular etapas.'},
    {grupo:'10. Robustez operacional', teste:'Proteção contra etapas fora da ordem', detalhe:'Não deve ser possível pular Retorno ou Saída.'},
    {grupo:'10. Robustez operacional', teste:'Bloqueio após jornada concluída', detalhe:'Uma quinta marcação deve ser recusada.'},
    {grupo:'10. Robustez operacional', teste:'Janela mínima entre marcações', detalhe:'Nova marcação em menos de 5 segundos deve ser bloqueada.'},

    {grupo:'11. Resiliência', teste:'Testar sem internet e mensagem amigável'},
    {grupo:'11. Resiliência', teste:'Testar duas abas abertas sem inconsistência'},
    {grupo:'11. Resiliência', teste:'Atualizar com Ctrl+F5 e confirmar ausência de erros no Console'}
  ];

  let saved = {};
  try { saved = JSON.parse(localStorage.getItem(checklistKey) || '{}'); }
  catch (_) { saved = {}; }

  const normalizarRegistro = (valor) => {
    if (typeof valor === 'boolean') {
      return {status: valor ? 'aprovado' : 'nao_iniciado', observacao: ''};
    }
    return {
      status: valor?.status || 'nao_iniciado',
      observacao: valor?.observacao || ''
    };
  };

  scenarios.forEach((_, i) => {
    saved[i] = normalizarRegistro(saved[i]);
  });

  const list = document.getElementById('checklist');
  const progressText = document.getElementById('checklist-progresso');
  const progressBar = document.getElementById('checklist-barra');
  const finalBadge = document.getElementById('resultado-final');

  function updateProgress() {
    const aprovados = scenarios.filter((_, i) => saved[i]?.status === 'aprovado').length;
    const reprovados = scenarios.filter((_, i) => saved[i]?.status === 'reprovado').length;
    const emTeste = scenarios.filter((_, i) => saved[i]?.status === 'em_teste').length;
    const pct = Math.round(aprovados / scenarios.length * 100);

    progressText.textContent =
      `${aprovados} de ${scenarios.length} aprovados (${pct}%) · ` +
      `${emTeste} em teste · ${reprovados} reprovado(s)`;

    progressBar.style.width = `${pct}%`;

    if (reprovados > 0) {
      finalBadge.textContent = 'Reprovado';
      finalBadge.className = 'badge danger';
    } else if (aprovados === scenarios.length) {
      finalBadge.textContent = 'Aprovado';
      finalBadge.className = 'badge success';
    } else {
      finalBadge.textContent = 'Em andamento';
      finalBadge.className = 'badge';
    }
  }

  function renderChecklist() {
    list.innerHTML = '';
    let lastGroup = '';

    scenarios.forEach((item, index) => {
      if (item.grupo !== lastGroup) {
        const heading = document.createElement('h3');
        heading.textContent = item.grupo;
        list.appendChild(heading);
        lastGroup = item.grupo;
      }

      const row = document.createElement('article');
      row.className = `homolog-case status-${saved[index].status}`;
      row.innerHTML = `
        <div class="homolog-case-main">
          <strong>${item.teste}</strong>
          ${item.detalhe ? `<small>${item.detalhe}</small>` : ''}
        </div>
        <select class="homolog-status" data-index="${index}" aria-label="Status do teste">
          <option value="nao_iniciado">Não iniciado</option>
          <option value="em_teste">Em teste</option>
          <option value="aprovado">Aprovado</option>
          <option value="reprovado">Reprovado</option>
        </select>
        <textarea
          class="homolog-case-note"
          data-note-index="${index}"
          placeholder="Observação deste teste..."
          aria-label="Observação do teste"
        >${saved[index].observacao || ''}</textarea>
      `;

      const select = row.querySelector('select');
      select.value = saved[index].status;
      select.onchange = () => {
        saved[index].status = select.value;
        localStorage.setItem(checklistKey, JSON.stringify(saved));
        renderChecklist();
      };

      const note = row.querySelector('textarea');
      note.onchange = () => {
        saved[index].observacao = note.value;
        localStorage.setItem(checklistKey, JSON.stringify(saved));
      };

      list.appendChild(row);
    });

    updateProgress();
  }

  document.getElementById('marcar-todos').onclick = () => {
    if (!confirm('Marcar todos os testes como aprovados?')) return;
    scenarios.forEach((_, index) => {
      saved[index] = {status:'aprovado', observacao:saved[index]?.observacao || ''};
    });
    localStorage.setItem(checklistKey, JSON.stringify(saved));
    renderChecklist();
  };

  document.getElementById('limpar-checklist').onclick = () => {
    if (!confirm('Limpar status e observações de todos os testes?')) return;
    saved = {};
    scenarios.forEach((_, index) => {
      saved[index] = {status:'nao_iniciado', observacao:''};
    });
    localStorage.removeItem(checklistKey);
    renderChecklist();
  };

  const notes = document.getElementById('notas-homologacao');
  const notesStatus = document.getElementById('notas-status');
  notes.value = localStorage.getItem(notesKey) || '';

  document.getElementById('salvar-notas').onclick = () => {
    localStorage.setItem(notesKey, notes.value);
    notesStatus.textContent = 'Anotações salvas neste navegador.';
    setTimeout(() => notesStatus.textContent = '', 3000);
  };

  document.getElementById('exportar-relatorio').onclick = () => {
    const lines = [
      'PLENITUDE PONTO — RELATÓRIO DE HOMOLOGAÇÃO RC2.2',
      `Gerado em: ${new Date().toLocaleString('pt-BR')}`,
      '',
      ...scenarios.flatMap((item, index) => {
        const registro = saved[index] || {status:'nao_iniciado', observacao:''};
        const rotulo = {
          nao_iniciado:'NÃO INICIADO',
          em_teste:'EM TESTE',
          aprovado:'APROVADO',
          reprovado:'REPROVADO'
        }[registro.status] || registro.status.toUpperCase();

        const linhas = [`[${rotulo}] ${item.grupo} — ${item.teste}`];
        if (registro.observacao) linhas.push(`  Observação: ${registro.observacao}`);
        return linhas;
      }),
      '',
      'ANOTAÇÕES:',
      notes.value || 'Nenhuma anotação registrada.'
    ];
    const blob = new Blob([lines.join('\n')], {type:'text/plain;charset=utf-8'});
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `homologacao-plenitude-${new Date().toISOString().slice(0,10)}.txt`;
    link.click();
    URL.revokeObjectURL(url);
  };

  document.getElementById('diagnosticar').onclick = async () => {
    const button = document.getElementById('diagnosticar');
    const summary = document.getElementById('diagnostico-resumo');
    const grid = document.getElementById('diagnostico-lista');

    button.disabled = true;
    button.textContent = 'Verificando...';
    summary.className = 'homolog-summary';
    summary.textContent = 'Consultando o Supabase...';
    grid.innerHTML = '';

    try {
      const {data, error} = await client.rpc('diagnostico_homologacao_admin');
      if (error) throw error;

      const approved = data?.status === 'aprovado';
      summary.className = `homolog-summary ${approved ? 'ok' : 'warn'}`;
      summary.textContent =
        `${data.aprovados} de ${data.total} verificações aprovadas. ` +
        (data.pendentes
          ? `${data.pendentes} item(ns) exigem atenção.`
          : 'Instalação técnica aprovada.');

      (data.checks || []).forEach(check => {
        const item = document.createElement('div');
        item.className = `homolog-diagnostic ${check.ok ? 'ok' : 'fail'}`;
        item.innerHTML = `
          <strong>${check.ok ? '✓' : '!'} ${check.item}</strong>
          <small>${check.grupo}${check.detalhe ? ` · ${check.detalhe}` : ''}</small>
        `;
        grid.appendChild(item);
      });
    } catch (error) {
      summary.className = 'homolog-summary fail';
      summary.textContent = `Diagnóstico indisponível: ${error.message}`;
    } finally {
      button.disabled = false;
      button.textContent = 'Executar diagnóstico';
    }
  };

  renderChecklist();
})();
