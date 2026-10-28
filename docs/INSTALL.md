# Instalação do AnberNext no RG353V

Este guia é para a **primeira instalação** — gravar o cartão de boot uma vez. Depois
disso, as novas versões entram pelo próprio aparelho, sem regravar nada
(veja [UPDATE.md](UPDATE.md)).

> Nada aqui mexe no Android do aparelho nem no cartão de jogos. O AnberNext mora num
> cartão só dele. Se um dia quiser o Anbernic de fábrica de volta, é só tirar o cartão.

## O que você precisa

- Um **Anbernic RG353V**.
- Um **cartão microSD** só para o AnberNext (o "cartão de boot"). 8 GB já sobra.
- Um leitor de cartão e um PC com Windows.
- O programa **balenaEtcher** (grátis): https://etcher.balena.io

## Passo 1 — Baixar a imagem

Na página de [Releases](../../releases), baixe a imagem da versão mais recente —
`anbernext-vX.Y-rg353v.img.gz`. É um arquivo comprimido (fica pequeno, ~400 MB); **você
não precisa descompactar**, o Etcher faz isso sozinho na hora de gravar.

Se quiser conferir que o download não veio corrompido, compare o checksum (`.sha256` ao
lado do arquivo). No PowerShell:

```powershell
Get-FileHash .\anbernext-vX.Y-rg353v.img.gz -Algorithm SHA256
```

O número tem que bater com o conteúdo do arquivo `.sha256`.

## Passo 2 — Gravar no cartão

1. Coloque o cartão de boot no leitor.
2. Abra o **balenaEtcher**.
3. **Flash from file** → escolha a imagem baixada (o `.img.gz`; o Etcher descompacta
   sozinho).
4. **Select target** → escolha o cartão. **Confira o tamanho** para não gravar no disco
   errado.
5. **Flash!** e espere terminar a gravação e a verificação.
6. Quando o Windows pedir para "formatar o disco" ao final, **cancele** — isso é normal,
   ele só não entende as partições do Linux. Pode retirar o cartão com segurança.

## Passo 3 — Primeira inicialização

1. Com o aparelho **desligado**, coloque o cartão de boot no **slot de cima** (TF1).
2. Ligue. Em alguns segundos o AnberNext (NextUI) abre.

Pronto — esse slot de cima é o AnberNext.

## Passo 4 — Voltar para o Android quando quiser

Com o aparelho desligado, **segure o botão `F` (MENU) enquanto liga**. Ele passa para o
Android de fábrica. Na próxima vez que ligar sem segurar o `F`, volta para o AnberNext.
É o mesmo gesto dos cartões de dois sistemas da Anbernic.

## Passo 5 (opcional) — Compartilhar seu cartão de jogos

Se você usa um cartão de jogos no TrimUI Brick, coloque-o no **slot de baixo** (TF2) do
RG353V. O AnberNext lê esse cartão **sem escrever nele**, então seus saves, capas e listas
continuam iguais nos dois aparelhos (e no Miyoo Mini, se você usa um).

## Conferir a versão instalada

No AnberNext, em **Configurações → Sobre** (About), aparece a versão atual. É esse número
que o aparelho compara com o repositório quando você for atualizar.

## Deu algo errado?

- **Tela preta ao ligar:** confira que o cartão está no slot de cima e que a gravação
  terminou a etapa de verificação no Etcher.
- **Abriu o Android em vez do AnberNext:** você pode ter segurado o `F`. Desligue e ligue
  sem segurar nada.
- **Quer recomeçar:** basta gravar a imagem de novo no cartão.
