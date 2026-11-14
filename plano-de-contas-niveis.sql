/* =============================================================================
   PLANO DE CONTAS COM NÍVEIS E NATUREZA (dimensão de contas)
   =============================================================================
   Objetivo
     Criar a tabela de contas (dimensão) para o Power BI, com:
       - código e nome da conta, e os dois juntos para exibir em visuais;
       - descrição do grupo (nível 1 = 4 primeiros dígitos da conta);
       - natureza (Receita, Custo, Despesa) e uma ordem para classificar a DRE.

   Técnicas
     - Subconsulta no SELECT (subconsulta escalar): busca, para cada conta, a
       descrição da conta-pai, na MESMA tabela.
     - CASE para classificar pela primeira posição do código.

   Tabela (padrão ERP TOTVS Protheus)
     ct1010 -> plano de contas

   Banco: PostgreSQL
   ============================================================================= */

select 
    trim(ct1_conta)                                  as conta_codigo,
    trim(ct1_desc01)                                 as conta_nome,
    (trim(ct1_conta) || ' | ' || trim(ct1_desc01))   as conta_codigo_nome,
    -- Descrição do nível 1: procura na mesma tabela a conta cujo código é
    -- igual aos 4 primeiros dígitos desta conta (a conta-pai).
    -- "limit 1" garante um único valor (a subconsulta no SELECT não pode
    -- devolver mais de uma linha).
    -- Obs.: roda uma vez por conta. Em tabelas grandes, um LEFT JOIN com a
    -- tabela de contas-pai é mais leve.
    (select trim(n.ct1_desc01)
        from staging_erp.ct1010 n
        where trim(n.ct1_conta) = left(trim(ct1.ct1_conta), 4)
        and n.D_E_L_E_T_ <> '*'
        order by n.ct1_conta
    limit 1) as descricao_nivel1,
    
    trim(ct1.ct1_desc01) as descricao_conta_nivel2,
    -- Natureza pela 1ª posição do código: 3 = receita, 4 = custo, 5 = despesa.
    case left(trim(ct1_conta), 1)
        when '3' then 'Receita'
        when '4' then 'Custo Operacional'
        when '5' then 'Despesa Administrativa'
        else 'Outros'
    end                                              as natureza,
    -- Mesma regra, em número: usado em "Classificar por coluna" no Power BI.
    case left(trim(ct1_conta), 1)
        when '3' then 1
        when '4' then 2
        when '5' then 3
        else 9
    end                                              as natureza_ordem,
    left(trim(ct1_conta), 2)                         as grupo_conta

from staging_erp.ct1010 ct1
where ct1.D_E_L_E_T_ <> '*'   -- ignora registros apagados (padrão Protheus)
