/* =============================================================================
   RAZÃO CONTÁBIL COM DÉBITO E CRÉDITO EM LINHAS SEPARADAS
   =============================================================================
   Objetivo
     Extrair os lançamentos contábeis de custos, despesas e impostos sobre o
     lucro de uma filial em um mês, em formato pronto para o Power BI:
     uma linha por movimento, com conta, centro de custo e descrições.

   Problema que resolve
     Na tabela de lançamentos (CT2), UMA linha guarda as DUAS pontas do
     lançamento: a conta de débito (ct2_debito) e a de crédito (ct2_credit).
     Para analisar por conta, cada ponta precisa virar uma linha própria.

   Lógica
     PARTE 1 - lê o lado do DÉBITO  -> valor positivo (lançamento normal)
     PARTE 2 - lê o lado do CRÉDITO -> valor negativo (estorno / redução)
     UNION ALL empilha as duas partes numa tabela só.
     Assim, somar a coluna "valor" por conta dá o saldo líquido da conta.

   Tabelas (padrão ERP TOTVS Protheus)
     ct2010      -> lançamentos contábeis
     ct1010      -> plano de contas (descrição da conta)
     ctt010      -> centros de custo (descrição do CC)
     sys_company -> filiais (nome da filial)

   Parâmetros para ajustar (aparecem nas DUAS partes)
     ct2_filial = '010101'     -> filial
     ct2_data LIKE '202603%'   -> mês (AAAAMM%). Período curto = consulta leve.

   Banco: PostgreSQL
   ============================================================================= */

/* -----------------------------------------------------------------------------
   PARTE 1: MOVIMENTOS A DÉBITO
   Contas de custo/despesa que receberam DÉBITO -> valor positivo.
   ----------------------------------------------------------------------------- */
SELECT DISTINCT 
    ct2.ct2_filial AS filial,
    COALESCE(sys.m0_fulname, 'NOME NÃO ENCONTRADO') AS filial_nome,
    TO_DATE(ct2.ct2_data, 'YYYYMMDD') AS data,
    SUBSTRING(ct2.ct2_data, 1, 4) AS ano,
    SUBSTRING(ct2.ct2_data, 5, 2) AS mes,
    SUBSTRING(ct2.ct2_data, 1, 4) || '-' || SUBSTRING(ct2.ct2_data, 5, 2) AS periodo,
    TRIM(ct2.ct2_lote) AS lote,
    TRIM(ct2.ct2_sblote) as sublote,
    TRIM(ct2.ct2_doc) AS documento,
    TRIM(ct2.ct2_linha) as linha,
    TRIM(ct2.ct2_hist) AS historico,
    CAST(ct2.ct2_valor AS FLOAT) AS valor, 
    'D' AS tipo_movimento,
    CASE 
        WHEN TRIM(ct2.ct2_debito) LIKE '4%' THEN '05. CUSTO (CPV/CMV)'
        WHEN TRIM(ct2.ct2_debito) LIKE '5%' THEN '06. DESPESAS OPERACIONAIS'
        WHEN TRIM(ct2.ct2_debito) IN ('210201001', '210201002', '210203001') THEN '07. IMPOSTOS S/ LUCRO'
        ELSE '08. OUTRAS DESPESAS'
    END AS tipo_conta,
    COALESCE(NULLIF(TRIM(ct2.ct2_debito), ''), 'S/ CONTA') AS conta_codigo,
    COALESCE(conta_d.ct1_desc01, 'DESCRIÇÃO NÃO ENCONTRADA') AS conta_descricao,
    -- CC do movimento (débito, nesta parte)
    COALESCE(NULLIF(TRIM(ct2.ct2_ccd), ''), 'S/ CC') AS cc_codigo,
    CASE WHEN TRIM(ct2.ct2_ccd) = '' THEN 'SEM CENTRO DE CUSTO'
         ELSE COALESCE(cc_d.ctt_desc01, 'CC DELETADO OU DE OUTRA FILIAL') END AS cc_descricao,
    -- CC de débito e de crédito lado a lado (iguais nas duas partes, para filtrar por qualquer um)
    COALESCE(NULLIF(TRIM(ct2.ct2_ccd), ''), 'S/ CC') AS cc_debito,
    COALESCE(cc_d.ctt_desc01, '-')                   AS cc_debito_desc,
    COALESCE(NULLIF(TRIM(ct2.ct2_ccc), ''), 'S/ CC') AS cc_credito,
    COALESCE(cc_cred.ctt_desc01, '-')                AS cc_credito_desc,
    CASE WHEN ct2.ct2_valor < 0 THEN 'ESTORNO' ELSE 'ORIGINAL' END AS tipo_movimento_flag
