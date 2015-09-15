#!/bin/bash
# backup.sh
#
# Faz o backup de um compartilhamento smb ou diretório local para um outro
# compartilhamento smb ou um outro diretório local.
# No destino especificado, são criados dois subdiretórios: dados e backup
# O conteúdo da origem é sincronizado no subdiretório dados e os arquivos
# excluídos e alterados em cada sincronização são armazenados no
# subdiretório backup/<ano-mes-dia-horas-minutos>.
#
# Autor: Renato Candido <renato@liria.com.br>
# Copyright 2014 Liria Tecnologia <http://www.liria.com.br>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
# Versão 0.5
#
# Changelog
#
# v0.6 2015-09-15
# Adicionado suporte à opções adicionais na montagem de compartilhamentos smb
# -p sec=ntml, por exemplo
#
# v0.5 2014-04-29
# Corrigido problema com rm -rfd (-d não existe mais)
#
# v0.4 2014-04-03
# Adicionado suporte à arquivos com nomes contendo espaços (usar aspas "")
#
# v0.3 2013-04-26
# Adicionado suporte à envio de mensagens de log com o maillog.py
#
# v0.2 2010-07-22
# Adicionada data ao texto do arquivo de log
#
# v0.1 2010-07-05
# Primeira versão
#
##################################################################
# Configurações:

# Pontos de montagem dos compartilhamentos smb: diretórios onde serão montados
# os compartilhamentos de origem e/ou destino durante a sincronização de dados
montagem="/mnt"

# Tempo em dias do backup armazenado
tempo=30

# Localização do arquivo de log
locallog="/var/log/backup.log"

# Fazer log via e-mail (requer a instalação do maillog.py)
fazlog=0
email="usuario@provedor.com"
assunto="Servidor $(hostname)"

##################################################################

# Não editar o arquivo deste ponto em diante

MENSAGEM_USO="Faz o backup de um compartilhamento smb ou diretório local 
para um outro compartilhamento smb ou um outro diretório local.
No destino especificado, são criados dois subdiretórios: dados e backup
O conteúdo da origem é sincronizado no subdiretório dados e os arquivos
excluídos e alterados em cada sincronização são armazenados no
subdiretório backup/<ano-mes-dia-horas-minutos>.

Os subdiretórios de backup com mais de $tempo dias são excluídos
automaticamente a cada sincronização.

Por padrão, um compartilhamento será acessado através da conta convidado
(guest), a não ser que seja especificado um usuário e senha através do
parâmetro -a ou --autentica

Uso:

De diretório local para diretório local:
$(basename "$0") -o|--origem <diretório> -d|--destino <diretório>

De diretório local para compartilhamento smb:
$(basename "$0") -o|--origem <diretório> -d|--destino <compartilhamento>
[-a|--autentica <usuário> <senha>] [-p|--parametros <parâmetros>]

De compartilhamento smb para diretório local:
$(basename "$0") -o|--origem <compartilhamento>
[-a|--autentica <usuário> <senha>] [-p|--parametros <parâmetros>] 
-d <diretório>

De compartilhamento smb para compartilhamento smb:
$(basename "$0") -o|--origem <compartilhamento>
[-a|--autentica <usuário> <senha>] [-p|--parametros <parâmetros>]
-d|--destino <compartilhamento> [-a|--autentica <usuário> <senha>]
[-p|--parametros <parâmetros>]

Os caminhos para os diretórios devem ser informados sem a inclusão da barra
final, como em /home/usuario/diretorio

Os caminhos para compartilhamentos smb são identificados por duas barras
iniciais como em //192.168.1.1/compartilhamento

"

# Chaves
smborig=0        # Origem a partir de compartilhamento smb
smbdest=0        # Destino em um compartilhamento smb
guestorig=1      # Acesso via conta convidado ou através de autenticação
                 # ao compartilhamento de origem
guestdest=1      # Acesso via conta convidado ou através de autenticação
                 # ao compartilhamento de destino
paramorigadc=0   # Parâmetros adicionais para mount.cifs (origem)
paramorigadc=0   # Parâmetros adicionais para mount.cifs (origem)

