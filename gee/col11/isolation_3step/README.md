# Isolamento Col. 11 – pipeline autogerenciável (Colab)

Mesmo método e mesmo formato de CSV do `../isolation_forest_col11.js` (commit c6dcaba),
em 3 etapas encadeadas por ano (100 m → mapas 30 m → tabela). O notebook
`run_isolation3_colab.ipynb` baixa `isolation3.py` deste branch, confere os insumos e
roda `iso.run(cfg)`, que lança, monitora, relança falhas e encadeia as etapas até o fim.

* Re-executável: pula assets prontos, reanexa tasks rodando (pelo nome) e não repete
  CSVs já concluídos.
* Timeouts (Error code 3) não são relançados; se ocorrerem, a saída sugere dividir o trabalho.
* `cfg.steps=[2, 3]` roda só as etapas finais (usa os assets de 100 m já existentes).
* Os CSVs vão para o Drive (`PAPER-DEGRAD-COL11`); copie para `data/raw/col11/isolation/`.

Substitui, para o paper, o pipeline antigo em `../isolation_pipeline/` (5 etapas com
`connectedPixelCount`), mantido só como histórico.
