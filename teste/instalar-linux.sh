#!/bin/sh
# Instalador do CIELLO CRM para Linux (Ubuntu, Mint ou Debian), para o cliente: não precisa do
# código nem de token. Publicado em cada versão no repositório público de versões, com a versão
# já preenchida (o workflow troca 0.35.0). Uso, no Terminal:
#   curl -fsSL https://github.com/MTCiello/CIELLO-CRM-VERSION/releases/latest/download/instalar-linux.sh | sudo sh
# ou baixe o arquivo e rode: sudo sh instalar-linux.sh   (aceita os mesmos argumentos do
# servidor/instalar.sh: um endereço com HTTPS, ou nada para usar na rede local)
# Ele instala o Docker, baixa a imagem pronta do CRM e chama o servidor/instalar.sh que vem
# dentro dela.
set -eu

VERSAO="${CIELLO_VERSAO:-0.35.0}"
IMAGEM="${CIELLO_IMAGEM:-ghcr.io/mtciello/ciello-crm:$VERSAO}"
SERVIDOR="${CIELLO_SERVIDOR:-/srv/ciello}"

erro() { printf '\033[31mErro:\033[0m %s\n' "$*" >&2; exit 1; }

# Docker: primeiro o do próprio sistema (docker.io), que sempre combina com ele (Ubuntu, Mint,
# Debian e derivados); se faltar o compose, o oficial, no repositório da base certa (o Mint e os
# derivados do Ubuntu usam o do Ubuntu: o get.docker.com lia alguns como Debian e quebrava). Tudo
# pelo IPv4: rede com IPv6 que não funciona é comum e o download do Docker falhava ("Could not
# handshake").
APT="apt-get -o Acquire::ForceIPv4=true"
apt_instalar() { DEBIAN_FRONTEND=noninteractive $APT install -y -q "$@" >/dev/null 2>&1; }
compose_ok() { docker compose version >/dev/null 2>&1; }
os_campo() { sed -n "s/^$1=//p" /etc/os-release 2>/dev/null | tr -d '"' | head -n 1; }
instalar_docker() {
  # sobra de uma tentativa anterior com o repositório errado
  rm -f /etc/apt/sources.list.d/docker.list
  $APT update -q >/dev/null 2>&1 || true
  if apt_instalar docker.io; then
    compose_ok || apt_instalar docker-compose-v2 || apt_instalar docker-compose-plugin \
      || apt_instalar docker-compose || true
    systemctl enable --now docker >/dev/null 2>&1 || true
    compose_ok && return 0
  fi
  echo "Instalando o Docker oficial..."
  BASE=debian
  CODINOME=$(os_campo VERSION_CODENAME)
  if [ -n "$(os_campo UBUNTU_CODENAME)" ]; then
    BASE=ubuntu; CODINOME=$(os_campo UBUNTU_CODENAME)
  elif [ "$(os_campo ID)" = ubuntu ]; then
    BASE=ubuntu
  elif [ -n "$(os_campo DEBIAN_CODENAME)" ]; then
    CODINOME=$(os_campo DEBIAN_CODENAME)
  fi
  [ -n "$CODINOME" ] || erro "não deu para saber a versão deste Linux (veja /etc/os-release)"
  # as peças do Docker do sistema brigam com as do oficial ("pacotes quebrados")
  DEBIAN_FRONTEND=noninteractive $APT remove -y -q docker.io docker-doc docker-compose \
    docker-compose-v2 podman-docker containerd runc >/dev/null 2>&1 || true
  install -m 0755 -d /etc/apt/keyrings
  curl -4 -fsSL "https://download.docker.com/linux/$BASE/gpg" -o /etc/apt/keyrings/docker.asc \
    || erro "não deu para baixar o Docker. Confira a internet e rode de novo"
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$BASE $CODINOME stable" \
    > /etc/apt/sources.list.d/docker.list
  $APT update -q >/dev/null 2>&1 || true
  apt_instalar docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin \
    || { rm -f /etc/apt/sources.list.d/docker.list
         erro "não deu para instalar o Docker neste Linux ($BASE $CODINOME). Mande esta tela para o suporte da CIELLO"; }
  systemctl enable --now docker >/dev/null 2>&1 || true
  compose_ok || erro "o Docker instalou sem o compose. Mande esta tela para o suporte da CIELLO"
}

case "$VERSAO" in @*) erro "use o instalar-linux.sh publicado numa versão (este é o modelo do código)" ;; esac
if [ "$(id -u)" != 0 ]; then
  # baixado e aberto com dois cliques ou "sh instalar-linux.sh": pede a senha e continua
  if [ -f "$0" ] && command -v sudo >/dev/null; then exec sudo sh "$0" "$@"; fi
  erro "rode com sudo: curl -fsSL .../instalar-linux.sh | sudo sh"
fi
command -v apt-get >/dev/null || erro "este instalador é para Ubuntu, Mint ou Debian"

printf '\n\033[1mCIELLO CRM %s para Linux\033[0m\n' "$VERSAO"
if ! command -v curl >/dev/null; then
  $APT update -q && DEBIAN_FRONTEND=noninteractive $APT install -y -q curl ca-certificates
fi
if ! command -v docker >/dev/null || ! compose_ok; then
  printf '\n\033[1m==> Instalando o Docker (2 a 3 minutos)\033[0m\n'
  instalar_docker
fi
systemctl enable --now docker >/dev/null 2>&1 || true

printf '\n\033[1m==> Baixando o CIELLO CRM %s (uns 600 MB, alguns minutos)\033[0m\n' "$VERSAO"
docker pull -q "$IMAGEM" >/dev/null || docker image inspect "$IMAGEM" >/dev/null 2>&1 \
  || erro "não deu para baixar o CRM. Confira a internet e rode de novo"

# os scripts do servidor vêm dentro da imagem, na mesma versão do CRM
DESTINO="$SERVIDOR/.instalador"
rm -rf "$DESTINO" && mkdir -p "$DESTINO"
docker run --rm --entrypoint sh -v "$DESTINO:/saida" "$IMAGEM" \
  -c 'cp -r /app/servidor/. /saida/ && cp /app/frontend/dist/icone-192.png /saida/icone.png 2>/dev/null || true'
[ -f "$DESTINO/instalar.sh" ] || erro "a imagem $IMAGEM não traz o instalador"

CIELLO_IMAGEM="$IMAGEM" CIELLO_VERSAO="$VERSAO" CIELLO_SERVIDOR="$SERVIDOR" \
  exec sh "$DESTINO/instalar.sh" "$@"