# Tratamento das opções de linha de comando
while test -n "$1"
do
    case "$1" in
        -o | --origem)
            shift
            origem="$1"
            iniorigem=$(echo $origem | cut -c1-2)
            if [ "$iniorigem" = "//" ]
            then
                smborig=1
                shift
                if [ "$1" = "-a" -o "$1" = "--autentica" ]
                then
                    shift
                    usuarioorig="$1"
                    if test -z "$usuarioorig"
                    then
                        echo "Faltou especificar o nome do usuário"
                        exit 1
                    fi
                    shift
                    senhaorig="$1"
                    if test -z "$senhaorig"
                    then
                        echo "Faltou especificar a senha"
                        exit 1
                    fi
                    # Opção $1 já processada, a fila deve andar
                    shift
                    guestorig=0
                fi
                if [ "$1" = "-p" -o "$1" = "--parametros" ]
                then
                    shift
                    paramorigad="$1"
                    paramorigadc=1
                    # Opção $1 já processada, a fila deve andar
                    shift
                fi
            else
                # Opção $1 já processada, a fila deve andar
                shift
            fi
        ;;
        -d | --destino)
            shift
            destino="$1"
            inidestino=$(echo $destino | cut -c1-2)
            if [ "$inidestino" = "//" ]
            then
                smbdest=1
                shift
                if [ "$1" = "-a" -o "$1" = "--autentica" ]
                then
                    shift
                    usuariodest="$1"
                    if test -z "$usuariodest"
                    then
                        echo "Faltou especificar o nome do usuário"
                        exit 1
                    fi
                    shift
                    senhadest="$1"
                    if test -z "$senhadest"
                    then
                        echo "Faltou especificar a senha"
                        exit 1
                    fi
                    # Opção $1 já processada, a fila deve andar
                    shift
                    guestdest=0
                fi
                if [ "$1" = "-p" -o "$1" = "--parametros" ]
                then
                    shift
                    paramdestad="$1"
                    paramdestadc=1
                    # Opção $1 já processada, a fila deve andar
                    shift
                fi
            else
                # Opção $1 já processada, a fila deve andar
                shift
            fi
        ;;

        -h | --help)
            echo "$MENSAGEM_USO"
            exit 0
        ;;

        -V | --version)
            echo -n $(basename "$0")
            # Extrai a versão diretamente dos cabeçalhos do programa
            grep '^# Versão ' "$0" | tail -1 | cut -d : -f 1 | tr -d \#
            exit 0
        ;;

        *)
            echo Opção inválida: $1
            exit 1
        ;;
    esac
done

# Nome do diretório onde será armazenado o backup <ano-mes-dia-horas-minutos>
bakdirname=$(date +%Y-%m-%d-%Hh-%Mm)

# Pontos de montagem de origem e destino
montagemorig="$montagem/orig"
montagemdest="$montagem/dest"

if [ "$origem" = "" ]
then
    echo "$MENSAGEM_USO"
    exit 1
fi

if [ "$destino" = "" ]
then
    echo "$MENSAGEM_USO"
    exit 1
fi

