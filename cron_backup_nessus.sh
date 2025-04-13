#!/bin/bash

dir_reports_original="/opt/nessus/var/nessus/users/stefanininessus/reports/"
dir_reports_backup="/mnt/backup_report/"
error_log="$dir_reports_backup/erro_backup.log"

# Verificar se o diretório de backup existe
if [ -d "$dir_reports_backup" ]; then
    # -f somente arquivos
    # -newermt modificação mais nova que
    # -maxdepth 1 apenas o diretorio atual
    # para cada arquivo encontrado ({}), executa mv para mover
    # \ encerra exec
    find $dir_reports_original -maxdepth 1 -type f -newermt "$(date +%Y-%m-%d)" -exec mv {} $dir_reports_backup \; 2>> $error_log
else echo "Diretorio de backup não encontrado: $dir_reports_backup"
fi



