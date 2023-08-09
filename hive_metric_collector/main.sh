#!/bin/bash

# Название: HiveMetricCollector
# Версия: 1.0
# Автор: ...
# Описание: Проверка соотвествия партиций HSM и HDFS, push метрик в Prometheus для получения графика в Grafana
# Лицензия: Released under GNU Public License (GPL)
# Ссылка на репозиторий: ...

# Переменные
METRIC_PATH="/opt/spm/metrics/"
OUT_FILE="cm_u_metrics.prom"
LOG_FILE="$HOME/HiveMetricCollector/tmp/logs.txt"
LOG_BEELINE="$HOME/HiveMetricCollector/tmp/beeline_logs.txt"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
CM="cm"
CLUSTER="..."
TABLE_ARRAY=("connections" "superconnections" "superconnections_new")

# Код скрипта

check_output_file() {
  # Проверка наличия строк в файле метрик
  if grep -q "." "$HOME/HiveMetricCollector/$OUT_FILE"; then
    return 0
  else
    echo "Метрик не обнаружено, дата: $TIMESTAMP" >> "$HOME"/HiveMetricCollector/"$LOG_FILE"
    return 1
  fi
}

metric_collector() {
  echo "# HELP sync table connections indicator"
  echo "# TYPE sync gauge"
  for TABLE in "${TABLE_ARRAY[@]}"; do
    # Переменные
    HDFS_TYPES_PATH="$HOME/HiveMetricCollector/tmp/HDFS_$TABLE.types"
    HSM_TEMP_PATH="$HOME/HiveMetricCollector/tmp/HSM_$TABLE.temp"
    HSM_TYPES_PATH="$HOME/HiveMetricCollector/tmp/HSM_$TABLE.types"

    if [ "$TABLE" == "superconnections" ] || [ "$TABLE" == "superconnections_new" ]; then
      # Получаем список партиций в HDFS для определенной таблицы
      hdfs dfs -ls "/data//pa/snp/$TABLE" | grep -oP "type=[^/]*" > "$HDFS_TYPES_PATH"

      # Получаем список партиций из HSM
      beeline -e "show partitions .$TABLE;" --silent=true 2>> "$LOG_BEELINE" > "$HSM_TEMP_PATH"
      # shellcheck disable=SC2002
      cat "$HOME"/HiveMetricCollector/tmp/HSM_"$TABLE".temp | grep -oP "type=[^/]*" | sed 's/ //g;s/|//g' > "$HSM_TYPES_PATH"
    else
      # Получаем список партиций в HDFS для определенной таблицы
      hdfs dfs -ls /data/pa/snp/"$TABLE"/*/* | grep -oP "(?<=$TABLE/).*/type=.*" >  "$HDFS_TYPES_PATH"

      # Получаем список партиций из HSM
      beeline -e "show partitions .$TABLE;" --silent=true 2>> "$LOG_BEELINE" > "$HSM_TEMP_PATH"
      # shellcheck disable=SC2002
      cat "$HOME"/HiveMetricCollector/tmp/HSM_"$TABLE".temp | grep -oP '(.*)/type=.*' | sed 's/ //g;s/|//g' > "$HSM_TYPES_PATH"
    fi

    # Сравниваем партиции
    # shellcheck disable=SC2006
    HivePartitions=`grep -Fxv -f "$HOME"/HiveMetricCollector/tmp/HDFS_"$TABLE".types "$HOME"/HiveMetricCollector/tmp/HSM_"$TABLE".types`

    # Генерируем файл метрики
    read -ra metric_array <<< "$HivePartitions" # Разделяет и создает массив из строки
    count_partitions=${#metric_array[@]}
    # shellcheck disable=SC2140
    echo "$CM{c_name="\""$CLUSTER"\"",table="\""$TABLE"\"",etl="\"pass\"",profile="\"pass\"",type="\"pass"\"} $count_partitions"
    if [[ count_partitions -gt 0 ]]; then # Если количество партиций больше 0
      # shellcheck disable=SC2068
      for data in ${metric_array[@]}; do
        if [ "$TABLE" == "superconnections" ] || [ "$TABLE" == "superconnections_new" ]; then
          etl="pass"
          profile="pass"
          type=$(echo "$data" | awk -F'=' '{print $2}')
          # shellcheck disable=SC2140
          echo "$CM{c_name="\""$CLUSTER"\"",table="\""$TABLE"\"",etl="\"$etl\"",profile="\"$profile\"",type="\""$type"\""} 1"
        else
          etl=$(echo "$data" | awk -F'/' '{print $1}' | awk -F'=' '{print $2}')
          profile=$(echo "$data" | awk -F'/' '{print $2}' | awk -F'=' '{print $2}')
          type=$(echo "$data" | awk -F'/' '{print $3}' | awk -F'=' '{print $2}')
          # shellcheck disable=SC2140
          echo "$CM{c_name="\""$CLUSTER"\"",table="\""$TABLE"\"",etl="\""$etl"\"",profile="\""$profile"\"",type="\""$type"\""} 1"
        fi
      done
    else
      : # Заглушка
    fi
  done
}

metric_collector > "$HOME"/HiveMetricCollector/$OUT_FILE
check_output_file

mv -f "$HOME"/HiveMetricCollector/$OUT_FILE $METRIC_PATH