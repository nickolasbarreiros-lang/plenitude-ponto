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
    ['1. Preparação','Diagnóstico técnico com todas as verificações aprovadas'],
    ['1. Preparação','Funcionário 999 criado ou reparado'],
    ['1. Preparação','Dados de homologação resetados'],
    ['1. Preparação','Computador de testes autorizado'],

    ['2. Jornada','Login com matrícula 999 e PIN 9999'],
    ['2. Jornada','Registrar entrada'],
    ['2. Jornada','Confirmar horário e próxima ação'],
    ['2. Jornada','Registrar saída para almoço'],
    ['2. Jornada','Registrar retorno do almoço'],
    ['2. Jornada','Registrar saída final'],
    ['2. Jornada','Confirmar jornada encerrada e resumo'],

    ['3. Movimentação temporária','Registrar saída temporária com motivo'],
    ['3. Movimentação temporária','Confirmar status Fora da loja'],
    ['3. Movimentação temporária','Registrar retorno temporário'],
    ['3. Movimentação temporária','Classificar movimentação no painel'],

    ['4. Ajustes','Solicitar entrada esquecida'],
    ['4. Ajustes','Solicitar saída esquecida'],
    ['4. Ajustes','Aprovar uma solicitação'],
    ['4. Ajustes','Rejeitar uma solicitação'],
    ['4. Ajustes','Confirmar reflexo no relatório e auditoria'],

    ['5. Banco de horas','Conferir tolerância de entrada'],
    ['5. Banco de horas','Conferir saldo diário'],
    ['5. Banco de horas','Conferir saldo semanal'],
    ['5. Banco de horas','Conferir saldo mensal'],
    ['5. Banco de horas','Conferir hora extra e saída antecipada'],

    ['6. Administração','Criar e editar funcionário'],
    ['6. Administração','Definir ou alterar PIN'],
    ['6. Administração','Bloquear e reativar acesso ao ponto'],
    ['6. Administração','Autorizar e revogar dispositivo'],
    ['6. Administração','Consultar auditoria'],
    ['6. Administração','Gerar backup e exportações'],

    ['7. Fechamento','Fechar competência'],
    ['7. Fechamento','Confirmar bloqueio de alterações'],
    ['7. Fechamento','Reabrir com motivo e PIN Mestre'],

    ['8. Relatórios','Gerar espelho mensal'],
    ['8. Relatórios','Imprimir ou salvar PDF'],
    ['8. Relatórios','Exportar CSV'],

    ['9. Segurança','Testar PIN incorreto'],
    ['9. Segurança','Confirmar bloqueio após tentativas inválidas'],
    ['9. Segurança','Testar computador não autorizado'],
    ['9. Segurança','Testar logout e sessão expirada'],

    ['10. Resiliência','Testar sem internet e mensagem amigável'],
    ['10. Resiliência','Testar duas abas abertas'],
    ['10. Resiliência','Atualizar com Ctrl+F5 e confirmar ausência de erros no Console']
  ];

  let saved = {};
  try { saved = JSON.parse(localStorage.getItem(checklistKey) || '{}'); }
  catch (_) { saved = {}; }

  const list = document.getElementById('checklist');
  const progressText = document.getElementById('checklist-progresso');
  const progressBar = document.getElementById('checklist-barra');
  const finalBadge = document.getElementById('resultado-final');

  function updateProgress() {
    const done = scenarios.filter((_, i) => saved[i]).length;
    const pct = Math.round(done / scenarios.length * 100);
    progressText.textContent = `${done} de ${scenarios.length} testes concluídos (${pct}%)`;
    progressBar.style.width = `${pct}%`;
    finalBadge.textContent = pct === 100 ? 'Aprovado' : 'Em andamento';
    finalBadge.classList.toggle('success', pct === 100);
  }

  function renderChecklist() {
    list.innerHTML = '';
    let lastGroup = '';
    scenarios.forEach(([group, label], index) => {
      if (group !== lastGroup) {
        const heading = document.createElement('h3');
        heading.textContent = group;
        list.appendChild(heading);
        lastGroup = group;
      }

      const row = document.createElement('label');
      row.className = 'homolog-check';
      row.innerHTML = `
        <input type="checkbox" data-index="${index}" ${saved[index] ? 'checked' : ''}>
        <span>${label}</span>
      `;
      list.appendChild(row);
    });

    list.querySelectorAll('input[type="checkbox"]').forEach(input => {
      input.onchange = () => {
        saved[input.dataset.index] = input.checked;
        localStorage.setItem(checklistKey, JSON.stringify(saved));
        updateProgress();
      };
    });
    updateProgress();
  }

  document.getElementById('marcar-todos').onclick = () => {
    if (!confirm('Marcar todos os testes como concluídos?')) return;
    scenarios.forEach((_, index) => saved[index] = true);
    localStorage.setItem(checklistKey, JSON.stringify(saved));
    renderChecklist();
  };

  document.getElementById('limpar-checklist').onclick = () => {
    if (!confirm('Limpar todo o checklist deste navegador?')) return;
    saved = {};
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
      ...scenarios.map(([group, label], index) =>
        `${saved[index] ? '[APROVADO]' : '[PENDENTE]'} ${group} — ${label}`
      ),
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
