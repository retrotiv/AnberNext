# Atualizar o AnberNext pelo próprio aparelho

A partir da primeira instalação, você **não precisa regravar o cartão** para pegar uma
versão nova. O aparelho busca a atualização neste repositório pelo Wi-Fi e aplica só na
parte do AnberNext do cartão de boot.

> **O que a atualização nunca toca:** o seu **cartão de jogos** (slot de baixo) e a
> **memória interna / Android** do aparelho. O atualizador se recusa a rodar se não
> conseguir provar que está escrevendo no cartão do AnberNext e em mais lugar nenhum.

## Como atualizar (para quem usa)

1. Conecte o aparelho ao **Wi-Fi**.
2. Abra **Tools → AnberNext Update**.
3. Ele confere a última versão, baixa, confere o checksum e aplica. Leva um minuto.
4. Quando disser que atualizou, **reinicie** o aparelho. Pronto.

Se já estiver na versão mais nova, ele avisa e não faz nada. Se não houver internet, ele
avisa e não faz nada.

### Se uma atualização sair ruim

Toda atualização guarda os arquivos antigos antes de trocar. Abra
**Tools → AnberNext Rollback** para voltar à versão anterior e reinicie.

---

## Como publicar uma versão (para quem mantém o projeto)

O AnberNext tem **duas coisas** numa release:

- **Pacote de atualização** (`anbernext-<tag>-update.zip` + `.sha256`) — o arquivo leve
  que o aparelho baixa. Contém só a camada do NextUI (`.system/rg353`, `Tools/rg353`,
  `Emus/rg353`).
- **Imagem completa** (`anbernext-<tag>-rg353v.img` + `.sha256`) — para quem vai instalar
  do zero pelo [guia de instalação](INSTALL.md).

### 1. Gerar o pacote de atualização

A partir de um cartão (ou de uma árvore de build) que tenha a pasta `.system/rg353`:

```bash
tools/make-update-package.sh v3.15 /caminho/para/o/NEXTUI ./dist
```

Isso gera em `./dist` o `anbernext-v3.15-update.zip` e o `.sha256`. Dentro do zip vão
o `anbernext-release.txt` (a tag, que o aparelho confere) e o `MANIFEST.sha256` (checksum
de cada arquivo, que o aparelho também confere).

### 2. Criar a release no GitHub

```bash
gh release create v3.15 \
  ./dist/anbernext-v3.15-update.zip \
  ./dist/anbernext-v3.15-update.zip.sha256 \
  anbernext-v3.15-rg353v.img.gz \
  anbernext-v3.15-rg353v.img.gz.sha256 \
  --repo retrotiv/AnberNext \
  --title "AnberNext v3.15" \
  --notes-file docs/release-notes/v3.15.md
```

> A imagem crua tem ~4 GB e passaria do limite de 2 GB por arquivo do GitHub. Por isso
> subimos **comprimida** (`gzip -c imagem.img > anbernext-v3.15-rg353v.img.gz`): fica em
> ~400 MB (a imagem é quase toda espaço vazio) e o balenaEtcher grava o `.gz` direto, sem
> o usuário precisar descompactar.

### 3. Rota de atualização

O aparelho olha **apenas** para `retrotiv/AnberNext` (configurado em
`Tools/rg353/AnberNext Update.pak`). Não usamos o auto-update de origem do NextUI — toda
atualização do AnberNext passa por aqui. Isso é de propósito: mantém tudo dentro da
estrutura do aparelho e evita conflito com o projeto de origem.

---

## O que muda em cada versão

### v3.15 — energia e bateria
- **Fim dos reinícios sob carga.** Em bateria não cheia, abrir coisas pesadas (lista do
  Boombrick, PSP, carga do Spotify) dava um pico de corrente que derrubava a tensão da
  célula abaixo do corte e o aparelho reiniciava sozinho. A v3.15 limita a frequência
  máxima da CPU e controla a GPU para cortar esse pico, mantendo quase todo o desempenho.
- **Porcentagem de bateria mais honesta.** O medidor do RK817 chuta para cima; agora o
  número é conferido contra a tensão real da célula.
