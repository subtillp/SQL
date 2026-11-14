# SQL

Consultas SQL que desenvolvi para **extrair dados contábeis de um ERP** e alimentar análises em **Power BI**, na área de controladoria.

Cada arquivo `.sql` começa com um cabeçalho explicando **objetivo, problema, lógica, tabelas e parâmetros**, e o código é comentado nos pontos importantes.

> Os nomes de schema, filial e empresa foram trocados por genéricos. A lógica é a original. As tabelas seguem o padrão do ERP **TOTVS Protheus**, e o banco é **PostgreSQL**.

## Consultas

| Arquivo | O que entrega | Técnicas |
|---|---|---|
| [`razao-contabil-debito-credito.sql`](razao-contabil-debito-credito.sql) | Lançamentos de custos e despesas de uma filial no mês, **uma linha por ponta do lançamento** (débito positivo, crédito negativo), com conta, centro de custo e descrições | `UNION ALL`, `CASE`, `COALESCE` + `NULLIF`, vários `LEFT JOIN` na mesma tabela |
| [`plano-de-contas-niveis.sql`](plano-de-contas-niveis.sql) | **Dimensão de contas** para o Power BI: código, nome, grupo (conta-pai), natureza e ordem de exibição | Subconsulta no `SELECT`, `CASE`, `LEFT` para hierarquia pelo código |

## Como essas consultas se encaixam no Power BI

```
plano-de-contas-niveis.sql ──► dContas (dimensão)
                                   │ conta_codigo
                                   ▼
razao-contabil-debito-credito.sql ──► fLancamentos (fato)
```

A dimensão filtra a fato pela conta: um gráfico por **natureza** (Receita, Custo, Despesa) soma os lançamentos de todas as contas daquela natureza.

## Tabelas do Protheus usadas

| Tabela | Conteúdo | Colunas principais |
|---|---|---|
| `ct2010` | Lançamentos contábeis | `ct2_data`, `ct2_debito`, `ct2_credit`, `ct2_ccd`, `ct2_ccc`, `ct2_valor` |
| `ct1010` | Plano de contas | `ct1_conta`, `ct1_desc01` |
| `ctt010` | Centros de custo | `ctt_custo`, `ctt_desc01` |
| `sys_company` | Filiais | `m0_codfil`, `m0_fulname` |

**Convenções do Protheus que aparecem nas consultas:**
- `d_e_l_e_t_ = '*'` marca registro **apagado**; por isso todo filtro tem `d_e_l_e_t_ <> '*'`.
- Datas ficam como **texto** `AAAAMMDD`; `TO_DATE(campo, 'YYYYMMDD')` converte para data.
- Códigos vêm com **espaços à direita**; por isso o `TRIM` antes de comparar.

## Guia rápido das funções usadas

| Função | Exemplo | O que faz |
|---|---|---|
| `UNION ALL` | `SELECT ... UNION ALL SELECT ...` | Empilha dois resultados com as **mesmas colunas, na mesma ordem**. Não remove repetidos (o `UNION` sem `ALL` remove e é mais lento) |
| `COALESCE(a, b)` | `COALESCE(descricao, 'NÃO ENCONTRADA')` | Devolve o primeiro valor que não é nulo |
| `NULLIF(a, b)` | `NULLIF(TRIM(conta), '')` | Transforma `''` em nulo, para o `COALESCE` funcionar também com texto vazio |
| `CASE WHEN` | `CASE WHEN conta LIKE '4%' THEN 'CUSTO' END` | `SE` do SQL |
| `LIKE '4%'` | | Começa com 4 |
| `LEFT(texto, n)` | `LEFT('41010001', 4)` → `'4101'` | Primeiros n caracteres |
| `\|\|` | `ano \|\| '-' \|\| mes` | Concatena textos |

## Boas práticas que sigo

- **Período curto no `WHERE`** (um mês por vez): consultas leves, que não travam o banco.
- **`LEFT JOIN` + `COALESCE`** para cadastros: nenhum lançamento some por falta de cadastro, e o problema fica visível ("NÃO ENCONTRADO").
- **Colunas com nomes claros** (`conta_codigo`, `cc_descricao`) já no SQL, para o Power BI receber a tabela pronta.

## Outros repositórios

- [DAX](https://github.com/subtillp/DAX): medidas para modelos no Power BI
- [power-query-m](https://github.com/subtillp/power-query-m): tratamento de dados em Power Query (M)