if [ "$smborig" = 1 ]
then
    if test "$guestorig" = 0
    then
        paramorig="-o user=$usuarioorig,password=$senhaorig"
    else
        paramorig="-o guest"
    fi
    if test "$paramorigadc" = 1
    then
        paramorig="$paramorig,$paramorigad"
    fi
    if [ "$smbdest" = 1 ]
    then
        if test "$guestdest" = 0
        then
            paramdest="-o user=$usuariodest,password=$senhadest"
        else
            paramdest="-o guest"
        fi
        if test "$paramdestadc" = 1
        then
            paramdest="$paramdest,$paramdestad"
        fi
        # Backup de compartilhamento smb para compartilhamento smb

        mkdir -p "$montagemorig"
        mkdir -p "$montagemdest"
        if mount.cifs "$origem" "$montagemorig" $paramorig 2> /dev/null
        then
            if mount.cifs "$destino" "$montagemdest" $paramdest 2> /dev/null
            then
                # Cria o diretório $montagemdest/dados, se não existir
                if ! test -d "$montagemdest/dados"
                then
                    mkdir -p "$montagemdest/dados"
                fi

                # Sincroniza o compartilhamento $montagemorig em
                # $montagemdest/dados/, fazendo o backup em $montagemdest/backup
                rsync -av --delete --backup \
                --backup-dir="$montagemdest/backup/$bakdirname" "$montagemorig/" \
                "$montagemdest/dados/"

                # Exclui os diretórios de backup mais velhos que o tempo
                # especificado
                if test -d "$montagemdest/backup"
                then
                    find "$montagemdest/backup/" -depth -type d \
                    -mtime +$((1+$tempo)) -exec rm -rf {} \;
                fi
                umount $montagemorig
                umount $montagemdest

                echo "Cópia de $origem para $destino executada com sucesso em $bakdirname" > $locallog
                rmdir $montagemorig
                rmdir $montagemdest
                exit 0
            else
                umount $montagemorig
                echo "Erro na cópia de $origem para $destino em $bakdirname" >> $locallog
                rmdir $montagemorig
                rmdir $montagemdest
                if [ "$fazlog" = 1 ]
                then
                    maillog.py "$email" "$assunto" "Erro na cópia de $origem para $destino em $bakdirname" &> /dev/null
                fi
                exit 1
            fi
        else
            echo "Erro na cópia de $origem para $destino em $bakdirname" >> $locallog
            rmdir $montagemorig
            rmdir $montagemdest
            if [ "$fazlog" = 1 ]
            then
                maillog.py "$email" "$assunto" "Erro na cópia de $origem para $destino em $bakdirname" &> /dev/null
            fi

            exit 1
        fi
    else
        # Backup de compartilhamento smb para diretório local

        mkdir -p "$montagemorig"
        if mount.cifs "$origem" "$montagemorig" $paramorig 2> /dev/null
        then
            # Cria o diretório $destino/dados, se não existir
            if ! test -d "$destino/dados"
            then
                mkdir -p "$destino/dados"
            fi

            # Sincroniza o compartilhamento $origem em $destino/dados/,
            # fazendo o backup em $destino/backup
            rsync -av --delete --backup \
            --backup-dir="$destino/backup/$bakdirname" "$montagemorig/" \
            "$destino/dados/"

            # Exclui os diretórios de backup mais velhos que o tempo
            # especificado
            if test -d "$destino/backup"
            then
                find "$destino/backup/" -depth -type d \
                -mtime +$((1+$tempo)) -exec rm -rf {} \;
            fi
            umount $montagemorig

            echo "Cópia de $origem para $destino executada com sucesso em $bakdirname" > $locallog
            rmdir $montagemorig
            exit 0
        else
            echo "Erro na cópia de $origem para $destino em $bakdirname" >> $locallog
            rmdir $montagemorig
            if [ "$fazlog" = 1 ]
            then
                maillog.py "$email" "$assunto" "Erro na cópia de $origem para $destino em $bakdirname" &> /dev/null
            fi
            exit 1
        fi
    fi
else
    if [ "$smbdest" = 1 ]
    then
        if test "$guestdest" = 0
        then
            paramdest="-o user=$usuariodest,password=$senhadest"
        else
            paramdest="-o guest"
        fi
        if test "$paramdestadc" = 1
        then
            paramdest="$paramdest,paramdestad"
        fi
        
        # Backup de diretório local para compartilhamento smb

        mkdir -p "$montagemdest"
        if mount.cifs "$destino" "$montagemdest" $paramdest 2> /dev/null
        then
            # Cria o diretório $montagemdest/dados, se não existir
            if ! test -d "$montagemdest/dados"
            then
                mkdir -p "$montagemdest/dados"
            fi

            # Sincroniza o compartilhamento $origem em $montagemdest/dados/,
            # fazendo o backup em $montagemdest/backup
            rsync -av --delete --backup \
            --backup-dir="$montagemdest/backup/$bakdirname" "$origem/" \
            "$montagemdest/dados/"

            # Exclui os diretórios de backup mais velhos
            # que o tempo especificado
            if test -d "$montagemdest/backup"
            then
                find "$montagemdest/backup/" -depth -type d \
                -mtime +$((1+$tempo)) -exec rm -rf {} \;
            fi
            umount $montagemdest

            echo "Cópia de $origem para $destino executada com sucesso em $bakdirname" > $locallog
            rmdir $montagemdest
            exit 0
        else
            echo "Erro na cópia de $origem para $destino em $bakdirname" >> $locallog
            rmdir $montagemdest
            if [ "$fazlog" = 1 ]
            then
                maillog.py "$email" "$assunto" "Erro na cópia de $origem para $destino em $bakdirname" &> /dev/null
            fi
            exit 1
        fi
    else
        # Backup de diretório local para diretório local
        
        # Cria o diretório $destino, se não existir
        if ! test -d "$destino/dados"
        then
            mkdir -p "$destino/dados"
        fi
        # Sincroniza o compartilhamento $origem em $destino/dados/,
        # fazendo o backup em $destino/backup
        rsync -av --delete --backup \
        --backup-dir="$destino/backup/$bakdirname" "$origem/" \
        "$destino/dados/"

        # Exclui os diretórios de backup mais velhos que o tempo especificado
        if test -d "$destino/backup"
        then
            find "$destino/backup/" -depth -type d \
            -mtime +$((1+$tempo)) -exec rm -rf {} \;
        fi
        echo "Cópia de $origem para $destino executada com sucesso em $bakdirname" > $locallog
        exit 0
    fi
fi
exit 0