FROM staging_erp.ct2010 AS ct2
-- LEFT JOIN: mantém o lançamento mesmo sem cadastro correspondente
-- (por isso os COALESCE acima: "NÃO ENCONTRADO" no lugar de vazio).
-- Subconsulta de filiais: agrupa por código para garantir 1 nome por filial
-- e não duplicar lançamentos no join.
LEFT JOIN (
    SELECT DISTINCT TRIM(m0_codfil) as m0_codfil, MAX(m0_fulname) as m0_fulname 
    FROM staging_erp.SYS_COMPANY 
    GROUP BY TRIM(m0_codfil)
) AS sys ON TRIM(ct2.ct2_filial) = sys.m0_codfil
LEFT JOIN staging_erp.ct1010 AS conta_d
    ON TRIM(ct2.ct2_debito) = TRIM(conta_d.ct1_conta) AND conta_d.d_e_l_e_t_ <> '*'
LEFT JOIN staging_erp.ctt010 AS cc_d
    ON TRIM(ct2.ct2_ccd) = TRIM(cc_d.ctt_custo) AND cc_d.d_e_l_e_t_ <> '*'
-- Join extra: descrição do CC de CRÉDITO (para a coluna cc_credito_desc)
LEFT JOIN staging_erp.ctt010 AS cc_cred
    ON TRIM(ct2.ct2_ccc) = TRIM(cc_cred.ctt_custo) AND cc_cred.d_e_l_e_t_ <> '*'
WHERE 
    ct2.d_e_l_e_t_ <> '*'                          -- ignora registros apagados (padrão Protheus)
    AND TRIM(ct2.ct2_filial) = '010101'
    AND ct2.ct2_data LIKE '202603%'
    AND ct2.ct2_valor > 0 
    AND TRIM(ct2.ct2_debito) <> ''
    AND (TRIM(ct2.ct2_debito) LIKE '4%' OR TRIM(ct2.ct2_debito) LIKE '5%' OR TRIM(ct2.ct2_debito) IN ('210201001', '210201002', '210203001'))

UNION ALL

/* -----------------------------------------------------------------------------
   PARTE 2: MOVIMENTOS A CRÉDITO (estornos)
   Mesmas colunas, na mesma ordem (exigência do UNION ALL), mas olhando o
   lado do CRÉDITO. O valor é multiplicado por -1 porque crédito numa conta
   de custo/despesa REDUZ o saldo dela.
   ----------------------------------------------------------------------------- */
SELECT DISTINCT 
    ct2.ct2_filial as filial,
    COALESCE(sys.m0_fulname, 'NOME NÃO ENCONTRADO') AS filial_nome,
    TO_DATE(ct2.ct2_data, 'YYYYMMDD') AS data,
    SUBSTRING(ct2.ct2_data, 1, 4) AS ano,
    SUBSTRING(ct2.ct2_data, 5, 2) AS mes,
    SUBSTRING(ct2.ct2_data, 1, 4) || '-' || SUBSTRING(ct2.ct2_data, 5, 2) AS periodo,
    TRIM(ct2.ct2_lote) AS lote,
    TRIM(ct2.ct2_sblote) as sublote,
    TRIM(ct2.ct2_doc) AS documento,
    TRIM(ct2.ct2_linha) as linha,
    TRIM(ct2.ct2_hist) AS historico,
    (CAST(ct2.ct2_valor AS FLOAT) * -1) AS valor, 
    'C' AS tipo_movimento,
    CASE 
        WHEN TRIM(ct2.ct2_credit) LIKE '4%' THEN '05. CUSTO (CPV/CMV)'
        WHEN TRIM(ct2.ct2_credit) LIKE '5%' THEN '06. DESPESAS OPERACIONAIS'
        WHEN TRIM(ct2.ct2_credit) IN ('210201001', '210201002', '210203001') THEN '07. IMPOSTOS S/ LUCRO'
        ELSE '08. OUTRAS DESPESAS'
    END AS tipo_conta,
    COALESCE(NULLIF(TRIM(ct2.ct2_credit), ''), 'S/ CONTA') AS conta_codigo,
    COALESCE(conta_c.ct1_desc01, 'DESCRIÇÃO NÃO ENCONTRADA') AS conta_descricao,
    -- CC do movimento (crédito, nesta parte)
    COALESCE(NULLIF(TRIM(ct2.ct2_ccc), ''), 'S/ CC') AS cc_codigo,
    CASE WHEN TRIM(ct2.ct2_ccc) = '' THEN 'SEM CENTRO DE CUSTO'
         ELSE COALESCE(cc_c.ctt_desc01, 'CC DELETADO OU DE OUTRA FILIAL') END AS cc_descricao,
    -- CC de débito e de crédito lado a lado (iguais nas duas partes, para filtrar por qualquer um)
    COALESCE(NULLIF(TRIM(ct2.ct2_ccd), ''), 'S/ CC') AS cc_debito,
    COALESCE(cc_deb.ctt_desc01, '-')                 AS cc_debito_desc,
    COALESCE(NULLIF(TRIM(ct2.ct2_ccc), ''), 'S/ CC') AS cc_credito,
    COALESCE(cc_c.ctt_desc01, '-')                   AS cc_credito_desc,
    CASE WHEN ct2.ct2_valor < 0 THEN 'ESTORNO' ELSE 'ORIGINAL' END AS tipo_movimento_flag
FROM staging_erp.ct2010 AS ct2
LEFT JOIN (
    SELECT DISTINCT TRIM(m0_codfil) as m0_codfil, MAX(m0_fulname) as m0_fulname 
    FROM staging_erp.SYS_COMPANY 
    GROUP BY TRIM(m0_codfil)
) AS sys ON TRIM(ct2.ct2_filial) = sys.m0_codfil
LEFT JOIN staging_erp.ct1010 AS conta_c
    ON TRIM(ct2.ct2_credit) = TRIM(conta_c.ct1_conta) AND conta_c.d_e_l_e_t_ <> '*'
LEFT JOIN staging_erp.ctt010 AS cc_c
    ON TRIM(ct2.ct2_ccc) = TRIM(cc_c.ctt_custo) AND cc_c.d_e_l_e_t_ <> '*'
-- Join extra: descrição do CC de DÉBITO (para a coluna cc_debito_desc)
LEFT JOIN staging_erp.ctt010 AS cc_deb
    ON TRIM(ct2.ct2_ccd) = TRIM(cc_deb.ctt_custo) AND cc_deb.d_e_l_e_t_ <> '*'
WHERE 
    ct2.d_e_l_e_t_ <> '*' 
    AND TRIM(ct2.ct2_filial) = '010101'
    AND ct2.ct2_data LIKE '202603%' 
    AND ct2.ct2_valor > 0
    AND TRIM(ct2.ct2_credit) <> ''
    AND (TRIM(ct2.ct2_credit) LIKE '4%' OR TRIM(ct2.ct2_credit) LIKE '5%' OR TRIM(ct2.ct2_credit) IN ('210201001', '210201002', '210203001'))

-- ORDER BY no fim vale para o resultado inteiro (as duas partes juntas).
ORDER BY data
